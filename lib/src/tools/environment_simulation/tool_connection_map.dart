/// Compatibility aliases for environment simulation tool connection mappings.
library;

import '../agent_simulator/tool_connection_map.dart';

export '../agent_simulator/tool_connection_map.dart'
    show StatefulParameter, ToolConnectionMap;

/// Compatibility alias for the renamed environment simulation mapping surface.
typedef EnvironmentSimulationToolConnectionMap = ToolConnectionMap;
