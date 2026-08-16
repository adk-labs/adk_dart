/// LLM-backed audio user simulator for multimodal evaluation conversations.
library;

import '../../events/event.dart';
import '../../models/base_llm.dart';
import '../../models/google_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../types/content.dart';
import '../conversation_scenarios.dart';
import '../eval_config.dart';
import '../evaluator.dart';
import 'llm_backed_user_simulator.dart';
import 'user_simulator.dart';

/// Configuration for an LLM-backed audio user simulator.
class LlmAudioUserSimulatorConfig extends BaseUserSimulatorConfig {
  /// Creates an audio user simulator configuration.
  LlmAudioUserSimulatorConfig({
    this.model = 'gemini-2.5-flash',
    GenerateContentConfig? modelConfiguration,
    this.audioModel = 'cloud_tts',
    this.audioModelConfiguration,
    this.includeTextWithAudio = false,
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
           );

  /// Text generation model identifier.
  final String model;

  /// Configuration for the text generation model.
  final GenerateContentConfig modelConfiguration;

  /// Audio/TTS model identifier.
  final String audioModel;

  /// Configuration for the audio model (e.g. voice persona, speech config).
  final GenerateContentConfig? audioModelConfiguration;

  /// Whether the user turn content should include both text and audio parts.
  final bool includeTextWithAudio;

  /// Maximum allowed simulation turns.
  final int maxAllowedInvocations;

  /// Custom prompt instructions.
  final String? customInstructions;

  /// Decodes this config from base dictionary / config.
  factory LlmAudioUserSimulatorConfig.fromBase(BaseUserSimulatorConfig config) {
    if (config is LlmAudioUserSimulatorConfig) {
      return config;
    }
    return LlmAudioUserSimulatorConfig(values: config.values);
  }
}

/// A multimodal [UserSimulator] that synthesizes speech audio user messages.
class LlmAudioUserSimulator
    extends UserSimulator<LlmAudioUserSimulatorConfig> {
  /// Creates an LLM audio user simulator.
  LlmAudioUserSimulator({
    required BaseUserSimulatorConfig config,
    required ConversationScenario conversationScenario,
    BaseLlm Function(String model)? llmFactory,
    BaseLlm? audioLlm,
  }) : _audioLlm = audioLlm,
       _textSimulator = LlmBackedUserSimulator(
         config: config,
         conversationScenario: conversationScenario,
         llmFactory: llmFactory,
       ),
       super(
         config: config,
         configDecoder: LlmAudioUserSimulatorConfig.fromBase,
       );

  final BaseLlm? _audioLlm;
  final LlmBackedUserSimulator _textSimulator;

  @override
  Evaluator? getSimulationEvaluator() =>
      _textSimulator.getSimulationEvaluator();

  @override
  Future<NextUserMessage> getNextUserMessage(List<Event> history) async {
    final NextUserMessage textNext =
        await _textSimulator.getNextUserMessage(history);

    if (textNext.status != Status.success || textNext.userMessage == null) {
      return textNext;
    }

    final Content baseContent = textNext.userMessage!;
    final String text = baseContent.parts
        .map((Part p) => p.text ?? '')
        .where((String s) => s.isNotEmpty)
        .join(' ');

    if (text.isEmpty) {
      return textNext;
    }

    // Synthesize audio bytes via audio model
    final BaseLlm audioModel = _audioLlm ?? Gemini(model: config.audioModel);

    List<int> audioBytes = const <int>[];
    String mimeType = 'audio/pcm';

    try {
      final LlmRequest audioReq = LlmRequest(
        model: config.audioModel,
        contents: <Content>[Content.userText(text)],
        config: config.audioModelConfiguration ?? GenerateContentConfig(),
      );
      final LlmResponse audioResp =
          await audioModel.generateContent(audioReq).first;
      if (audioResp.content?.parts.isNotEmpty == true) {
        final Part firstPart = audioResp.content!.parts.first;
        if (firstPart.inlineData != null) {
          audioBytes = firstPart.inlineData!.data;
          mimeType = firstPart.inlineData!.mimeType;
        }
      }
    } catch (_) {
      audioBytes = text.codeUnits;
    }

    final List<Part> parts = <Part>[
      Part.fromInlineData(
        mimeType: mimeType,
        data: audioBytes,
      ),
    ];

    if (config.includeTextWithAudio) {
      parts.insert(0, Part.text(text));
    }

    return NextUserMessage(
      status: textNext.status,
      userMessage: Content(role: 'user', parts: parts),
    );
  }
}
