/// Execution bridge from A2A requests to ADK runner invocations.
library;

import 'dart:async';

import '../../agents/invocation_context.dart';
import '../../agents/run_config.dart';
import '../../events/event.dart';
import '../../platform/uuid.dart';
import '../../runners/runner.dart';
import '../../sessions/session.dart';
import '../converters/event_converter.dart';
import '../converters/long_running_functions.dart';
import '../converters/part_converter.dart';
import '../converters/request_converter.dart';
import '../converters/utils.dart';
import '../protocol.dart';
import 'task_result_aggregator.dart';

/// Hook executed before A2A requests are converted and run.
typedef A2aExecutorBeforeAgentInterceptor =
    FutureOr<A2aRequestContext> Function(A2aRequestContext context);

/// Hook executed after each ADK event is converted to an A2A event.
typedef A2aExecutorAfterEventInterceptor =
    FutureOr<A2aEvent?> Function(
      A2aExecutorContext executorContext,
      A2aEvent a2aEvent,
      Event adkEvent,
    );

/// Hook executed before emitting the final status update event.
typedef A2aExecutorAfterAgentInterceptor =
    FutureOr<A2aTaskStatusUpdateEvent> Function(
      A2aExecutorContext executorContext,
      A2aTaskStatusUpdateEvent finalEvent,
    );

/// Interceptor bundle used around executor lifecycle stages.
class A2aExecuteInterceptor {
  /// Creates an executor interceptor bundle.
  A2aExecuteInterceptor({this.beforeAgent, this.afterEvent, this.afterAgent});

  /// Pre-run request interceptor.
  final A2aExecutorBeforeAgentInterceptor? beforeAgent;

  /// Per-event post-conversion interceptor.
  final A2aExecutorAfterEventInterceptor? afterEvent;

  /// Final-event interceptor.
  final A2aExecutorAfterAgentInterceptor? afterAgent;
}

/// Immutable context passed to post-execution interceptors.
class A2aExecutorContext {
  /// Creates an executor context.
  A2aExecutorContext({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.runner,
  });

  /// Application name.
  final String appName;

  /// User identifier.
  final String userId;

  /// Session identifier.
  final String sessionId;

  /// Runner used for execution.
  final Runner runner;
}

/// Runtime configuration for [A2aAgentExecutor].
class A2aAgentExecutorConfig {
  /// Creates an executor config.
  A2aAgentExecutorConfig({
    A2APartToGenAIPartConverter? a2aPartConverter,
    GenAIPartToA2APartConverter? genAiPartConverter,
    A2ARequestToAgentRunRequestConverter? requestConverter,
    AdkEventToA2AEventsConverter? eventConverter,
    this.executeInterceptors,
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

  /// Converter from A2A parts to GenAI parts.
  A2APartToGenAIPartConverter a2aPartConverter;

  /// Converter from GenAI parts to A2A parts.
  GenAIPartToA2APartConverter genAiPartConverter;

  /// Converter from request context to runner request.
  A2ARequestToAgentRunRequestConverter requestConverter;

  /// Converter from ADK events to A2A events.
  AdkEventToA2AEventsConverter eventConverter;

  /// Optional execution interceptors.
  List<A2aExecuteInterceptor>? executeInterceptors;
}

/// Executes A2A requests by delegating to an ADK [Runner].
class A2aAgentExecutor {
  /// Creates an A2A executor.
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

  /// Attempts to cancel an in-flight A2A task.
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
              messageId: 'a2a_cancel_${newUuid()}',
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

  /// Executes [context] and emits converted events to [eventQueue].
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
              messageId: 'a2a_failure_${newUuid()}',
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
    runRequest.invocationId ??= 'a2a_invocation_${newUuid()}';

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

    final A2aExecutorContext executorContext = A2aExecutorContext(
      appName: runner.appName,
      userId: runRequest.userId!,
      sessionId: runRequest.sessionId!,
      runner: runner,
    );

    final A2aTaskStatusUpdateEvent? missingUserInputEvent = _handleUserInput(
      context,
      executorContext,
    );
    if (missingUserInputEvent != null) {
      await eventQueue.enqueueEvent(missingUserInputEvent);
      return;
    }

    await eventQueue.enqueueEvent(
      A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: false,
        status: A2aTaskStatus(state: A2aTaskState.working),
        metadata: _getInvocationMetadata(executorContext),
      ),
    );

    final TaskResultAggregator taskResultAggregator = TaskResultAggregator();
    final LongRunningFunctions longRunningFunctions = LongRunningFunctions(
      partConverter: _config.genAiPartConverter,
    );
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
      final Event processedEvent = longRunningFunctions.processEvent(adkEvent);
      final List<A2aEvent> a2aEvents = _config.eventConverter(
        processedEvent,
        invocationContext,
        context.taskId,
        context.contextId,
        _config.genAiPartConverter,
      );

      for (final A2aEvent a2aEvent in a2aEvents) {
        final A2aEvent? interceptedEvent = await _executeAfterEventInterceptors(
          a2aEvent: a2aEvent,
          executorContext: executorContext,
          adkEvent: processedEvent,
        );
        if (interceptedEvent == null) {
          continue;
        }
        taskResultAggregator.processEvent(interceptedEvent);
        await eventQueue.enqueueEvent(interceptedEvent);
      }
    }

    A2aTaskStatusUpdateEvent finalEvent;
    final A2aTaskStatusUpdateEvent? longRunningFinalEvent = longRunningFunctions
        .createLongRunningFunctionCallEvent(
          taskId: context.taskId,
          contextId: context.contextId,
        );
    if (taskResultAggregator.taskState == A2aTaskState.failed) {
      finalEvent = A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: true,
        status: A2aTaskStatus(
          state: taskResultAggregator.taskState,
          message: taskResultAggregator.taskStatusMessage,
        ),
      );
    } else if (longRunningFinalEvent != null) {
      finalEvent = longRunningFinalEvent;
    } else if (taskResultAggregator.taskState == A2aTaskState.working &&
        taskResultAggregator.taskStatusMessage != null &&
        taskResultAggregator.taskStatusMessage!.parts.isNotEmpty) {
      await eventQueue.enqueueEvent(
        A2aTaskArtifactUpdateEvent(
          taskId: context.taskId,
          contextId: context.contextId,
          lastChunk: true,
          artifact: A2aArtifact(
            artifactId: 'a2a_artifact_${newUuid()}',
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

    finalEvent.metadata = _getInvocationMetadata(executorContext);

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

  Map<String, Object?> _getInvocationMetadata(
    A2aExecutorContext executorContext,
  ) {
    return <String, Object?>{
      getAdkMetadataKey('app_name'): executorContext.appName,
      getAdkMetadataKey('user_id'): executorContext.userId,
      getAdkMetadataKey('session_id'): executorContext.sessionId,
      getAdkMetadataKey('agent_executor_v2'): true,
    };
  }

  A2aTaskStatusUpdateEvent? _handleUserInput(
    A2aRequestContext context,
    A2aExecutorContext executorContext,
  ) {
    final A2aTask? currentTask = context.currentTask;
    final A2aTaskState? state = currentTask?.status.state;
    if (state != A2aTaskState.inputRequired &&
        state != A2aTaskState.authRequired) {
      return null;
    }

    final A2aMessage? message = context.message;
    if (message == null || _hasFunctionResponsePart(message) == false) {
      return A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: true,
        metadata: _getInvocationMetadata(executorContext),
        status: A2aTaskStatus(
          state: state!,
          message: A2aMessage(
            messageId: 'a2a_missing_function_response_${newUuid()}',
            role: A2aRole.agent,
            parts: <A2aPart>[
              A2aPart.text(
                'It was not provided a function response for the function call.',
              ),
            ],
          ),
        ),
      );
    }

    return null;
  }

  bool _hasFunctionResponsePart(A2aMessage message) {
    for (final A2aPart a2aPart in message.parts) {
      final A2aDataPart? dataPart = a2aPart.dataPart;
      if (dataPart == null) {
        continue;
      }
      if (dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)] ==
          a2aDataPartMetadataTypeFunctionResponse) {
        return true;
      }
    }
    return false;
  }
}
