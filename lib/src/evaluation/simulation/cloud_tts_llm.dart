/// Google Cloud Text-to-Speech (TTS) [BaseLlm] adapter for audio simulation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../models/base_llm.dart';
import '../../models/base_llm_connection.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../types/content.dart';

/// Mapping from Cloud TTS `AudioEncoding` names to output MIME types.
const Map<String, String> ttsEncodingToMimeType = <String, String>{
  'LINEAR16': 'audio/l16',
  'MP3': 'audio/mpeg',
  'OGG_OPUS': 'audio/ogg',
  'MULAW': 'audio/basic',
  'ALAW': 'audio/alaw',
};

/// Request payload passed to a [CloudTtsClient] or [CloudTtsSynthesizer].
class CloudTtsSynthesisRequest {
  /// Creates a Cloud TTS synthesis request.
  const CloudTtsSynthesisRequest({
    required this.text,
    required this.voiceName,
    required this.languageCode,
    required this.audioEncoding,
    required this.speakingRate,
    required this.pitch,
  });

  /// Text to synthesize into speech.
  final String text;

  /// Prebuilt Cloud TTS voice name (for example `'en-US-Studio-O'`).
  final String voiceName;

  /// BCP-47 language code (for example `'en-US'`).
  final String languageCode;

  /// Requested audio encoding name (for example `'LINEAR16'` or `'MP3'`).
  final String audioEncoding;

  /// Speaking rate multiplier.
  final double speakingRate;

  /// Speaking pitch offset in semitones.
  final double pitch;
}

/// Client interface for synthesizing speech via Google Cloud Text-to-Speech.
abstract class CloudTtsClient {
  /// Creates a Cloud TTS client.
  const CloudTtsClient();

  /// Synthesizes speech audio bytes for [request].
  FutureOr<List<int>> synthesizeSpeech(CloudTtsSynthesisRequest request);
}

/// Callback signature for synthesizing speech audio bytes.
typedef CloudTtsSynthesizer =
    FutureOr<List<int>> Function(CloudTtsSynthesisRequest request);

/// Default local [CloudTtsClient] that generates deterministic synthesized audio
/// bytes when no external Cloud TTS client is injected.
class DefaultCloudTtsClient extends CloudTtsClient {
  /// Creates a default local Cloud TTS client.
  const DefaultCloudTtsClient();

  @override
  List<int> synthesizeSpeech(CloudTtsSynthesisRequest request) {
    final String header =
        'RIFF_TTS:${request.audioEncoding}:${request.languageCode}:${request.voiceName}:';
    return Uint8List.fromList(utf8.encode('$header${request.text}'));
  }
}

/// [BaseLlm] implementation that converts text in [LlmRequest] into audio
/// inline data using Google Cloud Text-to-Speech semantics.
///
/// ```dart
/// final ttsLlm = CloudTtsLlm(
///   audioEncoding: 'MP3',
///   speakingSpeed: 1.1,
/// );
/// final responses = await ttsLlm.generateContent(
///   LlmRequest(contents: [Content.userText('Hello world!')]),
/// ).toList();
/// ```
class CloudTtsLlm extends BaseLlm {
  /// Creates a Cloud TTS LLM adapter.
  CloudTtsLlm({
    super.model = 'cloud_tts',
    this.audioEncoding = 'LINEAR16',
    this.speakingSpeed = 1.0,
    this.pitch = 0.0,
    CloudTtsClient? ttsClient,
    CloudTtsSynthesizer? synthesizer,
  }) : _ttsClient = ttsClient,
       _synthesizer = synthesizer;

  /// Audio encoding name (`'LINEAR16'`, `'MP3'`, `'OGG_OPUS'`, `'MULAW'`, `'ALAW'`).
  final String audioEncoding;

  /// Speaking rate in the range `[0.25, 2.0]` (`1.0` is normal speed).
  final double speakingSpeed;

  /// Speaking pitch in the range `[-20.0, 20.0]` (`0.0` is default pitch).
  final double pitch;

  CloudTtsClient? _ttsClient;
  final CloudTtsSynthesizer? _synthesizer;

  /// Lazily initialized [CloudTtsClient] instance.
  CloudTtsClient get ttsClient => _ttsClient ??= const DefaultCloudTtsClient();

  /// Returns regex patterns matching model names supported by [CloudTtsLlm].
  static List<String> supportedModels() => <String>[r'cloud_tts'];

  /// Extracts all text parts from [llmRequest] joined with single spaces.
  ///
  /// Throws an [ArgumentError] if no non-empty text part is present.
  static String extractText(LlmRequest llmRequest) {
    final List<String> texts = <String>[];
    for (final Content content in llmRequest.contents) {
      for (final Part part in content.parts) {
        final String? text = part.text;
        if (text != null && text.isNotEmpty) {
          texts.add(text);
        }
      }
    }
    if (texts.isEmpty) {
      throw ArgumentError('CloudTtsLlm requires text in LlmRequest.contents');
    }
    return texts.join(' ');
  }

  /// Extracts `(voiceName, languageCode)` from [llmRequest]'s speech config.
  ///
  /// Defaults to `('en-US-Studio-O', 'en-US')` when not specified.
  static (String, String) extractVoiceConfig(LlmRequest llmRequest) {
    String voiceName = 'en-US-Studio-O';
    String languageCode = 'en-US';

    final Object? speechConfig = llmRequest.config.speechConfig;
    if (speechConfig == null) {
      return (voiceName, languageCode);
    }

    if (speechConfig is Map) {
      final Object? rawLang =
          speechConfig['language_code'] ?? speechConfig['languageCode'];
      if (rawLang is String && rawLang.isNotEmpty) {
        languageCode = rawLang;
      }
      final Object? voiceConfig =
          speechConfig['voice_config'] ?? speechConfig['voiceConfig'];
      if (voiceConfig is Map) {
        final Object? prebuilt =
            voiceConfig['prebuilt_voice_config'] ??
            voiceConfig['prebuiltVoiceConfig'];
        if (prebuilt is Map) {
          final Object? rawVoice =
              prebuilt['voice_name'] ?? prebuilt['voiceName'];
          if (rawVoice is String && rawVoice.isNotEmpty) {
            voiceName = rawVoice;
          }
        }
      }
      return (voiceName, languageCode);
    }

    try {
      final dynamic dynSpeech = speechConfig;
      final Object? rawLang = dynSpeech.languageCode;
      if (rawLang is String && rawLang.isNotEmpty) {
        languageCode = rawLang;
      }
    } catch (_) {
      // Ignore missing languageCode getter.
    }

    try {
      final dynamic dynSpeech = speechConfig;
      final dynamic voiceCfg = dynSpeech.voiceConfig;
      if (voiceCfg != null) {
        final dynamic prebuilt = voiceCfg.prebuiltVoiceConfig;
        if (prebuilt != null) {
          final Object? rawVoice = prebuilt.voiceName;
          if (rawVoice is String && rawVoice.isNotEmpty) {
            voiceName = rawVoice;
          }
        }
      }
    } catch (_) {
      // Ignore missing voiceConfig getter chain.
    }

    return (voiceName, languageCode);
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String? mimeType = ttsEncodingToMimeType[audioEncoding];
    if (mimeType == null) {
      throw ArgumentError(
        'Unsupported audio_encoding: $audioEncoding. '
        'Supported encodings: ${ttsEncodingToMimeType.keys.toList()}',
      );
    }

    final String textToSynthesize = extractText(request);
    final (String voiceName, String languageCode) = extractVoiceConfig(request);

    final CloudTtsSynthesisRequest synthesisRequest = CloudTtsSynthesisRequest(
      text: textToSynthesize,
      voiceName: voiceName,
      languageCode: languageCode,
      audioEncoding: audioEncoding,
      speakingRate: speakingSpeed,
      pitch: pitch,
    );

    List<int> audioBytes;
    try {
      if (_synthesizer != null) {
        audioBytes = await _synthesizer(synthesisRequest);
      } else {
        audioBytes = await ttsClient.synthesizeSpeech(synthesisRequest);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Google Cloud TTS API call failed: $error',
        name: 'adk_dart.cloud_tts_llm',
        error: error,
        stackTrace: stackTrace,
      );
      yield LlmResponse(
        errorCode: 'TTS_SYNTHESIS_FAILED',
        errorMessage: '$error',
      );
      return;
    }

    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromInlineData(
            mimeType: mimeType,
            data: audioBytes,
          ),
        ],
      ),
    );
  }

  /// Opens a live [BaseLlmConnection] backed by this TTS adapter.
  BaseLlmConnection connect(LlmRequest request) {
    return CloudTtsLlmConnection(llm: this, initialRequest: request);
  }
}

/// Alias for [CloudTtsLlm] matching the Python `CloudTTSLlm` class name.
typedef CloudTTSLlm = CloudTtsLlm;

/// Live connection wrapper for [CloudTtsLlm].
class CloudTtsLlmConnection extends BaseLlmConnection {
  /// Creates a live connection backed by [llm].
  CloudTtsLlmConnection({
    required this.llm,
    LlmRequest? initialRequest,
  }) : _initialRequest = initialRequest;

  /// Underlying [CloudTtsLlm] instance.
  final CloudTtsLlm llm;

  final LlmRequest? _initialRequest;
  final StreamController<LlmResponse> _controller =
      StreamController<LlmResponse>.broadcast();
  bool _closed = false;

  @override
  Future<void> sendHistory(List<Content> history) async {
    if (_closed || history.isEmpty) {
      return;
    }
    await sendContent(history.last);
  }

  @override
  Future<void> sendContent(Content content) async {
    if (_closed) {
      throw StateError('CloudTtsLlmConnection is already closed.');
    }
    final LlmRequest req = LlmRequest(
      model: llm.model,
      contents: <Content>[content],
      config: _initialRequest?.config.copyWith(),
    );
    await for (final LlmResponse response in llm.generateContent(req)) {
      if (!_closed) {
        _controller.add(response);
      }
    }
  }

  @override
  Future<void> sendRealtime(RealtimeBlob blob) async {
    if (_closed) {
      throw StateError('CloudTtsLlmConnection is already closed.');
    }
    final String text = utf8.decode(blob.data, allowMalformed: true).trim();
    if (text.isEmpty) {
      return;
    }
    await sendContent(Content.userText(text));
  }

  @override
  Stream<LlmResponse> receive() => _controller.stream;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _controller.close();
  }
}
