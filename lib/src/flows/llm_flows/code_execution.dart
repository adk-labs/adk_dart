import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../code_executors/base_code_executor.dart';
import '../../code_executors/code_execution_utils.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../types/content.dart';
import 'base_llm_flow.dart';

final RegExp _fencedCodePattern = RegExp(
  r'```(?:[a-zA-Z0-9_+\-]+)?\s*\n([\s\S]*?)```',
);

class CodeExecutionRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    if (_getCodeExecutor(invocationContext) == null) {
      return;
    }

    // Python parity: code execution results from previous turns are converted
    // into plain text before sending to the model.
    for (final Content content in llmRequest.contents) {
      for (final Part part in content.parts) {
        final Object? result = part.codeExecutionResult;
        if (result == null) {
          continue;
        }

        final String resultText = _formatExecutionResult(result);
        if (part.text == null || part.text!.trim().isEmpty) {
          part.text = resultText;
        } else {
          part.text = '${part.text}\n\n$resultText';
        }
        part.codeExecutionResult = null;
      }
    }
  }
}

class CodeExecutionResponseProcessor extends BaseLlmResponseProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmResponse llmResponse,
  ) async* {
    if (llmResponse.partial == true) {
      return;
    }

    final BaseCodeExecutor? codeExecutor = _getCodeExecutor(invocationContext);
    if (codeExecutor == null) {
      return;
    }

    final Content? content = llmResponse.content;
    if (content == null || content.parts.isEmpty) {
      return;
    }

    final String? code = _extractFirstCodeBlock(content);
    if (code == null) {
      return;
    }

    yield Event(
      invocationId: invocationContext.invocationId,
      author: invocationContext.agent.name,
      branch: invocationContext.branch,
      content: Content(
        role: 'model',
        parts: <Part>[Part.text('Executing code:\n```sh\n$code\n```')],
      ),
    );

    CodeExecutionResult result;
    try {
      result = await codeExecutor.executeCode(
        invocationContext,
        CodeExecutionInput(code: code),
      );
    } catch (error) {
      result = CodeExecutionResult(exitCode: -1, stderr: '$error');
    }

    yield Event(
      invocationId: invocationContext.invocationId,
      author: invocationContext.agent.name,
      branch: invocationContext.branch,
      content: Content(
        role: 'model',
        parts: <Part>[
          Part(
            codeExecutionResult: <String, Object?>{
              'exitCode': result.exitCode,
              'stdout': result.stdout,
              'stderr': result.stderr,
              'timedOut': result.timedOut,
              'output_files': result.outputFiles
                  .map((CodeExecutionFile file) => file.toJson())
                  .toList(),
            },
          ),
        ],
      ),
    );

    // Skip the original model response and continue the code-generation loop.
    llmResponse.content = null;
  }
}

BaseCodeExecutor? _getCodeExecutor(InvocationContext invocationContext) {
  final Object agent = invocationContext.agent;
  if (agent is! LlmAgent) {
    return null;
  }
  final Object? codeExecutor = agent.codeExecutor;
  if (codeExecutor is BaseCodeExecutor) {
    return codeExecutor;
  }
  return null;
}

String? _extractFirstCodeBlock(Content content) {
  for (final Part part in content.parts) {
    final String? text = part.text;
    if (text == null || text.isEmpty) {
      continue;
    }
    final RegExpMatch? match = _fencedCodePattern.firstMatch(text);
    if (match == null) {
      continue;
    }
    final String? code = match.group(1)?.trim();
    if (code != null && code.isNotEmpty) {
      return code;
    }
  }
  return null;
}

String _formatExecutionResult(Object result) {
  if (result is Map) {
    final Object? exitCode = result['exitCode'] ?? result['exit_code'];
    final Object? stdout = result['stdout'];
    final Object? stderr = result['stderr'];
    final Object? timedOut = result['timedOut'] ?? result['timed_out'];
    return <String>[
      'Code execution result:',
      if (exitCode != null) 'exitCode: $exitCode',
      if (timedOut != null) 'timedOut: $timedOut',
      if (stdout != null && '$stdout'.isNotEmpty) 'stdout:\n$stdout',
      if (stderr != null && '$stderr'.isNotEmpty) 'stderr:\n$stderr',
    ].join('\n');
  }
  return 'Code execution result:\n$result';
}
