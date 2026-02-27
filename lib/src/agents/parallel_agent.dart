import 'dart:async';

import '../events/event.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

class ParallelAgent extends BaseAgent {
  ParallelAgent({
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  });

  @override
  ParallelAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> cloneUpdate = normalizeCloneUpdate(update);
    validateCloneUpdateFields(
      update: cloneUpdate,
      allowedFields: BaseAgent.baseCloneUpdateFields,
    );

    final List<BaseAgent> clonedSubAgents = cloneSubAgentsField(cloneUpdate);
    final ParallelAgent clonedAgent = ParallelAgent(
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

    final BaseAgentState? agentState = loadAgentState(context);
    if (context.isResumable && agentState == null) {
      context.setAgentState(name, agentState: BaseAgentState());
      yield createAgentStateEvent(context);
    }

    final Map<int, _PendingSubAgentRun> running = <int, _PendingSubAgentRun>{};

    for (int index = 0; index < subAgents.length; index += 1) {
      final BaseAgent subAgent = subAgents[index];
      final InvocationContext subAgentContext = _createBranchContextForSubAgent(
        subAgent,
        context,
      );

      if (subAgentContext.endOfAgents[subAgent.name] == true) {
        continue;
      }

      final StreamIterator<Event> iterator = StreamIterator<Event>(
        subAgent.runAsync(subAgentContext),
      );
      running[index] = _PendingSubAgentRun(
        iterator: iterator,
        pending: _nextResult(index, iterator),
      );
    }

    bool pauseInvocation = false;

    try {
      while (running.isNotEmpty) {
        final _ParallelResult result = await Future.any<_ParallelResult>(
          running.values
              .map((_PendingSubAgentRun run) => run.pending)
              .toList(growable: false),
        );

        final _PendingSubAgentRun? current = running[result.index];
        if (current == null) {
          continue;
        }

        if (!result.hasEvent) {
          running.remove(result.index);
          continue;
        }

        final Event event = result.event!;
        _syncSubAgentStateFromEvent(context, event);
        yield event;
        if (context.shouldPauseInvocation(event)) {
          pauseInvocation = true;
          break;
        }

        current.pending = _nextResult(result.index, current.iterator);
      }
    } finally {
      for (final _PendingSubAgentRun run in running.values) {
        await run.iterator.cancel();
      }
    }

    if (pauseInvocation) {
      return;
    }

    if (context.isResumable &&
        subAgents.every(
          (BaseAgent subAgent) => context.endOfAgents[subAgent.name] == true,
        )) {
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

  InvocationContext _createBranchContextForSubAgent(
    BaseAgent subAgent,
    InvocationContext context,
  ) {
    final String branchSuffix = '$name.${subAgent.name}';
    final String? branch = context.branch;
    final String nextBranch = branch == null || branch.isEmpty
        ? branchSuffix
        : '$branch.$branchSuffix';
    final InvocationContext subAgentContext = context.copyWith(
      branch: nextBranch,
    );
    subAgentContext.agentStates = context.agentStates;
    subAgentContext.endOfAgents = context.endOfAgents;
    return subAgentContext;
  }

  Future<_ParallelResult> _nextResult(
    int index,
    StreamIterator<Event> iterator,
  ) async {
    final bool hasEvent = await iterator.moveNext();
    return _ParallelResult(
      index: index,
      hasEvent: hasEvent,
      event: hasEvent ? iterator.current : null,
    );
  }

  void _syncSubAgentStateFromEvent(InvocationContext context, Event event) {
    if (event.actions.endOfAgent == true) {
      context.endOfAgents[event.author] = true;
      context.agentStates.remove(event.author);
      return;
    }

    if (event.actions.agentState != null) {
      context.agentStates[event.author] = Map<String, Object?>.from(
        event.actions.agentState!,
      );
      context.endOfAgents[event.author] = false;
      return;
    }

    if (event.author != 'user' &&
        event.content != null &&
        !context.agentStates.containsKey(event.author)) {
      context.agentStates[event.author] = <String, Object?>{};
      context.endOfAgents[event.author] = false;
    }
  }
}

class _PendingSubAgentRun {
  _PendingSubAgentRun({required this.iterator, required this.pending});

  final StreamIterator<Event> iterator;
  Future<_ParallelResult> pending;
}

class _ParallelResult {
  _ParallelResult({
    required this.index,
    required this.hasEvent,
    required this.event,
  });

  final int index;
  final bool hasEvent;
  final Event? event;
}
