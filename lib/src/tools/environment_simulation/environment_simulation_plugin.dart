/// Compatibility aliases for the environment simulation plugin surface.
library;

import '../agent_simulator/agent_simulator_plugin.dart';

export '../agent_simulator/agent_simulator_plugin.dart'
    show AgentSimulatorPlugin;

/// Compatibility alias for the renamed environment simulation plugin surface.
typedef EnvironmentSimulationPlugin = AgentSimulatorPlugin;
