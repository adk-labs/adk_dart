import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../../tools/base_tool.dart';
import 'agent_simulator_config.dart' as simulator_config;
import 'strategies/base.dart' as simulator_strategies;
import 'strategies/tool_spec_mock_strategy.dart';
import 'tool_connection_analyzer.dart';
import 'tool_connection_map.dart';

typedef SimulatorStrategyFactory =
    simulator_strategies.BaseMockStrategy Function(
      simulator_config.MockStrategy mockStrategyType,
      String llmName,
      GenerateContentConfig llmConfig,
    );

simulator_strategies.BaseMockStrategy _createMockStrategy(
  simulator_config.MockStrategy mockStrategyType,
  String llmName,
  GenerateContentConfig llmConfig,
) {
  if (mockStrategyType == simulator_config.MockStrategy.mockStrategyToolSpec) {
    return ToolSpecMockStrategy(llmName: llmName, llmConfig: llmConfig);
  }
  if (mockStrategyType == simulator_config.MockStrategy.mockStrategyTracing) {
    return simulator_strategies.TracingMockStrategy(
      llmName: llmName,
      llmConfig: llmConfig,
    );
  }
  throw ArgumentError('Unknown mock strategy type: $mockStrategyType');
}

class AgentSimulatorEngine {
  AgentSimulatorEngine(
    simulator_config.AgentSimulatorConfig config, {
    ToolConnectionAnalyzer? analyzer,
    SimulatorStrategyFactory? strategyFactory,
    math.Random? randomGenerator,
  }) : _config = config,
       _analyzer = analyzer,
       _strategyFactory = strategyFactory ?? _createMockStrategy,
       _randomGenerator = randomGenerator ?? math.Random(),
       _environmentData = config.environmentData {
    for (final simulator_config.ToolSimulationConfig toolConfig
        in _config.toolSimulationConfigs) {
      _toolSimConfigs[toolConfig.toolName] = toolConfig;
    }
  }

  final simulator_config.AgentSimulatorConfig _config;
  final Map<String, simulator_config.ToolSimulationConfig> _toolSimConfigs =
      <String, simulator_config.ToolSimulationConfig>{};
  ToolConnectionAnalyzer? _analyzer;
  final SimulatorStrategyFactory _strategyFactory;
  math.Random _randomGenerator;
  final String? _environmentData;

  bool _isAnalyzed = false;
  ToolConnectionMap? _toolConnectionMap;
  final Map<String, Object?> _stateStore = <String, Object?>{};

  Future<Map<String, Object?>?> simulate(
    BaseTool tool,
    Map<String, Object?> args,
    Object toolContext,
  ) async {
    if (!_toolSimConfigs.containsKey(tool.name)) {
      return null;
    }

    final simulator_config.ToolSimulationConfig toolSimConfig =
        _toolSimConfigs[tool.name]!;

    if (!_isAnalyzed &&
        _config.toolSimulationConfigs.any(
          (simulator_config.ToolSimulationConfig config) =>
              config.mockStrategyType !=
              simulator_config.MockStrategy.mockStrategyUnspecified,
        )) {
      final InvocationContext? invocationContext = _extractInvocationContext(
        toolContext,
      );
      final Object? agent = invocationContext?.agent;
      if (agent is LlmAgent) {
        _analyzer ??= ToolConnectionAnalyzer(
          llmName: _config.simulationModel,
          llmConfig: _config.simulationModelConfiguration,
        );
        final List<BaseTool> tools = await agent.canonicalTools(
          toolContext is ReadonlyContext ? toolContext : null,
        );
        _toolConnectionMap = await _analyzer!.analyze(tools);
      }
      _isAnalyzed = true;
    }

    for (final simulator_config.InjectionConfig injectionConfig
        in toolSimConfig.injectionConfigs) {
      final Map<String, Object?>? matchArgs = injectionConfig.matchArgs;
      if (matchArgs != null && !_containsAllEntries(args, matchArgs)) {
        continue;
      }

      if (injectionConfig.randomSeed != null) {
        _randomGenerator = math.Random(injectionConfig.randomSeed!);
      }

      if (_randomGenerator.nextDouble() <
          injectionConfig.injectionProbability) {
        if (injectionConfig.injectedLatencySeconds > 0) {
          await Future<void>.delayed(
            Duration(
              milliseconds: (injectionConfig.injectedLatencySeconds * 1000)
                  .round(),
            ),
          );
        }

        if (injectionConfig.injectedError != null) {
          return <String, Object?>{
            'error_code': injectionConfig.injectedError!.injectedHttpErrorCode,
            'error_message': injectionConfig.injectedError!.errorMessage,
          };
        }

        if (injectionConfig.injectedResponse != null) {
          return Map<String, Object?>.from(injectionConfig.injectedResponse!);
        }
      }
    }

    if (toolSimConfig.mockStrategyType ==
        simulator_config.MockStrategy.mockStrategyUnspecified) {
      developer.log(
        "Tool '${tool.name}' did not hit any injection config and has no mock "
        'strategy configured. Returning no-op.',
        name: 'agent_simulator_logger',
      );
      return null;
    }

    final simulator_strategies.BaseMockStrategy strategy = _strategyFactory(
      toolSimConfig.mockStrategyType,
      _config.simulationModel,
      _config.simulationModelConfiguration,
    );
    return strategy.mock(
      tool,
      args,
      toolContext,
      _toolConnectionMap,
      _stateStore,
      environmentData: _environmentData,
    );
  }
}

bool _containsAllEntries(
  Map<String, Object?> value,
  Map<String, Object?> expected,
) {
  for (final MapEntry<String, Object?> entry in expected.entries) {
    if (!value.containsKey(entry.key)) {
      return false;
    }
    if (value[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

InvocationContext? _extractInvocationContext(Object toolContext) {
  if (toolContext is ReadonlyContext) {
    return toolContext.invocationContext;
  }
  if (toolContext is InvocationContext) {
    return toolContext;
  }
  return null;
}
