/// Compatibility aliases for environment simulation tool-spec strategies.
library;

import '../../agent_simulator/strategies/tool_spec_mock_strategy.dart';

export '../../agent_simulator/strategies/tool_spec_mock_strategy.dart'
    show ToolSpecMockStrategy, toolSpecMockPromptTemplate;

/// Compatibility alias for the renamed environment simulation tool strategy.
typedef EnvironmentSimulationToolSpecMockStrategy = ToolSpecMockStrategy;
