/// Runtime configuration models used by agent runs.
library;

import 'dart:io';

import '../sessions/base_session_service.dart';
import '../types/content.dart';

/// Streaming transport mode used by a run.
enum StreamingMode { none, sse, bidi }

/// Execution mode used when a model requests multiple tools in one turn.
enum ToolExecutionMode {
  /// Preserve the runtime default behavior.
  none,

  /// Execute tools strictly in the order requested by the model.
  sequential,

  /// Start all tool calls eagerly and await all results.
  parallel,

  /// Java parity value. In Dart this currently behaves like [parallel].
  parallelSubscribe,
}

/// Serving tiers the Gemini/interactions API offers for a model call.
enum ServiceTier {
  /// Best-effort capacity at a lower cost, with no latency guarantee.
  flex('flex'),

  /// The default tier.
  standard('standard'),

  /// Reserved capacity for latency-sensitive calls.
  priority('priority'),

  /// Queued to run on off-peak capacity.
  ///
  /// The call waits for room instead of being turned away when capacity is
  /// tight. Cannot be combined with streaming.
  deferred('deferred');

  const ServiceTier(this.value);

  /// The string wire value.
  final String value;

  /// Resolves a [ServiceTier] from string, or returns `null`.
  static ServiceTier? fromString(String? value) {
    if (value == null) return null;
    for (final ServiceTier tier in ServiceTier.values) {
      if (tier.value == value) return tier;
    }
    return null;
  }
}

final BigInt _pythonSysMaxSize = BigInt.parse('9223372036854775807');
const int _defaultMaxLlmCallsValue = 500;

int _defaultMaxLlmCalls() {
  final String? envVal = Platform.environment['ADK_MAX_LLM_CALLS'];
  if (envVal != null && envVal.isNotEmpty) {
    try {
      return int.parse(envVal);
    } catch (_) {
      // Fallback on invalid integer format
    }
  }
  return _defaultMaxLlmCallsValue;
}

/// Thread-pool configuration for concurrent tool execution.
class ToolThreadPoolConfig {
  /// Creates tool thread-pool configuration.
  ToolThreadPoolConfig({this.maxWorkers = 4}) {
    if (maxWorkers < 1) {
      throw ArgumentError.value(maxWorkers, 'maxWorkers', 'Must be >= 1');
    }
  }

  /// Maximum number of worker threads.
  int maxWorkers;
}

/// Configuration object controlling one agent run behavior.
class RunConfig {
  /// Creates a run configuration.
  RunConfig({
    this.supportCfc = false,
    this.streamingMode = StreamingMode.none,
    this.toolExecutionMode = ToolExecutionMode.none,
    int? maxLlmCalls,
    this.speechConfig,
    this.saveLiveBlob = false,
    this.toolThreadPoolConfig,
    this.responseModalities,
    this.outputAudioTranscription,
    this.inputAudioTranscription,
    this.realtimeInputConfig,
    this.enableAffectiveDialog,
    this.proactivity,
    this.sessionResumption,
    this.historyConfig,
    this.contextWindowCompression,
    this.customMetadata,
    this.getSessionConfig,
    this.modelInputContext,
    this.includeThoughtsFromOtherAgents = false,
    this.labels,
    this.explicitVadSignal,
    this.serviceTier,
  }) : maxLlmCalls = validateMaxLlmCalls(maxLlmCalls ?? _defaultMaxLlmCalls());

  /// Whether CFC behavior is enabled.
  bool supportCfc;

  /// Streaming behavior for model responses.
  StreamingMode streamingMode;

  /// Execution behavior for multiple model-requested tool calls.
  ToolExecutionMode toolExecutionMode;

  /// Maximum number of model calls allowed in a run.
  int maxLlmCalls;

  /// Optional speech configuration payload.
  Object? speechConfig;

  /// Whether live blobs are persisted.
  bool saveLiveBlob;

  /// Optional tool thread-pool configuration.
  ToolThreadPoolConfig? toolThreadPoolConfig;

  /// Optional requested response modalities.
  List<String>? responseModalities;

  /// Optional output audio transcription config.
  Object? outputAudioTranscription;

  /// Optional input audio transcription config.
  Object? inputAudioTranscription;

  /// Optional realtime input configuration.
  Object? realtimeInputConfig;

  /// Whether affective dialog is enabled.
  bool? enableAffectiveDialog;

  /// Optional proactivity configuration.
  Object? proactivity;

  /// Optional session resumption configuration.
  Object? sessionResumption;

  /// Optional live history exchange configuration.
  Object? historyConfig;

  /// Optional context-window compression configuration.
  Object? contextWindowCompression;

  /// Optional custom metadata forwarded with the run.
  Map<String, dynamic>? customMetadata;

  /// Optional filter passed to session-service `getSession()` calls.
  GetSessionConfig? getSessionConfig;

  /// Transient context to include in the model input for this invocation.
  ///
  /// The Runner does not persist these contents to the session. They are only
  /// added to the LLM request assembled for the current invocation, which lets
  /// callers provide per-turn context without changing the conversation
  /// history.
  List<Content>? modelInputContext;

  /// Whether to include thought parts from other agents when presenting their
  /// messages as user context.
  ///
  /// Defaults to `false`, preserving the privacy-first behavior of excluding
  /// other agents' reasoning. Enabling it converts other-agent thoughts into
  /// explicit `[agent] thought: ...` context text, which can help orchestrator,
  /// reviewer, or planner agents coordinate in trusted multi-agent systems.
  bool includeThoughtsFromOtherAgents;

  /// User labels for the current invocation (e.g. for billing/attribution).
  Map<String, String>? labels;

  /// Whether to request explicit Voice Activity Detection (VAD) signals from Live mode.
  bool? explicitVadSignal;

  /// Serving tier for model calls of this run (e.g., 'flex', 'standard', 'priority', 'deferred').
  ///
  /// Corresponds to [ServiceTier.value] or a custom tier string.
  String? serviceTier;

  /// Validates [value] for [maxLlmCalls].
  static int validateMaxLlmCalls(int value) {
    if (BigInt.from(value) >= _pythonSysMaxSize) {
      throw ArgumentError.value(
        value,
        'maxLlmCalls',
        'maxLlmCalls should be less than $_pythonSysMaxSize.',
      );
    }
    if (value <= 0) {
      print(
        'maxLlmCalls is less than or equal to 0. This will result in no '
        'enforcement on total number of llm calls that will be made for a '
        'run. This may not be ideal, as this could result in a never ending '
        'communication between the model and the agent in certain cases.',
      );
    }
    return value;
  }

  /// Returns a copied run configuration with optional overrides.
  RunConfig copyWith({
    bool? supportCfc,
    StreamingMode? streamingMode,
    ToolExecutionMode? toolExecutionMode,
    int? maxLlmCalls,
    Object? speechConfig = _sentinel,
    bool? saveLiveBlob,
    Object? toolThreadPoolConfig = _sentinel,
    List<String>? responseModalities,
    Object? outputAudioTranscription = _sentinel,
    Object? inputAudioTranscription = _sentinel,
    Object? realtimeInputConfig = _sentinel,
    Object? enableAffectiveDialog = _sentinel,
    Object? proactivity = _sentinel,
    Object? sessionResumption = _sentinel,
    Object? historyConfig = _sentinel,
    Object? contextWindowCompression = _sentinel,
    Map<String, dynamic>? customMetadata,
    Object? getSessionConfig = _sentinel,
    Object? modelInputContext = _sentinel,
    bool? includeThoughtsFromOtherAgents,
    Map<String, String>? labels,
    String? serviceTier,
  }) {
    return RunConfig(
      supportCfc: supportCfc ?? this.supportCfc,
      streamingMode: streamingMode ?? this.streamingMode,
      toolExecutionMode: toolExecutionMode ?? this.toolExecutionMode,
      maxLlmCalls: maxLlmCalls ?? this.maxLlmCalls,
      speechConfig: identical(speechConfig, _sentinel)
          ? this.speechConfig
          : speechConfig,
      saveLiveBlob: saveLiveBlob ?? this.saveLiveBlob,
      toolThreadPoolConfig: identical(toolThreadPoolConfig, _sentinel)
          ? this.toolThreadPoolConfig == null
                ? null
                : ToolThreadPoolConfig(
                    maxWorkers: this.toolThreadPoolConfig!.maxWorkers,
                  )
          : toolThreadPoolConfig as ToolThreadPoolConfig?,
      responseModalities:
          responseModalities ??
          (this.responseModalities == null
              ? null
              : List<String>.from(this.responseModalities!)),
      outputAudioTranscription: identical(outputAudioTranscription, _sentinel)
          ? this.outputAudioTranscription
          : outputAudioTranscription,
      inputAudioTranscription: identical(inputAudioTranscription, _sentinel)
          ? this.inputAudioTranscription
          : inputAudioTranscription,
      realtimeInputConfig: identical(realtimeInputConfig, _sentinel)
          ? this.realtimeInputConfig
          : realtimeInputConfig,
      enableAffectiveDialog: identical(enableAffectiveDialog, _sentinel)
          ? this.enableAffectiveDialog
          : enableAffectiveDialog as bool?,
      proactivity: identical(proactivity, _sentinel)
          ? this.proactivity
          : proactivity,
      sessionResumption: identical(sessionResumption, _sentinel)
          ? this.sessionResumption
          : sessionResumption,
      historyConfig: identical(historyConfig, _sentinel)
          ? this.historyConfig
          : historyConfig,
      contextWindowCompression: identical(contextWindowCompression, _sentinel)
          ? this.contextWindowCompression
          : contextWindowCompression,
      customMetadata:
          customMetadata ??
          (this.customMetadata == null
              ? null
              : Map<String, dynamic>.from(this.customMetadata!)),
      getSessionConfig: identical(getSessionConfig, _sentinel)
          ? (this.getSessionConfig == null
                ? null
                : GetSessionConfig(
                    numRecentEvents: this.getSessionConfig!.numRecentEvents,
                    afterTimestamp: this.getSessionConfig!.afterTimestamp,
                  ))
          : getSessionConfig as GetSessionConfig?,
      modelInputContext: identical(modelInputContext, _sentinel)
          ? this.modelInputContext
                ?.map((Content content) => content.copyWith())
                .toList()
          : modelInputContext as List<Content>?,
      includeThoughtsFromOtherAgents:
          includeThoughtsFromOtherAgents ?? this.includeThoughtsFromOtherAgents,
      labels:
          labels ??
          (this.labels == null ? null : Map<String, String>.from(this.labels!)),
      serviceTier: serviceTier ?? this.serviceTier,
    );
  }
}

const Object _sentinel = Object();
