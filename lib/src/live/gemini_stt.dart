/// Speech-to-text transform backed by Gemini streaming transcription.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../features/_feature_registry.dart';
import '../models/base_llm.dart';
import '../models/base_llm_connection.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../types/content.dart';
import 'cascade_live_events.dart';
import 'transforms.dart';

const String _defaultSttModel = 'gemini-3.5-transcribe-live';
const int _defaultSilenceDurationMs = 500;
const int _defaultSampleRate = 16000;
const int _bytesPerSample = 2;
const int _defaultMaxReplayMs = 10000;
const double _defaultSessionRotationSeconds = 480.0;
const int _defaultMaxReconnects = 2;
const double _defaultStableSessionSeconds = 30.0;
const int _flushSilenceMarginMs = 200;

const Set<int> _transientCloseCodes = <int>{
  1000,
  1001,
  1006,
  1011,
  1012,
  1013,
  1014,
};

const Set<int> _transientStatusCodes = <int>{408, 429, 500, 502, 503, 504};

/// Extracts the PCM sample rate from [mimeType] (e.g. `audio/pcm;rate=24000`),
/// defaulting to `16000` Hz when unspecified or invalid.
int sampleRateOfAudioMime(String? mimeType) {
  final List<String> parts = (mimeType ?? '').toLowerCase().split(';');
  for (int i = 1; i < parts.length; i++) {
    final String parameter = parts[i];
    final int eq = parameter.indexOf('=');
    if (eq < 0) {
      continue;
    }
    final String name = parameter.substring(0, eq).trim();
    final String value = parameter.substring(eq + 1).trim();
    final int? parsed = int.tryParse(value);
    if (name == 'rate' && parsed != null && parsed > 0) {
      return parsed;
    }
  }
  return _defaultSampleRate;
}

bool _isTransientSttError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is RecoverableLiveConnectionException) {
    final int? code = error.code;
    if (code == null) {
      return true;
    }
    return _transientCloseCodes.contains(code) ||
        _transientStatusCodes.contains(code);
  }

  int? extractedCode;
  try {
    final Object? rawCode = (error as dynamic).code;
    if (rawCode is int) {
      extractedCode = rawCode;
    }
  } catch (_) {}
  if (extractedCode == null) {
    try {
      final Object? rawStatus = (error as dynamic).statusCode;
      if (rawStatus is int) {
        extractedCode = rawStatus;
      }
    } catch (_) {}
  }
  if (extractedCode != null) {
    return _transientCloseCodes.contains(extractedCode) ||
        _transientStatusCodes.contains(extractedCode);
  }

  final String typeName = error.runtimeType.toString();
  if (typeName.contains('SocketException') ||
      typeName.contains('HandshakeException') ||
      typeName.contains('WebSocketException') ||
      typeName.contains('WebSocketChannelException') ||
      typeName.contains('ClientException') ||
      typeName.contains('ConnectionError')) {
    return true;
  }

  final String lower = '$error'.toLowerCase();
  return lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('broken pipe') ||
      lower.contains('timed out') ||
      lower.contains('service unavailable') ||
      lower.contains('temporarily unavailable') ||
      lower.contains('bad gateway') ||
      lower.contains('try again later');
}

class _NotifySignal {
  Completer<void>? _waiter;

  void notify() {
    final Completer<void>? current = _waiter;
    if (current != null && !current.isCompleted) {
      current.complete();
    }
    _waiter = null;
  }

  Future<void> wait() {
    final Completer<void> completer = _waiter ??= Completer<void>();
    return completer.future;
  }
}

class _ReplayBuffer {
  _ReplayBuffer({required this.maxReplayMs, required this.replayTailMs});

  final int maxReplayMs;
  final int replayTailMs;
  final Queue<InlineData> _chunks = Queue<InlineData>();
  int _currentBytes = 0;
  int sampleRate = _defaultSampleRate;
  String mimeType = 'audio/pcm;rate=$_defaultSampleRate';

  int bytesFor(int durationMs) {
    return (sampleRate * durationMs * _bytesPerSample) ~/ 1000;
  }

  void add(InlineData blob) {
    if (blob.data.isEmpty) {
      return;
    }
    if (blob.mimeType.isNotEmpty) {
      mimeType = blob.mimeType;
    }
    sampleRate = sampleRateOfAudioMime(blob.mimeType);
    final InlineData stored = InlineData(
      mimeType: mimeType,
      data: Uint8List.fromList(blob.data),
    );
    _chunks.addLast(stored);
    _currentBytes += stored.data.length;
    _trimToMaxBytes(bytesFor(maxReplayMs));
  }

  void markFinalized() {
    _trimToMaxBytes(bytesFor(replayTailMs));
  }

  List<InlineData> replay() => List<InlineData>.unmodifiable(_chunks);

  int get totalBytes => _currentBytes;

  void _trimToMaxBytes(int maxBytes) {
    while (_currentBytes > maxBytes && _chunks.isNotEmpty) {
      final InlineData removed = _chunks.removeFirst();
      _currentBytes -= removed.data.length;
    }
  }
}

class _TranscriptionSessionState {
  _TranscriptionSessionState({
    required this.emit,
    required this.onFinalized,
    required this.onChanged,
  });

  final void Function(IngressEvent event) emit;
  final void Function() onFinalized;
  final void Function() onChanged;

  bool speaking = false;
  String lastPartial = '';
  final StringBuffer transcriptAccumulator = StringBuffer();
  bool resumedMidUtterance = false;
  bool goAway = false;
  bool activityEnded = false;

  bool get pending => speaking || transcriptAccumulator.isNotEmpty;

  void startSession() {
    resumedMidUtterance = pending;
    speaking = false;
    lastPartial = '';
    transcriptAccumulator.clear();
    goAway = false;
    activityEnded = false;
  }

  void onResponse(LlmResponse resp) {
    if (resp.goAway != null) {
      goAway = true;
    }

    final VoiceActivity? activity = resp.voiceActivity;
    if (activity != null) {
      if (activity.voiceActivityType == VoiceActivityType.activityStart) {
        _startSpeech();
      } else if (activity.voiceActivityType == VoiceActivityType.activityEnd) {
        speaking = false;
        activityEnded = true;
      }
    }

    final Object? inputTrans = resp.inputTranscription;
    if (inputTrans != null) {
      final ({String? text, bool finished}) parsed = _parseTranscription(
        inputTrans,
      );
      final String? text = parsed.text?.trim();
      if (text != null && text.isNotEmpty) {
        if (parsed.finished) {
          _finalize();
          emit(UserTurnFinished(text: text));
          onChanged();
          return;
        } else {
          _startSpeech();
          if (text != lastPartial) {
            lastPartial = text;
            transcriptAccumulator
              ..clear()
              ..write(text);
            emit(PartialTranscript(text: text));
          }
        }
      }
    }

    if (resp.content != null) {
      for (final Part part in resp.content!.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          _startSpeech();
          transcriptAccumulator.write(part.text);
          emit(PartialTranscript(text: part.text!));
        }
      }
    }

    if (resp.turnComplete == true) {
      final String finalTranscript = transcriptAccumulator.toString().trim();
      _finalize();
      if (finalTranscript.isNotEmpty) {
        emit(UserTurnFinished(text: finalTranscript));
      }
    }

    onChanged();
  }

  void _startSpeech() {
    if (!speaking) {
      speaking = true;
      activityEnded = false;
      if (resumedMidUtterance) {
        resumedMidUtterance = false;
      } else {
        emit(const UserSpeechStarted());
      }
    }
  }

  void _finalize() {
    speaking = false;
    lastPartial = '';
    transcriptAccumulator.clear();
    resumedMidUtterance = false;
    onFinalized();
  }

  static ({String? text, bool finished}) _parseTranscription(Object raw) {
    if (raw is String) {
      return (text: raw, finished: false);
    }
    if (raw is Map) {
      return (
        text: raw['text'] as String?,
        finished: raw['finished'] == true,
      );
    }
    try {
      final dynamic dyn = raw;
      return (
        text: dyn.text as String?,
        finished: dyn.finished == true,
      );
    } catch (_) {
      return (text: null, finished: false);
    }
  }
}

enum _SessionOutcome { completed, rotate, cancelled }

/// Speech-to-text transform converting live audio into transcripts using Gemini.
///
/// ```dart
/// final stt = GeminiSTT(
///   model: 'gemini-3.5-transcribe-live',
///   silenceDurationMs: 500,
/// );
/// ```
class GeminiSTT extends LiveIngress {
  /// Creates a [GeminiSTT] ingress transform.
  GeminiSTT({
    this.model = _defaultSttModel,
    this.silenceDurationMs = _defaultSilenceDurationMs,
    this.maxReplayMs = _defaultMaxReplayMs,
    this.replayTailMs = 0,
    this.sessionRotationSeconds = _defaultSessionRotationSeconds,
    this.languageCodes,
    this.audioTranscriptionConfig,
    this.activityDetection,
    this.maxReconnects = _defaultMaxReconnects,
    this.reconnectBaseDelay = const Duration(milliseconds: 50),
    this.stableSessionSeconds = _defaultStableSessionSeconds,
    this.flushTimeout = const Duration(milliseconds: 200),
  }) {
    isFeatureEnabled(FeatureName.cascadeLive);
    if (maxReplayMs < 0) {
      throw ArgumentError.value(
        maxReplayMs,
        'maxReplayMs',
        'Must not be negative.',
      );
    }
    if (replayTailMs < 0) {
      throw ArgumentError.value(
        replayTailMs,
        'replayTailMs',
        'Must not be negative.',
      );
    }
    if (maxReconnects < 0) {
      throw ArgumentError.value(
        maxReconnects,
        'maxReconnects',
        'Must not be negative.',
      );
    }
  }

  /// Target model name or [BaseLlm] instance.
  final Object model;

  /// Silence duration in milliseconds ending a user turn.
  final int silenceDurationMs;

  /// Maximum unfinalized audio duration replayed to a rotated/reopened session in milliseconds.
  final int maxReplayMs;

  /// Optional tail duration in milliseconds retained across finalized turn boundaries.
  final int replayTailMs;

  /// Duration in seconds before proactively rotating a streaming transcription session.
  final double sessionRotationSeconds;

  /// Optional language codes for transcription hint.
  final List<String>? languageCodes;

  /// Optional provider audio transcription configuration.
  final Object? audioTranscriptionConfig;

  /// Optional provider automatic activity detection configuration.
  final Object? activityDetection;

  /// Maximum consecutive transient reconnect attempts before failing.
  final int maxReconnects;

  /// Initial backoff delay before the first transient reconnect attempt.
  final Duration reconnectBaseDelay;

  /// Session uptime in seconds that resets the consecutive failure counter.
  final double stableSessionSeconds;

  /// Maximum time to wait at end-of-stream for a pending utterance to finalize.
  final Duration flushTimeout;

  bool get _isClientVad {
    final Object? detection = activityDetection;
    if (detection is Map) {
      return detection['disabled'] == true;
    }
    if (detection != null) {
      try {
        return (detection as dynamic).disabled == true;
      } catch (_) {}
    }
    return false;
  }

  BaseLlm _resolveModel() {
    if (model is BaseLlm) {
      return model as BaseLlm;
    }
    return LLMRegistry.newLlm('$model');
  }

  Future<BaseLlmConnection> _openConnection(
    BaseLlm llm,
    LlmRequest request,
  ) async {
    final dynamic dynamicLlm = llm;
    final dynamic conn = dynamicLlm.connect(request);
    if (conn is Future) {
      return await conn as BaseLlmConnection;
    }
    return conn as BaseLlmConnection;
  }

  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) async* {
    final BaseLlm llm = _resolveModel();
    final _ReplayBuffer replayBuffer = _ReplayBuffer(
      maxReplayMs: maxReplayMs,
      replayTailMs: replayTailMs,
    );
    final Queue<InlineData> pendingAudio = Queue<InlineData>();
    final _NotifySignal wakeUp = _NotifySignal();

    bool audioEnded = false;
    Object? audioStreamError;
    StackTrace? audioStreamStack;
    bool cancelled = false;

    StreamSubscription<InlineData>? audioSub;
    BaseLlmConnection? activeConnection;
    StreamSubscription<LlmResponse>? activeReceiveSub;
    Timer? activeRotationTimer;

    late final StreamController<IngressEvent> controller;
    controller = StreamController<IngressEvent>(
      onCancel: () async {
        cancelled = true;
        activeRotationTimer?.cancel();
        wakeUp.notify();
        await audioSub?.cancel();
        await activeReceiveSub?.cancel();
        await activeConnection?.close();
      },
    );

    final _TranscriptionSessionState state = _TranscriptionSessionState(
      emit: (IngressEvent event) {
        if (!cancelled && !controller.isClosed) {
          controller.add(event);
        }
      },
      onFinalized: replayBuffer.markFinalized,
      onChanged: wakeUp.notify,
    );

    LlmRequest buildConnectRequest() {
      final bool clientVad = _isClientVad;
      final Object effectiveDetection =
          activityDetection ??
          <String, Object?>{'silenceDurationMs': silenceDurationMs};
      return LlmRequest(
        model: llm.model,
        liveConnectConfig: LiveConnectConfig(
          responseModalities: <String>['TEXT'],
          inputAudioTranscription:
              audioTranscriptionConfig ??
              (languageCodes != null
                  ? <String, Object?>{'languageCodes': languageCodes}
                  : <String, Object?>{}),
          realtimeInputConfig: <String, Object?>{
            'automaticActivityDetection': effectiveDetection,
          },
          speechConfig: <String, Object?>{
            if (!clientVad) 'silenceDurationMs': silenceDurationMs,
            if (languageCodes != null) 'languageCodes': languageCodes,
          },
        ),
      );
    }

    Future<_SessionOutcome> runSingleSession(int sessionIndex) async {
      final BaseLlmConnection conn = await _openConnection(
        llm,
        buildConnectRequest(),
      );
      activeConnection = conn;
      state.startSession();

      bool rotationRequested = false;
      Object? sessionError;
      StackTrace? sessionStack;
      bool remoteClosed = false;

      if (sessionRotationSeconds > 0 && sessionRotationSeconds.isFinite) {
        final int micros = (sessionRotationSeconds * 1000000).round();
        activeRotationTimer = Timer(
          Duration(microseconds: micros < 1 ? 1 : micros),
          () {
            rotationRequested = true;
            wakeUp.notify();
          },
        );
      }

      activeReceiveSub = conn.receive().listen(
        (LlmResponse resp) {
          state.onResponse(resp);
          if (state.goAway) {
            rotationRequested = true;
            wakeUp.notify();
          }
        },
        onError: (Object err, StackTrace stack) {
          sessionError ??= err;
          sessionStack ??= stack;
          wakeUp.notify();
        },
        onDone: () {
          remoteClosed = true;
          wakeUp.notify();
        },
      );

      try {
        if (_isClientVad) {
          await conn.sendActivityStart();
        }

        if (sessionIndex > 0) {
          for (final InlineData replayed in replayBuffer.replay()) {
            if (cancelled) {
              return _SessionOutcome.cancelled;
            }
            await conn.sendRealtime(
              RealtimeBlob(mimeType: replayed.mimeType, data: replayed.data),
            );
          }
        }

        while (!cancelled) {
          if (audioStreamError != null) {
            Error.throwWithStackTrace(audioStreamError!, audioStreamStack!);
          }
          if (sessionError != null) {
            Error.throwWithStackTrace(sessionError!, sessionStack!);
          }

          while (pendingAudio.isNotEmpty && !cancelled && !rotationRequested) {
            final InlineData blob = pendingAudio.removeFirst();
            if (blob.data.isEmpty) {
              continue;
            }
            replayBuffer.add(blob);
            await conn.sendRealtime(
              RealtimeBlob(mimeType: blob.mimeType, data: blob.data),
            );
            if (sessionError != null) {
              Error.throwWithStackTrace(sessionError!, sessionStack!);
            }
            if (state.goAway) {
              rotationRequested = true;
            }
          }

          if (cancelled) {
            return _SessionOutcome.cancelled;
          }
          if (sessionError != null) {
            Error.throwWithStackTrace(sessionError!, sessionStack!);
          }
          if (rotationRequested) {
            return _SessionOutcome.rotate;
          }

          if (audioEnded && pendingAudio.isEmpty) {
            // Allow queued microtasks from synchronous mock transports to deliver.
            await Future<void>.delayed(Duration.zero);
            if (sessionError != null) {
              Error.throwWithStackTrace(sessionError!, sessionStack!);
            }

            if (_isClientVad) {
              await conn.sendActivityEnd();
              await Future<void>.delayed(Duration.zero);
            } else if (state.pending && !remoteClosed) {
              final int silenceBytes = replayBuffer.bytesFor(
                silenceDurationMs + _flushSilenceMarginMs,
              );
              if (silenceBytes > 0) {
                await conn.sendRealtime(
                  RealtimeBlob(
                    mimeType: replayBuffer.mimeType,
                    data: Uint8List(silenceBytes),
                  ),
                );
              }
              final Stopwatch flushWatch = Stopwatch()..start();
              while (state.pending &&
                  !cancelled &&
                  !remoteClosed &&
                  sessionError == null &&
                  flushWatch.elapsed < flushTimeout) {
                final Duration remaining = flushTimeout - flushWatch.elapsed;
                if (remaining <= Duration.zero) {
                  break;
                }
                await Future.any(<Future<void>>[
                  wakeUp.wait(),
                  Future<void>.delayed(remaining),
                ]);
              }
              if (sessionError != null) {
                Error.throwWithStackTrace(sessionError!, sessionStack!);
              }
            }
            return _SessionOutcome.completed;
          }

          if (remoteClosed && !audioEnded) {
            throw RecoverableLiveConnectionException(
              'The Gemini transcription session closed unexpectedly.',
              code: 1006,
            );
          }

          await wakeUp.wait();
        }
        return _SessionOutcome.cancelled;
      } finally {
        activeRotationTimer?.cancel();
        activeRotationTimer = null;
        final StreamSubscription<LlmResponse>? subToCancel = activeReceiveSub;
        activeReceiveSub = null;
        final BaseLlmConnection? connToClose = activeConnection;
        activeConnection = null;
        await subToCancel?.cancel();
        await connToClose?.close();
      }
    }

    Future<void> runSupervisor() async {
      audioSub = audio.listen(
        (InlineData blob) {
          pendingAudio.addLast(blob);
          wakeUp.notify();
        },
        onError: (Object err, StackTrace stack) {
          audioStreamError = err;
          audioStreamStack = stack;
          wakeUp.notify();
        },
        onDone: () {
          audioEnded = true;
          wakeUp.notify();
        },
      );

      int sessionIndex = 0;
      int failures = 0;
      try {
        while (!cancelled) {
          final Stopwatch sessionWatch = Stopwatch()..start();
          try {
            final _SessionOutcome outcome = await runSingleSession(
              sessionIndex,
            );
            if (outcome == _SessionOutcome.completed ||
                outcome == _SessionOutcome.cancelled) {
              break;
            }
            // Proactive session rotation succeeded; reset transient failure count.
            failures = 0;
            sessionIndex += 1;
          } catch (err, stack) {
            if (cancelled || identical(err, audioStreamError)) {
              Error.throwWithStackTrace(err, stack);
            }
            if (!_isTransientSttError(err)) {
              Error.throwWithStackTrace(err, stack);
            }
            final double elapsedSeconds =
                sessionWatch.elapsedMicroseconds / 1000000.0;
            if (elapsedSeconds >= stableSessionSeconds) {
              failures = 0;
            }
            failures += 1;
            if (failures > maxReconnects) {
              Error.throwWithStackTrace(err, stack);
            }
            final int multiplier = 1 << (failures - 1);
            final Duration backoff = Duration(
              microseconds: reconnectBaseDelay.inMicroseconds * multiplier,
            );
            if (backoff > Duration.zero) {
              await Future<void>.delayed(backoff);
            }
            sessionIndex += 1;
          }
        }
      } catch (err, stack) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(err, stack);
        }
      } finally {
        await audioSub?.cancel();
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    unawaited(runSupervisor());
    yield* controller.stream;
  }
}
