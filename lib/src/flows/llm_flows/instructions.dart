import '../../agents/base_agent.dart';
import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../types/content.dart';
import '../../utils/instructions_utils.dart';
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
    final ReadonlyContext readonlyContext = ReadonlyContext(invocationContext);

    if (rootAgent is LlmAgent &&
        _hasInstructionValue(rootAgent.globalInstruction)) {
      final (String rawGlobalInstruction, bool bypassStateInjection) =
          await rootAgent.canonicalGlobalInstruction(readonlyContext);
      String globalInstruction = rawGlobalInstruction;
      if (!bypassStateInjection) {
        globalInstruction = await injectSessionState(
          rawGlobalInstruction,
          readonlyContext,
        );
      }
      if (globalInstruction.isNotEmpty) {
        llmRequest.appendInstructions(<String>[globalInstruction]);
      }
    }

    final Object? staticInstruction = agent.staticInstruction;
    if (staticInstruction != null) {
      _appendStaticInstruction(llmRequest, staticInstruction);
    }

    if (_hasInstructionValue(agent.instruction) && staticInstruction == null) {
      final String instruction = await _processAgentInstruction(
        agent,
        invocationContext,
      );
      if (instruction.isNotEmpty) {
        llmRequest.appendInstructions(<String>[instruction]);
      }
      return;
    }

    if (_hasInstructionValue(agent.instruction) && staticInstruction != null) {
      final String instruction = await _processAgentInstruction(
        agent,
        invocationContext,
      );
      if (instruction.isNotEmpty) {
        llmRequest.contents.add(
          Content(role: 'user', parts: <Part>[Part.text(instruction)]),
        );
      }
    }
  }

  Future<String> _processAgentInstruction(
    LlmAgent agent,
    InvocationContext invocationContext,
  ) async {
    final ReadonlyContext readonlyContext = ReadonlyContext(invocationContext);
    final (String rawInstruction, bool bypassStateInjection) =
        await agent.canonicalInstruction(readonlyContext);
    if (bypassStateInjection) {
      return rawInstruction;
    }
    return injectSessionState(rawInstruction, readonlyContext);
  }

  bool _hasInstructionValue(Object? value) {
    if (value == null) {
      return false;
    }
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
