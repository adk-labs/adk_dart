/// Engine that simulates tool invocations using configurable strategies.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../../tools/base_tool.dart';
import '../tool_args_matcher/tool_args_matcher.dart';
import 'agent_simulator_config.dart' as simulator_config;
import 'strategies/base.dart' as simulator_strategies;
import 'strategies/tool_spec_mock_strategy.dart';
import 'tool_connection_analyzer.dart';
import 'tool_connection_map.dart';

const int _maxConcurrentArgMatches = 8;

/// Factory signature for creating mock strategies per configuration.
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

ToolArgsMatcher _withDefaultSemanticModel(
  ToolArgsMatcher matcher,
  String defaultModel,
) {
  BaseArgMatcher defaultMatcher = matcher.defaultMatcher;
  bool changed = false;
  if (defaultMatcher is SemanticArgMatcher && defaultMatcher.model == null) {
    defaultMatcher = defaultMatcher.withDefaultModel(defaultModel);
    changed = true;
  }

  final Map<String, BaseArgMatcher> perArgMatchers = <String, BaseArgMatcher>{};
  for (final MapEntry<String, BaseArgMatcher> entry
      in matcher.perArgMatchers.entries) {
    final BaseArgMatcher argMatcher = entry.value;
    if (argMatcher is SemanticArgMatcher && argMatcher.model == null) {
      perArgMatchers[entry.key] = argMatcher.withDefaultModel(defaultModel);
      changed = true;
    } else {
      perArgMatchers[entry.key] = argMatcher;
    }
  }

  if (!changed) {
    return matcher;
  }
  return ToolArgsMatcher(
    defaultMatcher: defaultMatcher,
    perArgMatchers: perArgMatchers,
    allowExtraArgs: matcher.allowExtraArgs,
  );
}

class _AsyncSemaphore {
  _AsyncSemaphore(this._maxPermits);

  final int _maxPermits;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    if (_active < _maxPermits) {
      _active += 1;
    } else {
      final Completer<void> waiter = Completer<void>();
      _waiters.addLast(waiter);
      await waiter.future;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _active -= 1;
      }
    }
  }
}

/// Applies injection rules and mock strategies for tool simulation.
class AgentSimulatorEngine {
  /// Creates an agent simulator engine with optional test seams.
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
      for (int i = 0; i < toolConfig.injectionConfigs.length; i += 1) {
        final simulator_config.InjectionConfig injectionConfig =
            toolConfig.injectionConfigs[i];
        if (injectionConfig.randomSeed != null) {
          _seededGenerators[(toolConfig.toolName, i)] = math.Random(
            injectionConfig.randomSeed!,
          );
        }
        if (injectionConfig.argsMatcher != null) {
          _argsMatchers[(toolConfig.toolName, i)] = _withDefaultSemanticModel(
            injectionConfig.argsMatcher!,
            _config.simulationModel,
          );
        }
      }
    }
  }

  final simulator_config.AgentSimulatorConfig _config;
  final Map<String, simulator_config.ToolSimulationConfig> _toolSimConfigs =
      <String, simulator_config.ToolSimulationConfig>{};
  final Map<(String, int), math.Random> _seededGenerators =
      <(String, int), math.Random>{};
  final Map<(String, int), ToolArgsMatcher> _argsMatchers =
      <(String, int), ToolArgsMatcher>{};
  final _AsyncSemaphore _argMatchSemaphore = _AsyncSemaphore(
    _maxConcurrentArgMatches,
  );
  ToolConnectionAnalyzer? _analyzer;
  final SimulatorStrategyFactory _strategyFactory;
  final math.Random _randomGenerator;
  final String? _environmentData;

  bool _isAnalyzed = false;
  ToolConnectionMap? _toolConnectionMap;
  final Map<String, Object?> _stateStore = <String, Object?>{};

  static bool _matchesExactly(
    Map<String, Object?> args,
    simulator_config.InjectionConfig injectionConfig,
  ) {
    final Map<String, Object?>? matchArgs = injectionConfig.matchArgs;
    if (matchArgs == null || matchArgs.isEmpty) {
      return true;
    }
    if (!matchArgs.entries.every(
      (MapEntry<String, Object?> entry) =>
          args.containsKey(entry.key) &&
          deepArgEquals(args[entry.key], entry.value),
    )) {
      return false;
    }
    final ToolArgsMatcher? argsMatcher = injectionConfig.argsMatcher;
    if (argsMatcher != null && !argsMatcher.allowExtraArgs) {
      return args.keys.every(matchArgs.containsKey);
    }
    return true;
  }

  Future<simulator_config.InjectionConfig?> _matchRemainingConfigs(
    String toolName,
    Map<String, Object?> args,
    List<simulator_config.InjectionConfig> injectionConfigs,
    Set<int> drawn,
  ) async {
    final List<(int, simulator_config.InjectionConfig)> remaining =
        <(int, simulator_config.InjectionConfig)>[
          for (int index = 0; index < injectionConfigs.length; index += 1)
            if (!drawn.contains(index)) (index, injectionConfigs[index]),
        ];
    if (remaining.isEmpty) {
      return null;
    }

    final List<(int, simulator_config.InjectionConfig)> withMatcher =
        <(int, simulator_config.InjectionConfig)>[
          for (final (int index, simulator_config.InjectionConfig config)
              in remaining)
            if (config.argsMatcher != null &&
                config.matchArgs != null &&
                config.matchArgs!.isNotEmpty)
              (index, config),
        ];

    final Map<int, ToolArgsMatchResult> matcherResults =
        <int, ToolArgsMatchResult>{};
    if (withMatcher.isNotEmpty) {
      final List<ToolArgsMatchResult> results = await Future.wait(
        withMatcher.map(((int, simulator_config.InjectionConfig) item) {
          final int index = item.$1;
          final simulator_config.InjectionConfig config = item.$2;
          final ToolArgsMatcher matcher =
              _argsMatchers[(toolName, index)] ?? config.argsMatcher!;
          return _argMatchSemaphore.withPermit(
            () => matcher.matchAsync(
              toolName: toolName,
              expected: config.matchArgs,
              actual: args,
              shortCircuit: true,
            ),
          );
        }),
      );
      for (int i = 0; i < withMatcher.length; i += 1) {
        matcherResults[withMatcher[i].$1] = results[i];
      }
    }

    for (final (int index, simulator_config.InjectionConfig config)
        in remaining) {
      final bool matched;
      if (matcherResults.containsKey(index)) {
        matched = matcherResults[index]!.matched;
      } else {
        matched = _matchesExactly(args, config);
      }
      if (!matched) {
        continue;
      }
      final math.Random generator =
          _seededGenerators[(toolName, index)] ?? _randomGenerator;
      if (generator.nextDouble() < config.injectionProbability) {
        return config;
      }
    }
    return null;
  }

  /// Simulates a tool invocation and returns a mocked response.
  ///
  /// Returns `null` when no simulation is configured for [tool].
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

    simulator_config.InjectionConfig? hitInjection;
    final Set<int> drawn = <int>{};
    for (int i = 0; i < toolSimConfig.injectionConfigs.length; i += 1) {
      final simulator_config.InjectionConfig injectionConfig =
          toolSimConfig.injectionConfigs[i];
      if (injectionConfig.matchArgs == null ||
          injectionConfig.matchArgs!.isEmpty) {
        // An unguarded config applies to every call, so stop before it to
        // preserve its priority over configs after it.
        break;
      }
      if (!_matchesExactly(args, injectionConfig)) {
        continue;
      }
      drawn.add(i);
      final math.Random generator =
          _seededGenerators[(tool.name, i)] ?? _randomGenerator;
      if (generator.nextDouble() < injectionConfig.injectionProbability) {
        hitInjection = injectionConfig;
        break;
      }
    }

    hitInjection ??= await _matchRemainingConfigs(
      tool.name,
      args,
      toolSimConfig.injectionConfigs,
      drawn,
    );

    if (hitInjection != null) {
      if (hitInjection.injectedLatencySeconds > 0) {
        await Future<void>.delayed(
          Duration(
            milliseconds: (hitInjection.injectedLatencySeconds * 1000).round(),
          ),
        );
      }

      if (hitInjection.injectedError != null) {
        return <String, Object?>{
          'error_code': hitInjection.injectedError!.injectedHttpErrorCode,
          'error_message': hitInjection.injectedError!.errorMessage,
        };
      }

      if (hitInjection.injectedResponse != null) {
        return Map<String, Object?>.from(hitInjection.injectedResponse!);
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

InvocationContext? _extractInvocationContext(Object toolContext) {
  if (toolContext is ReadonlyContext) {
    return toolContext.invocationContext;
  }
  if (toolContext is InvocationContext) {
    return toolContext;
  }
  return null;
}
