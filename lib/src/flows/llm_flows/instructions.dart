import '../../agents/base_agent.dart';
import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../types/content.dart';
import 'base_llm_flow.dart';

/// Appends global/static/dynamic instructions into the LLM request.
class InstructionsLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    final BaseAgent rootAgent = agent.rootAgent;

    if (rootAgent is LlmAgent &&
        _hasInstructionValue(rootAgent.globalInstruction)) {
      final (String globalInstruction, bool _) = await rootAgent
          .canonicalGlobalInstruction(ReadonlyContext(invocationContext));
      if (globalInstruction.isNotEmpty) {
        llmRequest.appendInstructions(<String>[globalInstruction]);
      }
    }

    final Object? staticInstruction = agent.staticInstruction;
    if (staticInstruction != null) {
      _appendStaticInstruction(llmRequest, staticInstruction);
    }

    if (_hasInstructionValue(agent.instruction)) {
      final (String instruction, bool _) = await agent.canonicalInstruction(
        ReadonlyContext(invocationContext),
      );
      if (instruction.isNotEmpty) {
        llmRequest.appendInstructions(<String>[instruction]);
      }
    }
  }

  bool _hasInstructionValue(Object value) {
    if (value is String) {
      return value.isNotEmpty;
    }
    return true;
  }

  void _appendStaticInstruction(
    LlmRequest llmRequest,
    Object staticInstruction,
  ) {
    if (staticInstruction is String) {
      if (staticInstruction.isNotEmpty) {
        llmRequest.appendInstructions(<String>[staticInstruction]);
      }
      return;
    }

    if (staticInstruction is Content) {
      llmRequest.appendInstructions(staticInstruction.copyWith());
      return;
    }

    if (staticInstruction is List<String>) {
      final List<String> values = staticInstruction
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
      if (values.isNotEmpty) {
        llmRequest.appendInstructions(values);
      }
      return;
    }

    throw ArgumentError(
      'staticInstruction must be String, List<String>, or Content.',
    );
  }
}
