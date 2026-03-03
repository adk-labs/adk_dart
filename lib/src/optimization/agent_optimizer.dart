/// Contracts for optimizer implementations that improve agent behavior.
library;

import '../agents/llm_agent.dart';
import 'data_types.dart';
import 'sampler.dart';

/// Optimizes an [Agent] by sampling candidate behavior and selecting winners.
abstract class AgentOptimizer<
  S extends BaseSamplingResult,
  A extends BaseAgentWithScores
> {
  /// Optimizes [initialAgent] using examples provided by [sampler].
  Future<OptimizerResult<A>> optimize(Agent initialAgent, Sampler<S> sampler);
}
