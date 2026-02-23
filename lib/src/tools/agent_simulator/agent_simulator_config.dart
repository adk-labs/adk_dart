import '../../models/llm_request.dart';

class InjectedError {
  InjectedError({
    required this.injectedHttpErrorCode,
    required this.errorMessage,
  });

  int injectedHttpErrorCode;
  String errorMessage;

  Map<String, Object?> toJson() => <String, Object?>{
    'injected_http_error_code': injectedHttpErrorCode,
    'error_message': errorMessage,
  };

  factory InjectedError.fromJson(Map<String, Object?> json) {
    final Object? code = json['injected_http_error_code'];
    return InjectedError(
      injectedHttpErrorCode: code is int ? code : int.tryParse('$code') ?? 0,
      errorMessage: '${json['error_message'] ?? ''}',
    );
  }
}

class InjectionConfig {
  InjectionConfig({
    this.injectionProbability = 1.0,
    this.matchArgs,
    this.injectedLatencySeconds = 0.0,
    this.randomSeed,
    this.injectedError,
    this.injectedResponse,
  }) {
    if (injectionProbability < 0 || injectionProbability > 1) {
      throw ArgumentError(
        'injectionProbability must be between 0 and 1, got '
        '$injectionProbability',
      );
    }
    if (injectedLatencySeconds < 0 || injectedLatencySeconds > 120) {
      throw ArgumentError(
        'injectedLatencySeconds must be between 0 and 120, got '
        '$injectedLatencySeconds',
      );
    }
    final bool hasError = injectedError != null;
    final bool hasResponse = injectedResponse != null;
    if (hasError == hasResponse) {
      throw ArgumentError(
        'Either injectedError or injectedResponse must be set, but not both, '
        'and not neither.',
      );
    }
  }

  double injectionProbability;
  Map<String, Object?>? matchArgs;
  double injectedLatencySeconds;
  int? randomSeed;
  InjectedError? injectedError;
  Map<String, Object?>? injectedResponse;

  Map<String, Object?> toJson() => <String, Object?>{
    'injection_probability': injectionProbability,
    'match_args': matchArgs == null
        ? null
        : Map<String, Object?>.from(matchArgs!),
    'injected_latency_seconds': injectedLatencySeconds,
    'random_seed': randomSeed,
    'injected_error': injectedError?.toJson(),
    'injected_response': injectedResponse == null
        ? null
        : Map<String, Object?>.from(injectedResponse!),
  };

  factory InjectionConfig.fromJson(Map<String, Object?> json) {
    Map<String, Object?>? matchArgs;
    final Object? rawMatchArgs = json['match_args'];
    if (rawMatchArgs is Map) {
      matchArgs = rawMatchArgs.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }

    Map<String, Object?>? injectedResponse;
    final Object? rawInjectedResponse = json['injected_response'];
    if (rawInjectedResponse is Map) {
      injectedResponse = rawInjectedResponse.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }

    InjectedError? injectedError;
    final Object? rawInjectedError = json['injected_error'];
    if (rawInjectedError is Map) {
      injectedError = InjectedError.fromJson(
        rawInjectedError.map(
          (Object? key, Object? value) =>
              MapEntry<String, Object?>('$key', value),
        ),
      );
    }

    final Object? probability = json['injection_probability'];
    final Object? latency = json['injected_latency_seconds'];
    final Object? randomSeed = json['random_seed'];
    return InjectionConfig(
      injectionProbability: probability is num
          ? probability.toDouble()
          : double.tryParse('$probability') ?? 1.0,
      matchArgs: matchArgs,
      injectedLatencySeconds: latency is num
          ? latency.toDouble()
          : double.tryParse('$latency') ?? 0,
      randomSeed: randomSeed is int ? randomSeed : int.tryParse('$randomSeed'),
      injectedError: injectedError,
      injectedResponse: injectedResponse,
    );
  }
}

enum MockStrategy {
  mockStrategyUnspecified,
  mockStrategyToolSpec,
  mockStrategyTracing,
}

MockStrategy _mockStrategyFromJson(Object? value) {
  if (value is int) {
    if (value == 1) {
      return MockStrategy.mockStrategyToolSpec;
    }
    if (value == 2) {
      return MockStrategy.mockStrategyTracing;
    }
    return MockStrategy.mockStrategyUnspecified;
  }

  final String normalized = '$value'.trim().toLowerCase();
  switch (normalized) {
    case 'mock_strategy_tool_spec':
    case 'mockstrategytoolspec':
    case 'toolspec':
      return MockStrategy.mockStrategyToolSpec;
    case 'mock_strategy_tracing':
    case 'mockstrategytracing':
    case 'tracing':
      return MockStrategy.mockStrategyTracing;
    default:
      return MockStrategy.mockStrategyUnspecified;
  }
}

int _mockStrategyToJson(MockStrategy value) {
  switch (value) {
    case MockStrategy.mockStrategyUnspecified:
      return 0;
    case MockStrategy.mockStrategyToolSpec:
      return 1;
    case MockStrategy.mockStrategyTracing:
      return 2;
  }
}

class ToolSimulationConfig {
  ToolSimulationConfig({
    required this.toolName,
    List<InjectionConfig>? injectionConfigs,
    this.mockStrategyType = MockStrategy.mockStrategyUnspecified,
  }) : injectionConfigs = injectionConfigs ?? <InjectionConfig>[] {
    if (toolName.trim().isEmpty) {
      throw ArgumentError('toolName cannot be empty.');
    }
    if (this.injectionConfigs.isEmpty &&
        mockStrategyType == MockStrategy.mockStrategyUnspecified) {
      throw ArgumentError(
        'If injectionConfigs is empty, mockStrategyType cannot be '
        'mockStrategyUnspecified.',
      );
    }
  }

  String toolName;
  List<InjectionConfig> injectionConfigs;
  MockStrategy mockStrategyType;

  Map<String, Object?> toJson() => <String, Object?>{
    'tool_name': toolName,
    'injection_configs': injectionConfigs
        .map((InjectionConfig config) => config.toJson())
        .toList(growable: false),
    'mock_strategy_type': _mockStrategyToJson(mockStrategyType),
  };

  factory ToolSimulationConfig.fromJson(Map<String, Object?> json) {
    final List<InjectionConfig> configs = <InjectionConfig>[];
    final Object? rawConfigs = json['injection_configs'];
    if (rawConfigs is List) {
      for (final Object? config in rawConfigs) {
        if (config is Map) {
          configs.add(
            InjectionConfig.fromJson(
              config.map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              ),
            ),
          );
        }
      }
    }
    return ToolSimulationConfig(
      toolName: '${json['tool_name'] ?? ''}',
      injectionConfigs: configs,
      mockStrategyType: _mockStrategyFromJson(json['mock_strategy_type']),
    );
  }
}

class AgentSimulatorConfig {
  AgentSimulatorConfig({
    required List<ToolSimulationConfig> toolSimulationConfigs,
    this.simulationModel = 'gemini-2.5-flash',
    GenerateContentConfig? simulationModelConfiguration,
    this.tracingPath,
    this.environmentData,
  }) : toolSimulationConfigs = toolSimulationConfigs,
       simulationModelConfiguration =
           simulationModelConfiguration ?? GenerateContentConfig() {
    if (toolSimulationConfigs.isEmpty) {
      throw ArgumentError('toolSimulationConfigs must be provided.');
    }

    final Set<String> seenToolNames = <String>{};
    for (final ToolSimulationConfig config in toolSimulationConfigs) {
      if (!seenToolNames.add(config.toolName)) {
        throw ArgumentError('Duplicate toolName found: ${config.toolName}');
      }
    }
  }

  List<ToolSimulationConfig> toolSimulationConfigs;
  String simulationModel;
  GenerateContentConfig simulationModelConfiguration;
  String? tracingPath;
  String? environmentData;

  Map<String, Object?> toJson() => <String, Object?>{
    'tool_simulation_configs': toolSimulationConfigs
        .map((ToolSimulationConfig config) => config.toJson())
        .toList(growable: false),
    'simulation_model': simulationModel,
    'simulation_model_configuration': <String, Object?>{
      'response_mime_type': simulationModelConfiguration.responseMimeType,
      'system_instruction': simulationModelConfiguration.systemInstruction,
      'labels': simulationModelConfiguration.labels.isEmpty
          ? null
          : Map<String, String>.from(simulationModelConfiguration.labels),
    },
    'tracing_path': tracingPath,
    'environment_data': environmentData,
  };

  factory AgentSimulatorConfig.fromJson(Map<String, Object?> json) {
    final List<ToolSimulationConfig> configs = <ToolSimulationConfig>[];
    final Object? rawConfigs = json['tool_simulation_configs'];
    if (rawConfigs is List) {
      for (final Object? config in rawConfigs) {
        if (config is Map) {
          configs.add(
            ToolSimulationConfig.fromJson(
              config.map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              ),
            ),
          );
        }
      }
    }

    GenerateContentConfig? modelConfig;
    final Object? rawModelConfig = json['simulation_model_configuration'];
    if (rawModelConfig is Map) {
      final Map<String, Object?> normalized = rawModelConfig.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
      modelConfig = GenerateContentConfig(
        responseMimeType: normalized['response_mime_type'] as String?,
        systemInstruction: normalized['system_instruction'] as String?,
        labels: (normalized['labels'] is Map)
            ? (normalized['labels'] as Map).map(
                (Object? key, Object? value) =>
                    MapEntry<String, String>('$key', '$value'),
              )
            : null,
      );
    }

    return AgentSimulatorConfig(
      toolSimulationConfigs: configs,
      simulationModel: '${json['simulation_model'] ?? 'gemini-2.5-flash'}',
      simulationModelConfiguration: modelConfig,
      tracingPath: json['tracing_path'] as String?,
      environmentData: json['environment_data'] as String?,
    );
  }
}
