/// GEPA-based root agent and skill instructions optimizer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import '../agents/context.dart';
import '../agents/invocation_context.dart';
import '../agents/llm_agent.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../sessions/in_memory_session_service.dart';
import '../sessions/session.dart';
import '../skills/skill_runtime.dart';
import '../tools/skill_toolset.dart';
import '../types/content.dart';
import 'agent_optimizer.dart';
import 'data_types.dart';
import 'sampler.dart';

export 'data_types.dart' show AgentWithScores, SamplingResult;

/// Candidate component key for the root agent instruction.
const String agentPromptKey = 'agent_prompt';

/// Prefix for candidate component keys corresponding to skill instructions.
const String skillKeyPrefix = 'skill_instructions:';

/// Fallback score assigned when an example ID is missing from sampler output.
const double missingExampleScore = 0.0;

/// Prompt template used to propose an improved root agent instruction.
const String agentPromptUpdatorInstTemplate = '''
I provided a system prompt to an LLM agent, along with a list of skills it can load and use.
Below is the current system prompt for the agent:
```
{curr_param}
```

Here are the execution traces of the agent on a few examples, along with the evaluation feedback:
```
{side_info}
```

Your task is to write a new, improved system prompt for the agent.
Carefully analyze the execution traces and feedback to identify any mistakes, inefficiencies, or areas for improvement in the agent's behavior.
Make sure the new system prompt incorporates any domain-specific factual information or constraints revealed in the feedback.

Provide the new system prompt within ``` blocks.
''';

/// Prompt template used to propose improved skill instructions.
const String skillInstUpdatorInstTemplate = '''
An LLM agent has access to a set of skills it can load and use.
Below are the current instructions for one of those skills:
```
{curr_param}
```

Here are the execution traces of the agent on a few examples where this skill was available, along with the evaluation feedback:
```
{side_info}
```

Your task is to write new, improved instructions for this skill.
Carefully analyze the execution traces and feedback to identify how the skill instructions can be clarified, expanded, or corrected to help the agent perform better.
Make sure the new skill instructions incorporate any domain-specific factual information or constraints revealed in the feedback.

Provide the new skill instructions within ``` blocks.
''';

/// Type alias for prompts accepted by [generateReflectionResponse].
typedef GEPAPrompt = Object;

/// Ensures [agent] has a static string instruction and returns it.
///
/// Throws an [ArgumentError] if [agent]'s instruction is a dynamic provider.
String requireStaticInstruction(Agent agent) {
  final Object instruction = agent.instruction;
  if (instruction is! String) {
    throw ArgumentError(
      'GEPA optimization requires initial_agent.instruction to be a static '
      'string; request-scoped instruction providers cannot be resolved '
      'without an invocation context.',
    );
  }
  return instruction;
}

/// Generates a single reflection response string from [llm] for [prompt].
Future<String> generateReflectionResponse({
  required BaseLlm llm,
  required String model,
  required GenerateContentConfig config,
  required GEPAPrompt prompt,
}) async {
  final LlmRequest request = LlmRequest(
    model: model,
    config: config.copyWith(),
    contents: <Content>[
      Content(
        role: 'user',
        parts: <Part>[Part.text('$prompt')],
      ),
    ],
  );

  LlmResponse? response;
  await for (final LlmResponse item in llm.generateContent(
    request,
    stream: false,
  )) {
    response = item;
    break;
  }

  final Content? content = response?.content;
  if (content == null || content.parts.isEmpty) {
    return '';
  }

  final StringBuffer buffer = StringBuffer();
  for (final Part part in content.parts) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty && !part.thought) {
      buffer.write(text);
    }
  }
  return buffer.toString();
}

final Expando<List<Skill>> _toolsetSkillsCache = Expando<List<Skill>>(
  'gepa_skill_toolset_skills',
);

/// Registers the known [skills] belonging to [toolset] for synchronous cloning.
void registerToolsetSkills(SkillToolset toolset, List<Skill> skills) {
  _toolsetSkillsCache[toolset] = List<Skill>.unmodifiable(skills);
}

/// Extracts and caches the local [Skill] list from [toolset].
Future<List<Skill>> extractToolsetSkills(SkillToolset toolset) async {
  final List<Skill>? cached = _toolsetSkillsCache[toolset];
  if (cached != null) {
    return cached;
  }

  try {
    final dynamic dynToolset = toolset;
    final Object? directSkills = dynToolset.skills;
    if (directSkills is Iterable) {
      final List<Skill> list = directSkills.whereType<Skill>().toList(
        growable: false,
      );
      _toolsetSkillsCache[toolset] = list;
      return list;
    }
  } catch (_) {
    // Proceed to tool-based extraction.
  }

  final InMemorySessionService sessionService = InMemorySessionService();
  final Session dummySession = Session(
    id: '_gepa_skill_extract_session',
    appName: '_gepa_skill_extract_app',
    userId: '_gepa_skill_extract_user',
  );
  final Agent dummyAgent = Agent(name: '_gepa_skill_extract_agent');
  final InvocationContext invCtx = InvocationContext(
    sessionService: sessionService,
    invocationId: '_gepa_skill_extract_inv',
    agent: dummyAgent,
    session: dummySession,
  );
  final Context toolCtx = Context(invCtx);

  final Object? xmlObj = await ListSkillsTool(
    toolset,
  ).run(args: <String, dynamic>{}, toolContext: toolCtx);
  final List<String> skillNames = <String>[];
  if (xmlObj is String && xmlObj.isNotEmpty) {
    final RegExp nameTagRegex = RegExp(r'<name>([^<]+)</name>');
    for (final RegExpMatch match in nameTagRegex.allMatches(xmlObj)) {
      final String? name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty) {
        skillNames.add(name);
      }
    }
  }

  final List<Skill> extracted = <Skill>[];
  final LoadSkillTool loader = LoadSkillTool(toolset);
  for (final String skillName in skillNames) {
    final Object? loaded = await loader.run(
      args: <String, dynamic>{'skill_name': skillName},
      toolContext: toolCtx,
    );
    if (loaded is Map) {
      final String instructions = '${loaded['instructions'] ?? ''}';
      final Object? fmRaw = loaded['frontmatter'];
      Frontmatter? frontmatter;
      if (fmRaw is Map) {
        frontmatter = Frontmatter.fromMap(
          fmRaw.map<String, Object?>((Object? k, Object? v) => MapEntry('$k', v)),
        );
      }
      extracted.add(
        Skill(
          frontmatter: frontmatter,
          name: frontmatter == null ? skillName : null,
          description: frontmatter == null ? skillName : null,
          instructions: instructions,
        ),
      );
    }
  }

  final List<Skill> immutableList = List<Skill>.unmodifiable(extracted);
  _toolsetSkillsCache[toolset] = immutableList;
  return immutableList;
}

List<Skill> _getKnownSkillsSync(
  SkillToolset toolset,
  Map<String, String> candidate,
) {
  final List<Skill>? cached = _toolsetSkillsCache[toolset];
  if (cached != null) {
    return cached;
  }
  try {
    final dynamic dynToolset = toolset;
    final Object? directSkills = dynToolset.skills;
    if (directSkills is Iterable) {
      final List<Skill> list = directSkills.whereType<Skill>().toList(
        growable: false,
      );
      _toolsetSkillsCache[toolset] = list;
      return list;
    }
  } catch (_) {
    // Fall back to candidate skill keys if toolset was not pre-indexed.
  }

  final List<Skill> synthesized = <Skill>[];
  candidate.forEach((String key, String value) {
    if (key.startsWith(skillKeyPrefix)) {
      final String skillName = key.substring(skillKeyPrefix.length);
      if (skillName.isNotEmpty) {
        synthesized.add(
          Skill(
            name: skillName,
            description: 'Skill $skillName',
            instructions: value,
          ),
        );
      }
    }
  });
  return synthesized;
}

/// Clones [toolset] with updated skill instructions from [candidate].
SkillToolset updateSkillToolset(
  SkillToolset toolset,
  Map<String, String> candidate, {
  List<Skill>? skills,
}) {
  final List<Skill> sourceSkills =
      skills ?? _getKnownSkillsSync(toolset, candidate);
  final List<Skill> newSkills = <Skill>[];
  for (final Skill skill in sourceSkills) {
    final String skillKey = '$skillKeyPrefix${skill.name}';
    if (candidate.containsKey(skillKey)) {
      newSkills.add(
        Skill(
          frontmatter: skill.frontmatter,
          instructions: candidate[skillKey]!,
          resources: skill.resources,
          version: skill.version,
        ),
      );
    } else {
      newSkills.add(skill);
    }
  }
  final SkillToolset cloned = toolset.cloneWithUpdatedSkills(newSkills);
  _toolsetSkillsCache[cloned] = List<Skill>.unmodifiable(newSkills);
  return cloned;
}

/// Creates a new [Agent] by applying [candidate] components to [initialAgent].
Agent createAgentFromCandidate(
  Agent initialAgent,
  Map<String, String> candidate,
) {
  final Map<String, Object?> update = <String, Object?>{};
  if (candidate.containsKey(agentPromptKey)) {
    update['instruction'] = candidate[agentPromptKey];
  }

  if (initialAgent.tools.isNotEmpty) {
    final List<Object> newTools = <Object>[];
    bool toolsUpdated = false;
    for (final Object tool in initialAgent.tools) {
      if (tool is SkillToolset) {
        newTools.add(updateSkillToolset(tool, candidate));
        toolsUpdated = true;
      } else {
        newTools.add(tool);
      }
    }
    if (toolsUpdated) {
      update['tools'] = newTools;
    }
  }

  return initialAgent.clone(update: update);
}

/// Batch evaluation result returned by [AgentGEPAAdapter.evaluate].
class GEPAEvaluationBatch {
  /// Creates a GEPA evaluation batch.
  GEPAEvaluationBatch({
    required List<Object?> outputs,
    required List<double> scores,
    List<Map<String, Object?>>? trajectories,
  }) : outputs = List<Object?>.unmodifiable(outputs),
       scores = List<double>.unmodifiable(scores),
       trajectories = trajectories == null
           ? null
           : List<Map<String, Object?>>.unmodifiable(
               trajectories.map(
                 (Map<String, Object?> t) =>
                     Map<String, Object?>.unmodifiable(t),
               ),
             );

  /// Outputs per evaluated example in batch order.
  final List<Object?> outputs;

  /// Numeric scores per evaluated example in batch order.
  final List<double> scores;

  /// Optional execution trajectories per evaluated example.
  final List<Map<String, Object?>>? trajectories;
}

/// Adapter connecting ADK [Agent] evaluation and reflection to GEPA.
///
/// ```dart
/// final adapter = AgentGEPAAdapter(
///   initialAgent: rootAgent,
///   sampler: sampler,
///   proposerLlm: proposerLlm,
/// );
/// ```
class AgentGEPAAdapter {
  /// Creates an ADK GEPA adapter.
  AgentGEPAAdapter({
    required Agent initialAgent,
    required Sampler<UnstructuredSamplingResult> sampler,
    required BaseLlm proposerLlm,
  }) : _initialAgent = initialAgent,
       _sampler = sampler,
       _proposerLlm = proposerLlm;

  final Agent _initialAgent;
  final Sampler<UnstructuredSamplingResult> _sampler;
  final BaseLlm _proposerLlm;

  static final RegExp _codeBlockPattern = RegExp(r'```(?:\w*\n)?([\s\S]*?)```');

  Future<UnstructuredSamplingResult> _runAsyncEval(
    List<String> batch,
    Map<String, String> candidate, {
    required bool captureTraces,
  }) async {
    final Agent currentAgent = createAgentFromCandidate(
      _initialAgent,
      candidate,
    );
    return _sampler.sampleAndScore(
      currentAgent,
      exampleSet: ExampleSet.train,
      batch: batch,
      captureFullEvalData: captureTraces,
    );
  }

  /// Evaluates [candidate] on [batch] of training example IDs.
  Future<GEPAEvaluationBatch> evaluate(
    List<String> batch,
    Map<String, String> candidate, {
    bool captureTraces = false,
  }) async {
    final UnstructuredSamplingResult evalResults = await _runAsyncEval(
      batch,
      candidate,
      captureTraces: captureTraces,
    );
    final Map<String, double> scoresDict = evalResults.scores;
    final Map<String, Map<String, Object?>> evalData =
        evalResults.data ?? const <String, Map<String, Object?>>{};

    final List<double> scores = <double>[];
    for (final String exampleId in batch) {
      if (!scoresDict.containsKey(exampleId)) {
        developer.log(
          'Score not found for example $exampleId, defaulting to $missingExampleScore.',
          name: 'adk_dart.gepa_root_agent_optimizer',
        );
        scores.add(missingExampleScore);
      } else {
        scores.add(scoresDict[exampleId]!);
      }
    }

    List<Map<String, Object?>>? trajectories;
    if (captureTraces) {
      trajectories = <Map<String, Object?>>[];
      for (final String exampleId in batch) {
        if (!evalData.containsKey(exampleId)) {
          developer.log(
            'Eval data not found for example $exampleId, defaulting to empty dict.',
            name: 'adk_dart.gepa_root_agent_optimizer',
          );
          trajectories.add(const <String, Object?>{});
        } else {
          trajectories.add(evalData[exampleId]!);
        }
      }
    }

    return GEPAEvaluationBatch(
      outputs: List<Object?>.filled(batch.length, null),
      scores: scores,
      trajectories: trajectories,
    );
  }

  /// Builds the reflective dataset mapping each component in
  /// [componentsToUpdate] to the list of trajectory records from [evalBatch].
  Map<String, List<Map<String, Object?>>> makeReflectiveDataset(
    Map<String, String> candidate,
    GEPAEvaluationBatch evalBatch,
    List<String> componentsToUpdate,
  ) {
    final List<Map<String, Object?>> trajectories =
        evalBatch.trajectories ?? const <Map<String, Object?>>[];
    return <String, List<Map<String, Object?>>>{
      for (final String component in componentsToUpdate)
        component: List<Map<String, Object?>>.from(trajectories),
    };
  }

  Future<String> _proposeOneComponent(
    String component,
    String currText,
    List<Map<String, Object?>> dataset,
  ) async {
    final String template = component.startsWith(skillKeyPrefix)
        ? skillInstUpdatorInstTemplate
        : agentPromptUpdatorInstTemplate;

    final String sideInfo = const JsonEncoder.withIndent('  ').convert(dataset);
    final String prompt = template
        .replaceAll('{curr_param}', currText)
        .replaceAll('{side_info}', sideInfo);

    final String responseText = await generateReflectionResponse(
      llm: _proposerLlm,
      model: _proposerLlm.model,
      config: GenerateContentConfig(),
      prompt: prompt,
    );

    final List<RegExpMatch> matches = _codeBlockPattern
        .allMatches(responseText)
        .toList();
    if (matches.isNotEmpty) {
      return (matches.last.group(1) ?? '').trim();
    }
    return responseText.trim();
  }

  /// Proposes updated texts for [componentsToUpdate] given [candidate] and
  /// [reflectiveDataset].
  Future<Map<String, String>> proposeNewTexts(
    Map<String, String> candidate,
    Map<String, List<Map<String, Object?>>> reflectiveDataset,
    List<String> componentsToUpdate,
  ) async {
    final List<String> activeComponents = <String>[];
    final List<Future<String>> tasks = <Future<String>>[];

    for (final String component in componentsToUpdate) {
      final List<Map<String, Object?>>? dataset = reflectiveDataset[component];
      if (dataset == null || dataset.isEmpty) {
        continue;
      }
      final String currText = candidate[component] ?? '';
      activeComponents.add(component);
      tasks.add(_proposeOneComponent(component, currText, dataset));
    }

    final List<String> results = await Future.wait(tasks);
    final Map<String, String> newTexts = <String, String>{};
    for (int i = 0; i < activeComponents.length; i++) {
      final String component = activeComponents[i];
      final String newText = results[i];
      newTexts[component] = newText.isNotEmpty
          ? newText
          : (candidate[component] ?? '');
    }
    return newTexts;
  }
}

/// Configuration for [GEPARootAgentOptimizer].
///
/// ```dart
/// final config = GEPARootAgentOptimizerConfig(
///   optimizerModel: 'gemini-2.5-flash',
///   maxMetricCalls: 20,
/// );
/// ```
class GEPARootAgentOptimizerConfig {
  /// Creates a GEPA root agent optimizer configuration.
  GEPARootAgentOptimizerConfig({
    this.optimizerModel = 'gemini-3.5-flash',
    GenerateContentConfig? modelConfiguration,
    this.maxMetricCalls = 100,
    this.reflectionMinibatchSize = 3,
    this.runDir,
  }) : modelConfiguration =
           modelConfiguration ??
           GenerateContentConfig(
             thinkingConfig: <String, Object?>{
               'include_thoughts': true,
               'thinking_level': 'HIGH',
             },
           ) {
    if (optimizerModel is! String && optimizerModel is! BaseLlm) {
      throw ArgumentError('optimizerModel must be a String or BaseLlm.');
    }
  }

  /// Parses a configuration from JSON.
  factory GEPARootAgentOptimizerConfig.fromJson(Map<String, Object?> json) {
    for (final String key in json.keys) {
      if (!_allowedKeys.contains(key)) {
        throw ArgumentError(
          'Unknown field `$key` in GEPARootAgentOptimizerConfig.',
        );
      }
    }
    final Object? rawModelConfig =
        json['modelConfiguration'] ?? json['model_configuration'];
    return GEPARootAgentOptimizerConfig(
      optimizerModel:
          json['optimizerModel'] ??
          json['optimizer_model'] ??
          'gemini-3.5-flash',
      modelConfiguration: rawModelConfig is GenerateContentConfig
          ? rawModelConfig
          : null,
      maxMetricCalls: _toInt(
        json['maxMetricCalls'] ?? json['max_metric_calls'],
        fallback: 100,
      ),
      reflectionMinibatchSize: _toInt(
        json['reflectionMinibatchSize'] ?? json['reflection_minibatch_size'],
        fallback: 3,
      ),
      runDir: (json['runDir'] ?? json['run_dir']) as String?,
    );
  }

  static const Set<String> _allowedKeys = <String>{
    'optimizerModel',
    'optimizer_model',
    'modelConfiguration',
    'model_configuration',
    'maxMetricCalls',
    'max_metric_calls',
    'reflectionMinibatchSize',
    'reflection_minibatch_size',
    'runDir',
    'run_dir',
  };

  /// Model name or [BaseLlm] instance used to propose updated prompts/skills.
  final Object optimizerModel;

  /// Generation config used when invoking the optimizer model.
  final GenerateContentConfig modelConfiguration;

  /// Maximum number of evaluation metric calls during optimization.
  final int maxMetricCalls;

  /// Number of training examples per reflection minibatch.
  final int reflectionMinibatchSize;

  /// Optional directory where GEPA run artifacts are written.
  final String? runDir;

  /// Serializes this configuration to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'optimizer_model': optimizerModel is BaseLlm
          ? (optimizerModel as BaseLlm).model
          : optimizerModel,
      'max_metric_calls': maxMetricCalls,
      'reflection_minibatch_size': reflectionMinibatchSize,
      if (runDir != null) 'run_dir': runDir,
    };
  }
}

/// Alias for [GEPARootAgentOptimizerConfig] using standard Dart casing.
typedef GepaRootAgentOptimizerConfig = GEPARootAgentOptimizerConfig;

/// Result returned by [GEPARootAgentOptimizer.optimize].
class GEPARootAgentOptimizerResult extends OptimizerResult<AgentWithScores> {
  /// Creates a GEPA optimizer result.
  GEPARootAgentOptimizerResult({
    required super.optimizedAgents,
    Map<String, Object?>? gepaResult,
  }) : gepaResult = gepaResult == null
           ? null
           : Map<String, Object?>.unmodifiable(gepaResult);

  /// Optional raw GEPA diagnostic result dictionary.
  final Map<String, Object?>? gepaResult;
}

/// Alias for [GEPARootAgentOptimizerResult] using standard Dart casing.
typedef GepaRootAgentOptimizerResult = GEPARootAgentOptimizerResult;

/// Raw output produced by a custom or built-in GEPA optimization runner.
class GepaOptimizeRawOutput {
  /// Creates a raw GEPA optimization output container.
  GepaOptimizeRawOutput({
    required List<Map<String, String>> candidates,
    required List<double> valAggregateScores,
    Map<String, Object?>? rawResult,
  }) : candidates = List<Map<String, String>>.unmodifiable(
         candidates.map(
           (Map<String, String> c) => Map<String, String>.unmodifiable(c),
         ),
       ),
       valAggregateScores = List<double>.unmodifiable(valAggregateScores),
       rawResult = rawResult == null
           ? null
           : Map<String, Object?>.unmodifiable(rawResult);

  /// Candidate component maps evaluated by GEPA.
  final List<Map<String, String>> candidates;

  /// Aggregate validation scores corresponding to [candidates].
  final List<double> valAggregateScores;

  /// Optional serialized GEPA result metadata.
  final Map<String, Object?>? rawResult;

  /// Converts this output to a diagnostic map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'candidates': candidates,
      'val_aggregate_scores': valAggregateScores,
      ...?rawResult,
    };
  }
}

/// Callback signature for custom GEPA optimization runners.
typedef GepaOptimizeRunner =
    Future<GepaOptimizeRawOutput> Function({
      required Map<String, String> seedCandidate,
      required List<String> trainset,
      required List<String> valset,
      required AgentGEPAAdapter adapter,
      required int reflectionMinibatchSize,
      required int maxMetricCalls,
      required String? runDir,
    });

/// Optimizer that Jointly optimizes the root agent prompt and its [SkillToolset]
/// skill instructions using GEPA reflective evolution.
///
/// ```dart
/// final optimizer = GEPARootAgentOptimizer(
///   GEPARootAgentOptimizerConfig(maxMetricCalls: 10),
/// );
/// final result = await optimizer.optimize(initialAgent, sampler);
/// ```
class GEPARootAgentOptimizer
    extends AgentOptimizer<UnstructuredSamplingResult, AgentWithScores> {
  /// Creates a GEPA root agent and skill instructions optimizer.
  GEPARootAgentOptimizer(
    this._config, {
    GepaOptimizeRunner? gepaOptimizeRunner,
  }) : _gepaOptimizeRunner = gepaOptimizeRunner;

  final GEPARootAgentOptimizerConfig _config;
  final GepaOptimizeRunner? _gepaOptimizeRunner;

  /// Optimizer configuration.
  GEPARootAgentOptimizerConfig get config => _config;

  BaseLlm _resolveProposerLlm() {
    final Object model = _config.optimizerModel;
    if (model is BaseLlm) {
      return model;
    }
    return LLMRegistry.newLlm('$model');
  }

  @override
  Future<GEPARootAgentOptimizerResult> optimize(
    Agent initialAgent,
    Sampler<UnstructuredSamplingResult> sampler,
  ) async {
    final String seedPrompt = requireStaticInstruction(initialAgent);
    final List<String> trainExampleIds = sampler.getTrainExampleIds();
    final List<String> valExampleIds = sampler.getValidationExampleIds();

    final Map<String, String> seedCandidate = <String, String>{
      agentPromptKey: seedPrompt,
    };

    if (initialAgent.tools.isNotEmpty) {
      for (final Object tool in initialAgent.tools) {
        if (tool is SkillToolset) {
          final List<Skill> skills = await extractToolsetSkills(tool);
          for (final Skill skill in skills) {
            seedCandidate['$skillKeyPrefix${skill.name}'] = skill.instructions;
          }
        }
      }
    }

    final BaseLlm proposerLlm = _resolveProposerLlm();
    final AgentGEPAAdapter adapter = AgentGEPAAdapter(
      initialAgent: initialAgent,
      sampler: sampler,
      proposerLlm: proposerLlm,
    );

    final GepaOptimizeRunner runner = _gepaOptimizeRunner ?? _defaultGepaRunner;
    final GepaOptimizeRawOutput gepaResult = await runner(
      seedCandidate: seedCandidate,
      trainset: trainExampleIds,
      valset: valExampleIds,
      adapter: adapter,
      reflectionMinibatchSize: _config.reflectionMinibatchSize,
      maxMetricCalls: _config.maxMetricCalls,
      runDir: _config.runDir,
    );

    final List<AgentWithScores> optimizedAgents = <AgentWithScores>[];
    for (int i = 0; i < gepaResult.candidates.length; i++) {
      final Map<String, String> candidate = gepaResult.candidates[i];
      final double score = i < gepaResult.valAggregateScores.length
          ? gepaResult.valAggregateScores[i]
          : 0.0;
      optimizedAgents.add(
        AgentWithScores(
          optimizedAgent: createAgentFromCandidate(initialAgent, candidate),
          overallScore: score,
        ),
      );
    }

    return GEPARootAgentOptimizerResult(
      optimizedAgents: optimizedAgents,
      gepaResult: gepaResult.toMap(),
    );
  }

  Future<GepaOptimizeRawOutput> _defaultGepaRunner({
    required Map<String, String> seedCandidate,
    required List<String> trainset,
    required List<String> valset,
    required AgentGEPAAdapter adapter,
    required int reflectionMinibatchSize,
    required int maxMetricCalls,
    required String? runDir,
  }) async {
    int metricCallsUsed = 0;

    Future<double> scoreValidation(Map<String, String> candidate) async {
      if (valset.isEmpty) {
        return 0.0;
      }
      final Agent candidateAgent = createAgentFromCandidate(
        adapter._initialAgent,
        candidate,
      );
      final UnstructuredSamplingResult result = await adapter._sampler
          .sampleAndScore(
            candidateAgent,
            exampleSet: ExampleSet.validation,
            batch: valset,
            captureFullEvalData: false,
          );
      metricCallsUsed += valset.length;
      if (result.scores.isEmpty) {
        return 0.0;
      }
      double sum = 0.0;
      for (final String id in valset) {
        sum += result.scores[id] ?? missingExampleScore;
      }
      return sum / valset.length;
    }

    final List<Map<String, String>> candidates = <Map<String, String>>[
      Map<String, String>.from(seedCandidate),
    ];
    final double initialScore = await scoreValidation(seedCandidate);
    final List<double> valScores = <double>[initialScore];

    Map<String, String> bestCandidate = Map<String, String>.from(seedCandidate);
    double bestScore = initialScore;
    final List<String> components = seedCandidate.keys.toList(growable: false);

    int step = 0;
    while (metricCallsUsed < maxMetricCalls && trainset.isNotEmpty) {
      final int batchSize = max(
        1,
        min(reflectionMinibatchSize, trainset.length),
      );
      final List<String> batch = <String>[
        for (int i = 0; i < batchSize; i++)
          trainset[(step * batchSize + i) % trainset.length],
      ];
      step += 1;

      if (metricCallsUsed + batch.length > maxMetricCalls) {
        break;
      }

      final GEPAEvaluationBatch evalBatch = await adapter.evaluate(
        batch,
        bestCandidate,
        captureTraces: true,
      );
      metricCallsUsed += batch.length;

      final Map<String, List<Map<String, Object?>>> reflectiveDataset = adapter
          .makeReflectiveDataset(bestCandidate, evalBatch, components);
      final Map<String, String> proposed = await adapter.proposeNewTexts(
        bestCandidate,
        reflectiveDataset,
        components,
      );

      final Map<String, String> nextCandidate = <String, String>{
        ...bestCandidate,
        ...proposed,
      };
      if (_mapsEqual(nextCandidate, bestCandidate)) {
        break;
      }

      if (metricCallsUsed + valset.length > maxMetricCalls) {
        break;
      }
      final double nextScore = await scoreValidation(nextCandidate);
      candidates.add(nextCandidate);
      valScores.add(nextScore);
      if (nextScore >= bestScore) {
        bestScore = nextScore;
        bestCandidate = nextCandidate;
      }
    }

    return GepaOptimizeRawOutput(
      candidates: candidates,
      valAggregateScores: valScores,
    );
  }
}

/// Alias for [GEPARootAgentOptimizer] using standard Dart casing.
typedef GepaRootAgentOptimizer = GEPARootAgentOptimizer;

int _toInt(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, String> entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
