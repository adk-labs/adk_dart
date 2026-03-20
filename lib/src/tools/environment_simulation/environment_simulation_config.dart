/// Compatibility aliases for environment simulation configuration models.
library;

import '../agent_simulator/agent_simulator_config.dart';

export '../agent_simulator/agent_simulator_config.dart'
    show
        AgentSimulatorConfig,
        InjectedError,
        InjectionConfig,
        MockStrategy,
        ToolSimulationConfig;

/// Compatibility alias for the renamed environment simulation config surface.
typedef EnvironmentSimulationConfig = AgentSimulatorConfig;
