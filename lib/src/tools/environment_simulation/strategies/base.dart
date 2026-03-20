/// Compatibility aliases for environment simulation strategy contracts.
library;

import '../../agent_simulator/strategies/base.dart';

export '../../agent_simulator/strategies/base.dart'
    show BaseMockStrategy, TracingMockStrategy;

/// Compatibility alias for the renamed environment simulation strategy base.
typedef BaseEnvironmentSimulationStrategy = BaseMockStrategy;
