/// Execution bridge from A2A requests to ADK runner invocations.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../../agents/abort_signal.dart';
import '../../agents/invocation_context.dart';
import '../../agents/run_config.dart';
import '../../events/abort_events.dart';
import '../../events/event.dart';
import '../../events/node_path_builder.dart';
import '../../platform/uuid.dart';
import '../../runners/runner.dart';
import '../../sessions/session.dart';
import '../../types/content.dart';
import '../converters/event_converter.dart';
import '../converters/long_running_functions.dart';
import '../converters/part_converter.dart';
import '../converters/request_converter.dart';
import '../converters/utils.dart';
import '../protocol.dart';
import 'task_result_aggregator.dart';

bool _isErrorEvent(Event event) {
  return (event.errorCode != null && event.errorCode!.isNotEmpty) ||
      (event.errorMessage != null && event.errorMessage!.isNotEmpty);
}

bool _isRootAgentEvent(Event event) {
  if (event.branch != null && event.branch!.isNotEmpty) {
    return false;
  }
  final String path = event.nodeInfo.path;
  if (path.isEmpty) {
    return true;
  }
  return NodePathBuilder.fromString(path).parent == null;
}

bool _hasResultPayload(Event event) {
  if (event.output != null) {
    return true;
  }
  final List<Part>? parts = event.content?.parts;
  if (parts == null || parts.isEmpty) {
    return false;
  }
  return parts.any(
    (Part part) =>
        !part.thought &&
        ((part.text != null && part.text!.trim().isNotEmpty) ||
            part.inlineData != null ||
            part.fileData != null),
  );
}

bool _isSuccessfulResult(Event event) {
  return event.author != 'user' &&
      event.partial != true &&
      !_isErrorEvent(event) &&
      _hasResultPayload(event) &&
      event.isFinalResponse();
}

bool _isInBranchScope(String? branch, String? scope) {
  if (scope == null || scope.isEmpty) {
    return true;
  }
  if (branch == null || branch.isEmpty) {
    return false;
  }
  return branch == scope || branch.startsWith('$scope.');
}

/// Tracks sub-agent error events and clears them when the enclosing scope
/// subsequently produces a successful final response.
class ErrorRecoveryTracker {
  final List<Event> _unresolvedErrors = <Event>[];

  /// Observes one streamed ADK [event] to record or resolve errors.
  void observe(Event event) {
    if (_isErrorEvent(event)) {
      _unresolvedErrors.add(event);
      return;
    }
    if (_isSuccessfulResult(event)) {
      _unresolvedErrors.removeWhere(
        (Event error) =>
            !_isRootAgentEvent(error) &&
            _isInBranchScope(error.branch, event.branch),
      );
    }
  }

  /// Whether [event] remains an unresolved error event.
  bool isUnresolved(Event event) =>
      _unresolvedErrors.any((Event item) => identical(item, event));

  /// Most recent unresolved error event, if any.
  Event? get unresolvedError =>
      _unresolvedErrors.isNotEmpty ? _unresolvedErrors.last : null;
}

/// Logs an uncaught executor [error] with a correlation ID and returns a
/// sanitized failure message for remote A2A peers.
String reportA2aExecutorError(
  Object error, [
  StackTrace? stackTrace,
  bool? debugErrorsOverride,
]) {
  final String rawUuid = newUuid().replaceAll('-', '');
  final String errorId = rawUuid.length >= 12
      ? rawUuid.substring(0, 12)
      : rawUuid.padRight(12, '0');
  developer.log(
    'Error handling A2A request [error_id=$errorId]: $error',
    name: 'adk_dart.a2a_agent_executor',
    error: error,
    stackTrace: stackTrace,
  );
  final bool debugErrors =
      debugErrorsOverride ?? _isDebugErrorsEnabledFromEnv();
  if (debugErrors) {
    return 'Agent execution failed. (error_id: $errorId): ${error.runtimeType}: $error';
  }
  return 'Agent execution failed. (error_id: $errorId)';
}

bool _isDebugErrorsEnabledFromEnv() {
  try {
    final String? raw = Platform.environment['ADK_DEBUG_ERRORS'];
    if (raw == null) {
      return false;
    }
    final String normalized = raw.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  } catch (_) {
    return false;
  }
}

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

class _ActiveTaskRun {
  _ActiveTaskRun({required this.taskId, required this.eventQueue});

  final String taskId;
  final A2aEventQueue eventQueue;
  final AdkAbortSignal abortSignal = AdkAbortSignal();
  final Completer<void> done = Completer<void>();
  bool terminalCancelEmitted = false;
}

class _ActiveTaskRegistry {
  final Map<String, _ActiveTaskRun> _runs = <String, _ActiveTaskRun>{};

  _ActiveTaskRun start(String taskId, A2aEventQueue eventQueue) {
    final _ActiveTaskRun run = _ActiveTaskRun(
      taskId: taskId,
      eventQueue: eventQueue,
    );
    if (taskId.isNotEmpty) {
      _runs[taskId] = run;
    }
    return run;
  }

  _ActiveTaskRun? get(String taskId) => _runs[taskId];

  void finish(_ActiveTaskRun run) {
    if (_runs[run.taskId] == run) {
      _runs.remove(run.taskId);
    }
    if (!run.done.isCompleted) {
      run.done.complete();
    }
  }

  Future<void> cancel(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
  ) async {
    final String taskId = context.taskId;
    final _ActiveTaskRun? activeRun = _runs[taskId];
    if (activeRun == null) {
      final A2aTaskState? currentState = context.currentTask?.status.state;
      if (currentState == A2aTaskState.completed ||
          currentState == A2aTaskState.failed ||
          currentState == A2aTaskState.canceled) {
        return;
      }
      await _enqueueCancelEvent(
        eventQueue,
        taskId: taskId,
        contextId: context.contextId,
      );
      return;
    }

    final bool sameQueue = _sharesDeliveryPath(
      activeRun.eventQueue,
      eventQueue,
    );
    activeRun.abortSignal.abort();
    await activeRun.done.future;
    if (!activeRun.terminalCancelEmitted || !sameQueue) {
      await _enqueueCancelEvent(
        eventQueue,
        taskId: taskId,
        contextId: context.contextId,
      );
    }
  }

  static bool _sharesDeliveryPath(A2aEventQueue a, A2aEventQueue b) {
    return identical(a, b);
  }

  static Future<void> _enqueueCancelEvent(
    A2aEventQueue eventQueue, {
    required String taskId,
    required String contextId,
  }) async {
    try {
      await eventQueue.enqueueEvent(
        A2aTaskStatusUpdateEvent(
          taskId: taskId,
          contextId: contextId,
          status: A2aTaskStatus(
            state: A2aTaskState.canceled,
            message: A2aMessage(
              messageId: 'a2a_cancel_${newUuid()}',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('Task cancellation requested.')],
            ),
          ),
          metadata: <String, Object?>{
            getAdkMetadataKey('cancel_requested'): true,
          },
          finalEvent: true,
        ),
      );
    } catch (_) {
      // Best-effort enqueue when eventQueue is already closed or failing.
    }
  }
}

/// Executes A2A requests by delegating to an ADK [Runner].
class A2aAgentExecutor {
  /// Creates an A2A executor.
  A2aAgentExecutor({required Object runner, A2aAgentExecutorConfig? config})
    : _runner = runner,
      _config = config ?? A2aAgentExecutorConfig();

  Object _runner;
  final A2aAgentExecutorConfig _config;
  final _ActiveTaskRegistry _activeTasks = _ActiveTaskRegistry();

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

  /// Cancels an active task or emits a terminal `canceled` event if inactive.
  Future<void> cancel(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
  ) async {
    if (context.taskId.isEmpty) {
      throw ArgumentError('Task ID is required for task cancellation.');
    }
    await _activeTasks.cancel(context, eventQueue);
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

    final _ActiveTaskRun activeRun = _activeTasks.start(
      context.taskId,
      eventQueue,
    );
    try {
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
        await _handleRequest(context, eventQueue, activeRun);
      } catch (error, stackTrace) {
        if (activeRun.abortSignal.aborted || error is AdkAbortException) {
          if (!activeRun.terminalCancelEmitted) {
            await eventQueue.enqueueEvent(
              A2aTaskStatusUpdateEvent(
                taskId: context.taskId,
                contextId: context.contextId,
                finalEvent: true,
                status: A2aTaskStatus(state: A2aTaskState.canceled),
              ),
            );
            activeRun.terminalCancelEmitted = true;
          }
          return;
        }
        final String failureText = reportA2aExecutorError(error, stackTrace);
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
                parts: <A2aPart>[A2aPart.text(failureText)],
              ),
            ),
          ),
        );
      }
    } finally {
      _activeTasks.finish(activeRun);
    }
  }

  Future<void> _handleRequest(
    A2aRequestContext context,
    A2aEventQueue eventQueue,
    _ActiveTaskRun activeRun,
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
      abortSignal: activeRun.abortSignal,
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
    final ErrorRecoveryTracker errorTracker = ErrorRecoveryTracker();
    final List<(Event?, A2aMessage?)> failures = <(Event?, A2aMessage?)>[];
    final LongRunningFunctions longRunningFunctions = LongRunningFunctions(
      partConverter: _config.genAiPartConverter,
    );
    final bool resumable = runner.resumabilityConfig?.isResumable ?? false;
    final String? invocationIdForRunAsync = resumable
        ? runRequest.invocationId
        : null;

    bool aborted = activeRun.abortSignal.aborted;
    final Stream<Event> eventStream = runner.runAsync(
      userId: runRequest.userId!,
      sessionId: runRequest.sessionId!,
      invocationId: invocationIdForRunAsync,
      newMessage: runRequest.newMessage,
      stateDelta: runRequest.stateDelta,
      runConfig: runRequest.runConfig,
      abortSignal: activeRun.abortSignal,
    );

    await _consumeRunnerWithAbort(
      eventStream: eventStream,
      abortSignal: activeRun.abortSignal,
      onEvent: (Event adkEvent) async {
        if (isAbortEvent(adkEvent) || activeRun.abortSignal.aborted) {
          aborted = true;
        }
        errorTracker.observe(adkEvent);
        final bool isErrorEvent = _isErrorEvent(adkEvent);
        final Event processedEvent = longRunningFunctions.processEvent(
          adkEvent,
        );
        final List<A2aEvent> a2aEvents = _config.eventConverter(
          processedEvent,
          invocationContext,
          context.taskId,
          context.contextId,
          _config.genAiPartConverter,
        );

        for (final A2aEvent a2aEvent in a2aEvents) {
          final A2aEvent? interceptedEvent =
              await _executeAfterEventInterceptors(
                a2aEvent: a2aEvent,
                executorContext: executorContext,
                adkEvent: processedEvent,
              );
          if (interceptedEvent == null) {
            continue;
          }
          if (interceptedEvent is A2aTaskStatusUpdateEvent &&
              interceptedEvent.status.state == A2aTaskState.failed) {
            failures.add((
              isErrorEvent ? adkEvent : null,
              interceptedEvent.status.message,
            ));
          }
          taskResultAggregator.processEvent(interceptedEvent);
          await eventQueue.enqueueEvent(interceptedEvent);
        }
      },
    );
    if (activeRun.abortSignal.aborted) {
      aborted = true;
    }

    if (taskResultAggregator.taskState == A2aTaskState.failed) {
      taskResultAggregator.keepFailures(<A2aMessage?>[
        for (final (Event? source, A2aMessage? message) in failures)
          if (source == null || errorTracker.isUnresolved(source)) message,
      ]);
    }

    A2aTaskStatusUpdateEvent finalEvent;
    final A2aTaskStatusUpdateEvent? longRunningFinalEvent = longRunningFunctions
        .createLongRunningFunctionCallEvent(
          taskId: context.taskId,
          contextId: context.contextId,
        );
    if (aborted && taskResultAggregator.taskState != A2aTaskState.canceled) {
      finalEvent = A2aTaskStatusUpdateEvent(
        taskId: context.taskId,
        contextId: context.contextId,
        finalEvent: true,
        status: A2aTaskStatus(state: A2aTaskState.canceled),
      );
    } else if (taskResultAggregator.taskState == A2aTaskState.canceled ||
        taskResultAggregator.taskState == A2aTaskState.failed) {
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
            metadata: Map<String, Object?>.from(
              taskResultAggregator.taskStatusMessage!.metadata,
            ),
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
    activeRun.terminalCancelEmitted =
        finalEvent.status.state == A2aTaskState.canceled;
    await eventQueue.enqueueEvent(finalEvent);
  }

  Future<void> _consumeRunnerWithAbort({
    required Stream<Event> eventStream,
    required AdkAbortSignal abortSignal,
    required Future<void> Function(Event event) onEvent,
  }) async {
    final Completer<void> done = Completer<void>();
    bool processingEvent = false;
    Timer? abortWatchdog;
    late final StreamSubscription<Event> subscription;

    void scheduleAbortWatchdog() {
      abortWatchdog?.cancel();
      abortWatchdog = Timer(Duration.zero, () async {
        if (done.isCompleted) {
          return;
        }
        if (processingEvent) {
          scheduleAbortWatchdog();
          return;
        }
        try {
          await subscription.cancel();
        } catch (_) {
          // Ignore errors during forced stream cancellation.
        }
        if (!done.isCompleted) {
          done.complete();
        }
      });
    }

    subscription = eventStream.listen(
      (Event event) async {
        processingEvent = true;
        subscription.pause();
        try {
          await onEvent(event);
        } catch (error, stackTrace) {
          if (!done.isCompleted) {
            done.completeError(error, stackTrace);
          }
          await subscription.cancel();
          return;
        } finally {
          processingEvent = false;
        }
        if (!done.isCompleted) {
          subscription.resume();
          if (abortSignal.aborted) {
            scheduleAbortWatchdog();
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!done.isCompleted) {
          done.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      cancelOnError: true,
    );

    abortSignal.addListener((Object? _) {
      if (!done.isCompleted) {
        scheduleAbortWatchdog();
      }
    });

    try {
      await done.future;
    } finally {
      abortWatchdog?.cancel();
      await subscription.cancel();
    }
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
