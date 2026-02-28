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

typedef A2aExecutorBeforeAgentInterceptor =
    FutureOr<A2aRequestContext> Function(A2aRequestContext context);
typedef A2aExecutorAfterEventInterceptor =
    FutureOr<A2aEvent?> Function(
      A2aExecutorContext executorContext,
      A2aEvent a2aEvent,
      Event adkEvent,
    );
typedef A2aExecutorAfterAgentInterceptor =
    FutureOr<A2aTaskStatusUpdateEvent> Function(
      A2aExecutorContext executorContext,
      A2aTaskStatusUpdateEvent finalEvent,
    );

class A2aExecuteInterceptor {
  A2aExecuteInterceptor({this.beforeAgent, this.afterEvent, this.afterAgent});

  final A2aExecutorBeforeAgentInterceptor? beforeAgent;
  final A2aExecutorAfterEventInterceptor? afterEvent;
  final A2aExecutorAfterAgentInterceptor? afterAgent;
}

class A2aExecutorContext {
  A2aExecutorContext({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.runner,
  });

  final String appName;
  final String userId;
  final String sessionId;
  final Runner runner;
}

class A2aAgentExecutorConfig {
  A2aAgentExecutorConfig({
    A2APartToGenAIPartConverter? a2aPartConverter,
    GenAIPartToA2APartConverter? genAiPartConverter,
    A2ARequestToAgentRunRequestConverter? requestConverter,
    AdkEventToA2AEventsConverter? eventConverter,
    List<A2aExecuteInterceptor>? executeInterceptors,
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
           }),
       executeInterceptors = executeInterceptors;

  A2APartToGenAIPartConverter a2aPartConverter;
  GenAIPartToA2APartConverter genAiPartConverter;
  A2ARequestToAgentRunRequestConverter requestConverter;
  AdkEventToA2AEventsConverter eventConverter;
  List<A2aExecuteInterceptor>? executeInterceptors;
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

  Future<void> cancel(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
  ) async {
    final A2aTaskState? currentState = context.currentTask?.status.state;
    if (currentState == A2aTaskState.completed ||
        currentState == A2aTaskState.failed) {
      return;
    }

    try {
      await eventQueue.enqueueEvent(
        A2aTaskStatusUpdateEvent(
          taskId: context.taskId,
          contextId: context.contextId,
          finalEvent: true,
          status: A2aTaskStatus(
            state: A2aTaskState.failed,
            message: A2aMessage(
              messageId: 'a2a_cancel_${DateTime.now().microsecondsSinceEpoch}',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('Task cancellation requested.')],
            ),
          ),
          metadata: <String, Object?>{
            getAdkMetadataKey('cancel_requested'): true,
          },
        ),
      );
    } catch (_) {
      // Cancellation is best effort; swallowing queue failures keeps the
      // cancel path safe for callers.
    }
  }

  Future<void> execute(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
  ) async {
    if (context.message == null) {
      throw ArgumentError('A2A request must include a message.');
    }
    context = await _executeBeforeAgentInterceptors(context);

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

    final A2aExecutorContext executorContext = A2aExecutorContext(
      appName: runner.appName,
      userId: runRequest.userId!,
      sessionId: runRequest.sessionId!,
      runner: runner,
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
        final A2aEvent? interceptedEvent = await _executeAfterEventInterceptors(
          a2aEvent: a2aEvent,
          executorContext: executorContext,
          adkEvent: adkEvent,
        );
        if (interceptedEvent == null) {
          continue;
        }
        taskResultAggregator.processEvent(interceptedEvent);
        await eventQueue.enqueueEvent(interceptedEvent);
      }
    }

    A2aTaskStatusUpdateEvent finalEvent;
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

      finalEvent = A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: true,
        status: A2aTaskStatus(state: A2aTaskState.completed),
      );
    } else {
      finalEvent = A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: true,
        status: A2aTaskStatus(
          state: taskResultAggregator.taskState,
          message: taskResultAggregator.taskStatusMessage,
        ),
      );
    }

    finalEvent = await _executeAfterAgentInterceptors(
      executorContext,
      finalEvent,
    );
    await eventQueue.enqueueEvent(finalEvent);
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

  Future<A2aRequestContext> _executeBeforeAgentInterceptors(
    A2aRequestContext context,
  ) async {
    final List<A2aExecuteInterceptor>? interceptors =
        _config.executeInterceptors;
    if (interceptors == null || interceptors.isEmpty) {
      return context;
    }
    A2aRequestContext current = context;
    for (final A2aExecuteInterceptor interceptor in interceptors) {
      final A2aExecutorBeforeAgentInterceptor? handler =
          interceptor.beforeAgent;
      if (handler == null) {
        continue;
      }
      current = await Future<A2aRequestContext>.value(handler(current));
    }
    return current;
  }

  Future<A2aEvent?> _executeAfterEventInterceptors({
    required A2aEvent a2aEvent,
    required A2aExecutorContext executorContext,
    required Event adkEvent,
  }) async {
    final List<A2aExecuteInterceptor>? interceptors =
        _config.executeInterceptors;
    if (interceptors == null || interceptors.isEmpty) {
      return a2aEvent;
    }
    A2aEvent? current = a2aEvent;
    for (final A2aExecuteInterceptor interceptor in interceptors) {
      final A2aExecutorAfterEventInterceptor? handler = interceptor.afterEvent;
      if (handler == null || current == null) {
        continue;
      }
      current = await Future<A2aEvent?>.value(
        handler(executorContext, current, adkEvent),
      );
      if (current == null) {
        return null;
      }
    }
    return current;
  }

  Future<A2aTaskStatusUpdateEvent> _executeAfterAgentInterceptors(
    A2aExecutorContext executorContext,
    A2aTaskStatusUpdateEvent finalEvent,
  ) async {
    final List<A2aExecuteInterceptor>? interceptors =
        _config.executeInterceptors;
    if (interceptors == null || interceptors.isEmpty) {
      return finalEvent;
    }
    A2aTaskStatusUpdateEvent current = finalEvent;
    for (final A2aExecuteInterceptor interceptor in interceptors.reversed) {
      final A2aExecutorAfterAgentInterceptor? handler = interceptor.afterAgent;
      if (handler == null) {
        continue;
      }
      current = await Future<A2aTaskStatusUpdateEvent>.value(
        handler(executorContext, current),
      );
    }
    return current;
  }
}
