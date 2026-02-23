import '../agents/llm_agent.dart';
import 'data_types.dart';
import 'sampler.dart';

abstract class AgentOptimizer<
  S extends BaseSamplingResult,
  A extends BaseAgentWithScores
> {
  Future<OptimizerResult<A>> optimize(Agent initialAgent, Sampler<S> sampler);
}
