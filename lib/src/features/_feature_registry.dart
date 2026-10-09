/// Feature registry models and helpers for runtime feature gating.
library;

import '../utils/env_utils.dart';

/// Identifiers for runtime-gated ADK features.
enum FeatureName {
  /// Declarative agent configuration support.
  agentConfig('AGENT_CONFIG'),

  /// Persistent agent state management.
  agentState('AGENT_STATE'),

  /// Function tools that require authentication.
  authenticatedFunctionTool('AUTHENTICATED_FUNCTION_TOOL'),

  /// Base class support for authenticated tools.
  baseAuthenticatedTool('BASE_AUTHENTICATED_TOOL'),

  /// BigQuery toolset integration.
  bigQueryToolset('BIG_QUERY_TOOLSET'),

  /// Configuration options for BigQuery tools.
  bigQueryToolConfig('BIG_QUERY_TOOL_CONFIG'),

  /// Settings for Bigtable tools.
  bigtableToolSettings('BIGTABLE_TOOL_SETTINGS'),

  /// Bigtable toolset integration.
  bigtableToolset('BIGTABLE_TOOLSET'),

  /// Computer use capability and toolset.
  computerUse('COMPUTER_USE'),

  /// Configuration options for Data Agent tools.
  dataAgentToolConfig('DATA_AGENT_TOOL_CONFIG'),

  /// Data Agent toolset integration.
  dataAgentToolset('DATA_AGENT_TOOLSET'),

  /// Daytona sandbox environment integration.
  daytonaEnvironment('DAYTONA_ENVIRONMENT'),

  /// Environment simulation support for evaluation and testing.
  environmentSimulation('ENVIRONMENT_SIMULATION'),

  /// Eventarc toolset integration.
  eventarcToolset('EVENTARC_TOOLSET'),

  /// Google Cloud IAM connector authentication.
  gcpIamConnectorAuth('GCP_IAM_CONNECTOR_AUTH'),

  /// Configuration for Google Cloud credentials.
  googleCredentialsConfig('GOOGLE_CREDENTIALS_CONFIG'),

  /// Google API tool wrapper support.
  googleTool('GOOGLE_TOOL'),

  /// JSON Schema support in function declarations.
  jsonSchemaForFuncDecl('JSON_SCHEMA_FOR_FUNC_DECL'),

  /// Graceful error handling for MCP tool execution.
  mcpGracefulErrorHandling('MCP_GRACEFUL_ERROR_HANDLING'),

  /// Pluggable authentication framework support.
  pluggableAuth('PLUGGABLE_AUTH'),

  /// Progressive Server-Sent Events (SSE) streaming.
  progressiveSseStreaming('PROGRESSIVE_SSE_STREAMING'),

  /// Configuration options for Cloud Pub/Sub tools.
  pubsubToolConfig('PUBSUB_TOOL_CONFIG'),

  /// Cloud Pub/Sub toolset integration.
  pubsubToolset('PUBSUB_TOOLSET'),

  /// Agent skill toolset support.
  skillToolset('SKILL_TOOLSET'),

  /// Snake-case naming enforcement for skills.
  snakeCaseSkillName('SNAKE_CASE_SKILL_NAME'),

  /// Cloud Spanner administrative toolset integration.
  spannerAdminToolset('SPANNER_ADMIN_TOOLSET'),

  /// Cloud Spanner toolset integration.
  spannerToolset('SPANNER_TOOLSET'),

  /// Settings for Cloud Spanner tools.
  spannerToolSettings('SPANNER_TOOL_SETTINGS'),

  /// Cloud Spanner vector store integration.
  spannerVectorStore('SPANNER_VECTOR_STORE'),

  /// General tool configuration support.
  toolConfig('TOOL_CONFIG'),

  /// Interactive user confirmation before tool execution.
  toolConfirmation('TOOL_CONFIRMATION');

  /// Creates a feature identifier with its environment variable [value].
  const FeatureName(this.value);

  /// The uppercase identifier suffix used in feature environment variables.
  final String value;
}

/// Release stages used by feature-gating decisions.
enum FeatureStage {
  /// Work-in-progress stage for incomplete features.
  wip('wip'),

  /// Experimental stage for preview features that may change.
  experimental('experimental'),

  /// Stable stage for production-ready features.
  stable('stable');

  /// Creates a feature release stage with its serialized [value].
  const FeatureStage(this.value);

  /// The lowercase string representation of this release stage.
  final String value;
}

/// Static configuration for a single feature.
class FeatureConfig {
  /// Creates feature configuration for [stage].
  const FeatureConfig(this.stage, {this.defaultOn = false});

  /// The release stage for the feature.
  final FeatureStage stage;

  /// Whether the feature is enabled without explicit overrides.
  final bool defaultOn;
}

/// Emits user-visible warnings for enabled non-stable features.
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
      FeatureName.daytonaEnvironment: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.environmentSimulation: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.eventarcToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.gcpIamConnectorAuth: const FeatureConfig(
        FeatureStage.experimental,
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
      FeatureName.mcpGracefulErrorHandling: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.pluggableAuth: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
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
      FeatureName.snakeCaseSkillName: const FeatureConfig(
        FeatureStage.experimental,
      ),
      FeatureName.spannerAdminToolset: const FeatureConfig(
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

/// Returns the registered configuration for [featureName], if any.
FeatureConfig? getFeatureConfig(FeatureName featureName) {
  return _featureRegistry[featureName];
}

/// Registers or replaces [featureName] with [config].
void registerFeature(FeatureName featureName, FeatureConfig config) {
  _featureRegistry[featureName] = config;
}

/// Overrides whether [featureName] is enabled.
///
/// Throws an [ArgumentError] if [featureName] is not registered.
void overrideFeatureEnabled(FeatureName featureName, bool enabled) {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null) {
    throw ArgumentError('Feature $featureName is not registered.');
  }
  _featureOverrides[featureName] = enabled;
}

/// Removes any explicit enablement override for [featureName].
void clearFeatureOverride(FeatureName featureName) {
  _featureOverrides.remove(featureName);
}

/// Whether [featureName] is currently enabled.
///
/// This checks explicit overrides first, then environment variables, and
/// finally the feature's [FeatureConfig.defaultOn] value.
///
/// Throws an [ArgumentError] if [featureName] is not registered.
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

/// Runs [body] with a temporary override for [featureName].
///
/// The previous override state is restored after [body] returns.
///
/// Throws an [ArgumentError] if [featureName] is not registered.
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

/// Runs async [body] with a temporary override for [featureName].
///
/// The previous override state is restored after [body] completes.
///
/// Throws an [ArgumentError] if [featureName] is not registered.
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

/// Replaces the warning emitter used for non-stable feature notices.
void setFeatureWarningEmitter(FeatureWarningEmitter emitter) {
  _featureWarningEmitter = emitter;
}

/// Resets runtime feature state for test isolation.
///
/// When [resetRegistry] is true, restores the initial built-in registry.
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

/// The current explicit feature overrides.
Map<FeatureName, bool> getFeatureOverrides() {
  return Map<FeatureName, bool>.unmodifiable(_featureOverrides);
}

final Map<FeatureName, FeatureConfig> _defaultFeatureRegistry =
    Map<FeatureName, FeatureConfig>.unmodifiable(_featureRegistry);
