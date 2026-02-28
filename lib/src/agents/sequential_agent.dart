import '../events/event.dart';
import '../tools/base_tool.dart';
import '../tools/function_tool.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'invocation_context.dart';
import 'llm_agent.dart';

const String _taskCompletedToolName = 'task_completed';
const String _taskCompletedInstruction = '''
If you finished the user's request according to its description, call the task_completed function to exit so the next agents can take over. When calling this function, do not generate any text other than the function call.
''';

String _taskCompleted() {
  return 'Task completion signaled.';
}

class SequentialAgentState extends BaseAgentState {
  SequentialAgentState({this.currentSubAgent = ''})
    : super(data: <String, Object?>{'current_sub_agent': currentSubAgent});

  final String currentSubAgent;

  factory SequentialAgentState.fromBase(BaseAgentState state) {
    final Map<String, Object?> json = state.toJson();
    return SequentialAgentState(
      currentSubAgent: (json['current_sub_agent'] as String?) ?? '',
    );
  }
}

class SequentialAgent extends BaseAgent {
  SequentialAgent({
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  });

  @override
  SequentialAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> cloneUpdate = normalizeCloneUpdate(update);
    validateCloneUpdateFields(
      update: cloneUpdate,
      allowedFields: BaseAgent.baseCloneUpdateFields,
    );

    final List<BaseAgent> clonedSubAgents = cloneSubAgentsField(cloneUpdate);
    final SequentialAgent clonedAgent = SequentialAgent(
      name: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'name',
        currentValue: name,
      ),
      description: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'description',
        currentValue: description,
      ),
      subAgents: <BaseAgent>[],
      beforeAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'beforeAgentCallback',
        currentValue: beforeAgentCallback,
      ),
      afterAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'afterAgentCallback',
        currentValue: afterAgentCallback,
      ),
    );
    clonedAgent.subAgents = clonedSubAgents;
    relinkClonedSubAgents(clonedAgent);
    return clonedAgent;
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    if (subAgents.isEmpty) {
      return;
    }

    final BaseAgentState? rawState = loadAgentState(context);
    final SequentialAgentState? agentState = rawState == null
        ? null
        : SequentialAgentState.fromBase(rawState);
    final int startIndex = _getStartIndex(agentState);

    bool pauseInvocation = false;
    bool resumingSubAgent = agentState != null;

    for (int index = startIndex; index < subAgents.length; index += 1) {
      final BaseAgent subAgent = subAgents[index];
      if (!resumingSubAgent && context.isResumable) {
        context.setAgentState(
          name,
          agentState: SequentialAgentState(currentSubAgent: subAgent.name),
        );
        yield createAgentStateEvent(context);
      }

      await for (final Event event in subAgent.runAsync(context)) {
        yield event;
        if (context.shouldPauseInvocation(event)) {
          pauseInvocation = true;
        }
      }

      if (context.endInvocation || pauseInvocation) {
        return;
      }

      resumingSubAgent = false;
    }

    if (context.isResumable) {
      context.setAgentState(name, endOfAgent: true);
      yield createAgentStateEvent(context);
    }
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    if (subAgents.isEmpty) {
      return;
    }

    _prepareLiveSubAgentsForHandoff();

    for (final BaseAgent subAgent in subAgents) {
      await for (final Event event in subAgent.runLive(context)) {
        yield event;
      }
    }
  }

  void _prepareLiveSubAgentsForHandoff() {
    for (final BaseAgent subAgent in subAgents) {
      if (subAgent is! LlmAgent) {
        continue;
      }

      final bool addedTaskCompletedTool = _ensureTaskCompletedTool(subAgent);
      if (!addedTaskCompletedTool) {
        continue;
      }

      final Object currentInstruction = subAgent.instruction;
      if (currentInstruction is! String) {
        continue;
      }
      final String separator = currentInstruction.isEmpty ? '' : '\n';
      subAgent.instruction =
          '$currentInstruction$separator$_taskCompletedInstruction';
    }
  }

  bool _ensureTaskCompletedTool(LlmAgent agent) {
    final bool hasTaskCompletedTool = agent.tools.any((Object tool) {
      if (tool is BaseTool) {
        return tool.name == _taskCompletedToolName;
      }
      final String toolLabel = '$tool';
      return toolLabel.contains(_taskCompletedToolName);
    });
    if (hasTaskCompletedTool) {
      return false;
    }

    agent.tools.add(
      FunctionTool(
        func: _taskCompleted,
        name: _taskCompletedToolName,
        description:
            'Signals that the agent has successfully completed the user\'s question or task.',
      ),
    );
    return true;
  }

  int _getStartIndex(SequentialAgentState? state) {
    if (state == null) {
      return 0;
    }

    if (state.currentSubAgent.isEmpty) {
      return subAgents.length;
    }

    final int index = subAgents.indexWhere(
      (BaseAgent agent) => agent.name == state.currentSubAgent,
    );
    return index >= 0 ? index : 0;
  }
}
