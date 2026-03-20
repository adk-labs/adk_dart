/// Compatibility aliases for the environment simulation engine surface.
library;

import '../agent_simulator/agent_simulator_engine.dart';

export '../agent_simulator/agent_simulator_engine.dart'
    show AgentSimulatorEngine;

/// Compatibility alias for the renamed environment simulation engine surface.
typedef EnvironmentSimulationEngine = AgentSimulatorEngine;
