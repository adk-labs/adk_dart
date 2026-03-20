/// Compatibility aliases for environment simulation tool connection analysis.
library;

import '../agent_simulator/tool_connection_analyzer.dart';

export '../agent_simulator/tool_connection_analyzer.dart'
    show ToolConnectionAnalyzer, toolConnectionAnalysisPromptTemplate;

/// Compatibility alias for the renamed environment simulation analyzer.
typedef EnvironmentSimulationToolConnectionAnalyzer = ToolConnectionAnalyzer;
