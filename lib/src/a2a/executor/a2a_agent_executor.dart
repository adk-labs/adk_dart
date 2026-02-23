import 'dart:async';

import '../../agents/invocation_context.dart';
import '../../agents/run_config.dart';
import '../../events/event.dart';
import '../../runners/runner.dart';
import '../../sessions/session.dart';
import '../converters/event_converter.dart';
import '../converters/part_converter.dart';
import '../converters/request_converter.dart';
import '../converters/utils.dart';
import '../protocol.dart';
import 'task_result_aggregator.dart';

class A2aAgentExecutorConfig {
  A2aAgentExecutorConfig({
    A2APartToGenAIPartConverter? a2aPartConverter,
    GenAIPartToA2APartConverter? genAiPartConverter,
    A2ARequestToAgentRunRequestConverter? requestConverter,
    AdkEventToA2AEventsConverter? eventConverter,
  }) : a2aPartConverter = a2aPartConverter ?? convertA2aPartToGenaiPart,
       genAiPartConverter = genAiPartConverter ?? convertGenaiPartToA2aPart,
       requestConverter =
           requestConverter ??
           ((A2aRequestContext request, A2APartToGenAIPartConverter converter) {
             return convertA2aRequestToAgentRunRequest(
               request,
               partConverter: converter,
             );
           }),
       eventConverter =
           eventConverter ??
           ((
             Event event,
             InvocationContext invocationContext,
             String? taskId,
             String? contextId,
             GenAIPartToA2APartConverter partConverter,
           ) {
             return convertEventToA2aEvents(
               event,
               invocationContext,
               taskId: taskId,
               contextId: contextId,
               partConverter: partConverter,
             );
           });

  A2APartToGenAIPartConverter a2aPartConverter;
  GenAIPartToA2APartConverter genAiPartConverter;
  A2ARequestToAgentRunRequestConverter requestConverter;
  AdkEventToA2AEventsConverter eventConverter;
}

class A2aAgentExecutor {
  A2aAgentExecutor({required Object runner, A2aAgentExecutorConfig? config})
    : _runner = runner,
      _config = config ?? A2aAgentExecutorConfig();

  Object _runner;
  final A2aAgentExecutorConfig _config;

  Future<Runner> _resolveRunner() async {
    if (_runner is Runner) {
      return _runner as Runner;
    }

    if (_runner is FutureOr<Runner> Function()) {
      final FutureOr<Runner> resolved =
          (_runner as FutureOr<Runner> Function())();
      final Runner runner = await Future<Runner>.value(resolved);
      _runner = runner;
      return runner;
    }

    if (_runner is Function) {
      final Object? resolved = await Future<Object?>.value(
        Function.apply(_runner as Function, const <Object>[]),
      );
      if (resolved is Runner) {
        _runner = resolved;
        return resolved;
      }
    }

    throw ArgumentError(
      'Runner must be a Runner instance or zero-arg callable that returns Runner.',
    );
  }

  Future<void> cancel(A2aRequestContext context, A2aEventQueue eventQueue) {
    throw UnsupportedError('Cancellation is not supported.');
  }

  Future<void> execute(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
  ) async {
    if (context.message == null) {
      throw ArgumentError('A2A request must include a message.');
    }

    if (context.currentTask == null) {
      await eventQueue.enqueueEvent(
        A2aTaskStatusUpdateEvent(
          taskId: context.taskId,
          contextId: context.contextId,
          status: A2aTaskStatus(
            state: A2aTaskState.submitted,
            message: context.message,
          ),
          finalEvent: false,
        ),
      );
    }

    try {
      await _handleRequest(context, eventQueue);
    } catch (error) {
      await eventQueue.enqueueEvent(
        A2aTaskStatusUpdateEvent(
          taskId: context.taskId,
          contextId: context.contextId,
          finalEvent: true,
          status: A2aTaskStatus(
            state: A2aTaskState.failed,
            message: A2aMessage(
              messageId: 'a2a_failure_${DateTime.now().microsecondsSinceEpoch}',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('$error')],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _handleRequest(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
  ) async {
    final Runner runner = await _resolveRunner();

    final AgentRunRequest runRequest = _config.requestConverter(
      context,
      _config.a2aPartConverter,
    );

    final Session session = await _prepareSession(context, runRequest, runner);
    runRequest.invocationId ??=
        'a2a_invocation_${DateTime.now().microsecondsSinceEpoch}';

    final InvocationContext invocationContext = InvocationContext(
      artifactService: runner.artifactService,
      sessionService: runner.sessionService,
      memoryService: runner.memoryService,
      credentialService: runner.credentialService,
      contextCacheConfig: runner.contextCacheConfig,
      invocationId: runRequest.invocationId!,
      agent: runner.agent,
      userContent: runRequest.newMessage,
      session: session,
      runConfig: runRequest.runConfig ?? RunConfig(),
      resumabilityConfig: runner.resumabilityConfig,
      pluginManager: runner.pluginManager,
    );

    await eventQueue.enqueueEvent(
      A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: false,
        status: A2aTaskStatus(state: A2aTaskState.working),
        metadata: <String, Object?>{
          getAdkMetadataKey('app_name'): runner.appName,
          getAdkMetadataKey('user_id'): runRequest.userId,
          getAdkMetadataKey('session_id'): runRequest.sessionId,
        },
      ),
    );

    final TaskResultAggregator taskResultAggregator = TaskResultAggregator();
    final bool resumable = runner.resumabilityConfig?.isResumable ?? false;
    final String? invocationIdForRunAsync = resumable
        ? runRequest.invocationId
        : null;

    await for (final Event adkEvent in runner.runAsync(
      userId: runRequest.userId!,
      sessionId: runRequest.sessionId!,
      invocationId: invocationIdForRunAsync,
      newMessage: runRequest.newMessage,
      stateDelta: runRequest.stateDelta,
      runConfig: runRequest.runConfig,
    )) {
      final List<A2aEvent> a2aEvents = _config.eventConverter(
        adkEvent,
        invocationContext,
        context.taskId,
        context.contextId,
        _config.genAiPartConverter,
      );

      for (final A2aEvent a2aEvent in a2aEvents) {
        taskResultAggregator.processEvent(a2aEvent);
        await eventQueue.enqueueEvent(a2aEvent);
      }
    }

    if (taskResultAggregator.taskState == A2aTaskState.working &&
        taskResultAggregator.taskStatusMessage != null &&
        taskResultAggregator.taskStatusMessage!.parts.isNotEmpty) {
      await eventQueue.enqueueEvent(
        A2aTaskArtifactUpdateEvent(
          taskId: context.taskId,
          contextId: context.contextId,
          lastChunk: true,
          artifact: A2aArtifact(
            artifactId: 'a2a_artifact_${DateTime.now().microsecondsSinceEpoch}',
            parts: taskResultAggregator.taskStatusMessage!.parts,
          ),
        ),
      );

      await eventQueue.enqueueEvent(
        A2aTaskStatusUpdateEvent(
          taskId: context.taskId,
          contextId: context.contextId,
          finalEvent: true,
          status: A2aTaskStatus(state: A2aTaskState.completed),
        ),
      );
      return;
    }

    await eventQueue.enqueueEvent(
      A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: true,
        status: A2aTaskStatus(
          state: taskResultAggregator.taskState,
          message: taskResultAggregator.taskStatusMessage,
        ),
      ),
    );
  }

  Future<Session> _prepareSession(
    A2aRequestContext context,
    AgentRunRequest runRequest,
    Runner runner,
  ) async {
    final String userId =
        runRequest.userId ??
        context.callContext?.user?.userName ??
        'A2A_USER_${context.contextId}';
    final String sessionId = runRequest.sessionId ?? context.contextId;

    Session? session = await runner.sessionService.getSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
    );

    session ??= await runner.sessionService.createSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      state: <String, Object?>{},
    );

    runRequest.userId = userId;
    runRequest.sessionId = session.id;
    return session;
  }
}
