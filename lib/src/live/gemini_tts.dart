/// Text-to-speech transform backed by Gemini text-to-speech models.
library;

import 'dart:async';

import '../features/_feature_registry.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../types/content.dart';
import 'cascade_live_events.dart';
import 'transforms.dart';

const String _defaultTtsModel = 'gemini-3.8-flash-lite-tts';
const String _defaultVoice = 'Kore';
const int _defaultSampleRate = 24000;
const int _defaultMinSegmentChars = 50;
const int _defaultMaxSegmentChars = 240;

final RegExp _sentenceEnd = RegExp(
  r'[.!?\u2026\u0964]["\x27\u201d\u2019)\]]*\s+'
  r'|[\u3002\uff01\uff1f]["\x27\u201d\u2019)\]\u300d\u300f\uff09]*\s*'
  r'|\n+',
);

final RegExp _cjkClauseEnd = RegExp(r'[\uff0c\u3001\uff1b\uff1a]');

(String?, String) _splitSegment(
  String buffer, {
  required int maxChars,
  int minChars = 0,
}) {
  if (buffer.isEmpty) return (null, buffer);

  final Iterable<RegExpMatch> matches = _sentenceEnd.allMatches(buffer);
  for (final RegExpMatch match in matches) {
    if (match.end >= minChars) {
      final String piece = buffer.substring(0, match.end);
      final String remainder = buffer.substring(match.end);
      return (piece, remainder);
    }
  }

  if (buffer.length >= maxChars) {
    final int lastSpace = buffer.lastIndexOf(' ', maxChars);
    if (lastSpace > minChars) {
      final String piece = buffer.substring(0, lastSpace + 1);
      final String remainder = buffer.substring(lastSpace + 1);
      return (piece, remainder);
    }

    final Iterable<RegExpMatch> cjkMatches =
        _cjkClauseEnd.allMatches(buffer.substring(0, maxChars));
    if (cjkMatches.isNotEmpty) {
      final int cutPoint = cjkMatches.last.end;
      if (cutPoint > minChars) {
        final String piece = buffer.substring(0, cutPoint);
        final String remainder = buffer.substring(cutPoint);
        return (piece, remainder);
      }
    }

    final String piece = buffer.substring(0, maxChars);
    final String remainder = buffer.substring(maxChars);
    return (piece, remainder);
  }

  return (null, buffer);
}

/// Text-to-speech transform converting text deltas into speech using Gemini.
///
/// ```dart
/// final tts = GeminiTTS(
///   model: 'gemini-3.8-flash-lite-tts',
///   voiceName: 'Kore',
/// );
/// ```
class GeminiTTS extends LiveEgress {
  /// Creates a [GeminiTTS] egress transform.
  GeminiTTS({
    this.model = _defaultTtsModel,
    this.voiceName = _defaultVoice,
    this.sampleRate = _defaultSampleRate,
    this.minSegmentChars = _defaultMinSegmentChars,
    this.maxSegmentChars = _defaultMaxSegmentChars,
    this.prefetchSegments = 1,
    this.speechConfig,
  }) {
    isFeatureEnabled(FeatureName.cascadeLive);
    if (maxSegmentChars < 1) {
      throw ArgumentError.value(maxSegmentChars, 'maxSegmentChars', 'Must be positive.');
    }
    if (minSegmentChars < 0) {
      throw ArgumentError.value(minSegmentChars, 'minSegmentChars', 'Must not be negative.');
    }
    if (prefetchSegments < 0) {
      throw ArgumentError.value(prefetchSegments, 'prefetchSegments', 'Must not be negative.');
    }
  }

  /// Target model name or [BaseLlm] instance.
  final Object model;

  /// Default voice name.
  final String voiceName;

  /// PCM audio sample rate.
  final int sampleRate;

  /// Minimum characters to group before cutting at sentence boundary.
  final int minSegmentChars;

  /// Maximum characters for a single synthesis segment.
  final int maxSegmentChars;

  /// Number of segments to prefetch ahead of delivery.
  final int prefetchSegments;

  /// Optional speech configuration dictionary.
  final Object? speechConfig;

  BaseLlm _resolveModel() {
    if (model is BaseLlm) {
      return model as BaseLlm;
    }
    return LLMRegistry.newLlm('$model');
  }

  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) async* {
    final BaseLlm llm = _resolveModel();
    String buffer = '';
    String whitespace = '';
    int currentMinChars = 0;

    await for (final String delta in text) {
      if (cancel.isSet) return;
      buffer += delta;

      while (true) {
        final (String? piece, String remainder) = _splitSegment(
          buffer,
          maxChars: maxSegmentChars,
          minChars: currentMinChars,
        );
        if (piece == null) break;
        buffer = remainder;

        if (piece.trim().isEmpty) {
          whitespace += piece;
          continue;
        }

        final String segmentText = whitespace + piece;
        whitespace = '';
        currentMinChars = minSegmentChars;

        yield* _synthesizeSegment(llm, segmentText, cancel);
        if (cancel.isSet) return;
      }
    }

    if (buffer.trim().isNotEmpty) {
      final String finalSegment = whitespace + buffer;
      yield* _synthesizeSegment(llm, finalSegment, cancel);
    }
  }

  Stream<EgressEvent> _synthesizeSegment(
    BaseLlm llm,
    String segmentText,
    CancelSignal cancel,
  ) async* {
    if (cancel.isSet) return;

    final LlmRequest request = LlmRequest(
      model: llm.model,
      contents: <Content>[Content.userText(segmentText)],
      config: GenerateContentConfig(
        responseModalities: <String>['AUDIO'],
        speechConfig: speechConfig ??
            <String, Object?>{
              'voiceConfig': <String, Object?>{
                'prebuiltVoiceConfig': <String, Object?>{
                  'voiceName': voiceName,
                },
              },
            },
      ),
    );

    bool producedAudio = false;

    await for (final LlmResponse response in llm.generateContent(request, stream: true)) {
      if (cancel.isSet) return;
      if (response.content != null) {
        for (final Part part in response.content!.parts) {
          if (part.inlineData != null) {
            producedAudio = true;
            yield AudioChunk(blob: part.inlineData!);
          }
        }
      }
    }

    if (cancel.isSet) return;

    if (producedAudio) {
      yield AgentSpokenOutput(text: segmentText);
    }
  }
}
