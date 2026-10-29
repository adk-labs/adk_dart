/// Invocation-scoped execution context and state containers.
library;

import 'dart:async';

import '../apps/app.dart';
import '../artifacts/base_artifact_service.dart';
import '../auth/auth_credential.dart';
import '../events/event.dart';
import '../events/node_path_builder.dart';
import '../memory/base_memory_service.dart';
import '../memory/memory_entry.dart';
import '../plugins/plugin_manager.dart';
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import 'abort_signal.dart';
import 'agent_state.dart';
import 'active_streaming_tool.dart';
import 'base_agent.dart';
import 'live_request_queue.dart';
import 'run_config.dart';

const Object _sentinel = Object();

/// Error thrown when LLM call count exceeds the configured limit.
class LlmCallsLimitExceededError implements Exception {
  /// Creates an LLM call-limit error with [message].
  LlmCallsLimitExceededError(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'LlmCallsLimitExceededError: $message';
}

/// One tool call running in the background of a live invocation.
class ActiveBackgroundTool {
  /// Creates a background tool descriptor for [toolName] and [functionCallId].
  ActiveBackgroundTool({
    required this.toolName,
    required this.functionCallId,
    this.task,
    this.inputStream,
    this.isGenerator = false,
    this.arguments,
    this.onCancel,
  });

  /// Name of the tool that was called.
  final String toolName;

  /// Identifier of the function call this entry runs.
  final String functionCallId;

  /// In-flight task running the tool call.
  Future<Object?>? task;

  /// Input stream the tool reads live requests from, if any.
  LiveRequestQueue? inputStream;

  /// Whether the tool is a streaming generator that yields multiple responses.
  final bool isGenerator;

  /// Arguments passed to the tool call when it started.
  final Map<String, dynamic>? arguments;

  /// Optional cancellation callback invoked by `stop_streaming`.
  FutureOr<void> Function()? onCancel;
}

/// Mutable invocation context shared across agent execution steps.
class InvocationContext {
  /// Creates an invocation context for a single run.
  InvocationContext({
    this.artifactService,
    required this.sessionService,
    this.memoryService,
    this.credentialService,
    this.contextCacheConfig,
    required this.invocationId,
    this.branch,
    this.nodePath,
    this.isolationScope,
    required this.agent,
    this.userContent,
    required this.session,
    Map<String, Map<String, Object?>>? agentStates,
    Map<String, bool>? endOfAgents,
    this.endInvocation = false,
    this.liveRequestQueue,
    this.activeStreamingTools,
    this.activeNonBlockingToolTasks,
    Map<String, ActiveBackgroundTool>? activeBackgroundTools,
    this.transcriptionCache,
    this.liveSessionResumptionHandle,
    this.inputRealtimeCache,
    this.inputVisualCache,
    this.outputRealtimeCache,
    this.runConfig,
    this.resumabilityConfig,
    this.eventsCompactionConfig,
    AdkAbortSignal? abortSignal,
    this.tokenCompactionChecked = false,
    PluginManager? pluginManager,
    this.canonicalToolsCache,
    Map<String, AuthCredential>? credentialByKey,
    Map<String, Object?>? callbackContextData,
    Map<String, Object?>? privateMetadata,
  }) : agentStates = agentStates ?? <String, Map<String, Object?>>{},
       endOfAgents = endOfAgents ?? <String, bool>{},
       activeBackgroundTools =
           activeBackgroundTools ?? <String, ActiveBackgroundTool>{},
       pluginManager = pluginManager ?? PluginManager(),
       credentialByKey = credentialByKey ?? <String, AuthCredential>{},
       callbackContextData = callbackContextData ?? <String, Object?>{},
       privateMetadata = privateMetadata ?? <String, Object?>{},
       abortSignal = abortSignal ?? AdkAbortSignal();

  /// Artifact service used for persistence and retrieval.
  BaseArtifactService? artifactService;

  /// Session service used for session reads and writes.
  BaseSessionService sessionService;

  /// Memory service backing long-term memory APIs.
  Object? memoryService;

  /// Credential service used for auth token persistence.
  Object? credentialService;

  /// Opaque context-cache configuration payload.
  Object? contextCacheConfig;

  /// Invocation identifier.
  String invocationId;

  /// Branch identifier for branched execution, if any.
  String? branch;

  /// Hierarchical node path in the workflow graph, if any.
  String? nodePath;

  /// Internal logical scope tag for filtering task-agent conversation views.
  ///
  /// This mirrors Python ADK's isolation scope: when set, LLM content builders
  /// include only session events whose [Event.isolationScope] matches exactly.
  String? isolationScope;

  /// Active agent for this invocation.
  BaseAgent agent;

  /// User-provided content for the current turn.
  Content? userContent;

  /// Backing session object.
  Session session;

  /// Serialized agent states by agent name.
  Map<String, Map<String, Object?>> agentStates;

  /// Per-agent completion markers for resumable flows.
  Map<String, bool> endOfAgents;

  /// Whether the overall invocation has ended.
  bool endInvocation;

  /// Queue used by live-mode request handling.
  LiveRequestQueue? liveRequestQueue;

  /// Active streaming tool handles by function call ID or tool name.
  Map<String, ActiveStreamingTool>? activeStreamingTools;

  /// Active background tasks executing non-blocking tools in Live mode.
  Map<String, Future<void>>? activeNonBlockingToolTasks;

  /// Active background tool calls (streaming and non-blocking) keyed by function call ID.
  Map<String, ActiveBackgroundTool> activeBackgroundTools;

  /// Cached transcription payloads across realtime turns.
  List<Object?>? transcriptionCache;

  /// Opaque live-session resumption handle.
  String? liveSessionResumptionHandle;

  /// Buffered realtime input chunks.
  List<Object?>? inputRealtimeCache;

  /// Buffered realtime visual input frames.
  List<Object?>? inputVisualCache;

  /// Buffered realtime output chunks.
  List<Object?>? outputRealtimeCache;

  /// Run configuration options.
  RunConfig? runConfig;

  /// Resumability policy for this invocation.
  ResumabilityConfig? resumabilityConfig;

  /// Event compaction settings for this invocation.
  EventsCompactionConfig? eventsCompactionConfig;

  /// Cooperative cancellation signal for this invocation.
  AdkAbortSignal? abortSignal;

  /// Whether an abort event has already been synthesized for this invocation.
  bool abortEventSynthesized = false;

  bool _aborted = false;

  /// Whether this invocation has been cancelled.
  bool get isAborted => _aborted || (abortSignal?.aborted ?? false);

  /// Requests cancellation of this invocation.
  void abort([Object? reason]) {
    _aborted = true;
    abortSignal?.abort(reason);
  }

  /// Whether token compaction checks already ran.
  bool tokenCompactionChecked;

  /// Plugin manager used throughout execution.
  PluginManager pluginManager;

  /// Cached canonical tool set, if computed.
  List<BaseTool>? canonicalToolsCache;

  /// Resolved credentials for this invocation keyed by auth credential key.
  Map<String, AuthCredential> credentialByKey;

  /// Shared invocation-scoped scratch data for flow/runner coordination.
  ///
  /// This map is intentionally shared across shallow context copies so agent
  /// transfers and nested flows can coordinate on one invocation-level state.
  Map<String, Object?> callbackContextData;

  /// Invocation-scoped private metadata cache shared across context copies.
  Map<String, Object?> privateMetadata;

  int _numberOfLlmCalls = 0;

  /// Whether resumable execution is enabled.
  bool get isResumable => resumabilityConfig?.isResumable ?? false;

  /// The application name for this invocation.
  String get appName => session.appName;

  /// The user ID for this invocation.
  String get userId => session.userId;

  /// Saves an [artifact] to [filename] and returns its version.
  ///
  /// Throws a [StateError] when artifact services are unavailable.
  Future<int> saveArtifact({
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      throw StateError('Artifact service is not initialized.');
    }

    return service.saveArtifact(
      appName: appName,
      userId: userId,
      sessionId: sessionId ?? session.id,
      filename: filename,
      artifact: artifact,
      customMetadata: customMetadata,
    );
  }

  /// Loads an artifact [filename] and optional [version].
  ///
  /// Throws a [StateError] when artifact services are unavailable.
  Future<Part?> loadArtifact({
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      throw StateError('Artifact service is not initialized.');
    }

    return service.loadArtifact(
      appName: appName,
      userId: userId,
      sessionId: sessionId ?? session.id,
      filename: filename,
      version: version,
    );
  }

  /// Searches memory with [query].
  ///
  /// Throws a [StateError] when memory services are unavailable.
  Future<SearchMemoryResponse> searchMemory({required String query}) async {
    final Object? service = memoryService;
    if (service is! BaseMemoryService) {
      throw StateError('Memory service is not initialized.');
    }
    return service.searchMemory(appName: appName, userId: userId, query: query);
  }

  /// Adds [events] to memory for this or another [sessionId].
  ///
  /// Throws a [StateError] when memory services are unavailable.
  Future<void> addEventsToMemory({
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final Object? service = memoryService;
    if (service is! BaseMemoryService) {
      throw StateError('Memory service is not initialized.');
    }
    await service.addEventsToMemory(
      appName: appName,
      userId: userId,
      events: events,
      sessionId: sessionId ?? session.id,
      customMetadata: customMetadata,
    );
  }

  /// Adds explicit [memories] to long-term memory.
  ///
  /// Throws a [StateError] when memory services are unavailable.
  Future<void> addMemory({
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    final Object? service = memoryService;
    if (service is! BaseMemoryService) {
      throw StateError('Memory service is not initialized.');
    }
    await service.addMemory(
      appName: appName,
      userId: userId,
      memories: memories,
      customMetadata: customMetadata,
    );
  }

  /// Persists the current session transcript to memory.
  ///
  /// Throws a [StateError] when memory services are unavailable.
  Future<void> addSessionToMemory({
    Map<String, Object?>? customMetadata,
  }) async {
    final Object? service = memoryService;
    if (service is! BaseMemoryService) {
      throw StateError('Memory service is not initialized.');
    }
    await service.addSessionToMemory(session, customMetadata: customMetadata);
  }

  /// Deletes a memory item by its [memoryId] for the current user and application.
  ///
  /// Throws a [StateError] when memory services are unavailable.
  Future<void> deleteMemory({String? memoryId}) async {
    final Object? service = memoryService;
    if (service is! BaseMemoryService) {
      throw StateError('Memory service is not initialized.');
    }
    await service.deleteMemory(
      appName: appName,
      userId: userId,
      memoryId: memoryId,
    );
  }

  /// Lists artifact filenames for this invocation session.
  ///
  /// Throws a [StateError] when artifact services are unavailable.
  Future<List<String>> listArtifacts({String? sessionId}) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      throw StateError('Artifact service is not initialized.');
    }

    return service.listArtifactKeys(
      appName: appName,
      userId: userId,
      sessionId: sessionId ?? session.id,
    );
  }

  /// Deletes artifact [filename] from storage.
  ///
  /// Throws a [StateError] when artifact services are unavailable.
  Future<void> deleteArtifact({
    required String filename,
    String? sessionId,
  }) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      throw StateError('Artifact service is not initialized.');
    }

    return service.deleteArtifact(
      appName: appName,
      userId: userId,
      sessionId: sessionId ?? session.id,
      filename: filename,
    );
  }

  /// Lists available versions for artifact [filename].
  ///
  /// Throws a [StateError] when artifact services are unavailable.
  Future<List<int>> listArtifactVersions({
    required String filename,
    String? sessionId,
  }) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      throw StateError('Artifact service is not initialized.');
    }

    return service.listVersions(
      appName: appName,
      userId: userId,
      sessionId: sessionId ?? session.id,
      filename: filename,
    );
  }

  /// Returns metadata for artifact [filename] and optional [version].
  ///
  /// Throws a [StateError] when artifact services are unavailable.
  Future<ArtifactVersion?> getArtifactVersion({
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      throw StateError('Artifact service is not initialized.');
    }

    return service.getArtifactVersion(
      appName: appName,
      userId: userId,
      sessionId: sessionId ?? session.id,
      filename: filename,
      version: version,
    );
  }

  /// Returns the key used to store agent state for [agentName].
  ///
  /// When [nodePath] is set and ends with [agentName], returns [nodePath] so
  /// repeated sub-agent invocations in workflow graphs do not collide.
  String agentStateKey(String agentName) {
    final String? path = nodePath;
    if (path != null && path.isNotEmpty && path.split('.').last == agentName) {
      return path;
    }
    return agentName;
  }

  /// Sets or clears serialized state for [agentName].
  void setAgentState(
    String agentName, {
    BaseAgentState? agentState,
    bool endOfAgent = false,
  }) {
    final String key = agentStateKey(agentName);
    if (endOfAgent) {
      endOfAgents[key] = true;
      agentStates.remove(key);
      return;
    }

    if (agentState != null) {
      agentStates[key] = agentState.toJson();
      endOfAgents[key] = false;
      return;
    }

    endOfAgents.remove(key);
    agentStates.remove(key);
  }

  /// Clears cached states for all descendants of [agentName].
  void resetSubAgentStates(String agentName) {
    final BaseAgent? target = agent.findAgent(agentName);
    if (target == null) {
      return;
    }

    for (final BaseAgent subAgent in target.subAgents) {
      setAgentState(subAgent.name);
      resetSubAgentStates(subAgent.name);
    }
  }

  /// Rebuilds in-memory agent state from current-invocation events.
  void populateInvocationAgentStates() {
    if (!isResumable) {
      return;
    }

    for (final Event event in getEvents(currentInvocation: true)) {
      if (event.actions.endOfAgent == true) {
        endOfAgents[event.author] = true;
        agentStates.remove(event.author);
      } else if (event.actions.agentState != null) {
        agentStates[event.author] = Map<String, Object?>.from(
          event.actions.agentState!,
        );
        endOfAgents[event.author] = false;
      } else if (event.author != 'user' &&
          event.content != null &&
          !agentStates.containsKey(event.author)) {
        agentStates[event.author] = <String, Object?>{};
        endOfAgents[event.author] = false;
      }
    }
  }

  /// Increments the LLM call counter and enforces [RunConfig.maxLlmCalls].
  ///
  /// Throws an [LlmCallsLimitExceededError] when the limit is exceeded.
  void incrementLlmCallCount() {
    _numberOfLlmCalls += 1;
    final RunConfig? config = runConfig;
    if (config != null &&
        config.maxLlmCalls > 0 &&
        _numberOfLlmCalls > config.maxLlmCalls) {
      throw LlmCallsLimitExceededError(
        'Max number of llm calls `${config.maxLlmCalls}` exceeded',
      );
    }
  }

  /// Returns events filtered by invocation and/or branch scopes.
  List<Event> getEvents({
    bool currentInvocation = false,
    bool currentBranch = false,
  }) {
    Iterable<Event> events = session.events;
    if (currentInvocation) {
      events = events.where(
        (Event event) => event.invocationId == invocationId,
      );
    }
    if (currentBranch) {
      final String? br = branch;
      NodePathBuilder? selfNodePath;
      String? agentMode;
      try {
        agentMode = (agent as dynamic).mode as String?;
      } catch (_) {}
      if (agentMode == 'single_turn' &&
          nodePath != null &&
          nodePath!.isNotEmpty) {
        selfNodePath = NodePathBuilder.fromString(nodePath!);
      }
      events = events.where((Event event) {
        if (selfNodePath != null &&
            !selfNodePath.includesNodePath(event.nodeInfo.path)) {
          return false;
        }
        if (event.author == 'user') {
          final List<FunctionResponse> frs = event.getFunctionResponses();
          if (frs.isNotEmpty && br != null) {
            final Set<String> frIds = frs
                .map((FunctionResponse fr) => fr.id)
                .where((String? id) => id != null && id.isNotEmpty)
                .cast<String>()
                .toSet();
            if (frIds.isNotEmpty) {
              final List<Event> branchEvents = session.events
                  .where(
                    (Event e) =>
                        e.branch != null &&
                        (e.branch == br || e.branch!.startsWith('$br.')),
                  )
                  .toList();
              final Set<String> branchFcIds = branchEvents
                  .expand((Event e) => e.getFunctionCalls())
                  .map((FunctionCall fc) => fc.id)
                  .where((String? id) => id != null && id.isNotEmpty)
                  .cast<String>()
                  .toSet();
              if (frIds.intersection(branchFcIds).isEmpty) {
                return false;
              }
            }
          }

          return event.branch == null ||
              br == null ||
              event.branch == br ||
              event.branch!.startsWith('$br.');
        }
        return event.branch == br;
      });
    }
    return events.toList();
  }

  /// Whether [event] should pause resumable invocation execution.
  bool shouldPauseInvocation(Event event) {
    if (!isResumable) {
      return false;
    }

    final List<FunctionCall> calls = event.getFunctionCalls();
    if (calls.isEmpty) {
      return false;
    }

    final Set<String> interruptIds = <String>{
      ...?event.longRunningToolIds,
      for (final FunctionCall call in calls)
        if (call.id != null &&
            (call.name == 'adk_request_input' ||
                call.name == 'adk_request_credential'))
          call.id!,
    };
    if (interruptIds.isEmpty) {
      return false;
    }

    for (final FunctionCall call in calls) {
      final String? id = call.id;
      if (id != null && interruptIds.contains(id)) {
        return true;
      }
    }

    return false;
  }

  /// Finds the function-call event that matches [functionResponseEvent].
  Event? findMatchingFunctionCall(Event functionResponseEvent) {
    final List<FunctionResponse> responses = functionResponseEvent
        .getFunctionResponses();
    if (responses.isEmpty) {
      return null;
    }

    final String? functionCallId = responses.first.id;
    if (functionCallId == null) {
      return null;
    }

    final List<Event> invocationEvents = getEvents(currentInvocation: true);
    final int responseIndex = invocationEvents.lastIndexWhere(
      (Event event) => event.id == functionResponseEvent.id,
    );
    final int startIndex = responseIndex >= 0
        ? responseIndex - 1
        : invocationEvents.length - 1;

    for (int index = startIndex; index >= 0; index -= 1) {
      final Event event = invocationEvents[index];
      for (final call in event.getFunctionCalls()) {
        if (call.id == functionCallId) {
          return event;
        }
      }
    }

    return null;
  }

  /// Stamps the event with the branch and isolation scope of its matching function call.
  void stampEventBranchContext(Event event) {
    final Event? functionCall = findMatchingFunctionCall(event);
    if (functionCall != null) {
      event.branch = functionCall.branch;
      if (event.isolationScope == null && functionCall.isolationScope != null) {
        event.isolationScope = functionCall.isolationScope;
      }
    }
  }

  /// Creates a shallow-cloned context with selected overrides.
  InvocationContext copyWith({
    BaseAgent? agent,
    String? branch,
    Object? nodePath = _sentinel,
    Object? isolationScope = _sentinel,
    Content? userContent,
    String? invocationId,
    RunConfig? runConfig,
    AdkAbortSignal? abortSignal,
  }) {
    return InvocationContext(
      artifactService: artifactService,
      sessionService: sessionService,
      memoryService: memoryService,
      credentialService: credentialService,
      contextCacheConfig: contextCacheConfig,
      invocationId: invocationId ?? this.invocationId,
      branch: branch ?? this.branch,
      nodePath: identical(nodePath, _sentinel)
          ? this.nodePath
          : nodePath as String?,
      isolationScope: identical(isolationScope, _sentinel)
          ? this.isolationScope
          : isolationScope as String?,
      agent: agent ?? this.agent,
      userContent: userContent ?? this.userContent?.copyWith(),
      session: session,
      agentStates: agentStates.map(
        (String key, Map<String, Object?> value) =>
            MapEntry<String, Map<String, Object?>>(
              key,
              Map<String, Object?>.from(value),
            ),
      ),
      endOfAgents: Map<String, bool>.from(endOfAgents),
      endInvocation: endInvocation,
      liveRequestQueue: liveRequestQueue,
      activeStreamingTools: activeStreamingTools == null
          ? null
          : Map<String, ActiveStreamingTool>.from(activeStreamingTools!),
      activeNonBlockingToolTasks: activeNonBlockingToolTasks == null
          ? null
          : Map<String, Future<void>>.from(activeNonBlockingToolTasks!),
      activeBackgroundTools: Map<String, ActiveBackgroundTool>.from(
        activeBackgroundTools,
      ),
      transcriptionCache: transcriptionCache == null
          ? null
          : List<Object?>.from(transcriptionCache!),
      liveSessionResumptionHandle: liveSessionResumptionHandle,
      inputRealtimeCache: inputRealtimeCache == null
          ? null
          : List<Object?>.from(inputRealtimeCache!),
      inputVisualCache: inputVisualCache == null
          ? null
          : List<Object?>.from(inputVisualCache!),
      outputRealtimeCache: outputRealtimeCache == null
          ? null
          : List<Object?>.from(outputRealtimeCache!),
      runConfig: runConfig ?? this.runConfig?.copyWith(),
      resumabilityConfig: resumabilityConfig,
      eventsCompactionConfig: eventsCompactionConfig,
      abortSignal: abortSignal ?? this.abortSignal,
      tokenCompactionChecked: tokenCompactionChecked,
      pluginManager: pluginManager,
      canonicalToolsCache: canonicalToolsCache == null
          ? null
          : List<BaseTool>.from(canonicalToolsCache!),
      credentialByKey: credentialByKey.map(
        (String key, AuthCredential value) =>
            MapEntry<String, AuthCredential>(key, value.copyWith()),
      ),
      callbackContextData: callbackContextData,
      privateMetadata: privateMetadata,
    )
      .._numberOfLlmCalls = _numberOfLlmCalls
      ..abortEventSynthesized = abortEventSynthesized;
  }
}
