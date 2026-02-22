import '../apps/app.dart';
import '../artifacts/base_artifact_service.dart';
import '../events/event.dart';
import '../plugins/plugin_manager.dart';
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'live_request_queue.dart';
import 'run_config.dart';

class LlmCallsLimitExceededError implements Exception {
  LlmCallsLimitExceededError(this.message);

  final String message;

  @override
  String toString() => 'LlmCallsLimitExceededError: $message';
}

class InvocationContext {
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

  BaseArtifactService? artifactService;
  BaseSessionService sessionService;
  Object? memoryService;
  Object? credentialService;
  Object? contextCacheConfig;

  String invocationId;
  String? branch;
  BaseAgent agent;
  Content? userContent;
  Session session;

  Map<String, Map<String, Object?>> agentStates;
  Map<String, bool> endOfAgents;
  bool endInvocation;

  LiveRequestQueue? liveRequestQueue;
  Map<String, Object?>? activeStreamingTools;
  List<Object?>? transcriptionCache;
  String? liveSessionResumptionHandle;
  List<Object?>? inputRealtimeCache;
  List<Object?>? outputRealtimeCache;

  RunConfig? runConfig;
  ResumabilityConfig? resumabilityConfig;
  EventsCompactionConfig? eventsCompactionConfig;
  bool tokenCompactionChecked;

  PluginManager pluginManager;
  List<BaseTool>? canonicalToolsCache;

  int _numberOfLlmCalls = 0;

  bool get isResumable => resumabilityConfig?.isResumable ?? false;

  String get appName => session.appName;

  String get userId => session.userId;

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

    for (int index = session.events.length - 1; index >= 0; index -= 1) {
      final Event event = session.events[index];
      for (final call in event.getFunctionCalls()) {
        if (call.id == functionCallId) {
          return event;
        }
      }
    }

    return null;
  }

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
          : Map<String, Object?>.from(activeStreamingTools!),
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
