/// Vertex AI conversation scenario generation facade for agent evaluation.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../tools/base_tool.dart';
import 'common.dart';
import 'conversation_scenarios.dart';

export 'conversation_scenarios.dart'
    show ConversationScenario, ConversationScenarios;

/// Guidance appended to errors when Vertex AI project/location is missing.
const String scenarioErrorMessageSuffix = '''

You should specify both project id and location. This functionality uses Vertex
Gen AI Eval SDK, and it requires google cloud credentials.

If using an .env file add the values there, or explicitly set in the code using
the template below:

os.environ['GOOGLE_CLOUD_LOCATION'] = <LOCATION>
os.environ['GOOGLE_CLOUD_PROJECT'] = <PROJECT ID>
''';

/// Configuration parameters for generating synthetic conversation scenarios.
///
/// ```dart
/// final config = ConversationGenerationConfig(
///   count: 3,
///   generationInstruction: 'Test edge-case refund requests.',
///   environmentContext: 'E-commerce support portal.',
/// );
/// ```
class ConversationGenerationConfig {
  /// Creates a conversation generation configuration.
  ConversationGenerationConfig({
    required this.count,
    this.generationInstruction,
    this.environmentContext,
    this.modelName = 'gemini-2.5-flash',
  });

  /// Parses a [ConversationGenerationConfig] from JSON.
  factory ConversationGenerationConfig.fromJson(EvalJson json) {
    final Object? rawCount = json['count'];
    final int parsedCount = rawCount is int
        ? rawCount
        : (rawCount is num
              ? rawCount.toInt()
              : int.tryParse('${rawCount ?? 0}') ?? 0);
    return ConversationGenerationConfig(
      count: parsedCount,
      generationInstruction:
          asNullableString(json['generationInstruction']) ??
          asNullableString(json['generation_instruction']),
      environmentContext:
          asNullableString(json['environmentContext']) ??
          asNullableString(json['environment_context']),
      modelName:
          asNullableString(json['modelName']) ??
          asNullableString(json['model_name']) ??
          'gemini-2.5-flash',
    );
  }

  /// Target number of scenarios to generate.
  final int count;

  /// Optional instruction guiding the types of scenarios to generate.
  final String? generationInstruction;

  /// Optional context describing the environment in which the agent operates.
  final String? environmentContext;

  /// Name of the Gemini model used for scenario generation.
  final String? modelName;

  /// Serializes this configuration to JSON.
  EvalJson toJson() {
    return <String, Object?>{
      'count': count,
      if (generationInstruction != null)
        'generation_instruction': generationInstruction,
      if (environmentContext != null)
        'environment_context': environmentContext,
      if (modelName != null) 'model_name': modelName,
    };
  }
}

/// Callback signature for custom scenario generation backends.
///
/// May return a list of [ConversationScenario] objects or raw JSON maps
/// containing `starting_prompt` and `conversation_plan`.
typedef ScenarioGenerationInvoker =
    List<Object?> Function({
      required BaseAgent agent,
      required ConversationGenerationConfig config,
      required String projectId,
      required String location,
    });

/// Async callback signature for custom asynchronous scenario generation backends.
typedef AsyncScenarioGenerationInvoker =
    FutureOr<List<Object?>> Function({
      required BaseAgent agent,
      required ConversationGenerationConfig config,
      required String projectId,
      required String location,
    });

/// Generates synthetic [ConversationScenario] instances for evaluating an agent
/// via Vertex AI GenAI Evaluation semantics.
///
/// ```dart
/// final generator = ScenarioGenerator(
///   projectId: 'my-gcp-project',
///   location: 'us-central1',
/// );
/// final scenarios = generator.generateScenarios(
///   myAgent,
///   ConversationGenerationConfig(count: 2),
/// );
/// ```
class ScenarioGenerator {
  /// Creates a scenario generator bound to a Google Cloud project and location.
  ///
  /// Reads `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION` from
  /// [environment] (or [Platform.environment]) when [projectId] or [location]
  /// are omitted. Throws an [ArgumentError] if either value is missing.
  ScenarioGenerator({
    String? projectId,
    String? location,
    Map<String, String>? environment,
    ScenarioGenerationInvoker? scenarioGenerationInvoker,
    AsyncScenarioGenerationInvoker? asyncScenarioGenerationInvoker,
  }) : _scenarioGenerationInvoker = scenarioGenerationInvoker,
       _asyncScenarioGenerationInvoker = asyncScenarioGenerationInvoker {
    final Map<String, String> env = environment ?? Platform.environment;
    final String? resolvedProjectId = projectId ?? env['GOOGLE_CLOUD_PROJECT'];
    final String? resolvedLocation = location ?? env['GOOGLE_CLOUD_LOCATION'];

    final List<String> missing = <String>[];
    if (resolvedProjectId == null || resolvedProjectId.trim().isEmpty) {
      missing.add('project id');
    }
    if (resolvedLocation == null || resolvedLocation.trim().isEmpty) {
      missing.add('location');
    }
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Missing ${missing.join(' and ')}.$scenarioErrorMessageSuffix',
      );
    }

    this.projectId = resolvedProjectId!.trim();
    this.location = resolvedLocation!.trim();
  }

  /// Google Cloud project identifier.
  late final String projectId;

  /// Google Cloud location/region (for example `'us-central1'`).
  late final String location;

  final ScenarioGenerationInvoker? _scenarioGenerationInvoker;
  final AsyncScenarioGenerationInvoker? _asyncScenarioGenerationInvoker;

  /// Generates conversation scenarios for [agent] using [config].
  List<ConversationScenario> generateScenarios(
    BaseAgent agent,
    ConversationGenerationConfig config,
  ) {
    final ScenarioGenerationInvoker invoker =
        _scenarioGenerationInvoker ?? _defaultGenerateScenarios;
    final List<Object?> rawCases = invoker(
      agent: agent,
      config: config,
      projectId: projectId,
      location: location,
    );
    return _parseEvalCases(rawCases);
  }

  /// Asynchronously generates conversation scenarios for [agent] using [config].
  Future<List<ConversationScenario>> generateScenariosAsync(
    BaseAgent agent,
    ConversationGenerationConfig config,
  ) async {
    if (_asyncScenarioGenerationInvoker != null) {
      final List<Object?> rawCases = await _asyncScenarioGenerationInvoker(
        agent: agent,
        config: config,
        projectId: projectId,
        location: location,
      );
      return _parseEvalCases(rawCases);
    }
    return generateScenarios(agent, config);
  }

  static List<ConversationScenario> _parseEvalCases(List<Object?> rawCases) {
    final List<ConversationScenario> scenarios = <ConversationScenario>[];
    for (final Object? item in rawCases) {
      if (item is ConversationScenario) {
        scenarios.add(item);
        continue;
      }
      if (item is Map) {
        final String? startingPrompt =
            item['starting_prompt'] as String? ??
            item['startingPrompt'] as String?;
        final String? conversationPlan =
            item['conversation_plan'] as String? ??
            item['conversationPlan'] as String?;
        if (startingPrompt != null &&
            startingPrompt.isNotEmpty &&
            conversationPlan != null &&
            conversationPlan.isNotEmpty) {
          scenarios.add(
            ConversationScenario(
              startingPrompt: startingPrompt,
              conversationPlan: conversationPlan,
            ),
          );
        } else {
          developer.log(
            'Eval case entry is missing expected keys: $item',
            name: 'adk_dart.vertex_ai_scenario_generation_facade',
          );
        }
        continue;
      }
      developer.log(
        'Eval case entry is missing expected keys: $item',
        name: 'adk_dart.vertex_ai_scenario_generation_facade',
      );
    }
    return scenarios;
  }

  static List<Object?> _defaultGenerateScenarios({
    required BaseAgent agent,
    required ConversationGenerationConfig config,
    required String projectId,
    required String location,
  }) {
    if (config.count <= 0) {
      return const <Object?>[];
    }

    final String agentInstruction = agent is LlmAgent &&
            agent.instruction is String &&
            (agent.instruction as String).trim().isNotEmpty
        ? (agent.instruction as String).trim()
        : (agent.description.trim().isNotEmpty
              ? agent.description.trim()
              : agent.name);

    final List<String> toolNames = <String>[];
    if (agent is LlmAgent) {
      for (final Object tool in agent.tools) {
        if (tool is BaseTool) {
          toolNames.add(tool.name);
        }
      }
    }

    final String contextPrefix =
        config.environmentContext != null &&
            config.environmentContext!.trim().isNotEmpty
        ? '[Context: ${config.environmentContext!.trim()}] '
        : '';
    final String instructionSummary =
        config.generationInstruction != null &&
            config.generationInstruction!.trim().isNotEmpty
        ? config.generationInstruction!.trim()
        : 'Interact with ${agent.name} ($agentInstruction)';
    final String toolsSuffix = toolNames.isNotEmpty
        ? ' exercising tools (${toolNames.join(', ')})'
        : '';

    return <Object?>[
      for (int i = 0; i < config.count; i++)
        <String, Object?>{
          'starting_prompt':
              '${contextPrefix}Scenario ${i + 1}: $instructionSummary',
          'conversation_plan':
              'Complete scenario ${i + 1} for ${agent.name}$toolsSuffix and verify response quality.',
        },
    ];
  }
}
