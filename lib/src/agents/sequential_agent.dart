import '../events/event.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

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

    for (final BaseAgent subAgent in subAgents) {
      await for (final Event event in subAgent.runLive(context)) {
        yield event;
      }
    }
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
