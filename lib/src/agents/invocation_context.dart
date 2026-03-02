/// Invocation-scoped execution context and state containers.
library;

import '../apps/app.dart';
import '../artifacts/base_artifact_service.dart';
import '../events/event.dart';
import '../memory/base_memory_service.dart';
import '../memory/memory_entry.dart';
import '../plugins/plugin_manager.dart';
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import 'agent_state.dart';
import 'active_streaming_tool.dart';
import 'base_agent.dart';
import 'live_request_queue.dart';
import 'run_config.dart';

/// Error thrown when LLM call count exceeds the configured limit.
class LlmCallsLimitExceededError implements Exception {
  /// Creates an LLM call-limit error with [message].
  LlmCallsLimitExceededError(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'LlmCallsLimitExceededError: $message';
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
    required this.agent,
    this.userContent,
    required this.session,
    Map<String, Map<String, Object?>>? agentStates,
    Map<String, bool>? endOfAgents,
    this.endInvocation = false,
    this.liveRequestQueue,
    this.activeStreamingTools,
    this.transcriptionCache,
    this.liveSessionResumptionHandle,
    this.inputRealtimeCache,
    this.outputRealtimeCache,
    this.runConfig,
    this.resumabilityConfig,
    this.eventsCompactionConfig,
    this.tokenCompactionChecked = false,
    PluginManager? pluginManager,
    this.canonicalToolsCache,
  }) : agentStates = agentStates ?? <String, Map<String, Object?>>{},
       endOfAgents = endOfAgents ?? <String, bool>{},
       pluginManager = pluginManager ?? PluginManager();

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

  /// Active streaming tool handles by function call ID.
  Map<String, ActiveStreamingTool>? activeStreamingTools;

  /// Cached transcription payloads across realtime turns.
  List<Object?>? transcriptionCache;

  /// Opaque live-session resumption handle.
  String? liveSessionResumptionHandle;

  /// Buffered realtime input chunks.
  List<Object?>? inputRealtimeCache;

  /// Buffered realtime output chunks.
  List<Object?>? outputRealtimeCache;

  /// Run configuration options.
  RunConfig? runConfig;

  /// Resumability policy for this invocation.
  ResumabilityConfig? resumabilityConfig;

  /// Event compaction settings for this invocation.
  EventsCompactionConfig? eventsCompactionConfig;

  /// Whether token compaction checks already ran.
  bool tokenCompactionChecked;

  /// Plugin manager used throughout execution.
  PluginManager pluginManager;

  /// Cached canonical tool set, if computed.
  List<BaseTool>? canonicalToolsCache;

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

  /// Adds the current session transcript to memory.
  ///
  /// Throws a [StateError] when memory services are unavailable.
  Future<void> addSessionToMemory() async {
    final Object? service = memoryService;
    if (service is! BaseMemoryService) {
      throw StateError('Memory service is not initialized.');
    }
    await service.addSessionToMemory(session);
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

  /// Sets or clears serialized state for [agentName].
  void setAgentState(
    String agentName, {
    BaseAgentState? agentState,
    bool endOfAgent = false,
  }) {
    if (endOfAgent) {
      endOfAgents[agentName] = true;
      agentStates.remove(agentName);
      return;
    }

    if (agentState != null) {
      agentStates[agentName] = agentState.toJson();
      endOfAgents[agentName] = false;
      return;
    }

    endOfAgents.remove(agentName);
    agentStates.remove(agentName);
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
      events = events.where((Event event) => event.branch == branch);
    }
    return events.toList();
  }

  /// Whether [event] should pause resumable invocation execution.
  bool shouldPauseInvocation(Event event) {
    if (!isResumable) {
      return false;
    }

    final Set<String>? ids = event.longRunningToolIds;
    if (ids == null || ids.isEmpty) {
      return false;
    }

    for (final FunctionCall call in event.getFunctionCalls()) {
      final String? id = call.id;
      if (id != null && ids.contains(id)) {
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

  /// Creates a shallow-cloned context with selected overrides.
  InvocationContext copyWith({
    BaseAgent? agent,
    String? branch,
    Content? userContent,
    String? invocationId,
    RunConfig? runConfig,
  }) {
    return InvocationContext(
      artifactService: artifactService,
      sessionService: sessionService,
      memoryService: memoryService,
      credentialService: credentialService,
      contextCacheConfig: contextCacheConfig,
      invocationId: invocationId ?? this.invocationId,
      branch: branch ?? this.branch,
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
      transcriptionCache: transcriptionCache == null
          ? null
          : List<Object?>.from(transcriptionCache!),
      liveSessionResumptionHandle: liveSessionResumptionHandle,
      inputRealtimeCache: inputRealtimeCache == null
          ? null
          : List<Object?>.from(inputRealtimeCache!),
      outputRealtimeCache: outputRealtimeCache == null
          ? null
          : List<Object?>.from(outputRealtimeCache!),
      runConfig: runConfig ?? this.runConfig?.copyWith(),
      resumabilityConfig: resumabilityConfig,
      eventsCompactionConfig: eventsCompactionConfig,
      tokenCompactionChecked: tokenCompactionChecked,
      pluginManager: pluginManager,
      canonicalToolsCache: canonicalToolsCache == null
          ? null
          : List<BaseTool>.from(canonicalToolsCache!),
    ).._numberOfLlmCalls = _numberOfLlmCalls;
  }
}
