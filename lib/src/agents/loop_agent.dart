/// Loop-based workflow agent implementations.
library;

import '../events/event.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

/// Serialized resumability state for [LoopAgent].
class LoopAgentState extends BaseAgentState {
  /// Creates a loop-agent state snapshot.
  LoopAgentState({this.currentSubAgent = '', this.timesLooped = 0})
    : super(
        data: <String, Object?>{
          'current_sub_agent': currentSubAgent,
          'times_looped': timesLooped,
        },
      );

  /// Sub-agent currently selected for execution.
  final String currentSubAgent;

  /// Number of completed loop iterations.
  final int timesLooped;

  /// Creates a typed loop state from base [state] data.
  factory LoopAgentState.fromBase(BaseAgentState state) {
    final Map<String, Object?> json = state.toJson();
    return LoopAgentState(
      currentSubAgent: (json['current_sub_agent'] as String?) ?? '',
      timesLooped: (json['times_looped'] as int?) ?? 0,
    );
  }
}

/// Workflow agent that iterates through sub-agents repeatedly.
class LoopAgent extends BaseAgent {
  /// Creates a loop agent.
  LoopAgent({
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
    this.maxIterations,
  });

  /// Maximum number of loop iterations.
  ///
  /// `null` or `0` indicates no iteration limit.
  final int? maxIterations;

  /// Returns a cloned loop agent with optional field overrides.
  @override
  LoopAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> cloneUpdate = normalizeCloneUpdate(update);
    validateCloneUpdateFields(
      update: cloneUpdate,
      allowedFields: <String>{
        ...BaseAgent.baseCloneUpdateFields,
        'maxIterations',
      },
    );

    final List<BaseAgent> clonedSubAgents = cloneSubAgentsField(cloneUpdate);
    final LoopAgent clonedAgent = LoopAgent(
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
      maxIterations: cloneFieldValue<int?>(
        update: cloneUpdate,
        fieldName: 'maxIterations',
        currentValue: maxIterations,
      ),
    );
    clonedAgent.subAgents = clonedSubAgents;
    relinkClonedSubAgents(clonedAgent);
    return clonedAgent;
  }

  /// Runs sub-agents in repeated loops until completion or stop conditions.
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

    while ((_hasNoIterationLimit || timesLooped < maxIterations!) &&
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

  /// Runs live mode using async loop execution semantics.
  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    await for (final Event event in runAsyncImpl(context)) {
      yield event;
    }
  }

  bool get _hasNoIterationLimit => maxIterations == null || maxIterations == 0;

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
