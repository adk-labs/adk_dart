import '../../events/event.dart';
import '../../models/base_llm.dart';
import '../../models/google_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../models/registry.dart';
import '../../types/content.dart';
import '../_retry_options_utils.dart';
import '../conversation_scenarios.dart';
import '../eval_config.dart';
import '../eval_metrics.dart';
import '../evaluator.dart';
import 'llm_backed_user_simulator_prompts.dart';
import 'per_turn_user_simulator_quality_v1.dart';
import 'user_simulator.dart';
import 'user_simulator_personas.dart';

const String _authorUser = 'user';
const String _stopSignal = '</finished>';

class LlmBackedUserSimulatorConfig extends BaseUserSimulatorConfig {
  LlmBackedUserSimulatorConfig({
    this.model = 'gemini-2.5-flash',
    GenerateContentConfig? modelConfiguration,
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
           ) {
    if (customInstructions != null &&
        !isValidUserSimulatorTemplate(
          customInstructions!,
          requiredParams: <String>[
            'stop_signal',
            'conversation_plan',
            'conversation_history',
          ],
        )) {
      throw ArgumentError(
        'customInstructions must include placeholders: '
        '{{ stop_signal }}, {{ conversation_plan }}, '
        '{{ conversation_history }}',
      );
    }
  }

  final String model;
  final GenerateContentConfig modelConfiguration;
  final int maxAllowedInvocations;
  final String? customInstructions;

  factory LlmBackedUserSimulatorConfig.fromBase(
    BaseUserSimulatorConfig config,
  ) {
    if (config is LlmBackedUserSimulatorConfig) {
      return config;
    }

    final Map<String, Object?> raw = config.toJson();
    return LlmBackedUserSimulatorConfig(
      model:
          (raw['model'] as String?) ??
          (raw['model_name'] as String?) ??
          'gemini-2.5-flash',
      maxAllowedInvocations: _asInt(
        raw['maxAllowedInvocations'] ?? raw['max_allowed_invocations'],
        fallback: 20,
      ),
      customInstructions:
          (raw['customInstructions'] ?? raw['custom_instructions']) as String?,
      values: raw,
    );
  }

  @override
  Map<String, Object?> toJson() {
    final Map<String, Object?> result = <String, Object?>{
      ...values,
      'model': model,
      'max_allowed_invocations': maxAllowedInvocations,
    };
    if (customInstructions != null) {
      result['custom_instructions'] = customInstructions;
    }
    return result;
  }
}

class LlmBackedUserSimulator
    extends UserSimulator<LlmBackedUserSimulatorConfig> {
  LlmBackedUserSimulator({
    required BaseUserSimulatorConfig config,
    required ConversationScenario conversationScenario,
    BaseLlm Function(String model)? llmFactory,
  }) : _conversationScenario = conversationScenario,
       _userPersona = conversationScenario.userPersona,
       _llmFactory = llmFactory ?? _defaultLlmFactory,
       _invocationCount = 0,
       super(
         config: config,
         configDecoder: LlmBackedUserSimulatorConfig.fromBase,
       ) {
    _llm = _llmFactory(this.config.model);
  }

  final ConversationScenario _conversationScenario;
  final UserPersona? _userPersona;
  final BaseLlm Function(String model) _llmFactory;
  late final BaseLlm _llm;
  int _invocationCount;

  String summarizeConversation(List<Event> events) {
    final List<String> rewrittenDialogue = <String>[];
    for (final Event event in events) {
      if (event.content == null || event.content!.parts.isEmpty) {
        continue;
      }
      final String author = event.author;
      for (final Part part in event.content!.parts) {
        if ((part.text ?? '').isEmpty || part.thought) {
          continue;
        }
        rewrittenDialogue.add('$author: ${part.text!}');
      }
    }
    return rewrittenDialogue.join('\n\n');
  }

  Future<String> getLlmResponse(String rewrittenDialogue) async {
    if (_invocationCount == 0) {
      return _conversationScenario.startingPrompt;
    }

    final String prompt = getLlmBackedUserSimulatorPrompt(
      conversationPlan: _conversationScenario.conversationPlan,
      conversationHistory: rewrittenDialogue,
      stopSignal: _stopSignal,
      customInstructions: config.customInstructions,
      userPersona: _userPersona,
    );

    final LlmRequest llmRequest = LlmRequest(
      model: config.model,
      config: config.modelConfiguration.copyWith(),
      contents: <Content>[
        Content(role: _authorUser, parts: <Part>[Part.text(prompt)]),
      ],
    );
    addDefaultRetryOptionsIfNotPresent(llmRequest);

    final StringBuffer response = StringBuffer();
    await for (final LlmResponse llmResponse in _llm.generateContent(
      llmRequest,
      stream: true,
    )) {
      final Content? generated = llmResponse.content;
      if (generated == null || generated.parts.isEmpty) {
        continue;
      }
      for (final Part part in generated.parts) {
        if ((part.text ?? '').isEmpty || part.thought) {
          continue;
        }
        response.write(part.text);
      }
    }
    return response.toString();
  }

  @override
  Future<NextUserMessage> getNextUserMessage(List<Event> events) async {
    final int invocationLimit = config.maxAllowedInvocations;
    if (invocationLimit >= 0 && _invocationCount >= invocationLimit) {
      return NextUserMessage(status: Status.turnLimitReached);
    }

    final String rewrittenDialogue = summarizeConversation(events);
    final String response = await getLlmResponse(rewrittenDialogue);
    _invocationCount += 1;

    if (response.toLowerCase().contains(_stopSignal.toLowerCase())) {
      return NextUserMessage(status: Status.stopSignalDetected);
    }

    if (response.trim().isNotEmpty) {
      return NextUserMessage(
        status: Status.success,
        userMessage: Content(
          role: _authorUser,
          parts: <Part>[Part.text(response)],
        ),
      );
    }

    return NextUserMessage(status: Status.noMessageGenerated);
  }

  @override
  Evaluator? getSimulationEvaluator() {
    return PerTurnUserSimulatorQualityV1(
      EvalMetricSpec(
        metricName: 'per_turn_user_simulator_quality_v1',
        criterion: LlmBackedUserSimulatorCriterion(
          threshold: 0.5,
          stopSignal: _stopSignal,
        ),
      ),
    );
  }

  static BaseLlm _defaultLlmFactory(String model) {
    try {
      return LLMRegistry.newLlm(model);
    } on StateError {
      return Gemini(model: model);
    }
  }
}

int _asInt(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}
