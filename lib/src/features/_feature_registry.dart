/// Feature registry models and helpers for runtime feature gating.
library;

import '../utils/env_utils.dart';

/// Identifiers for runtime-gated ADK features.
enum FeatureName {
  /// Declarative agent configuration support.
  agentConfig('AGENT_CONFIG'),

  /// Vertex AI Agent Engine sandbox environment integration.
  agentEngineSandboxEnvironment('AGENT_ENGINE_SANDBOX_ENVIRONMENT'),

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

  /// Cascaded STT -> LLM -> TTS live audio pipeline.
  cascadeLive('CASCADE_LIVE'),

  /// Probability-distribution classifiers and classifier routing nodes.
  classifier('CLASSIFIER'),

  /// Computer use capability and toolset.
  computerUse('COMPUTER_USE'),

  /// Configuration options for Data Agent tools.
  dataAgentToolConfig('DATA_AGENT_TOOL_CONFIG'),

  /// Data Agent toolset integration.
  dataAgentToolset('DATA_AGENT_TOOLSET'),

  /// Daytona sandbox environment integration.
  daytonaEnvironment('DAYTONA_ENVIRONMENT'),

  /// E2B sandbox environment integration.
  e2bEnvironment('E2B_ENVIRONMENT'),

  /// ElevenLabs speech-to-text and text-to-speech integration.
  elevenLabs('ELEVEN_LABS'),

  /// Environment simulation support for evaluation and testing.
  environmentSimulation('ENVIRONMENT_SIMULATION'),

  /// Eventarc toolset integration.
  eventarcToolset('EVENTARC_TOOLSET'),

  /// Google Cloud IAM connector authentication.
  gcpIamConnectorAuth('GCP_IAM_CONNECTOR_AUTH'),

  /// Google Cloud Storage administrative toolset integration.
  gcsAdminToolset('GCS_ADMIN_TOOLSET'),

  /// Settings for Google Cloud Storage tools.
  gcsToolSettings('GCS_TOOL_SETTINGS'),

  /// Google Cloud Storage toolset integration.
  gcsToolset('GCS_TOOLSET'),

  /// Configuration for Google Cloud credentials.
  googleCredentialsConfig('GOOGLE_CREDENTIALS_CONFIG'),

  /// Google API tool wrapper support.
  googleTool('GOOGLE_TOOL'),

  /// JSON Schema support in function declarations.
  jsonSchemaForFuncDecl('JSON_SCHEMA_FOR_FUNC_DECL'),

  /// MCP agent server integration.
  mcpAgentServer('MCP_AGENT_SERVER'),

  /// Graceful error handling for MCP tool execution.
  mcpGracefulErrorHandling('MCP_GRACEFUL_ERROR_HANDLING'),

  /// Model Context Protocol (MCP) toolset integration.
  mcpToolset('MCP_TOOLSET'),

  /// MongoDB memory service integration.
  mongodbMemoryService('MONGODB_MEMORY_SERVICE'),

  /// MongoDB session service integration.
  mongodbSessionService('MONGODB_SESSION_SERVICE'),

  /// OpenAPI toolset integration.
  openapiToolset('OPENAPI_TOOLSET'),

  /// OpenSandbox environment integration.
  opensandboxEnvironment('OPENSANDBOX_ENVIRONMENT'),

  /// Agent planners support.
  planners('PLANNERS'),

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

  /// Pluggable tool call argument matching support.
  toolArgsMatcher('TOOL_ARGS_MATCHER'),

  /// General tool configuration support.
  toolConfig('TOOL_CONFIG'),

  /// Interactive user confirmation before tool execution.
  toolConfirmation('TOOL_CONFIRMATION'),

  /// Toolbox toolset integration.
  toolboxToolset('TOOLBOX_TOOLSET');

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
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.agentEngineSandboxEnvironment: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.agentState: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.authenticatedFunctionTool: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.baseAuthenticatedTool: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.bigQueryToolset: const FeatureConfig(
        FeatureStage.stable,
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
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.cascadeLive: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.classifier: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.computerUse: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.dataAgentToolConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.dataAgentToolset: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.daytonaEnvironment: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.e2bEnvironment: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.elevenLabs: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.environmentSimulation: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.eventarcToolset: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.gcpIamConnectorAuth: const FeatureConfig(
        FeatureStage.experimental,
      ),
      FeatureName.gcsAdminToolset: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.gcsToolSettings: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.gcsToolset: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.googleCredentialsConfig: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.googleTool: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.jsonSchemaForFuncDecl: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.mcpAgentServer: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.mcpGracefulErrorHandling: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.mcpToolset: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.mongodbMemoryService: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.mongodbSessionService: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: false,
      ),
      FeatureName.openapiToolset: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.opensandboxEnvironment: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.planners: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.pluggableAuth: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.progressiveSseStreaming: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.pubsubToolConfig: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: true,
      ),
      FeatureName.pubsubToolset: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.skillToolset: const FeatureConfig(
        FeatureStage.stable,
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
        FeatureStage.stable,
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
      FeatureName.toolArgsMatcher: const FeatureConfig(
        FeatureStage.experimental,
        defaultOn: false,
      ),
      FeatureName.toolConfig: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.toolConfirmation: const FeatureConfig(
        FeatureStage.stable,
        defaultOn: true,
      ),
      FeatureName.toolboxToolset: const FeatureConfig(
        FeatureStage.stable,
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
      _emitNonStableWarningOnce(
        featureName,
        config.stage,
        environment: environment,
      );
    }
    return enabled;
  }

  final String enableVar = 'ADK_ENABLE_${featureName.value}';
  final String disableVar = 'ADK_DISABLE_${featureName.value}';
  if (isEnvEnabled(enableVar, environment: environment)) {
    if (config.stage != FeatureStage.stable) {
      _emitNonStableWarningOnce(
        featureName,
        config.stage,
        environment: environment,
      );
    }
    return true;
  }
  if (isEnvEnabled(disableVar, environment: environment)) {
    return false;
  }

  if (config.stage != FeatureStage.stable && config.defaultOn) {
    _emitNonStableWarningOnce(
      featureName,
      config.stage,
      environment: environment,
    );
  }
  return config.defaultOn;
}

/// Emits a one-time warning when a non-stable [featureName] is used.
void warnFeatureUse(
  FeatureName featureName, {
  Map<String, String>? environment,
}) {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null || config.stage == FeatureStage.stable) {
    return;
  }
  _emitNonStableWarningOnce(
    featureName,
    config.stage,
    environment: environment,
  );
}

void _emitNonStableWarningOnce(
  FeatureName featureName,
  FeatureStage featureStage, {
  Map<String, String>? environment,
}) {
  if (featureStage == FeatureStage.experimental &&
      isExperimentalWarningSuppressed(environment: environment)) {
    return;
  }
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
