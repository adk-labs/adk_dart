/// LLM-backed audio user simulator for multimodal evaluation conversations.
library;

import 'dart:typed_data';

import '../../events/event.dart';
import '../../models/base_llm.dart';
import '../../models/google_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../models/registry.dart';
import '../../types/content.dart';
import '../_retry_options_utils.dart';
import '../audio_utils.dart';
import '../conversation_scenarios.dart';
import '../eval_config.dart';
import '../evaluator.dart';
import 'cloud_tts_llm.dart';
import 'llm_backed_user_simulator.dart';
import 'llm_backed_user_simulator_prompts.dart';
import 'user_simulator.dart';

const String _authorUser = 'user';
const String _defaultAudioModel = 'cloud_tts';

/// Configuration for an LLM-backed audio user simulator.
class LlmAudioUserSimulatorConfig extends BaseUserSimulatorConfig {
  /// Creates an audio user simulator configuration.
  LlmAudioUserSimulatorConfig({
    this.type = 'llm_audio',
    this.model = 'gemini-2.5-flash',
    GenerateContentConfig? modelConfiguration,
    this.audioModel = _defaultAudioModel,
    GenerateContentConfig? audioModelConfiguration,
    this.includeTextWithAudio = true,
    this.includeFunctionCalls = false,
    this.maxAllowedInvocations = 20,
    this.customInstructions,
    super.values,
  }) : modelConfiguration =
           modelConfiguration ??
           GenerateContentConfig(
             thinkingConfig: <String, Object?>{
               'include_thoughts': true,
               'thinking_budget': 10240,
             },
           ),
       audioModelConfiguration =
           audioModelConfiguration ??
           GenerateContentConfig(
             speechConfig: <String, Object?>{
               'voice_config': <String, Object?>{
                 'prebuilt_voice_config': <String, Object?>{
                   'voice_name': 'en-US-Studio-O',
                 },
               },
               'language_code': 'en-US',
             },
           ) {
    if (customInstructions != null &&
        !isValidUserSimulatorTemplate(
          customInstructions!,
          requiredParams: const <String>[
            'stop_signal',
            'conversation_plan',
            'conversation_history',
          ],
        )) {
      throw ArgumentError(
        'custom_instructions must contain each of the following formatting '
        'placeholders using Jinja syntax: {{ stop_signal }}, '
        '{{ conversation_plan }}, {{ conversation_history }}',
      );
    }
  }

  /// Discriminator tag for this simulator config subclass.
  final String type;

  /// Text generation model identifier.
  final String model;

  /// Configuration for the text generation model.
  final GenerateContentConfig modelConfiguration;

  /// Audio/TTS model identifier.
  final String audioModel;

  /// Configuration for the audio model (e.g. voice persona, speech config).
  final GenerateContentConfig audioModelConfiguration;

  /// Whether the user turn content should include both text and audio parts.
  final bool includeTextWithAudio;

  /// Whether function calls and responses are included in conversation history.
  final bool includeFunctionCalls;

  /// Maximum allowed simulation turns.
  final int maxAllowedInvocations;

  /// Custom prompt instructions.
  final String? customInstructions;

  /// Decodes this config from base dictionary / config.
  factory LlmAudioUserSimulatorConfig.fromBase(BaseUserSimulatorConfig config) {
    if (config is LlmAudioUserSimulatorConfig) {
      return config;
    }
    final Map<String, Object?> raw = config.values;
    final Object? rawMax =
        raw['maxAllowedInvocations'] ?? raw['max_allowed_invocations'];
    return LlmAudioUserSimulatorConfig(
      type: (raw['type'] as String?) ?? 'llm_audio',
      model: (raw['model'] as String?) ?? 'gemini-2.5-flash',
      audioModel:
          (raw['audioModel'] ?? raw['audio_model']) as String? ??
          _defaultAudioModel,
      includeTextWithAudio:
          (raw['includeTextWithAudio'] ?? raw['include_text_with_audio'])
              as bool? ??
          true,
      includeFunctionCalls:
          (raw['includeFunctionCalls'] ?? raw['include_function_calls'])
              as bool? ??
          false,
      maxAllowedInvocations: rawMax is int
          ? rawMax
          : (rawMax is num ? rawMax.toInt() : 20),
      customInstructions:
          (raw['customInstructions'] ?? raw['custom_instructions']) as String?,
      values: raw,
    );
  }
}

/// A multimodal [UserSimulator] that synthesizes 16 kHz PCM speech audio user
/// messages by decorating a text-producing [UserSimulator].
class LlmAudioUserSimulator extends UserSimulator<LlmAudioUserSimulatorConfig> {
  /// Creates an LLM audio user simulator.
  ///
  /// Provide either [textSimulator] (for example an [LlmBackedUserSimulator] or
  /// `StaticUserSimulator`) or [conversationScenario] (which builds an internal
  /// [LlmBackedUserSimulator]).
  LlmAudioUserSimulator({
    required super.config,
    ConversationScenario? conversationScenario,
    UserSimulator? textSimulator,
    BaseLlm Function(String model)? llmFactory,
    BaseLlm? audioLlm,
  }) : _audioLlm = audioLlm,
       _textSimulator =
           textSimulator ??
           LlmBackedUserSimulator(
             config: config,
             conversationScenario: _requireConversationScenario(
               conversationScenario,
             ),
             llmFactory: llmFactory,
           ),
       super(configDecoder: LlmAudioUserSimulatorConfig.fromBase);

  final BaseLlm? _audioLlm;
  final UserSimulator _textSimulator;

  static ConversationScenario _requireConversationScenario(
    ConversationScenario? scenario,
  ) {
    if (scenario == null) {
      throw ArgumentError(
        'Either textSimulator or conversationScenario must be provided to '
        'LlmAudioUserSimulator.',
      );
    }
    return scenario;
  }

  BaseLlm _resolveAudioModel() {
    if (_audioLlm != null) {
      return _audioLlm;
    }
    if (config.audioModel == _defaultAudioModel) {
      return CloudTtsLlm(model: config.audioModel);
    }
    try {
      return LLMRegistry.newLlm(config.audioModel);
    } on StateError {
      return Gemini(model: config.audioModel);
    }
  }

  @override
  Evaluator? getSimulationEvaluator() =>
      _textSimulator.getSimulationEvaluator();

  @override
  Future<NextUserMessage> getNextUserMessage(List<Event> history) async {
    final NextUserMessage textNext = await _textSimulator.getNextUserMessage(
      history,
    );

    if (textNext.status != Status.success) {
      return textNext;
    }

    final StringBuffer textBuffer = StringBuffer();
    final Content? baseContent = textNext.userMessage;
    if (baseContent != null && baseContent.parts.isNotEmpty) {
      for (final Part part in baseContent.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          textBuffer.write(part.text);
        }
      }
    }

    final String text = textBuffer.toString();
    if (text.isEmpty) {
      return textNext;
    }

    return NextUserMessage(
      status: Status.success,
      userMessage: await toAudioContent(text),
    );
  }

  /// Converts [text] into a user [Content] carrying 16 kHz PCM audio.
  ///
  /// Consumes all streamed audio chunks from the configured audio model, throws
  /// a [StateError] on model error responses or empty audio output, and
  /// converts the synthesized audio via [toLiveInput] to
  /// `audio/pcm;rate=16000`.
  Future<Content> toAudioContent(String text) async {
    final List<Part> parts = <Part>[];
    if (config.includeTextWithAudio) {
      parts.add(Part.text(text));
    }

    final (Uint8List audioBytes, String mimeType) = await _generateAudio(text);
    final Blob liveAudioBlob = toLiveInput(
      Blob(mimeType: mimeType, data: audioBytes),
    );
    parts.add(Part(inlineData: liveAudioBlob));

    return Content(role: _authorUser, parts: parts);
  }

  Future<(Uint8List, String)> _generateAudio(String text) async {
    final BaseLlm audioModel = _resolveAudioModel();
    final LlmRequest llmRequest = LlmRequest(
      model: config.audioModel,
      contents: <Content>[
        Content(
          role: _authorUser,
          parts: <Part>[Part.text(text)],
        ),
      ],
      config: config.audioModelConfiguration.copyWith(),
    );
    addDefaultRetryOptionsIfNotPresent(llmRequest);

    final BytesBuilder audioBuffer = BytesBuilder(copy: false);
    String mimeType = 'audio/pcm';

    await for (final LlmResponse llmResponse in audioModel.generateContent(
      llmRequest,
    )) {
      if (llmResponse.errorCode != null && llmResponse.errorCode!.isNotEmpty) {
        throw StateError(
          'Audio generation failed: ${llmResponse.errorCode}'
          ' — ${llmResponse.errorMessage}',
        );
      }

      final Content? responseContent = llmResponse.content;
      if (responseContent != null && responseContent.parts.isNotEmpty) {
        for (final Part part in responseContent.parts) {
          final InlineData? inlineData = part.inlineData;
          if (inlineData != null && inlineData.data.isNotEmpty) {
            audioBuffer.add(inlineData.data);
            if (inlineData.mimeType.isNotEmpty) {
              mimeType = inlineData.mimeType;
            }
          }
        }
      }
    }

    final Uint8List collectedBytes = audioBuffer.takeBytes();
    if (collectedBytes.isEmpty) {
      throw StateError('Audio model returned no audio data');
    }

    return (collectedBytes, mimeType);
  }
}
