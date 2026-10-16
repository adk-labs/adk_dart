/// Speech-to-text transform backed by Gemini streaming transcription.
library;

import 'dart:async';
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
const int _defaultMaxReplayMs = 10000;
const double _defaultSessionRotationSeconds = 480.0;

class _AudioBuffer {
  _AudioBuffer({required this.maxBytes});

  final int maxBytes;
  final List<Uint8List> _chunks = <Uint8List>[];
  int _currentBytes = 0;

  void add(Uint8List bytes) {
    _chunks.add(bytes);
    _currentBytes += bytes.length;
    while (_currentBytes > maxBytes && _chunks.isNotEmpty) {
      final Uint8List removed = _chunks.removeAt(0);
      _currentBytes -= removed.length;
    }
  }

  void clear() {
    _chunks.clear();
    _currentBytes = 0;
  }
}

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
    this.sessionRotationSeconds = _defaultSessionRotationSeconds,
    this.languageCodes,
  }) {
    isFeatureEnabled(FeatureName.cascadeLive);
    if (maxReplayMs < 0) {
      throw ArgumentError.value(maxReplayMs, 'maxReplayMs', 'Must not be negative.');
    }
  }

  /// Target model name or [BaseLlm] instance.
  final Object model;

  /// Silence duration in milliseconds ending a user turn.
  final int silenceDurationMs;

  /// Maximum audio duration replayed to a new session in milliseconds.
  final int maxReplayMs;

  /// Duration before rotating a streaming session.
  final double sessionRotationSeconds;

  /// Optional language codes for transcription hint.
  final List<String>? languageCodes;

  BaseLlm _resolveModel() {
    if (model is BaseLlm) {
      return model as BaseLlm;
    }
    return LLMRegistry.newLlm('$model');
  }

  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) async* {
    final BaseLlm llm = _resolveModel();
    final int maxReplayBytes = (maxReplayMs * _defaultSampleRate * 2) ~/ 1000;
    final _AudioBuffer replayBuffer = _AudioBuffer(maxBytes: maxReplayBytes);

    StreamSubscription<LlmResponse>? sub;
    BaseLlmConnection? connection;

    final StreamController<IngressEvent> controller =
        StreamController<IngressEvent>(
      onCancel: () async {
        await sub?.cancel();
        await connection?.close();
      },
    );

    Future<void> runLoop() async {
      try {
        final LlmRequest request = LlmRequest(
          model: llm.model,
          liveConnectConfig: LiveConnectConfig(
            responseModalities: <String>['TEXT'],
            speechConfig: <String, Object?>{
              'silenceDurationMs': silenceDurationMs,
              if (languageCodes != null) 'languageCodes': languageCodes,
            },
          ),
        );

        final dynamic dynamicLlm = llm;
        final dynamic conn = dynamicLlm.connect(request);
        connection = (conn is Future) ? await conn : conn as BaseLlmConnection;

        final StringBuffer transcriptAccumulator = StringBuffer();
        bool speechStartedEmitted = false;

        sub = connection!.receive().listen(
          (LlmResponse resp) {
            if (resp.content != null) {
              for (final Part part in resp.content!.parts) {
                if (part.text != null && part.text!.isNotEmpty) {
                  if (!speechStartedEmitted) {
                    speechStartedEmitted = true;
                    controller.add(const UserSpeechStarted());
                  }
                  transcriptAccumulator.write(part.text);
                  controller.add(PartialTranscript(text: part.text!));
                }
              }
            }
            if (resp.turnComplete == true) {
              final String finalTranscript = transcriptAccumulator.toString().trim();
              if (finalTranscript.isNotEmpty) {
                controller.add(UserTurnFinished(text: finalTranscript));
              }
              transcriptAccumulator.clear();
              speechStartedEmitted = false;
              replayBuffer.clear();
            }
          },
          onError: (Object err, StackTrace stack) {
            if (!controller.isClosed) {
              controller.addError(err, stack);
            }
          },
        );

        await for (final InlineData blob in audio) {
          final Uint8List rawBytes = Uint8List.fromList(blob.data);
          replayBuffer.add(rawBytes);
          await connection!.sendRealtime(
            RealtimeBlob(mimeType: blob.mimeType, data: blob.data),
          );
        }

        await sub?.cancel();
      } catch (err, stack) {
        if (!controller.isClosed) {
          controller.addError(err, stack);
        }
      } finally {
        await connection?.close();
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    unawaited(runLoop());
    yield* controller.stream;
  }
}
