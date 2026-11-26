/// LLM flow pipeline components and processors.
library;

import 'dart:async';
import 'dart:collection';

import '../../agents/abort_signal.dart';
import '../../agents/base_agent.dart';
import '../../agents/callback_context.dart';
import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/live_request_queue.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../agents/run_config.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_handler.dart';
import '../../auth/auth_tool.dart';
import '../../auth/credential_manager.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../features/_feature_registry.dart';
import '../../live/cascade_live_connection.dart' show LiveTranscription;
import '../../models/base_llm.dart';
import '../../models/base_llm_connection.dart';
import '../../models/conformance_replay_llm.dart';
import '../../plugins/conformance/conformance_recordings_schema.dart';
import '../../platform/time.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/mcp_tool/mcp_tool.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import 'agent_transfer.dart';
import 'audio_cache_manager.dart';
import 'contents.dart' show addInstructionsToUserContent;
import 'functions.dart' as flow_functions;
import 'instructions.dart' show labelDynamicInstruction;
import 'output_schema_processor.dart' as output_schema;
import 'persist_barrier.dart';

bool _routesIntoContents(InvocationContext invocationContext) {
  if (invocationContext.liveRequestQueue != null) {
    return false;
  }
  final RunConfig? runConfig = invocationContext.runConfig;
  if (runConfig != null && runConfig.supportCfc) {
    return false;
  }
  final BaseAgent agent = invocationContext.agent;
  if (agent is LlmAgent) {
    return agent.canonicalModel.supportsDynamicInstructionRouting;
  }
  return true;
}

/// Finalizes and resolves tool-contributed dynamic instructions on [llmRequest].
Future<void> finalizeDynamicInstructions(
  InvocationContext invocationContext,
  LlmRequest llmRequest,
) async {
  if (llmRequest.dynamicInstructions.isEmpty) {
    return;
  }

  final String combinedText = llmRequest.dynamicInstructions.join('\n\n');

  // Check routing support first: isFeatureEnabled warns while experimental.
  if (_routesIntoContents(invocationContext) &&
      isFeatureEnabled(FeatureName.dynamicInstructionRouting)) {
    final Content instructionContent = Content(
      role: 'user',
      parts: <Part>[Part.text(labelDynamicInstruction(combinedText))],
    );
    await addInstructionsToUserContent(
      invocationContext,
      llmRequest,
      <Content>[instructionContent],
    );
  } else {
    llmRequest.appendInstructions(<String>[combinedText]);
  }

  llmRequest.clearDynamicInstructions();
}

/// Request processor that folds tool-contributed dynamic instructions into the
/// request after tools have been resolved.
class DynamicInstructionsLlmRequestProcessor extends BaseLlmRequestProcessor {
  /// Creates a dynamic instructions request processor.
  DynamicInstructionsLlmRequestProcessor();

  @override
  Stream<Event> runAsync(
    InvocationContext context,
    LlmRequest request,
  ) async* {
    await finalizeDynamicInstructions(context, request);
  }
}

/// Contract for preprocessing a model request into emitted events.
abstract class BaseLlmRequestProcessor {
  /// Runs the processor with [context] and mutable [request].
  Stream<Event> runAsync(InvocationContext context, LlmRequest request);
}

/// Contract for postprocessing a model response into emitted events.
abstract class BaseLlmResponseProcessor {
  /// Runs the processor with [context] and [response].
  Stream<Event> runAsync(InvocationContext context, LlmResponse response);
}

const int _defaultMaxReconnectAttempts = 5;
const Object _liveSendCanceled = Object();

class _LiveReconnectRequested implements Exception {
  _LiveReconnectRequested([this.reason]);

  final Object? reason;
}

class _LiveSessionRestartRequested implements Exception {
  const _LiveSessionRestartRequested();
}

class _MergedLiveStreamEntry {
  _MergedLiveStreamEntry(this.event, this.handled);

  final Event event;
  final Completer<void> handled;
}

class _MergedLiveEntryQueue {
  final Queue<_MergedLiveStreamEntry?> _entries =
      Queue<_MergedLiveStreamEntry?>();
  Completer<void>? _waiter;

  void push(_MergedLiveStreamEntry? entry) {
    _entries.addLast(entry);
    final Completer<void>? waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete();
    }
  }

  Future<_MergedLiveStreamEntry?> pop() async {
    while (_entries.isEmpty) {
      await (_waiter ??= Completer<void>()).future;
    }
    return _entries.removeFirst();
  }
}

/// Core LLM flow coordinator for request/response processing and tool loops.
class BaseLlmFlow {
  /// Creates a base LLM flow.
  BaseLlmFlow();

  /// Request processors applied before model generation.
  final List<BaseLlmRequestProcessor> requestProcessors =
      <BaseLlmRequestProcessor>[];

  /// Response processors applied after model generation.
  final List<BaseLlmResponseProcessor> responseProcessors =
      <BaseLlmResponseProcessor>[];

  /// Cache manager used for live audio blob handling.
  final AudioCacheManager audioCacheManager = AudioCacheManager();

  /// Realtime cache manager used for live audio and media blob handling.
  RealtimeCacheManager get realtimeCacheManager => audioCacheManager;

  /// Maximum time a normally ending live run waits for running non-streaming
  /// tool calls to finish before cancelling them.
  Duration liveToolFinishTimeout = flow_functions.defaultLiveToolFinishTimeout;

  /// Optional delay before closing the parent connection on live agent handoff.
  Duration liveTransferAgentDelay = Duration.zero;

  /// Optional delay before ending a live run on `task_completed`.
  Duration liveTaskCompletionDelay = Duration.zero;

  /// Merges live [modelEvents] and [functionResponseQueue] into a single
  /// backpressured stream without reading ahead or losing queued responses on
  /// connection drop or reconnect.
  Stream<Event> mergeFunctionResponses(
    Stream<Event> modelEvents,
    flow_functions.LiveFunctionResponseQueue functionResponseQueue,
  ) async* {
    final _MergedLiveEntryQueue merged = _MergedLiveEntryQueue();
    final StreamIterator<Event> modelIterator = StreamIterator<Event>(
      modelEvents,
    );
    final Completer<void> stopAllSignal = Completer<void>();
    final Completer<void> stopFunctionSignal = Completer<void>();
    bool stopAll = false;
    bool stopFunction = false;
    bool modelIteratorCancelled = false;
    bool modelPumpDone = false;
    Object? modelPumpError;
    StackTrace? modelPumpStackTrace;

    Future<void> cancelModelIteratorOnce() {
      if (modelIteratorCancelled) {
        return Future<void>.value();
      }
      modelIteratorCancelled = true;
      return modelIterator.cancel();
    }

    Future<void> stopFunctionPumpOnce(Future<void> functionPumpFuture) async {
      stopFunction = true;
      if (!stopFunctionSignal.isCompleted) {
        stopFunctionSignal.complete();
      }
      await functionPumpFuture;
    }

    final Future<void> modelPumpFuture = () async {
      try {
        while (!stopAll) {
          final bool hasNext = await modelIterator.moveNext();
          if (!hasNext || stopAll) {
            break;
          }
          final Completer<void> handled = Completer<void>();
          merged.push(_MergedLiveStreamEntry(modelIterator.current, handled));
          await Future.any<void>(<Future<void>>[
            handled.future,
            stopAllSignal.future,
          ]);
        }
      } catch (error, stackTrace) {
        if (!stopAll) {
          modelPumpError = error;
          modelPumpStackTrace = stackTrace;
        }
      } finally {
        modelPumpDone = true;
        merged.push(null);
        await cancelModelIteratorOnce();
      }
    }();

    final Future<void> functionPumpFuture = () async {
      while (!stopAll && !stopFunction) {
        if (functionResponseQueue.isEmpty) {
          await Future.any<void>(<Future<void>>[
            functionResponseQueue.waitForItem(),
            stopFunctionSignal.future,
            stopAllSignal.future,
          ]);
          if (stopAll || stopFunction) {
            break;
          }
          if (functionResponseQueue.isEmpty) {
            continue;
          }
        }
        final Event result = functionResponseQueue.getNowait();
        final Completer<void> handled = Completer<void>();
        merged.push(_MergedLiveStreamEntry(result, handled));
        try {
          await Future.any<void>(<Future<void>>[
            handled.future,
            stopFunctionSignal.future,
            stopAllSignal.future,
          ]);
        } finally {
          if (!handled.isCompleted) {
            functionResponseQueue.putFrontNowait(result);
          }
        }
        if (!handled.isCompleted) {
          break;
        }
      }
    }();

    try {
      while (true) {
        final _MergedLiveStreamEntry? entry = await merged.pop();
        if (entry == null || modelPumpDone) {
          break;
        }
        try {
          yield entry.event;
        } finally {
          if (!entry.handled.isCompleted) {
            entry.handled.complete();
          }
        }
        await Future<void>.delayed(Duration.zero);
      }

      await stopFunctionPumpOnce(functionPumpFuture);
      if (modelPumpError == null) {
        while (functionResponseQueue.isNotEmpty) {
          yield functionResponseQueue.getNowait();
        }
      } else {
        Error.throwWithStackTrace(modelPumpError!, modelPumpStackTrace!);
      }
    } finally {
      stopAll = true;
      stopFunction = true;
      if (!stopFunctionSignal.isCompleted) {
        stopFunctionSignal.complete();
      }
      if (!stopAllSignal.isCompleted) {
        stopAllSignal.complete();
      }
      await cancelModelIteratorOnce();
      await Future.wait<void>(<Future<void>>[
        modelPumpFuture,
        functionPumpFuture,
      ]);
    }
  }

  /// Runs the flow in live mode when a live queue is available.
  Stream<Event> runLive(InvocationContext context) async* {
    if (context.isAborted) {
      return;
    }

    final LiveRequestQueue? liveQueue = context.liveRequestQueue;
    if (liveQueue == null) {
      await for (final Event event in runAsync(context)) {
        yield event;
      }
      return;
    }

    final BaseLlm llm = _getLlm(context);
    if (!_supportsLiveConnect(llm)) {
      try {
        await for (final Event event in _runLiveFallback(context, liveQueue)) {
          yield event;
        }
      } finally {
        context.liveRequestQueue?.close();
        await flow_functions.stopBackgroundToolTasks(context);
      }
      return;
    }

    final flow_functions.LiveFunctionResponseQueue functionResponseQueue =
        flow_functions.LiveFunctionResponseQueue();
    bool keepLiveQueueOpen = false;

    Stream<Event> finishInFlightCalls() async* {
      await flow_functions.waitForLiveToolCalls(
        context,
        timeout: liveToolFinishTimeout,
      );
      while (functionResponseQueue.isNotEmpty) {
        yield functionResponseQueue.getNowait();
      }
    }

    try {
      try {
        final LlmRequest request = LlmRequest();
        await for (final Event event in _preprocessAsync(
          context,
          request,
          live: true,
        )) {
          if (context.isAborted) {
            return;
          }
          yield event;
        }
        if (context.endInvocation || context.isAborted) {
          return;
        }

        int reconnectAttempts = 0;
        while (true) {
          _applyLiveSessionResumptionHandle(context, request);
          _applyLiveInitialHistoryConfig(context, request);

          final BaseLlmConnection connection = _connectLive(llm, request);
          final Completer<void> stopSending = Completer<void>();
          Future<void>? sendTask;
          Future<void>? closeTask;
          bool closedByClient = false;

          Future<void> closeConnectionOnce() {
            closeTask ??= connection.close();
            return closeTask!;
          }

          try {
            if (request.contents.isNotEmpty &&
                !_hasLiveSessionResumptionHandle(context)) {
              await connection.sendHistory(
                request.contents
                    .map((Content content) => content.copyWith())
                    .toList(growable: false),
              );
            }

            sendTask = _sendToModel(
              connection,
              context,
              request,
              closeConnection: closeConnectionOnce,
              cancelSignal: stopSending.future,
              onTerminalClose: () {
                closedByClient = true;
              },
              onBlockedEvent: functionResponseQueue.putNowait,
            );

            final StreamIterator<Event> mergedIterator = StreamIterator<Event>(
              mergeFunctionResponses(
                _receiveFromModel(connection, context, request),
                functionResponseQueue,
              ),
            );
            bool mergedCancelled = false;
            Future<void> cancelMergedOnce() {
              if (mergedCancelled) {
                return Future<void>.value();
              }
              mergedCancelled = true;
              return mergedIterator.cancel();
            }

            try {
              while (await mergedIterator.moveNext()) {
                final Event event = mergedIterator.current;
                if (context.isAborted) {
                  await cancelMergedOnce();
                  return;
                }
                reconnectAttempts = 0;
                yield event;

                if (event.getFunctionCalls().isNotEmpty &&
                    event.partial != true) {
                  flow_functions.launchFunctionCallsLive(
                    context,
                    event,
                    request.toolsDict,
                    functionResponseQueue,
                  );
                }

                if (event.getFunctionResponses().isNotEmpty &&
                    event.content != null) {
                  context.liveRequestQueue?.sendContent(
                    event.content!.copyWith(),
                  );
                }

                final String? transferToAgent = event.actions.transferToAgent;
                if (transferToAgent != null && transferToAgent.isNotEmpty) {
                  await cancelMergedOnce();
                  await flow_functions.stopBackgroundToolTasks(context);
                  while (functionResponseQueue.isNotEmpty) {
                    yield functionResponseQueue.getNowait();
                  }
                  if (liveTransferAgentDelay > Duration.zero) {
                    await Future<void>.delayed(liveTransferAgentDelay);
                  } else {
                    await Future<void>.delayed(Duration.zero);
                  }
                  if (!stopSending.isCompleted) {
                    stopSending.complete();
                  }
                  if (sendTask != null) {
                    try {
                      await sendTask;
                    } catch (_) {}
                    sendTask = null;
                  }
                  await closeConnectionOnce();

                  final BaseAgent agentToRun = _getAgentToRun(
                    context,
                    transferToAgent,
                    allowSelfTransfer: true,
                  );
                  final InvocationContext childContext =
                      _createLiveTransferContext(context);
                  keepLiveQueueOpen = true;
                  await for (final Event childEvent in agentToRun.runLive(
                    childContext,
                  )) {
                    if (context.isAborted || childContext.isAborted) {
                      return;
                    }
                    yield childEvent;
                  }
                  return;
                }

                if (event.getFunctionResponses().any(
                  (FunctionResponse fr) => fr.name == 'task_completed',
                )) {
                  await cancelMergedOnce();
                  if (liveTaskCompletionDelay > Duration.zero) {
                    await Future<void>.delayed(liveTaskCompletionDelay);
                  } else {
                    await Future<void>.delayed(Duration.zero);
                    await Future<void>.delayed(Duration.zero);
                  }
                  while (functionResponseQueue.isNotEmpty) {
                    yield functionResponseQueue.getNowait();
                  }
                  if (!stopSending.isCompleted) {
                    stopSending.complete();
                  }
                  keepLiveQueueOpen = true;
                  return;
                }
              }
            } finally {
              await cancelMergedOnce();
            }

            if (closedByClient) {
              yield* finishInFlightCalls();
              return;
            }
            yield* finishInFlightCalls();
            return;
          } on _LiveSessionRestartRequested {
            if (!stopSending.isCompleted) {
              stopSending.complete();
            }
            if (sendTask != null) {
              try {
                await sendTask;
              } catch (_) {}
              sendTask = null;
            }
            await closeConnectionOnce();
            await flow_functions.stopBackgroundToolTasks(context);
            while (functionResponseQueue.isNotEmpty) {
              yield functionResponseQueue.getNowait();
            }
            final InvocationContext restartContext = _createLiveTransferContext(
              context,
            );
            keepLiveQueueOpen = true;
            await for (final Event restartedEvent in runLive(restartContext)) {
              if (context.isAborted || restartContext.isAborted) {
                return;
              }
              yield restartedEvent;
            }
            return;
          } on _LiveReconnectRequested {
            if (!_canRetryLiveConnection(context, reconnectAttempts)) {
              rethrow;
            }
            reconnectAttempts += 1;
          } on RecoverableLiveConnectionException catch (error, stackTrace) {
            if (!_canRetryLiveConnection(context, reconnectAttempts)) {
              Error.throwWithStackTrace(error, stackTrace);
            }
            reconnectAttempts += 1;
          } finally {
            if (!stopSending.isCompleted) {
              stopSending.complete();
            }
            if (sendTask != null) {
              try {
                await sendTask;
              } catch (_) {}
            }
            await closeConnectionOnce();
          }
        }
      } catch (error, stackTrace) {
        while (functionResponseQueue.isNotEmpty) {
          yield functionResponseQueue.getNowait();
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      if (!keepLiveQueueOpen) {
        context.liveRequestQueue?.close();
      }
      await flow_functions.stopBackgroundToolTasks(context);
    }
  }

  bool _supportsLiveConnect(BaseLlm llm) {
    final dynamic dynamicLlm = llm;
    try {
      final Object? connectMethod = dynamicLlm.connect;
      return connectMethod is Function;
    } on NoSuchMethodError {
      return false;
    }
  }

  BaseLlmConnection _connectLive(BaseLlm llm, LlmRequest request) {
    final dynamic dynamicLlm = llm;
    final Object? value = dynamicLlm.connect(request);
    if (value is! BaseLlmConnection) {
      throw StateError(
        'Model `${llm.runtimeType}` returned an invalid live connection.',
      );
    }
    return value;
  }

  Stream<Event> _runLiveFallback(
    InvocationContext context,
    LiveRequestQueue liveQueue,
  ) async* {
    while (true) {
      if (context.isAborted) {
        return;
      }
      final LiveRequest liveRequest = await liveQueue.get();
      _fanOutLiveRequest(context, liveRequest);

      if (liveRequest.close) {
        break;
      }

      if (liveRequest.activityStart != null) {
        yield _buildLiveSignalEvent(context, 'live_activity_start');
      } else if (liveRequest.activityEnd != null) {
        yield _buildLiveSignalEvent(context, 'live_activity_end');
      } else if (liveRequest.blob != null) {
        final Event blobEvent = await _handleLiveBlob(
          context,
          liveRequest.blob!,
        );
        yield blobEvent;
      }

      Content? content = liveRequest.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }

      content = _normalizeLiveContentRole(content);
      content = await _appendLiveUserContent(context, content);

      final InvocationContext turnContext = context.copyWith(
        userContent: content.copyWith(),
      );
      await for (final Event event in runAsync(turnContext)) {
        if (context.isAborted || turnContext.isAborted) {
          return;
        }
        _maybeUpdateLiveSessionResumptionHandle(context, event.customMetadata);
        yield event;
      }

      if (turnContext.endInvocation) {
        context.endInvocation = true;
        break;
      }
    }
  }

  /// Screens live user [content] with before-model callbacks on a copy of
  /// [request] so callbacks cannot mutate the live session request's config or
  /// tools.
  Future<Event?> screenLiveUserContent(
    InvocationContext context,
    Content content,
    LlmRequest request,
  ) => _screenLiveUserContent(context, content, request);

  Future<Event?> _screenLiveUserContent(
    InvocationContext context,
    Content content,
    LlmRequest request,
  ) async {
    if (context.agent is! LlmAgent) {
      return null;
    }
    final LlmRequest callbackRequest = LlmRequest(
      model: request.model,
      contents: <Content>[content.copyWith()],
      config: copyRequestScopedFields(request.config),
      liveConnectConfig: request.liveConnectConfig.copyWith(),
      toolsDict: Map<String, BaseTool>.from(request.toolsDict),
      cacheConfig: request.cacheConfig,
      cacheMetadata: request.cacheMetadata,
      cacheableContentsTokenCount: request.cacheableContentsTokenCount,
      previousInteractionId: request.previousInteractionId,
      isManagedAgent: request.isManagedAgent,
      serviceTier: request.serviceTier,
      dynamicInstructions: request.dynamicInstructions,
      hasStaticInstruction: request.hasStaticInstruction,
      staticInstructionPrefixEndIndex: request.staticInstructionPrefixEndIndex,
    );
    final Event callbackResponseEvent = Event(
      id: Event.newId(),
      invocationId: context.invocationId,
      author: context.agent.name,
      branch: context.branch,
    );
    final LlmResponse? blockedResponse = await _handleBeforeModelCallback(
      context,
      callbackRequest,
      callbackResponseEvent,
    );
    if (blockedResponse != null) {
      final Event blockedEvent = _finalizeModelResponseEvent(
        callbackRequest,
        blockedResponse,
        callbackResponseEvent,
      )..turnComplete = true;
      return blockedEvent;
    }
    return null;
  }

  static ({String? text, bool finished}) _extractTranscriptionInfo(
    Object? raw,
  ) {
    if (raw == null) {
      return (text: null, finished: false);
    }
    if (raw is Map) {
      final Object? rawText = raw['text'];
      return (
        text: rawText is String ? rawText : null,
        finished: raw['finished'] == true,
      );
    }
    try {
      final dynamic dynamicRaw = raw;
      String? text;
      bool finished = false;
      try {
        final Object? rawText = dynamicRaw.text;
        if (rawText is String) {
          text = rawText;
        }
      } catch (_) {}
      try {
        finished = dynamicRaw.finished == true;
      } catch (_) {}
      return (text: text, finished: finished);
    } catch (_) {
      return (text: null, finished: false);
    }
  }

  Future<void> _sendToModel(
    BaseLlmConnection connection,
    InvocationContext context,
    LlmRequest request, {
    required Future<void> Function() closeConnection,
    required Future<void> cancelSignal,
    void Function()? onTerminalClose,
    void Function(Event event)? onBlockedEvent,
  }) async {
    while (true) {
      if (context.isAborted) {
        return;
      }
      final LiveRequestQueue? liveQueue = context.liveRequestQueue;
      if (liveQueue == null) {
        return;
      }

      final Object next = await Future.any<Object>(<Future<Object>>[
        liveQueue.get(),
        cancelSignal.then<Object>((_) => _liveSendCanceled),
      ]);
      if (identical(next, _liveSendCanceled)) {
        return;
      }
      final LiveRequest liveRequest = next as LiveRequest;
      _fanOutLiveRequest(context, liveRequest);

      await Future<void>.delayed(Duration.zero);
      if (context.isAborted) {
        return;
      }
      if (liveRequest.close) {
        onTerminalClose?.call();
        await closeConnection();
        return;
      }

      if (liveRequest.activityStart != null) {
        await connection.sendRealtime(
          RealtimeBlob(
            mimeType: 'application/vnd.adk.activity_start',
            data: const <int>[],
          ),
        );
      } else if (liveRequest.activityEnd != null) {
        await connection.sendRealtime(
          RealtimeBlob(
            mimeType: 'application/vnd.adk.activity_end',
            data: const <int>[],
          ),
        );
      } else if (liveRequest.blob != null) {
        final RealtimeBlob realtimeBlob = _coerceRealtimeBlob(
          liveRequest.blob!,
        );
        if (context.runConfig?.saveLiveBlob == true) {
          audioCacheManager.cacheRealtimeBlob(
            context,
            InlineData(
              mimeType: realtimeBlob.mimeType,
              data: List<int>.from(realtimeBlob.data),
            ),
          );
        } else if (realtimeBlob.mimeType.startsWith('audio/')) {
          audioCacheManager.cacheAudio(
            context,
            InlineData(
              mimeType: realtimeBlob.mimeType,
              data: List<int>.from(realtimeBlob.data),
            ),
            cacheType: 'input',
          );
        }
        await connection.sendRealtime(realtimeBlob);
      }

      Content? content = liveRequest.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      // Reject user-authored function calls: they would bypass the LLM and
      // directly execute arbitrary registered tools.
      if (content.parts.any((Part part) => part.functionCall != null)) {
        throw ArgumentError('User message cannot contain function calls.');
      }
      final bool isOnlyFunctionResponses =
          content.parts.isNotEmpty &&
          content.parts.every((Part part) => part.functionResponse != null);
      content = _normalizeLiveContentRole(content);
      content = await _appendLiveUserContent(context, content);
      if (!isOnlyFunctionResponses) {
        final Event? blockedEvent = await _screenLiveUserContent(
          context,
          content,
          request,
        );
        if (blockedEvent != null) {
          onBlockedEvent?.call(blockedEvent);
          continue;
        }
      }
      await connection.sendContent(content.copyWith());
    }
  }

  Stream<Event> _receiveFromModel(
    BaseLlmConnection connection,
    InvocationContext context,
    LlmRequest request,
  ) async* {
    String turnOutputTranscription = '';
    await for (final LlmResponse response in connection.receive()) {
      if (context.isAborted) {
        return;
      }
      _updateLiveSessionResumptionHandle(
        context,
        response.liveSessionResumptionUpdate,
      );
      _maybeUpdateLiveSessionResumptionHandle(context, response.customMetadata);
      final bool reconnectRequested = response.goAway != null;
      if (response.turnComplete == true || response.interrupted == true) {
        turnOutputTranscription = '';
      }

      final Event modelResponseEvent = Event(
        id: Event.newId(),
        invocationId: context.invocationId,
        author:
            response.inputTranscription != null ||
                response.content?.role == 'user'
            ? 'user'
            : context.agent.name,
        branch: context.branch,
      );

      if (response.outputTranscription != null) {
        final ({String? text, bool finished}) outInfo =
            _extractTranscriptionInfo(response.outputTranscription);
        if (outInfo.finished) {
          turnOutputTranscription = '';
        } else if (outInfo.text != null && outInfo.text!.isNotEmpty) {
          turnOutputTranscription += outInfo.text!;
        }

        if (turnOutputTranscription.isNotEmpty && context.agent is LlmAgent) {
          final LlmResponse callbackLlmResponse = response.copyWith(
            outputTranscription: LiveTranscription(
              text: turnOutputTranscription,
              finished: false,
            ),
          );
          final LlmResponse? blockedResponse = await _handleAfterModelCallback(
            context,
            callbackLlmResponse,
            modelResponseEvent,
          );
          if (blockedResponse != null &&
              !identical(blockedResponse, callbackLlmResponse)) {
            final Event blockedOutputEvent = _finalizeModelResponseEvent(
              request,
              blockedResponse,
              modelResponseEvent,
            )..turnComplete = true;
            yield blockedOutputEvent;
            throw const _LiveSessionRestartRequested();
          }
        }
      }

      await for (final Event event in _postprocessLive(
        context,
        request,
        response,
        modelResponseEvent,
      )) {
        if (context.isAborted) {
          return;
        }
        if ((context.runConfig?.saveLiveBlob ?? false) &&
            event.content?.parts.isNotEmpty == true &&
            event.content!.parts.first.inlineData != null &&
            event.content!.parts.first.inlineData!.mimeType.startsWith(
              'audio/',
            )) {
          audioCacheManager.cacheAudio(
            context,
            event.content!.parts.first.inlineData!.copyWith(),
            cacheType: 'output',
          );
        }
        yield event;
      }

      if (response.inputTranscription != null && context.agent is LlmAgent) {
        final ({String? text, bool finished}) inInfo =
            _extractTranscriptionInfo(response.inputTranscription);
        if (inInfo.finished && inInfo.text != null && inInfo.text!.isNotEmpty) {
          final Content spokenContent = Content(
            role: 'user',
            parts: <Part>[Part.text(inInfo.text!)],
          );
          final Event? blockedEvent = await _screenLiveUserContent(
            context,
            spokenContent,
            request,
          );
          if (blockedEvent != null) {
            yield blockedEvent;
            throw const _LiveSessionRestartRequested();
          }
        }
      }

      if (reconnectRequested) {
        throw _LiveReconnectRequested(response.goAway);
      }
    }
  }

  Stream<Event> _postprocessLive(
    InvocationContext context,
    LlmRequest request,
    LlmResponse response,
    Event modelResponseEvent,
  ) async* {
    await for (final Event event in _postprocessRunProcessorsAsync(
      context,
      response,
    )) {
      if (context.isAborted) {
        return;
      }
      yield event;
    }

    if (context.isAborted) {
      return;
    }

    if (response.content == null &&
        response.errorCode == null &&
        response.interrupted != true &&
        response.turnComplete != true &&
        response.inputTranscription == null &&
        response.outputTranscription == null &&
        response.usageMetadata == null &&
        response.liveSessionResumptionUpdate == null &&
        response.goAway == null &&
        response.groundingMetadata == null &&
        response.voiceActivity == null) {
      return;
    }

    if (response.liveSessionResumptionUpdate != null ||
        response.goAway != null) {
      yield modelResponseEvent.copyWith(
        liveSessionResumptionUpdate: response.liveSessionResumptionUpdate,
        goAway: response.goAway,
        liveSessionId: response.liveSessionId,
      );
      if (response.content == null &&
          response.errorCode == null &&
          response.interrupted != true &&
          response.turnComplete != true &&
          response.inputTranscription == null &&
          response.outputTranscription == null &&
          response.usageMetadata == null &&
          response.groundingMetadata == null) {
        return;
      }
    }

    if (response.inputTranscription != null) {
      modelResponseEvent.inputTranscription = response.inputTranscription;
      modelResponseEvent.partial = response.partial;
      yield modelResponseEvent;
      return;
    }

    if (response.outputTranscription != null) {
      modelResponseEvent.outputTranscription = response.outputTranscription;
      modelResponseEvent.partial = response.partial;
      yield modelResponseEvent;
      return;
    }

    final bool isBargeIn =
        response.interrupted == true && response.turnComplete != true;
    if (context.runConfig?.saveLiveBlob == true && !isBargeIn) {
      final List<Event> flushed = await handleControlEventFlush(
        context,
        response,
      );
      if (flushed.isNotEmpty) {
        for (final Event event in flushed) {
          yield event;
        }
      }
    }

    final Event finalized = _finalizeModelResponseEvent(
      request,
      response,
      modelResponseEvent,
    );
    if (context.isAborted) {
      return;
    }
    yield finalized;

    if (context.runConfig?.saveLiveBlob == true && isBargeIn) {
      final List<Event> flushed = await handleControlEventFlush(
        context,
        response,
      );
      if (flushed.isNotEmpty) {
        for (final Event event in flushed) {
          yield event;
        }
      }
    }
  }

  void _fanOutLiveRequest(InvocationContext context, LiveRequest liveRequest) {
    final Set<LiveRequestQueue> targetStreams = <LiveRequestQueue>{};
    final activeStreams = context.activeStreamingTools;
    if (activeStreams != null) {
      for (final dynamic activeStream in activeStreams.values) {
        final LiveRequestQueue? stream = activeStream.stream;
        if (stream != null && !identical(stream, context.liveRequestQueue)) {
          targetStreams.add(stream);
        }
      }
    }
    for (final ActiveBackgroundTool active
        in context.activeBackgroundTools.values) {
      final LiveRequestQueue? stream = active.inputStream;
      if (stream != null && !identical(stream, context.liveRequestQueue)) {
        targetStreams.add(stream);
      }
    }

    for (final LiveRequestQueue stream in targetStreams) {
      stream.send(liveRequest);
    }
  }

  Content _normalizeLiveContentRole(Content content) {
    if (content.role != 'user') {
      return content.copyWith(role: 'user');
    }
    return content;
  }

  RealtimeBlob _coerceRealtimeBlob(Object blob) {
    if (blob is RealtimeBlob) {
      return RealtimeBlob(
        mimeType: blob.mimeType,
        data: List<int>.from(blob.data),
      );
    }
    if (blob is InlineData) {
      return RealtimeBlob(
        mimeType: blob.mimeType,
        data: List<int>.from(blob.data),
      );
    }
    if (blob is List<int>) {
      return RealtimeBlob(
        mimeType: 'application/octet-stream',
        data: List<int>.from(blob),
      );
    }
    if (blob is Map) {
      final Object? rawMimeType = blob['mimeType'] ?? blob['mime_type'];
      final Object? rawData = blob['data'];
      if (rawMimeType is String && rawData is List<int>) {
        return RealtimeBlob(
          mimeType: rawMimeType,
          data: List<int>.from(rawData),
        );
      }
      if (rawMimeType is String && rawData is List) {
        final List<int> bytes = <int>[];
        for (final Object? item in rawData) {
          if (item is! int) {
            throw ArgumentError.value(
              blob,
              'blob',
              'Realtime blob map data must contain bytes.',
            );
          }
          bytes.add(item);
        }
        return RealtimeBlob(mimeType: rawMimeType, data: bytes);
      }
    }

    throw ArgumentError.value(
      blob,
      'blob',
      'Unsupported live realtime blob payload.',
    );
  }

  void _applyLiveSessionResumptionHandle(
    InvocationContext context,
    LlmRequest request,
  ) {
    final String? handle = context.liveSessionResumptionHandle;
    if (handle == null || handle.isEmpty) {
      return;
    }

    final Object? sessionResumption =
        request.liveConnectConfig.sessionResumption;
    final Map<String, Object?> mutable = sessionResumption is Map
        ? sessionResumption.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          )
        : <String, Object?>{};
    mutable['handle'] = handle;
    mutable['transparent'] = true;
    request.liveConnectConfig.sessionResumption = mutable;
  }

  void _applyLiveInitialHistoryConfig(
    InvocationContext context,
    LlmRequest request,
  ) {
    if (request.contents.isEmpty || _hasLiveSessionResumptionHandle(context)) {
      return;
    }

    final Object? historyConfig =
        request.liveConnectConfig.historyConfig ??
        context.runConfig?.historyConfig;
    if (historyConfig != null && historyConfig is! Map) {
      return;
    }

    final Map<String, Object?> mutable = historyConfig is Map
        ? historyConfig.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          )
        : <String, Object?>{};
    const List<String> initialHistoryKeys = <String>[
      'initial_history_in_client_content',
      'initialHistoryInClientContent',
    ];
    if (!initialHistoryKeys.any(mutable.containsKey)) {
      mutable['initial_history_in_client_content'] = true;
    }
    request.liveConnectConfig.historyConfig = mutable;
  }

  InvocationContext _createLiveTransferContext(InvocationContext context) {
    final InvocationContext childContext = context.copyWith(
      runConfig: _copyRunConfigWithoutSessionResumptionHandle(
        context.runConfig,
      ),
    );
    childContext.liveSessionResumptionHandle = null;
    childContext.activeBackgroundTools = <String, ActiveBackgroundTool>{};
    return childContext;
  }

  RunConfig? _copyRunConfigWithoutSessionResumptionHandle(RunConfig? config) {
    if (config == null) {
      return null;
    }
    return config.copyWith(
      sessionResumption: _removeSessionResumptionHandle(
        config.sessionResumption,
      ),
    );
  }

  Object? _removeSessionResumptionHandle(Object? sessionResumption) {
    if (sessionResumption is Map) {
      final Map<String, Object?> mutable = sessionResumption.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
      mutable.remove('handle');
      return mutable;
    }
    return sessionResumption;
  }

  bool _hasLiveSessionResumptionHandle(InvocationContext context) {
    final String? handle = context.liveSessionResumptionHandle;
    return handle != null && handle.isNotEmpty;
  }

  bool _canRetryLiveConnection(
    InvocationContext context,
    int reconnectAttempts,
  ) {
    final bool clientClosed = context.liveRequestQueue?.closed ?? false;
    if (clientClosed) {
      return false;
    }
    return _hasLiveSessionResumptionHandle(context) &&
        reconnectAttempts < _defaultMaxReconnectAttempts;
  }

  void _updateLiveSessionResumptionHandle(
    InvocationContext context,
    Object? update,
  ) {
    if (update == null) {
      return;
    }
    if (update is String && update.isNotEmpty) {
      context.liveSessionResumptionHandle = update;
      return;
    }
    if (update is Map) {
      final Object? handle =
          update['new_handle'] ?? update['newHandle'] ?? update['handle'];
      if (handle is String && handle.isNotEmpty) {
        context.liveSessionResumptionHandle = handle;
      }
      return;
    }
    try {
      final dynamic dynamicUpdate = update;
      Object? handle;
      try {
        handle = dynamicUpdate.newHandle;
      } catch (_) {
        try {
          handle = dynamicUpdate.new_handle;
        } catch (_) {
          handle = dynamicUpdate.handle;
        }
      }
      if (handle is String && handle.isNotEmpty) {
        context.liveSessionResumptionHandle = handle;
      }
    } catch (_) {
      // Update object does not expose a handle property.
    }
  }

  void _maybeUpdateLiveSessionResumptionHandle(
    InvocationContext context,
    Map<String, dynamic>? metadata,
  ) {
    if (metadata == null || metadata.isEmpty) {
      return;
    }

    final Object? update =
        metadata['live_session_resumption_update'] ??
        metadata['liveSessionResumptionUpdate'];
    if (update != null) {
      _updateLiveSessionResumptionHandle(context, update);
      return;
    }

    final Object? topLevelHandle =
        metadata['new_handle'] ?? metadata['newHandle'] ?? metadata['handle'];
    if (topLevelHandle is String && topLevelHandle.isNotEmpty) {
      context.liveSessionResumptionHandle = topLevelHandle;
    }
  }

  Event _buildLiveSignalEvent(InvocationContext context, String signal) {
    return Event(
      invocationId: context.invocationId,
      author: 'user',
      branch: context.branch,
      content: Content(role: 'user', parts: <Part>[Part.text(signal)]),
    );
  }

  Future<Event> _handleLiveBlob(InvocationContext context, Object blob) async {
    final String blobText = blob is List<int>
        ? '[binary:${blob.length}]'
        : '$blob';
    final bool saveBlob = context.runConfig?.saveLiveBlob ?? false;
    if (!saveBlob || context.artifactService == null) {
      return Event(
        invocationId: context.invocationId,
        author: 'user',
        branch: context.branch,
        content: Content(
          role: 'user',
          parts: <Part>[Part.text('live_blob:$blobText')],
        ),
      );
    }

    final String filename =
        '_adk_live/live_blob_${DateTime.now().microsecondsSinceEpoch}.txt';
    final int version = await context.saveArtifact(
      filename: filename,
      artifact: Part.text(blobText),
    );

    return Event(
      invocationId: context.invocationId,
      author: 'user',
      branch: context.branch,
      content: Content(
        role: 'user',
        parts: <Part>[Part.text('Saved live blob as artifact: $filename')],
      ),
      actions: EventActions(artifactDelta: <String, int>{filename: version}),
    );
  }

  Future<Content> _appendLiveUserContent(
    InvocationContext context,
    Content content,
  ) async {
    final bool isFunctionResponse = content.parts.any(
      (Part part) => part.functionResponse != null,
    );
    if (isFunctionResponse) {
      return content;
    }

    final Content? modifiedContent = await context.pluginManager
        .runOnUserMessageCallback(
          userMessage: content,
          invocationContext: context,
        );
    final Content resolvedContent = modifiedContent ?? content;

    final Event event = Event(
      invocationId: context.invocationId,
      author: 'user',
      branch: context.branch,
      isolationScope: context.isolationScope,
      content: resolvedContent.copyWith(),
    );
    await context.sessionService.appendEvent(
      session: context.session,
      event: event,
    );
    return resolvedContent;
  }

  /// Runs the standard request-response flow until completion.
  Stream<Event> runAsync(InvocationContext context) async* {
    while (true) {
      if (context.isAborted) {
        return;
      }
      Event? lastEvent;
      final List<Event> stepEvents = <Event>[];
      await for (final Event event in _runOneStepAsync(context)) {
        if (context.isAborted) {
          return;
        }
        lastEvent = event;
        stepEvents.add(event);
        yield event;
      }

      if (context.isAborted) {
        return;
      }

      await PersistBarrier.awaitPersisted(context, stepEvents);

      if (lastEvent == null ||
          lastEvent.isFinalResponse() ||
          lastEvent.partial == true) {
        break;
      }
    }
  }

  Stream<Event> _runOneStepAsync(InvocationContext context) async* {
    if (context.isAborted) {
      return;
    }

    final LlmRequest request = LlmRequest();

    await for (final Event event in _preprocessAsync(context, request)) {
      if (context.isAborted) {
        return;
      }
      yield event;
    }

    if (context.endInvocation || context.isAborted) {
      return;
    }

    final List<Event> events = context.getEvents(
      currentInvocation: true,
      currentBranch: true,
    );

    final bool shouldPauseForLongRunning =
        context.isResumable &&
        events.isNotEmpty &&
        (context.shouldPauseInvocation(events.last) ||
            (events.length > 1 &&
                _hasUnansweredPauseCalls(
                  context,
                  events[events.length - 2],
                  events.last,
                )));
    if (shouldPauseForLongRunning) {
      return;
    }

    if (context.isResumable &&
        events.isNotEmpty &&
        events.last.partial != true &&
        events.last.getFunctionCalls().isNotEmpty &&
        events.last.author == context.agent.name) {
      final Event functionCallEvent = events.last;
      await for (final Event event in _postprocessHandleFunctionCallsAsync(
        context,
        functionCallEvent,
        request,
      )) {
        if (context.isAborted) {
          return;
        }
        yield event;
      }
      return;
    }

    final Event modelResponseEvent = Event(
      id: Event.newId(),
      invocationId: context.invocationId,
      author: context.agent.name,
      branch: context.branch,
    );

    await for (final LlmResponse response in _callLlmAsync(
      context,
      request,
      modelResponseEvent,
    )) {
      if (context.isAborted) {
        return;
      }
      if (context.runConfig?.supportCfc == true) {
        yield response is Event
            ? response
            : _finalizeModelResponseEvent(
                request,
                response,
                modelResponseEvent,
              );
        continue;
      }
      await for (final Event event in _postprocessAsync(
        context,
        request,
        response,
        modelResponseEvent,
      )) {
        if (context.isAborted) {
          return;
        }
        if (event.partial != true) {
          modelResponseEvent.id = Event.newId();
        }
        yield event;
      }
    }
  }

  bool _hasUnansweredPauseCalls(
    InvocationContext context,
    Event pauseEvent,
    Event trailingEvent,
  ) {
    if (!context.shouldPauseInvocation(pauseEvent)) {
      return false;
    }
    if (trailingEvent.author != 'user' && trailingEvent.errorCode == null) {
      return true;
    }
    final Set<String> pauseIds = <String>{
      ...?pauseEvent.longRunningToolIds,
      for (final FunctionCall call in pauseEvent.getFunctionCalls())
        if (call.id != null &&
            (call.name == 'adk_request_input' ||
                call.name == 'adk_request_credential'))
          call.id!,
    };
    final Set<String> answeredIds = <String>{
      for (final FunctionResponse fr in trailingEvent.getFunctionResponses())
        if (fr.id != null) fr.id!,
    };
    return pauseIds.difference(answeredIds).isNotEmpty;
  }

  Stream<Event> _preprocessAsync(
    InvocationContext context,
    LlmRequest request, {
    bool live = false,
  }) async* {
    for (final BaseLlmRequestProcessor processor in requestProcessors) {
      if (live && processor is output_schema.OutputSchemaRequestProcessor) {
        continue;
      }
      await for (final Event event in processor.runAsync(context, request)) {
        if (context.isAborted) {
          return;
        }
        yield event;
      }
    }

    if (context.endInvocation || context.isAborted) {
      return;
    }

    await for (final Event event in _resolveToolsetAuth(context)) {
      if (context.isAborted) {
        return;
      }
      yield event;
    }

    if (context.endInvocation || context.isAborted) {
      return;
    }

    if (request.contents.isEmpty) {
      final LlmAgent agent = context.agent as LlmAgent;
      final List<Event> sourceEvents = switch (agent.includeContents) {
        'none' => const <Event>[],
        'current_turn' => context.getEvents(
          currentInvocation: true,
          currentBranch: true,
        ),
        _ => context.getEvents(currentBranch: true),
      };

      for (final Event event in sourceEvents.where(
        (Event event) => event.isolationScope == context.isolationScope,
      )) {
        final Content? content = event.content;
        if (content != null) {
          request.contents.add(content.copyWith());
        }
      }
    }

    await _processAgentTools(context, request);
    await finalizeDynamicInstructions(context, request);
  }

  Stream<Event> _resolveToolsetAuth(InvocationContext context) async* {
    final BaseAgent current = context.agent;
    if (current is! LlmAgent || current.tools.isEmpty) {
      return;
    }

    final Map<String, AuthConfig> pendingAuthRequests = <String, AuthConfig>{};
    final Context callbackContext = Context(context);

    for (final Object toolUnion in current.tools) {
      if (toolUnion is! BaseToolset) {
        continue;
      }

      final AuthConfig? authConfig = toolUnion.getAuthConfig()?.copyWith();
      if (authConfig == null) {
        continue;
      }

      AuthCredential? credential;
      try {
        credential = await CredentialManager(
          authConfig: authConfig,
        ).getAuthCredential(callbackContext);
      } catch (_) {
        // Keep toolset execution tolerant to auth validation errors.
        continue;
      }

      if (credential != null) {
        context.credentialByKey[authConfig.credentialKey] = credential
            .copyWith();
        continue;
      }

      final String toolsetCredentialId =
          '$toolsetAuthCredentialIdPrefix${toolUnion.runtimeType}';
      try {
        pendingAuthRequests[toolsetCredentialId] = AuthHandler(
          authConfig: authConfig,
        ).generateAuthRequest();
      } on ArgumentError {
        // Invalid auth config should not block tools that can still run unauthenticated.
        continue;
      }
    }

    if (pendingAuthRequests.isEmpty) {
      return;
    }

    yield flow_functions.buildAuthRequestEvent(
      context,
      pendingAuthRequests,
      author: current.name,
    );
    context.endInvocation = true;
  }

  Future<void> _processAgentTools(
    InvocationContext context,
    LlmRequest request,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    if (agent.tools.isEmpty) {
      context.canonicalToolsCache = <BaseTool>[];
      return;
    }

    final ToolContext toolContext = Context(context);
    for (final Object toolUnion in agent.tools) {
      if (toolUnion is BaseToolset) {
        await toolUnion.processLlmRequest(
          toolContext: toolContext,
          llmRequest: request,
        );
      }
    }

    final List<BaseTool> tools = await agent.canonicalTools(
      ReadonlyContext(context),
    );
    for (final BaseTool tool in tools) {
      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );
    }
    if (context.liveRequestQueue != null) {
      markLiveFunctionDeclarationBehavior(request);
    }
    context.canonicalToolsCache = tools;
  }

  /// Marks `FunctionDeclaration.behavior` on [request] for live sessions.
  static void markLiveFunctionDeclarationBehavior(LlmRequest request) {
    final List<ToolDeclaration>? tools = request.config.tools;
    if (tools == null || tools.isEmpty) {
      return;
    }
    for (final ToolDeclaration geminiTool in tools) {
      for (final FunctionDeclaration declaration
          in geminiTool.functionDeclarations) {
        if (declaration.name.isEmpty) {
          continue;
        }
        final BaseTool? tool = request.toolsDict[declaration.name];
        if (tool == null) {
          continue;
        }
        if (flow_functions.isLiveStreamingTool(tool)) {
          declaration.behavior = ToolBehavior.nonBlocking;
        } else if (tool.behavior != null) {
          declaration.behavior = tool.behavior;
        } else if (tool.responseScheduling != null) {
          declaration.behavior = ToolBehavior.nonBlocking;
        }
      }
    }
  }

  Stream<Event> _postprocessAsync(
    InvocationContext context,
    LlmRequest request,
    LlmResponse response,
    Event modelResponseEvent,
  ) async* {
    await for (final Event event in _postprocessRunProcessorsAsync(
      context,
      response,
    )) {
      if (context.isAborted) {
        return;
      }
      yield event;
    }

    if (context.isAborted) {
      return;
    }

    final bool hasParts =
        response.content != null && response.content!.parts.isNotEmpty;
    if (response.partial != true &&
        response.errorCode == null &&
        response.finishReason == 'STOP' &&
        !hasMeaningfulContent(response) &&
        (context.runConfig?.streamingMode != StreamingMode.sse ||
            (hasParts && isFeatureEnabled(FeatureName.progressiveSseStreaming)))) {
      response.errorCode = 'MODEL_RETURNED_NO_CONTENT';
      final String defaultMessage = hasParts
          ? 'The model returned no actionable content (finish_reason=STOP with thought-only or whitespace-only parts).'
          : 'The model returned no content (finish_reason=STOP with empty parts).';
      response.errorMessage = response.errorMessage ?? defaultMessage;
    }

    if (response.content == null &&
        response.errorCode == null &&
        response.interrupted != true &&
        response.groundingMetadata == null) {
      return;
    }

    modelResponseEvent.timestamp = getTime();
    final Event finalized = _finalizeModelResponseEvent(
      request,
      response,
      modelResponseEvent,
    );
    if (context.isAborted) {
      return;
    }
    yield finalized;

    if (finalized.getFunctionCalls().isNotEmpty) {
      if (finalized.partial == true) {
        return;
      }

      await PersistBarrier.awaitPersisted(context, <Event>[finalized]);
      if (context.isAborted) {
        return;
      }

      await for (final Event event in _postprocessHandleFunctionCallsAsync(
        context,
        finalized,
        request,
      )) {
        if (context.isAborted) {
          return;
        }
        yield event;
      }
    }
  }

  Stream<Event> _postprocessRunProcessorsAsync(
    InvocationContext context,
    LlmResponse response,
  ) async* {
    for (final BaseLlmResponseProcessor processor in responseProcessors) {
      await for (final Event event in processor.runAsync(context, response)) {
        if (context.isAborted) {
          return;
        }
        yield event;
      }
    }
  }

  Stream<Event> _postprocessHandleFunctionCallsAsync(
    InvocationContext context,
    Event functionCallEvent,
    LlmRequest request,
  ) async* {
    if (context.isAborted) {
      return;
    }

    final Event? functionResponseEvent;
    try {
      functionResponseEvent = await flow_functions.handleFunctionCallsAsync(
        context,
        functionCallEvent,
        request.toolsDict,
      );
    } catch (error) {
      final Event? keptEvent = flow_functions.popKeptFunctionResponseEvent(
        error,
      );
      if (keptEvent != null && !context.isAborted) {
        yield keptEvent;
      }
      rethrow;
    }
    if (context.isAborted) {
      return;
    }

    if (functionResponseEvent == null) {
      return;
    }

    final Event? authEvent = flow_functions.generateAuthEvent(
      context,
      functionResponseEvent,
    );
    if (authEvent != null) {
      yield authEvent;
      context.endInvocation = true;
    }

    final Event? confirmationEvent = flow_functions
        .generateRequestConfirmationEvent(
          context,
          functionCallEvent,
          functionResponseEvent,
        );
    if (confirmationEvent != null) {
      yield confirmationEvent;
    }

    yield functionResponseEvent;

    final String? jsonResponse = output_schema.getStructuredModelResponse(
      functionResponseEvent,
    );
    if (jsonResponse != null) {
      yield output_schema.createFinalModelResponseEvent(context, jsonResponse);
    }

    final String? transferToAgent =
        functionResponseEvent.actions.transferToAgent;
    if (transferToAgent != null && transferToAgent.isNotEmpty) {
      final BaseAgent agentToRun = _getAgentToRun(context, transferToAgent);
      await for (final Event event in agentToRun.runAsync(context)) {
        if (context.isAborted) {
          return;
        }
        yield event;
      }
    }
  }

  Stream<LlmResponse> _callLlmAsync(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
  ) async* {
    if (context.isAborted) {
      return;
    }

    final LlmResponse? beforeResponse = await _handleBeforeModelCallback(
      context,
      request,
      modelResponseEvent,
    );
    if (context.isAborted) {
      return;
    }
    if (beforeResponse != null) {
      yield beforeResponse;
      return;
    }

    request.config.labels['adk_agent_name'] ??= context.agent.name;

    final BaseLlm llm = _getLlm(context);
    context.incrementLlmCallCount();

    bool streamCompleted = false;
    bool notifiedOnCancel = false;
    try {
      if (context.runConfig?.supportCfc == true) {
        if (context.liveRequestQueue == null ||
            context.liveRequestQueue!.closed) {
          context.liveRequestQueue = LiveRequestQueue();
        }
        await for (Event event in runLive(context)) {
          if (context.isAborted) {
            notifiedOnCancel = true;
            await _notifyModelCancelled(
              context,
              request,
              modelResponseEvent,
              AdkAbortException(
                context.abortSignal?.reason ?? 'Model call cancelled',
              ),
            );
            return;
          }
          final LlmResponse? altered = await _handleAfterModelCallback(
            context,
            event,
            modelResponseEvent,
          );
          if (context.isAborted) {
            notifiedOnCancel = true;
            await _notifyModelCancelled(
              context,
              request,
              modelResponseEvent,
              AdkAbortException(
                context.abortSignal?.reason ?? 'Model call cancelled',
              ),
            );
            return;
          }
          if (altered != null && !identical(altered, event)) {
            event = altered is Event
                ? altered
                : _finalizeModelResponseEvent(request, altered, event);
          }
          if (context.runConfig?.streamingMode == StreamingMode.sse ||
              event.partial != true) {
            yield event;
          }
          if (event.turnComplete == true) {
            context.liveRequestQueue?.close();
          }
        }
        streamCompleted = true;
        return;
      }

      await for (LlmResponse response in llm.generateContent(
        request.sanitizedForModelCall(),
        stream: context.runConfig?.streamingMode == StreamingMode.sse,
      )) {
        if (context.isAborted) {
          notifiedOnCancel = true;
          await _notifyModelCancelled(
            context,
            request,
            modelResponseEvent,
            AdkAbortException(
              context.abortSignal?.reason ?? 'Model call cancelled',
            ),
          );
          return;
        }
        final LlmResponse? altered = await _handleAfterModelCallback(
          context,
          response,
          modelResponseEvent,
        );
        if (context.isAborted) {
          notifiedOnCancel = true;
          await _notifyModelCancelled(
            context,
            request,
            modelResponseEvent,
            AdkAbortException(
              context.abortSignal?.reason ?? 'Model call cancelled',
            ),
          );
          return;
        }
        if (altered != null) {
          response = altered;
        }
        yield response;
      }
      streamCompleted = true;
    } catch (error) {
      if (error is AdkAbortException || context.isAborted) {
        notifiedOnCancel = true;
        final Exception cancelException = error is Exception
            ? error
            : AdkAbortException(error.toString());
        await _notifyModelCancelled(
          context,
          request,
          modelResponseEvent,
          cancelException,
        );
        rethrow;
      }
      notifiedOnCancel = true;
      final Exception exception = error is Exception
          ? error
          : Exception(error.toString());
      final LlmResponse? handled = await _handleModelErrorCallbacks(
        context,
        request,
        modelResponseEvent,
        exception,
      );
      if (handled != null) {
        yield handled;
        return;
      }
      rethrow;
    } finally {
      if (!streamCompleted && !notifiedOnCancel) {
        await _notifyModelCancelled(
          context,
          request,
          modelResponseEvent,
          AdkAbortException(
            context.abortSignal?.reason ?? 'Model call cancelled',
          ),
        );
      }
    }
  }

  Future<void> _notifyModelCancelled(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
    Exception cancelled,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    try {
      await context.pluginManager.runOnModelErrorCallback(
        callbackContext: callbackContext,
        llmRequest: request,
        error: cancelled,
      );
    } catch (_) {
      // Ignore callback errors during cancellation cleanup.
    }

    for (final OnModelErrorCallback callback
        in agent.canonicalOnModelErrorCallbacks) {
      try {
        await runWithCallbackScope<LlmResponse?>(
          CallbackInfo(
            type: CallbackType.onModelError,
            name: resolveCallbackName(callback),
          ),
          () => callback(callbackContext, request, cancelled),
          callbackContext: callbackContext,
        );
      } catch (_) {
        // Ignore callback errors during cancellation cleanup.
      }
    }
  }

  Future<LlmResponse?> _handleBeforeModelCallback(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    final LlmResponse? pluginOverride = await context.pluginManager
        .runBeforeModelCallback(
          callbackContext: callbackContext,
          llmRequest: request,
        );
    if (pluginOverride != null) {
      return pluginOverride;
    }

    for (final BeforeModelCallback callback
        in agent.canonicalBeforeModelCallbacks) {
      final LlmResponse? response = await runWithCallbackScope<LlmResponse?>(
        CallbackInfo(
          type: CallbackType.beforeModel,
          name: resolveCallbackName(callback),
        ),
        () => callback(callbackContext, request),
        callbackContext: callbackContext,
      );
      if (response != null) {
        return response;
      }
    }

    return null;
  }

  Future<LlmResponse?> _handleAfterModelCallback(
    InvocationContext context,
    LlmResponse response,
    Event modelResponseEvent,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );
    final CallbackContext pluginCallbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    final LlmResponse? pluginOverride = await context.pluginManager
        .runAfterModelCallback(
          callbackContext: pluginCallbackContext,
          llmResponse: response,
        );
    if (pluginOverride != null) {
      final LlmResponse? withGrounding = await _maybeAddGroundingMetadata(
        context,
        response,
        pluginOverride,
      );
      return _inheritUnsetStreamingFields(response, withGrounding);
    }

    for (final AfterModelCallback callback
        in agent.canonicalAfterModelCallbacks) {
      final LlmResponse? altered = await runWithCallbackScope<LlmResponse?>(
        CallbackInfo(
          type: CallbackType.afterModel,
          name: resolveCallbackName(callback),
        ),
        () => callback(callbackContext, response),
        callbackContext: callbackContext,
      );
      if (altered != null) {
        final LlmResponse? withGrounding = await _maybeAddGroundingMetadata(
          context,
          response,
          altered,
        );
        return _inheritUnsetStreamingFields(response, withGrounding);
      }
    }

    return _maybeAddGroundingMetadata(context, response);
  }

  static LlmResponse? _inheritUnsetStreamingFields(
    LlmResponse original,
    LlmResponse? replacement,
  ) {
    if (replacement == null || identical(replacement, original)) {
      return replacement;
    }
    final bool inheritPartial =
        replacement.partial == null && original.partial != null;
    final bool inheritTurnComplete =
        replacement.turnComplete == null && original.turnComplete != null;
    final bool inheritUsageMetadata =
        replacement.usageMetadata == null && original.usageMetadata != null;
    final bool inheritCacheCreationTokenCount =
        replacement.cacheCreationTokenCount == null &&
        original.cacheCreationTokenCount != null;
    if (!inheritPartial &&
        !inheritTurnComplete &&
        !inheritUsageMetadata &&
        !inheritCacheCreationTokenCount) {
      return replacement;
    }
    return replacement.copyWith(
      partial: inheritPartial ? original.partial : replacement.partial,
      turnComplete: inheritTurnComplete
          ? original.turnComplete
          : replacement.turnComplete,
      usageMetadata: inheritUsageMetadata
          ? original.usageMetadata
          : replacement.usageMetadata,
      cacheCreationTokenCount: inheritCacheCreationTokenCount
          ? original.cacheCreationTokenCount
          : replacement.cacheCreationTokenCount,
    );
  }

  Future<LlmResponse?> _maybeAddGroundingMetadata(
    InvocationContext context,
    LlmResponse response, [
    LlmResponse? override,
  ]) async {
    final LlmAgent agent = context.agent as LlmAgent;
    List<BaseTool>? tools = context.canonicalToolsCache;
    if (tools == null) {
      tools = await agent.canonicalTools(ReadonlyContext(context));
      context.canonicalToolsCache = tools;
    }
    final bool hasGroundingTool = tools.any(
      (BaseTool tool) =>
          tool.name == 'google_search_agent' ||
          (tool is McpTool && tool.propagateGroundingMetadata),
    );
    if (!hasGroundingTool) {
      return override;
    }

    final Object? groundingMetadata =
        context.session.state['temp:_adk_grounding_metadata'];
    if (groundingMetadata == null) {
      return override;
    }

    final LlmResponse target = override ?? response;
    target.groundingMetadata = groundingMetadata;
    return target;
  }

  Future<LlmResponse?> _handleModelErrorCallbacks(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
    Exception error,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    final LlmResponse? pluginHandled = await context.pluginManager
        .runOnModelErrorCallback(
          callbackContext: callbackContext,
          llmRequest: request,
          error: error,
        );
    if (pluginHandled != null) {
      return pluginHandled;
    }

    for (final OnModelErrorCallback callback
        in agent.canonicalOnModelErrorCallbacks) {
      final LlmResponse? handled = await runWithCallbackScope<LlmResponse?>(
        CallbackInfo(
          type: CallbackType.onModelError,
          name: resolveCallbackName(callback),
        ),
        () => callback(callbackContext, request, error),
        callbackContext: callbackContext,
      );
      if (handled != null) {
        return handled;
      }
    }

    return null;
  }

  Event _finalizeModelResponseEvent(
    LlmRequest request,
    LlmResponse response,
    Event modelResponseEvent,
  ) {
    final Event finalized = modelResponseEvent.copyWith(
      modelVersion: response.modelVersion,
      content: response.content?.copyWith(),
      partial: response.partial,
      turnComplete: response.turnComplete,
      finishReason: response.finishReason,
      errorCode: response.errorCode,
      errorMessage: response.errorMessage,
      interrupted: response.interrupted,
      customMetadata: response.customMetadata,
      usageMetadata: response.usageMetadata,
      cacheCreationTokenCount: response.cacheCreationTokenCount,
      inputTranscription: response.inputTranscription,
      outputTranscription: response.outputTranscription,
      avgLogprobs: response.avgLogprobs,
      logprobsResult: response.logprobsResult,
      cacheMetadata: response.cacheMetadata,
      citationMetadata: response.citationMetadata,
      groundingMetadata: response.groundingMetadata,
      interactionId: response.interactionId,
      liveSessionId: response.liveSessionId,
      liveSessionResumptionUpdate: response.liveSessionResumptionUpdate,
      goAway: response.goAway,
      voiceActivity: response.voiceActivity,
    );

    if (finalized.content != null) {
      final List<FunctionCall> calls = finalized.getFunctionCalls();
      if (calls.isNotEmpty) {
        flow_functions.populateClientFunctionCallId(finalized);
        finalized.longRunningToolIds = flow_functions
            .getLongRunningFunctionCalls(calls, request.toolsDict);
        _populateToolDisplayNames(finalized, calls, request.toolsDict);
      }
    }

    return finalized;
  }

  void _populateToolDisplayNames(
    Event modelResponseEvent,
    List<FunctionCall> functionCalls,
    Map<String, BaseTool> toolsDict,
  ) {
    final Map<String, String> displayNames = <String, String>{};
    for (final FunctionCall functionCall in functionCalls) {
      final String name = functionCall.name;
      if (name.isEmpty || !toolsDict.containsKey(name)) {
        continue;
      }
      final BaseTool tool = toolsDict[name]!;
      String? title;
      final String? directTitle = tool.title?.trim();
      if (directTitle != null && directTitle.isNotEmpty) {
        title = directTitle;
      } else {
        final Object? metaTitle = tool.customMetadata?['title'];
        if (metaTitle is String) {
          final String trimmedMeta = metaTitle.trim();
          if (trimmedMeta.isNotEmpty) {
            title = trimmedMeta;
          }
        }
      }
      if (title != null && title.isNotEmpty) {
        displayNames[name] = title;
      }
    }
    if (displayNames.isNotEmpty) {
      final Map<String, dynamic> customMetadata =
          modelResponseEvent.customMetadata != null
          ? Map<String, dynamic>.from(modelResponseEvent.customMetadata!)
          : <String, dynamic>{};
      final Object? rawExisting = customMetadata[toolDisplayNamesMetadataKey];
      final Map<String, Object?> existingNames = rawExisting is Map
          ? rawExisting.map((Object? k, Object? v) => MapEntry('$k', v))
          : <String, Object?>{};
      customMetadata[toolDisplayNamesMetadataKey] = <String, Object?>{
        ...existingNames,
        ...displayNames,
      };
      modelResponseEvent.customMetadata = customMetadata;
    }
  }

  /// Flushes cached live audio and visual events based on control flags in [response].
  Future<List<Event>> handleControlEventFlush(
    InvocationContext context,
    LlmResponse response,
  ) async {
    if (response.interrupted == true) {
      return audioCacheManager.flushCaches(
        context,
        flushUserAudio: false,
        flushUserVisual: false,
        flushModelAudio: true,
      );
    }
    if (response.turnComplete == true) {
      return audioCacheManager.flushCaches(
        context,
        flushUserAudio: true,
        flushUserVisual: true,
        flushModelAudio: true,
      );
    }
    return const <Event>[];
  }

  BaseLlm _getLlm(InvocationContext context) {
    final LlmAgent agent = context.agent as LlmAgent;
    final Object? rawConfig = context.session.state['_adk_replay_config'];
    if (rawConfig is Map) {
      final ConformanceJson config = rawConfig is Map<String, Object?>
          ? rawConfig
          : asConformanceObjectMap(rawConfig);
      context.session.state['_adk_replay_config'] = config;
      final int userMessageIndex = asConformanceInt(
        config['user_message_index'],
      );
      final Object? rawReplayIndexes = config['_adk_replay_indexes'];
      final ConformanceJson replayIndexes =
          rawReplayIndexes is Map<String, Object?>
          ? rawReplayIndexes
          : asConformanceObjectMap(rawReplayIndexes);
      final String replayKey = '${agent.name}::$userMessageIndex';
      final int currentReplayIndex = asConformanceInt(replayIndexes[replayKey]);
      config['current_replay_index'] = currentReplayIndex;
      replayIndexes[replayKey] = currentReplayIndex + 1;
      config['_adk_replay_indexes'] = replayIndexes;
      return ConformanceReplayLlm(config: config, agentName: agent.name);
    }
    return agent.canonicalModel;
  }

  BaseAgent _getAgentToRun(
    InvocationContext context,
    String agentName, {
    bool allowSelfTransfer = false,
  }) {
    final BaseAgent currentAgent = context.agent;
    final BaseAgent? agent = currentAgent.rootAgent.findAgent(agentName);
    if (agent == null) {
      throw StateError('Agent $agentName not found in the agent tree.');
    }
    if (agent.name == currentAgent.name) {
      if (allowSelfTransfer) {
        return agent;
      }
      throw ArgumentError("Agent '$agentName' cannot transfer to itself.");
    }
    if (currentAgent is LlmAgent) {
      if (agent.parentAgent != null &&
          currentAgent.parentAgent != null &&
          agent.parentAgent!.name == currentAgent.parentAgent!.name &&
          currentAgent.disallowTransferToPeers) {
        throw ArgumentError(
          "Cannot transfer from '${currentAgent.name}' to peer agent '$agentName': disallow_transfer_to_peers is set.",
        );
      }
      if (currentAgent.parentAgent != null &&
          currentAgent.parentAgent!.name == agent.name &&
          currentAgent.disallowTransferToParent) {
        throw ArgumentError(
          "Cannot transfer from '${currentAgent.name}' to parent agent '$agentName': disallow_transfer_to_parent is set.",
        );
      }
      final Set<String> allowedNames = getTransferTargets(
        currentAgent,
      ).map((BaseAgent a) => a.name).toSet();
      if (!allowedNames.contains(agent.name)) {
        throw ArgumentError(
          "Agent '${currentAgent.name}' is not allowed to transfer to agent '$agentName'.",
        );
      }
    }
    return agent;
  }
}

/// Returns whether the LLM response contains meaningful, actionable content.
///
/// A response is considered to have meaningful content if it contains at least
/// one part with:
/// - An active function call or function response
/// - Executable code or a code execution result
/// - Inline data or file data
/// - Non-thought, non-whitespace text
bool hasMeaningfulContent(LlmResponse? response) {
  if (response == null ||
      response.content == null ||
      response.content!.parts.isEmpty) {
    return false;
  }

  for (final Part part in response.content!.parts) {
    if (part.functionCall != null) {
      return true;
    }
    if (part.functionResponse != null) {
      return true;
    }
    if (part.executableCode != null) {
      return true;
    }
    if (part.codeExecutionResult != null) {
      return true;
    }
    if (part.inlineData != null) {
      return true;
    }
    if (part.fileData != null) {
      return true;
    }
    if (!part.thought && part.text != null && part.text!.trim().isNotEmpty) {
      return true;
    }
  }

  return false;
}
