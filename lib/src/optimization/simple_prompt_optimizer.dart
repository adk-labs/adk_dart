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

const String _optimizerPromptTemplate = '''
You are an expert prompt engineer. Your task is to improve the system prompt for an AI agent.
The agent's current prompt achieved an average score of {current_score} on a set of evaluation tasks. A higher score is better.

Here is the current prompt:
<current_prompt>
{current_prompt_text}
</current_prompt>

Based on the current prompt, rewrite it to create a new, improved version that is likely to achieve a higher score.
The agent needs to solve customer support tasks by using tools correctly and following policies.
Focus on clarity, structure, and providing actionable guidance for the agent.

Output only the new, full, improved agent prompt. Do not add any other text, explanations, or markdown formatting.
''';

class SimplePromptOptimizerConfig {
  SimplePromptOptimizerConfig({
    this.optimizerModel = 'gemini-2.5-flash',
    GenerateContentConfig? modelConfiguration,
    this.numIterations = 10,
    this.batchSize = 5,
  }) : modelConfiguration =
           modelConfiguration ??
           GenerateContentConfig(
             thinkingConfig: <String, Object?>{
               'include_thoughts': true,
               'thinking_budget': 10240,
             },
           );

  final Object optimizerModel;
  final GenerateContentConfig modelConfiguration;
  final int numIterations;
  final int batchSize;
}

class SimplePromptOptimizer
    extends AgentOptimizer<UnstructuredSamplingResult, BaseAgentWithScores> {
  SimplePromptOptimizer(this._config, {Random? random})
    : _random = random ?? Random(),
      _llm = _resolveLlm(_config.optimizerModel);

  final SimplePromptOptimizerConfig _config;
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

  Future<String> _generateCandidatePrompt(
    Agent bestAgent,
    double bestScore,
  ) async {
    final String currentPromptText = '${bestAgent.instruction}';
    final String promptForOptimizer = _optimizerPromptTemplate
        .replaceAll('{current_score}', bestScore.toStringAsFixed(2))
        .replaceAll('{current_prompt_text}', currentPromptText);

    final LlmRequest request = LlmRequest(
      model: _llm.model,
      config: _config.modelConfiguration.copyWith(),
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text(promptForOptimizer)]),
      ],
    );

    final StringBuffer response = StringBuffer();
    await for (final LlmResponse llmResponse in _llm.generateContent(request)) {
      final Content? content = llmResponse.content;
      if (content == null) {
        continue;
      }
      for (final Part part in content.parts) {
        if (part.text != null && !part.thought) {
          response.write(part.text);
        }
      }
    }
    return response.toString();
  }

  List<String> _sampleBatch(List<String> exampleIds, int batchSize) {
    if (exampleIds.isEmpty || batchSize <= 0) {
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

  Future<double> _scoreAgentOnBatch(
    Agent agent,
    Sampler<UnstructuredSamplingResult> sampler,
    List<String> exampleIds,
    int batchSize,
  ) async {
    final List<String> evalBatch = _sampleBatch(exampleIds, batchSize);
    final UnstructuredSamplingResult evalResults = await sampler.sampleAndScore(
      agent,
      exampleSet: ExampleSet.train,
      batch: evalBatch,
      captureFullEvalData: false,
    );
    if (evalResults.scores.isEmpty) {
      return 0.0;
    }
    final double total = evalResults.scores.values.fold(
      0.0,
      (double sum, double score) => sum + score,
    );
    return total / evalResults.scores.length;
  }

  Agent _cloneAgentWithInstruction(Agent source, String instruction) {
    return LlmAgent(
      name: source.name,
      description: source.description,
      subAgents: source.subAgents,
      beforeAgentCallback: source.beforeAgentCallback,
      afterAgentCallback: source.afterAgentCallback,
      model: source.model,
      instruction: instruction,
      globalInstruction: source.globalInstruction,
      staticInstruction: source.staticInstruction,
      tools: List<Object>.from(source.tools),
      generateContentConfig: source.generateContentConfig?.copyWith(),
      disallowTransferToParent: source.disallowTransferToParent,
      disallowTransferToPeers: source.disallowTransferToPeers,
      includeContents: source.includeContents,
      inputSchema: source.inputSchema,
      outputSchema: source.outputSchema,
      outputKey: source.outputKey,
      planner: source.planner,
      codeExecutor: source.codeExecutor,
      beforeModelCallback: source.beforeModelCallback,
      afterModelCallback: source.afterModelCallback,
      onModelErrorCallback: source.onModelErrorCallback,
      beforeToolCallback: source.beforeToolCallback,
      afterToolCallback: source.afterToolCallback,
      onToolErrorCallback: source.onToolErrorCallback,
    );
  }

  Future<(Agent, double)> _runOptimizationIterations(
    Agent initialAgent,
    Sampler<UnstructuredSamplingResult> sampler,
    List<String> trainExampleIds,
    int batchSize,
  ) async {
    Agent bestAgent = initialAgent;
    double bestScore = await _scoreAgentOnBatch(
      bestAgent,
      sampler,
      trainExampleIds,
      batchSize,
    );

    for (int i = 0; i < _config.numIterations; i += 1) {
      final String newPrompt = await _generateCandidatePrompt(
        bestAgent,
        bestScore,
      );
      if (newPrompt.trim().isEmpty) {
        continue;
      }

      final Agent candidateAgent = _cloneAgentWithInstruction(
        bestAgent,
        newPrompt,
      );
      final double candidateScore = await _scoreAgentOnBatch(
        candidateAgent,
        sampler,
        trainExampleIds,
        batchSize,
      );

      if (candidateScore > bestScore) {
        bestAgent = candidateAgent;
        bestScore = candidateScore;
      }
    }

    return (bestAgent, bestScore);
  }

  Future<double> _runFinalValidation(
    Agent bestAgent,
    Sampler<UnstructuredSamplingResult> sampler,
  ) async {
    final UnstructuredSamplingResult validation = await sampler.sampleAndScore(
      bestAgent,
      exampleSet: ExampleSet.validation,
    );
    if (validation.scores.isEmpty) {
      return 0.0;
    }
    final double total = validation.scores.values.fold(
      0.0,
      (double sum, double score) => sum + score,
    );
    return total / validation.scores.length;
  }

  @override
  Future<OptimizerResult<BaseAgentWithScores>> optimize(
    Agent initialAgent,
    Sampler<UnstructuredSamplingResult> sampler,
  ) async {
    final List<String> trainExampleIds = sampler.getTrainExampleIds();
    final int batchSize = trainExampleIds.isEmpty
        ? 0
        : min(_config.batchSize, trainExampleIds.length);

    final (Agent bestAgent, double _) = await _runOptimizationIterations(
      initialAgent,
      sampler,
      trainExampleIds,
      batchSize,
    );

    final double finalScore = await _runFinalValidation(bestAgent, sampler);
    return OptimizerResult<BaseAgentWithScores>(
      optimizedAgents: <BaseAgentWithScores>[
        BaseAgentWithScores(
          optimizedAgent: bestAgent,
          overallScore: finalScore,
        ),
      ],
    );
  }
}
