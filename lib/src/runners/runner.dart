import 'dart:async';

import '../agents/base_agent.dart';
import '../agents/invocation_context.dart';
import '../agents/live_request_queue.dart';
import '../agents/llm_agent.dart';
import '../agents/run_config.dart';
import '../apps/app.dart';
import '../apps/compaction.dart' as app_compaction;
import '../artifacts/base_artifact_service.dart';
import '../artifacts/in_memory_artifact_service.dart';
import '../events/event.dart';
import '../events/event_actions.dart';
import '../flows/llm_flows/functions.dart' as flow_functions;
import '../plugins/base_plugin.dart';
import '../plugins/plugin_manager.dart';
import '../sessions/base_session_service.dart';
import '../sessions/in_memory_session_service.dart';
import '../sessions/session.dart';
import '../tools/base_toolset.dart';
import '../types/content.dart';

bool _isToolCallOrResponse(Event event) {
  return event.getFunctionCalls().isNotEmpty ||
      event.getFunctionResponses().isNotEmpty;
}

bool _isTranscription(Event event) {
  return event.inputTranscription != null || event.outputTranscription != null;
}

bool _hasNonEmptyTranscriptionText(Object? transcription) {
  if (transcription is Map) {
    final Object? text = transcription['text'];
    if (text is String && text.trim().isNotEmpty) {
      return true;
    }
  }
  if (transcription is String && transcription.trim().isNotEmpty) {
    return true;
  }
  return false;
}

class SessionNotFoundError implements Exception {
  SessionNotFoundError(this.message);

  final String message;

  @override
  String toString() => 'SessionNotFoundError: $message';
}

class Runner {
  Runner({
    this.app,
    String? appName,
    BaseAgent? agent,
    List<BasePlugin>? plugins,
    required this.sessionService,
    this.artifactService,
    this.memoryService,
    this.credentialService,
    Duration? pluginCloseTimeout,
    this.autoCreateSession = false,
  }) : pluginManager = PluginManager(
         plugins: plugins,
         closeTimeout: pluginCloseTimeout ?? const Duration(seconds: 5),
       ) {
    final (_RunnerParams params, List<BasePlugin> resolvedPlugins) =
        _validateRunnerParams(app, appName, agent, plugins);

    this.appName = params.appName;
    this.agent = params.agent;
    contextCacheConfig = params.contextCacheConfig;
    resumabilityConfig = params.resumabilityConfig;

    if (app != null) {
      for (final BasePlugin plugin in resolvedPlugins) {
        if (pluginManager.getPlugin(plugin.name) == null) {
          pluginManager.registerPlugin(plugin);
        }
      }
    }
  }

  final App? app;
  late String appName;
  late BaseAgent agent;

  final BaseArtifactService? artifactService;
  final BaseSessionService sessionService;
  final Object? memoryService;
  final Object? credentialService;
  final PluginManager pluginManager;

  final bool autoCreateSession;

  Object? contextCacheConfig;
  ResumabilityConfig? resumabilityConfig;

  (_RunnerParams, List<BasePlugin>) _validateRunnerParams(
    App? app,
    String? appName,
    BaseAgent? agent,
    List<BasePlugin>? plugins,
  ) {
    if (app != null) {
      if (agent != null) {
        throw ArgumentError(
          'When app is provided, agent should not be provided.',
        );
      }

      final String resolvedAppName = appName ?? app.name;
      return (
        _RunnerParams(
          appName: resolvedAppName,
          agent: app.rootAgent,
          contextCacheConfig: app.contextCacheConfig,
          resumabilityConfig: app.resumabilityConfig,
        ),
        app.plugins,
      );
    }

    if (appName == null || appName.isEmpty || agent == null) {
      throw ArgumentError(
        'Either app or both appName and agent must be provided.',
      );
    }

    return (
      _RunnerParams(appName: appName, agent: agent),
      plugins ?? <BasePlugin>[],
    );
  }

  Future<Session> _getOrCreateSession({
    required String userId,
    required String sessionId,
  }) async {
    Session? session = await sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );

    if (session == null) {
      if (!autoCreateSession) {
        throw SessionNotFoundError(
          'Session not found: $sessionId. '
          'Runner appName is "$appName". '
          'To automatically create a session when missing, set autoCreateSession=true.',
        );
      }
      session = await sessionService.createSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
    }

    return session;
  }

  Stream<Event> run({
    required String userId,
    required String sessionId,
    required Content newMessage,
    RunConfig? runConfig,
  }) {
    return runAsync(
      userId: userId,
      sessionId: sessionId,
      newMessage: newMessage,
      runConfig: runConfig,
    );
  }

  Stream<Event> runAsync({
    required String userId,
    required String sessionId,
    String? invocationId,
    Content? newMessage,
    Map<String, Object?>? stateDelta,
    RunConfig? runConfig,
  }) async* {
    final RunConfig config = runConfig ?? RunConfig();

    if (newMessage != null &&
        (newMessage.role == null || newMessage.role!.isEmpty)) {
      newMessage.role = 'user';
    }

    final Session session = await _getOrCreateSession(
      userId: userId,
      sessionId: sessionId,
    );

    if (invocationId == null && newMessage == null) {
      throw ArgumentError(
        'Running an agent requires either newMessage or invocationId.',
      );
    }

    final bool isResumable = resumabilityConfigOrDefault;
    if (!isResumable && newMessage == null) {
      throw ArgumentError(
        'Running an agent requires newMessage when app is not resumable.',
      );
    }

    InvocationContext context;
    if (!isResumable) {
      context = await _setupContextForNewInvocation(
        session: session,
        newMessage: newMessage!,
        stateDelta: stateDelta,
        runConfig: config,
      );
    } else {
      final String? resolvedInvocationId = _resolveInvocationId(
        session: session,
        newMessage: newMessage,
        invocationId: invocationId,
      );
      if (resolvedInvocationId == null) {
        context = await _setupContextForNewInvocation(
          session: session,
          newMessage: newMessage!,
          stateDelta: stateDelta,
          runConfig: config,
        );
      } else {
        context = await _setupContextForResumedInvocation(
          session: session,
          invocationId: resolvedInvocationId,
          newMessage: newMessage,
          stateDelta: stateDelta,
          runConfig: config,
        );
        if (context.endOfAgents[context.agent.name] == true) {
          return;
        }
      }
    }

    await for (final Event event in _execWithPlugin(
      invocationContext: context,
      session: session,
      execute: (InvocationContext ctx) => ctx.agent.runAsync(ctx),
      isLiveCall: false,
    )) {
      yield event;
    }

    if (app != null && app!.eventsCompactionConfig != null) {
      await app_compaction.runCompactionForSlidingWindow(
        app: app!,
        session: session,
        sessionService: sessionService,
        skipTokenCompaction: context.tokenCompactionChecked,
      );
    }
  }

  Future<void> rewindAsync({
    required String userId,
    required String sessionId,
    required String rewindBeforeInvocationId,
  }) async {
    final Session session = await _getOrCreateSession(
      userId: userId,
      sessionId: sessionId,
    );

    int rewindEventIndex = -1;
    for (int i = 0; i < session.events.length; i += 1) {
      if (session.events[i].invocationId == rewindBeforeInvocationId) {
        rewindEventIndex = i;
        break;
      }
    }

    if (rewindEventIndex == -1) {
      throw ArgumentError('Invocation ID not found: $rewindBeforeInvocationId');
    }

    final Map<String, Object?> stateDelta = _computeStateDeltaForRewind(
      session,
      rewindEventIndex,
    );
    final Map<String, int> artifactDelta = await _computeArtifactDeltaForRewind(
      session,
      rewindEventIndex,
    );

    final Event rewindEvent = Event(
      invocationId: _newInvocationContextId(),
      author: 'user',
      actions: EventActions(
        rewindBeforeInvocationId: rewindBeforeInvocationId,
        stateDelta: stateDelta,
        artifactDelta: artifactDelta,
      ),
    );

    await sessionService.appendEvent(session: session, event: rewindEvent);
  }

  Map<String, Object?> _computeStateDeltaForRewind(
    Session session,
    int rewindEventIndex,
  ) {
    final Map<String, Object?> stateAtRewindPoint = <String, Object?>{};
    for (int i = 0; i < rewindEventIndex; i += 1) {
      final Map<String, Object?> delta = session.events[i].actions.stateDelta;
      if (delta.isEmpty) {
        continue;
      }
      delta.forEach((String key, Object? value) {
        if (key.startsWith('app:') || key.startsWith('user:')) {
          return;
        }
        if (value == null) {
          stateAtRewindPoint.remove(key);
        } else {
          stateAtRewindPoint[key] = value;
        }
      });
    }

    final Map<String, Object?> rewindStateDelta = <String, Object?>{};
    final Map<String, Object?> currentState = session.state;

    stateAtRewindPoint.forEach((String key, Object? valueAtRewind) {
      if (!currentState.containsKey(key) ||
          currentState[key] != valueAtRewind) {
        rewindStateDelta[key] = valueAtRewind;
      }
    });

    for (final String key in currentState.keys) {
      if (key.startsWith('app:') || key.startsWith('user:')) {
        continue;
      }
      if (!stateAtRewindPoint.containsKey(key)) {
        rewindStateDelta[key] = null;
      }
    }

    return rewindStateDelta;
  }

  Future<Map<String, int>> _computeArtifactDeltaForRewind(
    Session session,
    int rewindEventIndex,
  ) async {
    final BaseArtifactService? service = artifactService;
    if (service == null) {
      return <String, int>{};
    }

    final Map<String, int> versionsAtRewindPoint = <String, int>{};
    for (int i = 0; i < rewindEventIndex; i += 1) {
      versionsAtRewindPoint.addAll(session.events[i].actions.artifactDelta);
    }

    final Map<String, int> currentVersions = <String, int>{};
    for (final Event event in session.events) {
      currentVersions.addAll(event.actions.artifactDelta);
    }

    final Map<String, int> rewindArtifactDelta = <String, int>{};

    for (final MapEntry<String, int> entry in currentVersions.entries) {
      final String filename = entry.key;
      final int vn = entry.value;

      if (filename.startsWith('user:')) {
        continue;
      }

      final int? vt = versionsAtRewindPoint[filename];
      if (vt == vn) {
        continue;
      }

      rewindArtifactDelta[filename] = vn + 1;

      Part artifact;
      if (vt == null) {
        artifact = Part();
      } else {
        artifact =
            await service.loadArtifact(
              appName: appName,
              userId: session.userId,
              sessionId: session.id,
              filename: filename,
              version: vt,
            ) ??
            Part();
      }

      await service.saveArtifact(
        appName: appName,
        userId: session.userId,
        sessionId: session.id,
        filename: filename,
        artifact: artifact,
      );
    }

    return rewindArtifactDelta;
  }

  Stream<Event> runLive({
    required LiveRequestQueue liveRequestQueue,
    String? userId,
    String? sessionId,
    Session? session,
    RunConfig? runConfig,
  }) async* {
    final RunConfig config = runConfig ?? RunConfig();
    config.responseModalities ??= <String>['AUDIO'];
    if (agent.subAgents.isNotEmpty) {
      if (config.responseModalities!.contains('AUDIO') &&
          config.outputAudioTranscription == null) {
        config.outputAudioTranscription = <String, Object?>{};
      }
      config.inputAudioTranscription ??= <String, Object?>{};
    }

    if (session == null) {
      if (userId == null || sessionId == null) {
        throw ArgumentError(
          'Either session or both userId and sessionId are required.',
        );
      }
      session = await _getOrCreateSession(userId: userId, sessionId: sessionId);
    }

    final InvocationContext context = _newInvocationContext(
      session,
      liveRequestQueue: liveRequestQueue,
      runConfig: config,
    );

    context.agent = _findAgentToRun(session, agent);

    await for (final Event event in _execWithPlugin(
      invocationContext: context,
      session: session,
      execute: (InvocationContext ctx) => ctx.agent.runLive(ctx),
      isLiveCall: true,
    )) {
      yield event;
    }
  }

  Future<List<Event>> runDebug(
    Object userMessages, {
    String userId = 'debug_user_id',
    String sessionId = 'debug_session_id',
    RunConfig? runConfig,
    bool quiet = false,
  }) async {
    Session? session = await sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );

    session ??= await sessionService.createSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );

    final List<String> messages;
    if (userMessages is String) {
      messages = <String>[userMessages];
    } else if (userMessages is List<String>) {
      messages = List<String>.from(userMessages);
    } else if (userMessages is List) {
      messages = userMessages.map((dynamic item) => '$item').toList();
    } else {
      throw ArgumentError(
        'userMessages must be String or List<String>. Received: ${userMessages.runtimeType}',
      );
    }

    final List<Event> events = <Event>[];
    for (final String message in messages) {
      if (!quiet) {
        // ignore: avoid_print
        print('User > $message');
      }

      await for (final Event event in runAsync(
        userId: userId,
        sessionId: session.id,
        newMessage: Content.userText(message),
        runConfig: runConfig,
      )) {
        events.add(event);
      }
    }

    return events;
  }

  Future<InvocationContext> _setupContextForNewInvocation({
    required Session session,
    required Content newMessage,
    required RunConfig runConfig,
    Map<String, Object?>? stateDelta,
  }) async {
    final InvocationContext context = _newInvocationContext(
      session,
      newMessage: newMessage,
      runConfig: runConfig,
    );

    await _handleNewMessage(
      session: session,
      newMessage: newMessage,
      context: context,
      runConfig: runConfig,
      stateDelta: stateDelta,
    );

    context.agent = _findAgentToRun(session, agent);
    return context;
  }

  Future<InvocationContext> _setupContextForResumedInvocation({
    required Session session,
    required String invocationId,
    required Content? newMessage,
    required RunConfig runConfig,
    Map<String, Object?>? stateDelta,
  }) async {
    if (!resumabilityConfigOrDefault) {
      throw StateError(
        'invocationId is provided but the app is not resumable.',
      );
    }

    if (session.events.isEmpty) {
      throw StateError('Session ${session.id} has no events to resume.');
    }

    final Content? userMessage =
        newMessage ??
        _findUserMessageForInvocation(session.events, invocationId);
    if (userMessage == null) {
      throw StateError(
        'No user message available for invocation: $invocationId',
      );
    }

    final InvocationContext context = _newInvocationContext(
      session,
      invocationId: invocationId,
      newMessage: userMessage,
      runConfig: runConfig,
    );

    if (newMessage != null) {
      await _handleNewMessage(
        session: session,
        newMessage: userMessage,
        context: context,
        runConfig: runConfig,
        stateDelta: stateDelta,
      );
    }

    context.populateInvocationAgentStates();
    if (!context.endOfAgents.containsKey(agent.name)) {
      context.agent = _findAgentToRun(session, agent);
    }

    return context;
  }

  bool get resumabilityConfigOrDefault {
    return resumabilityConfig?.isResumable ?? false;
  }

  String? _resolveInvocationId({
    required Session session,
    required Content? newMessage,
    required String? invocationId,
  }) {
    final List<FunctionResponse> responses = _functionResponsesFromContent(
      newMessage,
    );
    if (responses.isEmpty) {
      return invocationId;
    }

    final String? functionCallId = responses.first.id;
    if (functionCallId == null || functionCallId.isEmpty) {
      return invocationId;
    }

    final Event? functionCallEvent = _findEventByFunctionCallId(
      session.events,
      functionCallId,
    );
    if (functionCallEvent == null) {
      throw ArgumentError(
        'Function call event not found for function response id: $functionCallId',
      );
    }

    return functionCallEvent.invocationId;
  }

  List<FunctionResponse> _functionResponsesFromContent(Content? content) {
    if (content == null) {
      return const <FunctionResponse>[];
    }
    final List<FunctionResponse> responses = <FunctionResponse>[];
    for (final Part part in content.parts) {
      final FunctionResponse? response = part.functionResponse;
      if (response != null) {
        responses.add(response);
      }
    }
    return responses;
  }

  Event? _findEventByFunctionCallId(List<Event> events, String functionCallId) {
    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      for (final FunctionCall call in event.getFunctionCalls()) {
        if (call.id == functionCallId) {
          return event;
        }
      }
    }
    return null;
  }

  Content? _findUserMessageForInvocation(
    List<Event> events,
    String invocationId,
  ) {
    for (final Event event in events) {
      if (event.invocationId == invocationId &&
          event.author == 'user' &&
          event.content != null &&
          event.content!.parts.isNotEmpty &&
          event.content!.parts.first.text != null) {
        return event.content!.copyWith();
      }
    }
    return null;
  }

  InvocationContext _newInvocationContext(
    Session session, {
    String? invocationId,
    Content? newMessage,
    LiveRequestQueue? liveRequestQueue,
    RunConfig? runConfig,
  }) {
    return InvocationContext(
      artifactService: artifactService,
      sessionService: sessionService,
      memoryService: memoryService,
      credentialService: credentialService,
      contextCacheConfig: contextCacheConfig,
      invocationId: invocationId ?? _newInvocationContextId(),
      agent: agent,
      session: session,
      userContent: newMessage,
      liveRequestQueue: liveRequestQueue,
      runConfig: runConfig ?? RunConfig(),
      resumabilityConfig: resumabilityConfig,
      eventsCompactionConfig: app?.eventsCompactionConfig,
      pluginManager: pluginManager,
    );
  }

  Future<void> _handleNewMessage({
    required Session session,
    required Content newMessage,
    required InvocationContext context,
    required RunConfig runConfig,
    Map<String, Object?>? stateDelta,
  }) async {
    final Content? modifiedMessage = await context.pluginManager
        .runOnUserMessageCallback(
          userMessage: newMessage,
          invocationContext: context,
        );

    final Content finalMessage = modifiedMessage ?? newMessage;
    context.userContent = finalMessage;

    await _appendNewMessageToSession(
      session: session,
      newMessage: finalMessage,
      context: context,
      stateDelta: stateDelta,
    );
  }

  Future<void> _appendNewMessageToSession({
    required Session session,
    required Content newMessage,
    required InvocationContext context,
    Map<String, Object?>? stateDelta,
  }) async {
    if (newMessage.parts.isEmpty) {
      throw ArgumentError('No parts in the newMessage.');
    }

    final Event event = Event(
      invocationId: context.invocationId,
      author: 'user',
      content: newMessage,
      actions: stateDelta == null
          ? EventActions()
          : EventActions(stateDelta: stateDelta),
    );

    if (context.runConfig?.customMetadata != null) {
      event.customMetadata = <String, dynamic>{
        ...context.runConfig!.customMetadata!,
        ...(event.customMetadata ?? <String, dynamic>{}),
      };
    }

    final Event? matchingCall = context.findMatchingFunctionCall(event);
    if (matchingCall != null) {
      event.branch = matchingCall.branch;
    }

    await sessionService.appendEvent(session: session, event: event);
  }

  Stream<Event> _execWithPlugin({
    required InvocationContext invocationContext,
    required Session session,
    required Stream<Event> Function(InvocationContext context) execute,
    required bool isLiveCall,
  }) async* {
    final Content? earlyExit = await invocationContext.pluginManager
        .runBeforeRunCallback(invocationContext: invocationContext);

    if (earlyExit != null) {
      final Event event = Event(
        invocationId: invocationContext.invocationId,
        author: 'model',
        content: earlyExit,
      );
      _applyRunConfigCustomMetadata(event, invocationContext.runConfig);
      if (_shouldAppendEvent(event, isLiveCall)) {
        await sessionService.appendEvent(session: session, event: event);
      }
      yield event;
    } else {
      final List<Event> bufferedEvents = <Event>[];
      bool isTranscribing = false;

      await for (final Event event in execute(invocationContext)) {
        _applyRunConfigCustomMetadata(event, invocationContext.runConfig);

        if (isLiveCall) {
          if (event.partial == true && _isTranscription(event)) {
            isTranscribing = true;
          }

          if (isTranscribing && _isToolCallOrResponse(event)) {
            bufferedEvents.add(event);
            continue;
          }

          if (event.partial != true) {
            if (_isTranscription(event) &&
                (_hasNonEmptyTranscriptionText(event.inputTranscription) ||
                    _hasNonEmptyTranscriptionText(event.outputTranscription))) {
              isTranscribing = false;
              if (_shouldAppendEvent(event, isLiveCall)) {
                await sessionService.appendEvent(session: session, event: event);
              }

              for (final Event buffered in bufferedEvents) {
                if (_shouldAppendEvent(buffered, isLiveCall)) {
                  await sessionService.appendEvent(
                    session: session,
                    event: buffered,
                  );
                }
                yield buffered;
              }
              bufferedEvents.clear();
            } else if (_shouldAppendEvent(event, isLiveCall)) {
              await sessionService.appendEvent(session: session, event: event);
            }
          }
        } else if (event.partial != true &&
            _shouldAppendEvent(event, isLiveCall)) {
          await sessionService.appendEvent(session: session, event: event);
        }

        final Event? modified = await invocationContext.pluginManager
            .runOnEventCallback(
              invocationContext: invocationContext,
              event: event,
            );

        if (modified != null) {
          _applyRunConfigCustomMetadata(modified, invocationContext.runConfig);
          yield modified;
        } else {
          yield event;
        }
      }
    }

    await invocationContext.pluginManager.runAfterRunCallback(
      invocationContext: invocationContext,
    );
  }

  BaseAgent _findAgentToRun(Session session, BaseAgent rootAgent) {
    final Event? matchingFunctionCall = flow_functions.findMatchingFunctionCall(
      session.events,
    );
    if (matchingFunctionCall != null &&
        matchingFunctionCall.author.isNotEmpty) {
      final BaseAgent? agent = rootAgent.findAgent(matchingFunctionCall.author);
      if (agent != null) {
        return agent;
      }
    }

    for (final Event event in session.events.reversed) {
      if (event.author == 'user') {
        continue;
      }
      if (event.actions.agentState != null ||
          event.actions.endOfAgent == true) {
        continue;
      }

      if (event.author == rootAgent.name) {
        return rootAgent;
      }

      final BaseAgent? candidate = rootAgent.findSubAgent(event.author);
      if (candidate == null) {
        continue;
      }

      if (_isTransferableAcrossAgentTree(candidate)) {
        return candidate;
      }
    }

    return rootAgent;
  }

  bool _isTransferableAcrossAgentTree(BaseAgent agentToRun) {
    BaseAgent? current = agentToRun;
    while (current != null) {
      if (current is! LlmAgent) {
        return false;
      }
      if (current.disallowTransferToParent) {
        return false;
      }
      current = current.parentAgent;
    }
    return true;
  }

  bool _shouldAppendEvent(Event event, bool isLiveCall) {
    if (!isLiveCall) {
      return true;
    }
    if (_isLiveModelAudioEventWithInlineData(event)) {
      return false;
    }
    return true;
  }

  bool _isLiveModelAudioEventWithInlineData(Event event) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return false;
    }
    for (final Part part in content.parts) {
      final InlineData? inlineData = part.inlineData;
      if (inlineData != null && inlineData.mimeType.startsWith('audio/')) {
        return true;
      }
    }
    return false;
  }

  void _applyRunConfigCustomMetadata(Event event, RunConfig? runConfig) {
    if (runConfig?.customMetadata == null ||
        runConfig!.customMetadata!.isEmpty) {
      return;
    }

    event.customMetadata = <String, dynamic>{
      ...runConfig.customMetadata!,
      ...(event.customMetadata ?? <String, dynamic>{}),
    };
  }

  Set<BaseToolset> _collectToolsets(BaseAgent agent) {
    final Set<BaseToolset> toolsets = <BaseToolset>{};

    if (agent is LlmAgent) {
      for (final Object tool in agent.tools) {
        if (tool is BaseToolset) {
          toolsets.add(tool);
        }
      }
    }

    for (final BaseAgent subAgent in agent.subAgents) {
      toolsets.addAll(_collectToolsets(subAgent));
    }

    return toolsets;
  }

  Future<void> _cleanupToolsets(Set<BaseToolset> toolsets) async {
    for (final BaseToolset toolset in toolsets) {
      await toolset.close();
    }
  }

  Future<void> close() async {
    await _cleanupToolsets(_collectToolsets(agent));
    await pluginManager.close();
  }
}

class InMemoryRunner extends Runner {
  InMemoryRunner({
    BaseAgent? agent,
    String? appName,
    List<BasePlugin>? plugins,
    App? app,
    Duration? pluginCloseTimeout,
  }) : super(
         app: app,
         appName: app == null ? (appName ?? 'InMemoryRunner') : appName,
         agent: agent,
         plugins: plugins,
         artifactService: InMemoryArtifactService(),
         sessionService: InMemorySessionService(),
         pluginCloseTimeout: pluginCloseTimeout,
       );
}

class _RunnerParams {
  _RunnerParams({
    required this.appName,
    required this.agent,
    this.contextCacheConfig,
    this.resumabilityConfig,
  });

  final String appName;
  final BaseAgent agent;
  final Object? contextCacheConfig;
  final ResumabilityConfig? resumabilityConfig;
}

String _newInvocationContextId() {
  return 'invocation_${DateTime.now().microsecondsSinceEpoch}';
}
