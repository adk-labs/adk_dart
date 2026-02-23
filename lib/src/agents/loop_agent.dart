import '../events/event.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

class LoopAgentState extends BaseAgentState {
  LoopAgentState({this.currentSubAgent = '', this.timesLooped = 0})
    : super(
        data: <String, Object?>{
          'current_sub_agent': currentSubAgent,
          'times_looped': timesLooped,
        },
      );

  final String currentSubAgent;
  final int timesLooped;

  factory LoopAgentState.fromBase(BaseAgentState state) {
    final Map<String, Object?> json = state.toJson();
    return LoopAgentState(
      currentSubAgent: (json['current_sub_agent'] as String?) ?? '',
      timesLooped: (json['times_looped'] as int?) ?? 0,
    );
  }
}

class LoopAgent extends BaseAgent {
  LoopAgent({
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
    this.maxIterations,
  });

  final int? maxIterations;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    if (subAgents.isEmpty) {
      return;
    }

    final BaseAgentState? rawState = loadAgentState(context);
    final LoopAgentState? state = rawState == null
        ? null
        : LoopAgentState.fromBase(rawState);

    bool isResumingAtCurrentAgent = state != null;
    final (int timesLoopedStart, int startIndexStart) = _getStartState(state);
    int timesLooped = timesLoopedStart;
    int startIndex = startIndexStart;

    bool shouldExit = false;
    bool pauseInvocation = false;

    while ((maxIterations == null || timesLooped < maxIterations!) &&
        !(shouldExit || pauseInvocation)) {
      for (int index = startIndex; index < subAgents.length; index += 1) {
        final BaseAgent subAgent = subAgents[index];

        if (context.isResumable && !isResumingAtCurrentAgent) {
          context.setAgentState(
            name,
            agentState: LoopAgentState(
              currentSubAgent: subAgent.name,
              timesLooped: timesLooped,
            ),
          );
          yield createAgentStateEvent(context);
        }

        isResumingAtCurrentAgent = false;

        await for (final Event event in subAgent.runAsync(context)) {
          yield event;
          if (event.actions.escalate == true) {
            shouldExit = true;
          }
          if (context.shouldPauseInvocation(event)) {
            pauseInvocation = true;
          }
        }

        if (context.endInvocation || shouldExit || pauseInvocation) {
          break;
        }
      }

      startIndex = 0;
      timesLooped += 1;
      context.resetSubAgentStates(name);

      if (context.endInvocation) {
        return;
      }
    }

    if (pauseInvocation) {
      return;
    }

    if (context.isResumable) {
      context.setAgentState(name, endOfAgent: true);
      yield createAgentStateEvent(context);
    }
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    await for (final Event event in runAsyncImpl(context)) {
      yield event;
    }
  }

  (int, int) _getStartState(LoopAgentState? state) {
    if (state == null) {
      return (0, 0);
    }

    int startIndex = 0;
    if (state.currentSubAgent.isNotEmpty) {
      final int index = subAgents.indexWhere(
        (BaseAgent subAgent) => subAgent.name == state.currentSubAgent,
      );
      if (index >= 0) {
        startIndex = index;
      }
    }
    return (state.timesLooped, startIndex);
  }
}
