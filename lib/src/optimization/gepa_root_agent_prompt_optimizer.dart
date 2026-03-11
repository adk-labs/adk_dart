/// GEPA-style root-agent prompt optimization utilities.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import '../agents/llm_agent.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../types/content.dart';
import 'agent_optimizer.dart';
import 'data_types.dart';
import 'sampler.dart';

const String _agentPromptName = 'agent_prompt';

/// Configuration for [GepaRootAgentPromptOptimizer].
class GepaRootAgentPromptOptimizerConfig {
  /// Creates GEPA optimizer settings.
  GepaRootAgentPromptOptimizerConfig({
    this.optimizerModel = 'gemini-2.5-flash',
    GenerateContentConfig? modelConfiguration,
    this.maxMetricCalls = 100,
    this.reflectionMinibatchSize = 3,
    this.runDir,
  }) : modelConfiguration =
           modelConfiguration ??
           GenerateContentConfig(
             thinkingConfig: <String, Object?>{
               'include_thoughts': true,
               'thinking_budget': 10240,
             },
           );

  /// Parses one optimizer config payload from JSON.
  factory GepaRootAgentPromptOptimizerConfig.fromJson(
    Map<String, Object?> json,
  ) {
    final Map<String, Object?> modelConfig = _asObjectMap(
      json['modelConfiguration'] ?? json['model_configuration'],
    );
    return GepaRootAgentPromptOptimizerConfig(
      optimizerModel:
          json['optimizerModel'] ??
          json['optimizer_model'] ??
          'gemini-2.5-flash',
      modelConfiguration: modelConfig.isEmpty
          ? null
          : GenerateContentConfig(
              systemInstruction: _emptyToNull(
                '${modelConfig['systemInstruction'] ?? modelConfig['system_instruction'] ?? ''}',
              ),
              temperature: _asDoubleOrNull(modelConfig['temperature']),
              topP: _asDoubleOrNull(modelConfig['topP'] ?? modelConfig['top_p']),
              topK: _asIntOrNull(modelConfig['topK'] ?? modelConfig['top_k']),
              maxOutputTokens: _asIntOrNull(
                modelConfig['maxOutputTokens'] ??
                    modelConfig['max_output_tokens'],
              ),
              stopSequences: _asStringList(
                    modelConfig['stopSequences'] ??
                        modelConfig['stop_sequences'],
                  ) ??
                  <String>[],
              frequencyPenalty: _asDoubleOrNull(
                modelConfig['frequencyPenalty'] ??
                    modelConfig['frequency_penalty'],
              ),
              presencePenalty: _asDoubleOrNull(
                modelConfig['presencePenalty'] ??
                    modelConfig['presence_penalty'],
              ),
              seed: _asIntOrNull(modelConfig['seed']),
              candidateCount: _asIntOrNull(
                modelConfig['candidateCount'] ??
                    modelConfig['candidate_count'],
              ),
              responseLogprobs: _asBoolOrNull(
                modelConfig['responseLogprobs'] ??
                    modelConfig['response_logprobs'],
              ),
              logprobs: _asIntOrNull(modelConfig['logprobs']),
              thinkingConfig:
                  modelConfig['thinkingConfig'] ?? modelConfig['thinking_config'],
              responseSchema:
                  modelConfig['responseSchema'] ??
                  modelConfig['response_schema'],
              responseJsonSchema:
                  modelConfig['responseJsonSchema'] ??
                  modelConfig['response_json_schema'],
              responseMimeType: _emptyToNull(
                '${modelConfig['responseMimeType'] ?? modelConfig['response_mime_type'] ?? ''}',
              ),
              cachedContent: _emptyToNull(
                '${modelConfig['cachedContent'] ?? modelConfig['cached_content'] ?? ''}',
              ),
              labels: _asStringStringMap(modelConfig['labels']),
            ),
      maxMetricCalls: _asIntOrNull(
            json['maxMetricCalls'] ?? json['max_metric_calls'],
          ) ??
          100,
      reflectionMinibatchSize: _asIntOrNull(
            json['reflectionMinibatchSize'] ??
                json['reflection_minibatch_size'],
          ) ??
          3,
      runDir: _emptyToNull('${json['runDir'] ?? json['run_dir'] ?? ''}'),
    );
  }

  /// Model instance or model name used to generate reflective prompt updates.
  final Object optimizerModel;

  /// Generation configuration used by the optimizer model.
  final GenerateContentConfig modelConfiguration;

  /// Maximum number of optimizer evaluation passes.
  final int maxMetricCalls;

  /// Train minibatch size used for each reflection round.
  final int reflectionMinibatchSize;

  /// Optional directory to persist optimization artifacts.
  final String? runDir;

  /// Serializes this config to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'optimizer_model': optimizerModel is String ? optimizerModel : '$optimizerModel',
      'model_configuration': <String, Object?>{
        if (modelConfiguration.systemInstruction != null)
          'system_instruction': modelConfiguration.systemInstruction,
        if (modelConfiguration.temperature != null)
          'temperature': modelConfiguration.temperature,
        if (modelConfiguration.topP != null) 'top_p': modelConfiguration.topP,
        if (modelConfiguration.topK != null) 'top_k': modelConfiguration.topK,
        if (modelConfiguration.maxOutputTokens != null)
          'max_output_tokens': modelConfiguration.maxOutputTokens,
        if (modelConfiguration.stopSequences.isNotEmpty)
          'stop_sequences': modelConfiguration.stopSequences,
        if (modelConfiguration.frequencyPenalty != null)
          'frequency_penalty': modelConfiguration.frequencyPenalty,
        if (modelConfiguration.presencePenalty != null)
          'presence_penalty': modelConfiguration.presencePenalty,
        if (modelConfiguration.seed != null) 'seed': modelConfiguration.seed,
        if (modelConfiguration.candidateCount != null)
          'candidate_count': modelConfiguration.candidateCount,
        if (modelConfiguration.responseLogprobs != null)
          'response_logprobs': modelConfiguration.responseLogprobs,
        if (modelConfiguration.logprobs != null)
          'logprobs': modelConfiguration.logprobs,
        if (modelConfiguration.thinkingConfig != null)
          'thinking_config': modelConfiguration.thinkingConfig,
        if (modelConfiguration.responseSchema != null)
          'response_schema': modelConfiguration.responseSchema,
        if (modelConfiguration.responseJsonSchema != null)
          'response_json_schema': modelConfiguration.responseJsonSchema,
        if (modelConfiguration.responseMimeType != null)
          'response_mime_type': modelConfiguration.responseMimeType,
        if (modelConfiguration.cachedContent != null)
          'cached_content': modelConfiguration.cachedContent,
        if (modelConfiguration.labels.isNotEmpty)
          'labels': modelConfiguration.labels,
      },
      'max_metric_calls': maxMetricCalls,
      'reflection_minibatch_size': reflectionMinibatchSize,
      if (runDir != null) 'run_dir': runDir,
    };
  }
}

/// Final GEPA optimization result including raw run metadata.
class GepaRootAgentPromptOptimizerResult
    extends OptimizerResult<BaseAgentWithScores> {
  /// Creates a GEPA optimizer result.
  GepaRootAgentPromptOptimizerResult({
    required super.optimizedAgents,
    this.gepaResult,
  });

  /// Raw GEPA-style metadata for debugging and artifact persistence.
  final Map<String, Object?>? gepaResult;
}

class _ScoredPromptCandidate {
  _ScoredPromptCandidate({
    required this.prompt,
    required this.trainScore,
    required this.validationScore,
    required this.reflectionBatch,
    required this.reflectionDataset,
  });

  final String prompt;
  final double trainScore;
  final double validationScore;
  final List<String> reflectionBatch;
  final List<Map<String, Object?>> reflectionDataset;
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<String>? _asStringList(Object? value) {
  if (value is! List) {
    return null;
  }
  final List<String> items = value
      .map((Object? item) => '$item'.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
  return items.isEmpty ? null : items;
}

Map<String, String>? _asStringStringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final Map<String, String> result = <String, String>{};
  value.forEach((Object? key, Object? item) {
    result['$key'] = '$item';
  });
  return result.isEmpty ? null : result;
}

int? _asIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value');
}

double? _asDoubleOrNull(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value');
}

bool? _asBoolOrNull(Object? value) {
  if (value is bool) {
    return value;
  }
  final String lower = '$value'.trim().toLowerCase();
  if (lower == 'true') {
    return true;
  }
  if (lower == 'false') {
    return false;
  }
  return null;
}

String? _emptyToNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// GEPA-style optimizer that improves only the root agent prompt.
class GepaRootAgentPromptOptimizer
    extends AgentOptimizer<UnstructuredSamplingResult, BaseAgentWithScores> {
  /// Creates a GEPA-style root-agent prompt optimizer.
  GepaRootAgentPromptOptimizer(this._config, {Random? random})
    : _random = random ?? Random(),
      _llm = _resolveLlm(_config.optimizerModel);

  final GepaRootAgentPromptOptimizerConfig _config;
  final Random _random;
  final BaseLlm _llm;

  static BaseLlm _resolveLlm(Object model) {
    if (model is BaseLlm) {
      return model;
    }
    if (model is String && model.isNotEmpty) {
      return LLMRegistry.newLlm(model);
    }
    throw ArgumentError('optimizerModel must be BaseLlm or non-empty String.');
  }

  @override
  Future<GepaRootAgentPromptOptimizerResult> optimize(
    Agent initialAgent,
    Sampler<UnstructuredSamplingResult> sampler,
  ) async {
    if (initialAgent.subAgents.isNotEmpty) {
      developer.log(
        'GepaRootAgentPromptOptimizer only optimizes the root agent prompt.',
        name: 'adk.optimization.gepa',
      );
    }

    final List<String> trainIds = sampler.getTrainExampleIds();
    final List<String> validationIds = sampler.getValidationExampleIds();
    final Set<String> overlap = trainIds.toSet().intersection(
      validationIds.toSet(),
    );
    if (overlap.isNotEmpty) {
      developer.log(
        'GEPA train and validation example IDs overlap: ${overlap.toList()}.',
        name: 'adk.optimization.gepa',
      );
    }

    final String seedPrompt = '${initialAgent.instruction}';
    final List<_ScoredPromptCandidate> candidates = <_ScoredPromptCandidate>[];
    final Set<String> seenPrompts = <String>{seedPrompt};
    final int iterations = max(1, _config.maxMetricCalls);
    final int minibatchSize = max(1, _config.reflectionMinibatchSize);

    String bestPrompt = seedPrompt;
    double bestValidationScore = await _scorePrompt(
      initialAgent,
      sampler,
      exampleSet: ExampleSet.validation,
    );

    for (int iteration = 0; iteration < iterations; iteration += 1) {
      final List<String> batch = _sampleBatch(trainIds, minibatchSize);
      final UnstructuredSamplingResult reflectionResult =
          await sampler.sampleAndScore(
            initialAgent.clone(update: <String, Object?>{
              'instruction': bestPrompt,
            }),
            exampleSet: ExampleSet.train,
            batch: batch,
            captureFullEvalData: true,
          );
      final double trainScore = _averageScore(reflectionResult);
      final List<Map<String, Object?>> reflectionDataset =
          _buildReflectionDataset(bestPrompt, batch, reflectionResult);
      final String candidatePrompt = (await _generateCandidatePrompt(
        bestPrompt,
        reflectionDataset,
      )).trim();
      if (candidatePrompt.isEmpty || !seenPrompts.add(candidatePrompt)) {
        continue;
      }

      final Agent candidateAgent = initialAgent.clone(
        update: <String, Object?>{'instruction': candidatePrompt},
      );
      final double validationScore = await _scorePrompt(
        candidateAgent,
        sampler,
        exampleSet: ExampleSet.validation,
      );

      candidates.add(
        _ScoredPromptCandidate(
          prompt: candidatePrompt,
          trainScore: trainScore,
          validationScore: validationScore,
          reflectionBatch: List<String>.from(batch),
          reflectionDataset: reflectionDataset,
        ),
      );

      if (validationScore > bestValidationScore) {
        bestPrompt = candidatePrompt;
        bestValidationScore = validationScore;
      }
    }

    if (candidates.isEmpty) {
      candidates.add(
        _ScoredPromptCandidate(
          prompt: bestPrompt,
          trainScore: 0,
          validationScore: bestValidationScore,
          reflectionBatch: const <String>[],
          reflectionDataset: const <Map<String, Object?>>[],
        ),
      );
    }

    candidates.sort(
      (_ScoredPromptCandidate a, _ScoredPromptCandidate b) =>
          b.validationScore.compareTo(a.validationScore),
    );

    final List<BaseAgentWithScores> optimizedAgents = candidates
        .map(
          (_ScoredPromptCandidate candidate) => BaseAgentWithScores(
            optimizedAgent: initialAgent.clone(
              update: <String, Object?>{'instruction': candidate.prompt},
            ),
            overallScore: candidate.validationScore,
          ),
        )
        .toList(growable: false);

    final Map<String, Object?> gepaResult = <String, Object?>{
      'seed_candidate': <String, Object?>{_agentPromptName: seedPrompt},
      'trainset': List<String>.from(trainIds),
      'valset': List<String>.from(validationIds),
      'max_metric_calls': _config.maxMetricCalls,
      'reflection_minibatch_size': _config.reflectionMinibatchSize,
      'candidates': candidates
          .map(
            (_ScoredPromptCandidate candidate) => <String, Object?>{
              _agentPromptName: candidate.prompt,
            },
          )
          .toList(growable: false),
      'train_aggregate_scores': candidates
          .map((_ScoredPromptCandidate candidate) => candidate.trainScore)
          .toList(growable: false),
      'val_aggregate_scores': candidates
          .map((_ScoredPromptCandidate candidate) => candidate.validationScore)
          .toList(growable: false),
      'reflection_batches': candidates
          .map(
            (_ScoredPromptCandidate candidate) =>
                List<String>.from(candidate.reflectionBatch),
          )
          .toList(growable: false),
      'reflection_datasets': candidates
          .map(
            (_ScoredPromptCandidate candidate) => candidate.reflectionDataset
                .map(
                  (Map<String, Object?> row) => Map<String, Object?>.from(row),
                )
                .toList(growable: false),
          )
          .toList(growable: false),
    };

    await _maybePersistRunArtifacts(gepaResult);
    return GepaRootAgentPromptOptimizerResult(
      optimizedAgents: optimizedAgents,
      gepaResult: gepaResult,
    );
  }

  Future<void> _maybePersistRunArtifacts(Map<String, Object?> gepaResult) async {
    final String? runDir = _config.runDir;
    if (runDir == null || runDir.isEmpty) {
      return;
    }
    try {
      final Directory directory = Directory(runDir);
      await directory.create(recursive: true);
      final File resultFile = File('$runDir/gepa_result.json');
      await resultFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(gepaResult),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to persist GEPA artifacts: $error',
        name: 'adk.optimization.gepa',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String> _generateCandidatePrompt(
    String currentPrompt,
    List<Map<String, Object?>> reflectionDataset,
  ) async {
    final String prompt = _buildReflectionPrompt(
      currentPrompt,
      reflectionDataset,
    );
    final LlmRequest request = LlmRequest(
      model: _llm.model,
      config: _config.modelConfiguration.copyWith(),
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text(prompt)]),
      ],
    );

    final StringBuffer buffer = StringBuffer();
    await for (final LlmResponse response in _llm.generateContent(request)) {
      final Content? content = response.content;
      if (content == null) {
        continue;
      }
      for (final Part part in content.parts) {
        if (part.text != null && !part.thought) {
          buffer.write(part.text);
        }
      }
    }
    return buffer.toString();
  }

  String _buildReflectionPrompt(
    String currentPrompt,
    List<Map<String, Object?>> reflectionDataset,
  ) {
    final String serializedExamples = const JsonEncoder.withIndent(
      '  ',
    ).convert(reflectionDataset);
    return '''
You are optimizing the root instruction for an ADK agent.

Current prompt:
<current_prompt>
$currentPrompt
</current_prompt>

Recent evaluation traces:
$serializedExamples

Rewrite the full root agent instruction so it better handles the failing or low-scoring examples.
Return only the improved prompt text.
''';
  }

  List<Map<String, Object?>> _buildReflectionDataset(
    String candidatePrompt,
    List<String> batch,
    UnstructuredSamplingResult result,
  ) {
    return batch.map((String exampleId) {
      final Map<String, Object?> evalData = Map<String, Object?>.from(
        result.data?[exampleId] ?? <String, Object?>{},
      );
      return <String, Object?>{
        _agentPromptName: candidatePrompt,
        'example_id': exampleId,
        'score': result.scores[exampleId] ?? 0,
        'eval_data': evalData,
      };
    }).toList(growable: false);
  }

  Future<double> _scorePrompt(
    Agent agent,
    Sampler<UnstructuredSamplingResult> sampler, {
    required ExampleSet exampleSet,
  }) async {
    final UnstructuredSamplingResult result = await sampler.sampleAndScore(
      agent,
      exampleSet: exampleSet,
      captureFullEvalData: false,
    );
    return _averageScore(result);
  }

  double _averageScore(UnstructuredSamplingResult result) {
    if (result.scores.isEmpty) {
      return 0;
    }
    final double total = result.scores.values.fold(
      0,
      (double sum, double score) => sum + score,
    );
    return total / result.scores.length;
  }

  List<String> _sampleBatch(List<String> exampleIds, int batchSize) {
    if (exampleIds.isEmpty) {
      return const <String>[];
    }
    if (batchSize >= exampleIds.length) {
      return List<String>.from(exampleIds);
    }

    final List<String> pool = List<String>.from(exampleIds);
    for (int i = pool.length - 1; i > 0; i -= 1) {
      final int j = _random.nextInt(i + 1);
      final String tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return pool.sublist(0, batchSize);
  }
}
