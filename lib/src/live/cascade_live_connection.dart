/// Bidirectional connection orchestrating a cascaded STT -> LLM -> TTS pipeline.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import '../agents/live_request_queue.dart';
import '../features/_feature_decorator.dart';
import '../features/_feature_registry.dart';
import '../models/base_llm.dart';
import '../models/base_llm_connection.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';
import 'cascade_live_events.dart';
import 'transforms.dart';

/// Exception thrown when [CascadeLiveConnection.receive] is called on an
/// already-closed connection.
///
/// ```dart
/// final error = CascadeConnectionClosedException();
/// ```
class CascadeConnectionClosedException extends StateError {
  /// Creates a closed-connection exception with an optional [message].
  CascadeConnectionClosedException([
    super.message = 'CascadeLive connection closed.',
  ]);
}

/// Transcription payload emitted on [LlmResponse.inputTranscription] and
/// [LlmResponse.outputTranscription].
///
/// Implements [MapMixin] so consumers inspecting either `transcription.text` /
/// `transcription.finished` or `transcription['text']` /
/// `transcription['finished']` work interchangeably.
///
/// ```dart
/// final tx = LiveTranscription(text: 'Hello world', finished: true);
/// print(tx.text); // Hello world
/// print(tx['finished']); // true
/// ```
class LiveTranscription with MapMixin<String, Object?> {
  /// Creates a transcription record with [text] and [finished] status.
  const LiveTranscription({required this.text, this.finished = false});

  /// Transcribed text content.
  final String text;

  /// Whether this transcription represents a finalized segment.
  final bool finished;

  @override
  Object? operator [](Object? key) {
    return switch (key) {
      'text' => text,
      'finished' => finished,
      _ => null,
    };
  }

  @override
  void operator []=(String key, Object? value) {
    throw UnsupportedError('LiveTranscription is immutable.');
  }

  @override
  void clear() {
    throw UnsupportedError('LiveTranscription is immutable.');
  }

  @override
  Iterable<String> get keys => const <String>['text', 'finished'];

  @override
  Object? remove(Object? key) {
    throw UnsupportedError('LiveTranscription is immutable.');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveTranscription &&
          other.text == text &&
          other.finished == finished;

  @override
  int get hashCode => Object.hash(LiveTranscription, text, finished);

  @override
  String toString() => 'LiveTranscription(text: $text, finished: $finished)';
}

/// Structured realtime input payload for [CascadeLiveConnection.sendRealtimeInput].
///
/// ```dart
/// final input = LiveClientRealtimeInput(
///   mediaChunks: [InlineData(mimeType: 'audio/pcm;rate=16000', data: [0, 1])],
/// );
/// ```
class LiveClientRealtimeInput {
  /// Creates a realtime input payload.
  const LiveClientRealtimeInput({
    this.mediaChunks,
    this.audio,
    this.audioStreamEnd = false,
    this.activityStart,
    this.activityEnd,
  });

  /// Media chunks to forward to the connection.
  final List<InlineData>? mediaChunks;

  /// Single audio chunk to forward to the connection.
  final InlineData? audio;

  /// Whether the audio input stream has ended.
  final bool audioStreamEnd;

  /// Optional explicit activity-start marker.
  final LiveActivityStart? activityStart;

  /// Optional explicit activity-end marker.
  final LiveActivityEnd? activityEnd;
}

class _AsyncQueue<T> {
  final Queue<T> _items = Queue<T>();
  final Queue<Completer<T>> _waiters = Queue<Completer<T>>();

  bool get isEmpty => _items.isEmpty;

  void add(T item) {
    if (_waiters.isNotEmpty) {
      final Completer<T> waiter = _waiters.removeFirst();
      waiter.complete(item);
      return;
    }
    _items.addLast(item);
  }

  Future<T> get() {
    if (_items.isNotEmpty) {
      return Future<T>.value(_items.removeFirst());
    }
    final Completer<T> waiter = Completer<T>();
    _waiters.addLast(waiter);
    return waiter.future;
  }
}

/// Live connection bridging STT ingress, text reasoning, and TTS egress.
///
/// Audio input from the client is processed by the [LiveIngress] transform.
/// When endpointing occurs, the recognized text triggers a reasoning turn on
/// the underlying [BaseLlm]. Streaming text responses are synthesized by the
/// [LiveEgress] transform into audio chunks and output transcriptions
/// delivered to the client.
///
/// ```dart
/// final connection = CascadeLiveConnection(
///   LlmRequest(model: 'gemini-2.5-flash'),
///   llm,
///   sttTransform,
///   ttsTransform,
/// );
/// await connection.sendContent(Content.userText('Hello'));
/// await connection.close();
/// ```
class CascadeLiveConnection extends BaseLlmConnection {
  /// Creates a cascaded live connection for [llmRequest] using [llm], [stt],
  /// and [tts].
  CascadeLiveConnection(
    LlmRequest llmRequest,
    BaseLlm llm,
    LiveIngress stt,
    LiveEgress tts, {
    this.onEmit,
  }) : _llmRequest = llmRequest,
       _llm = llm,
       _stt = stt,
       _tts = tts,
       _contents = llmRequest.contents
           .map((Content c) => c.copyWith())
           .toList() {
    experimental(FeatureName.cascadeLive).checkEnabled();
    unawaited(_pumpIngress());
  }

  static const String _activityStartMimeType =
      'application/vnd.adk.activity_start';
  static const String _activityEndMimeType = 'application/vnd.adk.activity_end';

  final LlmRequest _llmRequest;
  final BaseLlm _llm;
  final LiveIngress _stt;
  final LiveEgress _tts;

  /// Optional observer invoked whenever a response is emitted.
  void Function(LlmResponse response)? onEmit;

  final List<Content> _contents;
  final _AsyncQueue<InlineData?> _audioIn = _AsyncQueue<InlineData?>();
  final Set<String?> _droppedMimeTypes = <String?>{};
  final _AsyncQueue<LlmResponse?> _out = _AsyncQueue<LlmResponse?>();

  final CancelSignal _cancel = CancelSignal();
  bool _closed = false;
  Object? _error;
  StackTrace? _errorStackTrace;
  LlmResponse? _pendingFunctionCall;
  bool _rerunRequested = false;

  Future<void>? _reasoningTask;
  StreamSubscription<EgressEvent>? _activeEgressSubscription;
  Future<void> Function()? _activeTextStreamCloser;

  StreamSubscription<IngressEvent>? _activeIngressSubscription;

  /// Unmodifiable snapshot of the conversation contents replayed to the LLM.
  List<Content> get contents => List<Content>.unmodifiable(_contents);

  /// Alias for [contents] returning the connection's conversation history.
  List<Content> get history => List<Content>.unmodifiable(_contents);

  /// Non-audio MIME types that have been dropped and logged.
  Set<String?> get droppedMimeTypes =>
      Set<String?>.unmodifiable(_droppedMimeTypes);

  /// Seeds the conversation [history] without triggering a reasoning turn.
  @override
  Future<void> sendHistory(List<Content> history) async {
    _contents
      ..clear()
      ..addAll(history.map((Content c) => c.copyWith()));
  }

  /// Appends non-partial [content] and starts a reasoning turn.
  ///
  /// When [partial] is `true`, [content] is ignored and no turn is started.
  @override
  Future<void> sendContent(Content content, {bool partial = false}) async {
    if (partial) {
      return;
    }
    _contents.add(content.copyWith());
    _startReasoning();
  }

  /// Accepts audio frames and realtime control messages from the client.
  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {
    await sendRealtimeInput(blob);
  }

  /// Accepts audio frames, [InlineData], [LiveActivityStart],
  /// [LiveActivityEnd], or [LiveClientRealtimeInput] from the client.
  Future<void> sendRealtimeInput(Object blob) async {
    if (blob is LiveActivityStart) {
      await _onSpeechStarted(const UserSpeechStarted());
      return;
    }
    if (blob is LiveActivityEnd) {
      _audioIn.add(null);
      return;
    }
    if (blob is LiveClientRealtimeInput) {
      if (blob.activityStart != null) {
        await _onSpeechStarted(const UserSpeechStarted());
      }
      if (blob.activityEnd != null || blob.audioStreamEnd) {
        _audioIn.add(null);
      }
      if (blob.audio != null) {
        await sendRealtimeInput(blob.audio!);
      }
      if (blob.mediaChunks != null) {
        for (final InlineData chunk in blob.mediaChunks!) {
          await sendRealtimeInput(chunk);
        }
      }
      return;
    }
    if (blob is RealtimeBlob) {
      if (blob.mimeType == _activityStartMimeType) {
        await _onSpeechStarted(const UserSpeechStarted());
        return;
      }
      if (blob.mimeType == _activityEndMimeType) {
        _audioIn.add(null);
        return;
      }
      if (blob.mimeType.startsWith('audio/')) {
        _audioIn.add(
          InlineData(
            mimeType: blob.mimeType,
            data: List<int>.from(blob.data),
          ),
        );
      } else if (!_droppedMimeTypes.contains(blob.mimeType)) {
        _droppedMimeTypes.add(blob.mimeType);
        developer.log(
          'CascadeLive accepts only audio input; dropping ${blob.mimeType} blobs.',
          name: 'adk_dart.live',
        );
      }
      return;
    }
    if (blob is InlineData) {
      if (blob.mimeType.startsWith('audio/')) {
        _audioIn.add(blob.copyWith());
      } else if (!_droppedMimeTypes.contains(blob.mimeType)) {
        _droppedMimeTypes.add(blob.mimeType);
        developer.log(
          'CascadeLive accepts only audio input; dropping ${blob.mimeType} blobs.',
          name: 'adk_dart.live',
        );
      }
      return;
    }
  }

  /// Signals the start of user speech activity when manual VAD is enabled.
  @override
  Future<void> sendActivityStart() async {
    await _onSpeechStarted(const UserSpeechStarted());
  }

  /// Signals the end of user speech activity, finalizing the current audio segment.
  @override
  Future<void> sendActivityEnd() async {
    _audioIn.add(null);
  }

  /// Yields [LlmResponse] events until the connection is closed.
  ///
  /// Throws the ingress error if the STT transform failed, or throws
  /// [CascadeConnectionClosedException] if called after the connection has
  /// already closed.
  @override
  Stream<LlmResponse> receive() async* {
    if (_closed && _out.isEmpty) {
      if (_error != null) {
        Error.throwWithStackTrace(
          _error!,
          _errorStackTrace ?? StackTrace.current,
        );
      }
      throw CascadeConnectionClosedException();
    }
    while (true) {
      final LlmResponse? item = await _out.get();
      if (item == null) {
        if (_error != null) {
          Error.throwWithStackTrace(
            _error!,
            _errorStackTrace ?? StackTrace.current,
          );
        }
        return;
      }
      yield item;
    }
  }

  /// Tears down the ingress pump and any in-flight reasoning turn.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    _cancel.set();
    _audioIn.add(null);

    final StreamSubscription<EgressEvent>? egressSub =
        _activeEgressSubscription;
    _activeEgressSubscription = null;
    if (egressSub != null) {
      try {
        await egressSub.cancel();
      } catch (_) {}
    }

    final Future<void> Function()? textCloser = _activeTextStreamCloser;
    _activeTextStreamCloser = null;
    if (textCloser != null) {
      try {
        await textCloser();
      } catch (_) {}
    }

    final StreamSubscription<IngressEvent>? ingressSub =
        _activeIngressSubscription;
    _activeIngressSubscription = null;
    if (ingressSub != null) {
      try {
        await ingressSub.cancel();
      } catch (_) {}
    }

    _out.add(null);
  }

  Stream<InlineData> _drainAudio(InlineData first) async* {
    yield first;
    while (true) {
      final InlineData? blob = await _audioIn.get();
      if (blob == null) {
        return;
      }
      yield blob;
    }
  }

  Future<void> _pumpIngress() async {
    try {
      while (!_closed) {
        final InlineData? first = await _audioIn.get();
        if (first == null || _closed) {
          continue;
        }
        final Completer<void> segmentDone = Completer<void>();
        Future<void> chain = Future<void>.value();
        final StreamSubscription<IngressEvent> sub = _stt
            .call(_drainAudio(first))
            .listen(
              (IngressEvent ingressEvent) {
                chain = chain.then((_) async {
                  if (_closed) {
                    return;
                  }
                  await _onIngressEvent(ingressEvent);
                });
              },
              onError: (Object error, StackTrace stackTrace) {
                chain = chain.then((_) {
                  if (!segmentDone.isCompleted) {
                    segmentDone.completeError(error, stackTrace);
                  }
                });
              },
              onDone: () {
                chain = chain.then((_) {
                  if (!segmentDone.isCompleted) {
                    segmentDone.complete();
                  }
                });
              },
              cancelOnError: true,
            );
        _activeIngressSubscription = sub;
        try {
          await segmentDone.future;
        } finally {
          if (identical(_activeIngressSubscription, sub)) {
            _activeIngressSubscription = null;
          }
          try {
            await sub.cancel();
          } catch (_) {}
        }
      }
    } catch (error, stackTrace) {
      if (_closed) {
        return;
      }
      developer.log(
        'Cascade ingress failed; closing the live connection.',
        name: 'adk_dart.live',
        error: error,
        stackTrace: stackTrace,
      );
      _error = error;
      _errorStackTrace = stackTrace;
      await close();
    }
  }

  Future<void> _onIngressEvent(IngressEvent ingressEvent) async {
    if (ingressEvent is PartialTranscript) {
      _emit(
        LlmResponse(
          inputTranscription: LiveTranscription(
            text: ingressEvent.text,
            finished: false,
          ),
          partial: true,
        ),
      );
    } else if (ingressEvent is UserSpeechStarted) {
      await _onSpeechStarted(ingressEvent);
    } else if (ingressEvent is UserTurnFinished) {
      await _onUserTurnFinished(ingressEvent);
    } else {
      developer.log(
        'Ignoring unknown ingress event: $ingressEvent',
        name: 'adk_dart.live',
      );
    }
  }

  Future<void> _onSpeechStarted(UserSpeechStarted event) async {
    // Reserved for speech-onset barge-in handling.
  }

  Future<void> _onUserTurnFinished(UserTurnFinished event) async {
    _emit(
      LlmResponse(
        inputTranscription: LiveTranscription(
          text: event.text,
          finished: true,
        ),
        partial: false,
      ),
    );
    _contents.add(Content(role: 'user', parts: <Part>[Part.text(event.text)]));
    _startReasoning();
  }

  void _startReasoning() {
    if (_closed) {
      return;
    }
    if (_reasoningTask != null) {
      _rerunRequested = true;
      return;
    }
    _cancel.reset();
    _reasoningTask = _driveTurns();
  }

  Future<void> _driveTurns() async {
    try {
      while (true) {
        await _runTurn();
        if (_closed || !_rerunRequested) {
          return;
        }
        _rerunRequested = false;
        _cancel.reset();
      }
    } finally {
      _reasoningTask = null;
      if (!_closed && _rerunRequested) {
        _rerunRequested = false;
        _startReasoning();
      }
    }
  }

  Future<void> _runTurn() async {
    _pendingFunctionCall = null;
    final List<String> spoken = <String>[];
    final ({Stream<String> stream, Future<void> Function() close}) textPipe =
        _createClosableTextStream();
    _activeTextStreamCloser = textPipe.close;

    try {
      final Completer<void> egressDone = Completer<void>();
      final StreamSubscription<EgressEvent> sub = _tts
          .call(textPipe.stream, cancel: _cancel)
          .listen(
            (EgressEvent event) {
              if (_closed) {
                return;
              }
              if (event is AudioChunk) {
                _emit(
                  LlmResponse(
                    content: Content(
                      role: 'model',
                      parts: <Part>[
                        Part.fromInlineData(
                          mimeType: event.blob.mimeType,
                          data: List<int>.from(event.blob.data),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (event is AgentSpokenOutput) {
                spoken.add(event.text);
                _emit(
                  LlmResponse(
                    outputTranscription: LiveTranscription(
                      text: event.text,
                      finished: false,
                    ),
                    partial: true,
                  ),
                );
              } else {
                developer.log(
                  'Ignoring unknown egress event: $event',
                  name: 'adk_dart.live',
                );
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!egressDone.isCompleted) {
                egressDone.completeError(error, stackTrace);
              }
            },
            onDone: () {
              if (!egressDone.isCompleted) {
                egressDone.complete();
              }
            },
            cancelOnError: true,
          );
      _activeEgressSubscription = sub;
      try {
        await egressDone.future;
      } finally {
        if (identical(_activeEgressSubscription, sub)) {
          _activeEgressSubscription = null;
        }
        try {
          await sub.cancel();
        } catch (_) {}
        await textPipe.close();
        if (identical(_activeTextStreamCloser, textPipe.close)) {
          _activeTextStreamCloser = null;
        }
      }

      if (_closed) {
        return;
      }

      _recordSpoken(spoken);

      if (_pendingFunctionCall != null) {
        final LlmResponse response = _pendingFunctionCall!;
        _pendingFunctionCall = null;
        final Content functionCalls = Content(
          role: 'model',
          parts: <Part>[
            for (final Part part in response.content?.parts ?? const <Part>[])
              if (part.functionCall != null) part.copyWith(),
          ],
        );
        _contents.add(functionCalls);
        _emit(response.copyWith(content: functionCalls));
        return;
      }

      _emit(LlmResponse(turnComplete: true));
    } catch (error, stackTrace) {
      await textPipe.close();
      if (_closed) {
        return;
      }
      developer.log(
        'Cascade reasoning turn failed.',
        name: 'adk_dart.live',
        error: error,
        stackTrace: stackTrace,
      );
      _recordSpoken(spoken);
      _emit(
        LlmResponse(
          errorCode: 'CASCADE_TURN_FAILED',
          errorMessage: 'Cascaded reasoning turn encountered an error.',
          turnComplete: true,
        ),
      );
    }
  }

  void _recordSpoken(List<String> spoken) {
    if (spoken.isEmpty) {
      return;
    }
    final String spokenText = spoken.join();
    _contents.add(
      Content(role: 'model', parts: <Part>[Part.text(spokenText)]),
    );
    _emit(
      LlmResponse(
        outputTranscription: LiveTranscription(
          text: spokenText,
          finished: true,
        ),
        partial: false,
      ),
    );
  }

  ({Stream<String> stream, Future<void> Function() close})
  _createClosableTextStream() {
    StreamSubscription<String>? innerSub;
    late final StreamController<String> controller;
    bool closed = false;

    Future<void> closeStream() async {
      if (closed) {
        return;
      }
      closed = true;
      final StreamSubscription<String>? sub = innerSub;
      innerSub = null;
      if (sub != null) {
        await sub.cancel();
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    controller = StreamController<String>(
      onListen: () {
        if (closed) {
          if (!controller.isClosed) {
            unawaited(controller.close());
          }
          return;
        }
        innerSub = _streamText().listen(
          (String chunk) {
            if (!closed && !controller.isClosed) {
              controller.add(chunk);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!closed && !controller.isClosed) {
              controller.addError(error, stackTrace);
              unawaited(controller.close());
            }
          },
          onDone: () {
            if (!closed && !controller.isClosed) {
              unawaited(controller.close());
            }
          },
          cancelOnError: true,
        );
      },
      onCancel: closeStream,
    );

    return (stream: controller.stream, close: closeStream);
  }

  Stream<String> _streamText() async* {
    final LlmRequest request = _buildRequest();
    bool streamed = false;

    await for (final LlmResponse response in _llm.generateContent(
      request,
      stream: true,
    )) {
      if (response.errorCode != null) {
        _emit(response);
        return;
      }
      final Content? content = response.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      if (content.parts.any((Part part) => part.functionCall != null)) {
        if (response.partial == true) {
          continue;
        }
        _pendingFunctionCall = response;
        if (!streamed) {
          for (final Part part in content.parts) {
            if (part.text != null && part.text!.isNotEmpty && !part.thought) {
              yield part.text!;
            }
          }
        }
        return;
      }
      if (streamed && response.partial != true) {
        continue;
      }
      for (final Part part in content.parts) {
        if (part.text != null && part.text!.isNotEmpty && !part.thought) {
          streamed = true;
          yield part.text!;
        }
      }
    }
  }

  LlmRequest _buildRequest() {
    return LlmRequest(
      model: _llm.model,
      contents: _contents.map((Content c) => c.copyWith()).toList(),
      config: _llmRequest.config.copyWith(),
      liveConnectConfig: _llmRequest.liveConnectConfig.copyWith(),
      toolsDict: Map<String, dynamic>.from(_llmRequest.toolsDict).map(
        (String k, dynamic v) => MapEntry(k, v),
      ),
      cacheConfig: _llmRequest.cacheConfig,
      cacheMetadata: _llmRequest.cacheMetadata,
      cacheableContentsTokenCount: _llmRequest.cacheableContentsTokenCount,
      previousInteractionId: _llmRequest.previousInteractionId,
      isManagedAgent: _llmRequest.isManagedAgent,
      serviceTier: _llmRequest.serviceTier,
    );
  }

  void _emit(LlmResponse response) {
    if (!_closed) {
      onEmit?.call(response);
      _out.add(response);
    }
  }
}
