import '../utils/env_utils.dart';

enum FeatureName {
  agentConfig('AGENT_CONFIG'),
  agentState('AGENT_STATE'),
  authenticatedFunctionTool('AUTHENTICATED_FUNCTION_TOOL'),
  baseAuthenticatedTool('BASE_AUTHENTICATED_TOOL'),
  bigQueryToolset('BIG_QUERY_TOOLSET'),
  bigQueryToolConfig('BIG_QUERY_TOOL_CONFIG'),
  bigtableToolSettings('BIGTABLE_TOOL_SETTINGS'),
  bigtableToolset('BIGTABLE_TOOLSET'),
  computerUse('COMPUTER_USE'),
  dataAgentToolConfig('DATA_AGENT_TOOL_CONFIG'),
  dataAgentToolset('DATA_AGENT_TOOLSET'),
  googleCredentialsConfig('GOOGLE_CREDENTIALS_CONFIG'),
  googleTool('GOOGLE_TOOL'),
  jsonSchemaForFuncDecl('JSON_SCHEMA_FOR_FUNC_DECL'),
  progressiveSseStreaming('PROGRESSIVE_SSE_STREAMING'),
  pubsubToolConfig('PUBSUB_TOOL_CONFIG'),
  pubsubToolset('PUBSUB_TOOLSET'),
  skillToolset('SKILL_TOOLSET'),
  spannerToolset('SPANNER_TOOLSET'),
  spannerToolSettings('SPANNER_TOOL_SETTINGS'),
  spannerVectorStore('SPANNER_VECTOR_STORE'),
  toolConfig('TOOL_CONFIG'),
  toolConfirmation('TOOL_CONFIRMATION');

  const FeatureName(this.value);

  final String value;
}

enum FeatureStage {
  wip('wip'),
  experimental('experimental'),
  stable('stable');

  const FeatureStage(this.value);

  final String value;
}

class FeatureConfig {
  const FeatureConfig(this.stage, {this.defaultOn = false});

  final FeatureStage stage;
  final bool defaultOn;
}

typedef FeatureWarningEmitter = void Function(String message);

final Map<FeatureName, FeatureConfig> _featureRegistry =
    <FeatureName, FeatureConfig>{
      FeatureName.agentConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.agentState: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.authenticatedFunctionTool: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.baseAuthenticatedTool: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.bigQueryToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.bigQueryToolConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.bigtableToolSettings: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.bigtableToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.computerUse: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.dataAgentToolConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.dataAgentToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.googleCredentialsConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.googleTool: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.jsonSchemaForFuncDecl: const FeatureConfig(FeatureStage.wip),
      FeatureName.progressiveSseStreaming: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.pubsubToolConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.pubsubToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.skillToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.spannerToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.spannerToolSettings: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.spannerVectorStore: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.toolConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.toolConfirmation: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
    };

final Set<FeatureName> _warnedFeatures = <FeatureName>{};
final Map<FeatureName, bool> _featureOverrides = <FeatureName, bool>{};
FeatureWarningEmitter _featureWarningEmitter = _defaultFeatureWarningEmitter;

FeatureConfig? getFeatureConfig(FeatureName featureName) {
  return _featureRegistry[featureName];
}

void registerFeature(FeatureName featureName, FeatureConfig config) {
  _featureRegistry[featureName] = config;
}

void overrideFeatureEnabled(FeatureName featureName, bool enabled) {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null) {
    throw ArgumentError('Feature $featureName is not registered.');
  }
  _featureOverrides[featureName] = enabled;
}

void clearFeatureOverride(FeatureName featureName) {
  _featureOverrides.remove(featureName);
}

bool isFeatureEnabled(
  FeatureName featureName, {
  Map<String, String>? environment,
}) {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null) {
    throw ArgumentError('Feature $featureName is not registered.');
  }

  if (_featureOverrides.containsKey(featureName)) {
    final bool enabled = _featureOverrides[featureName]!;
    if (enabled && config.stage != FeatureStage.stable) {
      _emitNonStableWarningOnce(featureName, config.stage);
    }
    return enabled;
  }

  final String enableVar = 'ADK_ENABLE_${featureName.value}';
  final String disableVar = 'ADK_DISABLE_${featureName.value}';
  if (isEnvEnabled(enableVar, environment: environment)) {
    if (config.stage != FeatureStage.stable) {
      _emitNonStableWarningOnce(featureName, config.stage);
    }
    return true;
  }
  if (isEnvEnabled(disableVar, environment: environment)) {
    return false;
  }

  if (config.stage != FeatureStage.stable && config.defaultOn) {
    _emitNonStableWarningOnce(featureName, config.stage);
  }
  return config.defaultOn;
}

void _emitNonStableWarningOnce(
  FeatureName featureName,
  FeatureStage featureStage,
) {
  if (_warnedFeatures.contains(featureName)) {
    return;
  }
  _warnedFeatures.add(featureName);
  final String message =
      '[${featureStage.name.toUpperCase()}] feature ${featureName.value} is enabled.';
  _featureWarningEmitter(message);
}

void _defaultFeatureWarningEmitter(String message) {
  // Matches Python behavior of emitting a user-visible warning once.
  print(message);
}

T withTemporaryFeatureOverride<T>(
  FeatureName featureName,
  bool enabled,
  T Function() body,
) {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null) {
    throw ArgumentError('Feature $featureName is not registered.');
  }

  final bool hadOverride = _featureOverrides.containsKey(featureName);
  final bool? originalValue = _featureOverrides[featureName];
  _featureOverrides[featureName] = enabled;
  try {
    return body();
  } finally {
    if (hadOverride) {
      _featureOverrides[featureName] = originalValue!;
    } else {
      _featureOverrides.remove(featureName);
    }
  }
}

Future<T> withTemporaryFeatureOverrideAsync<T>(
  FeatureName featureName,
  bool enabled,
  Future<T> Function() body,
) async {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null) {
    throw ArgumentError('Feature $featureName is not registered.');
  }

  final bool hadOverride = _featureOverrides.containsKey(featureName);
  final bool? originalValue = _featureOverrides[featureName];
  _featureOverrides[featureName] = enabled;
  try {
    return await body();
  } finally {
    if (hadOverride) {
      _featureOverrides[featureName] = originalValue!;
    } else {
      _featureOverrides.remove(featureName);
    }
  }
}

void setFeatureWarningEmitter(FeatureWarningEmitter emitter) {
  _featureWarningEmitter = emitter;
}

void resetFeatureRegistryForTest({bool resetRegistry = false}) {
  _featureOverrides.clear();
  _warnedFeatures.clear();
  _featureWarningEmitter = _defaultFeatureWarningEmitter;

  if (!resetRegistry) {
    return;
  }
  _featureRegistry
    ..clear()
    ..addAll(_defaultFeatureRegistry);
}

Map<FeatureName, bool> getFeatureOverrides() {
  return Map<FeatureName, bool>.unmodifiable(_featureOverrides);
}

final Map<FeatureName, FeatureConfig> _defaultFeatureRegistry =
    Map<FeatureName, FeatureConfig>.unmodifiable(_featureRegistry);
