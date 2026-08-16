/// Runner implementation that orchestrates agent execution.
library;

import 'dart:async';

import '../agents/abort_signal.dart';
import '../agents/base_agent.dart';
import '../agents/invocation_context.dart';
import '../agents/live_request_queue.dart';
import '../agents/llm_agent.dart';
import '../agents/run_config.dart';
import '../apps/app.dart';
import '../apps/compaction.dart' as app_compaction;
import '../artifacts/base_artifact_service.dart';
import '../artifacts/in_memory_artifact_service.dart';
import '../errors/session_not_found_error.dart';
import '../events/event.dart';
import '../events/event_actions.dart';
import '../flows/llm_flows/persist_barrier.dart';
import '../flows/llm_flows/functions.dart' as flow_functions;
import '../plugins/base_plugin.dart';
import '../plugins/plugin_manager.dart';
import '../sessions/base_session_service.dart';
import '../sessions/in_memory_session_service.dart';
import '../sessions/session.dart';
import '../tools/base_toolset.dart';
import '../types/content.dart';

/// Best-effort on_run_error notification; never masks the original error.
///
/// on_run_error_callback is notification-only: the triggering [error] is
/// always re-raised by the caller, so any exception from the callback itself
/// is suppressed.
Future<void> _notifyRunError(
  PluginManager pluginManager,
  InvocationContext invocationContext,
  Object error,
) async {
  try {
    await pluginManager.runOnRunErrorCallback(
      invocationContext: invocationContext,
      error: error,
    );
  } catch (_) {
    // Suppress so the original run error propagates.
  }
}

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

bool _isEmptyEventActions(EventActions actions) {
  return actions.skipSummarization == null &&
      actions.stateDelta.isEmpty &&
      actions.artifactDelta.isEmpty &&
      actions.transferToAgent == null &&
      actions.escalate == null &&
      actions.requestedAuthConfigs.isEmpty &&
      actions.requestedToolConfirmations.isEmpty &&
      actions.compaction == null &&
      actions.endOfAgent == null &&
      actions.agentState == null &&
      actions.rewindBeforeInvocationId == null &&
      actions.renderUiWidgets.isEmpty;
}

/// Coordinates session lifecycle, plugins, and agent execution.
class Runner {
  /// Creates a runner from an [app] or direct [appName]/[agent] pair.
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

  /// Optional app container used to initialize runner defaults.
  final App? app;

  /// Effective application name used for session lookups.
  late String appName;

  /// Root agent executed by this runner.
  late BaseAgent agent;

  /// Artifact persistence service, if configured.
  final BaseArtifactService? artifactService;

  /// Session service used for reads/writes during execution.
  final BaseSessionService sessionService;

  /// Memory service implementation or adapter payload.
  final Object? memoryService;

  /// Credential service implementation used by auth-aware tools.
  final Object? credentialService;

  /// Plugin manager orchestrating lifecycle and callbacks.
  final PluginManager pluginManager;

  /// Whether missing sessions should be created automatically.
  final bool autoCreateSession;

  /// Optional context-cache configuration forwarded to invocation context.
  Object? contextCacheConfig;

  /// Optional resumability policy for invocation replay/resume.
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
    GetSessionConfig? getSessionConfig,
  }) async {
    Session? session = await sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: getSessionConfig,
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

  /// Convenience wrapper that forwards to [runAsync].
  Stream<Event> run({
    required String userId,
    required String sessionId,
    required Content newMessage,
    RunConfig? runConfig,
    AdkAbortSignal? abortSignal,
  }) {
    return runAsync(
      userId: userId,
      sessionId: sessionId,
      newMessage: newMessage,
      runConfig: runConfig,
      abortSignal: abortSignal,
    );
  }

  /// Executes a single invocation and streams emitted events.
  Stream<Event> runAsync({
    required String userId,
    required String sessionId,
    String? invocationId,
    Content? newMessage,
    Map<String, Object?>? stateDelta,
    RunConfig? runConfig,
    AdkAbortSignal? abortSignal,
  }) async* {
    final RunConfig config = runConfig ?? RunConfig();
    if (abortSignal?.aborted ?? false) {
      return;
    }

    if (newMessage != null &&
        (newMessage.role == null || newMessage.role!.isEmpty)) {
      newMessage.role = 'user';
    }

    final Session session = await _getOrCreateSession(
      userId: userId,
      sessionId: sessionId,
      getSessionConfig: config.getSessionConfig,
    );
    if (abortSignal?.aborted ?? false) {
      return;
    }

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
        abortSignal: abortSignal,
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
          abortSignal: abortSignal,
        );
      } else {
        context = await _setupContextForResumedInvocation(
          session: session,
          invocationId: resolvedInvocationId,
          newMessage: newMessage,
          stateDelta: stateDelta,
          runConfig: config,
          abortSignal: abortSignal,
        );
        if (context.endOfAgents[context.agent.name] == true) {
          return;
        }
      }
    }

    if (context.isAborted) {
      return;
    }

    final Set<BaseToolset> toolsets = _collectToolsets(agent);
    try {
      await for (final Event event in _execWithPlugin(
        invocationContext: context,
        session: session,
        execute: (InvocationContext ctx) => ctx.agent.runAsync(ctx),
        isLiveCall: false,
      )) {
        yield event;
      }

      if (app != null && app!.eventsCompactionConfig != null) {
        // Compaction runs on the success path. A failure here is an unhandled
        // runner error, so notify on_run_error_callback once and re-raise.
        // Compaction yields its event instead of appending it; the runner is
        // the single append site so persistence stays at the runtime's
        // synchronization point.
        try {
          await for (final Event compactionEvent
              in app_compaction.runCompactionForSlidingWindow(
                app: app!,
                session: context.session,
                sessionService: sessionService,
                skipTokenCompaction: context.tokenCompactionChecked,
              )) {
            await sessionService.appendEvent(
              session: context.session,
              event: compactionEvent,
            );
          }
        } catch (error) {
          await _notifyRunError(context.pluginManager, context, error);
          rethrow;
        }
      }
    } finally {
      await _cleanupToolsets(toolsets, ignoreErrors: true);
    }
  }

  /// Rewinds session state and artifact versions to before an invocation.
  Future<void> rewindAsync({
    required String userId,
    required String sessionId,
    required String rewindBeforeInvocationId,
    RunConfig? runConfig,
  }) async {
    final RunConfig config = runConfig ?? RunConfig();
    final Session session = await _getOrCreateSession(
      userId: userId,
      sessionId: sessionId,
      getSessionConfig: config.getSessionConfig,
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

  /// Executes live bidirectional agent streaming with [liveRequestQueue].
  Stream<Event> runLive({
    required LiveRequestQueue liveRequestQueue,
    String? userId,
    String? sessionId,
    Session? session,
    RunConfig? runConfig,
    AdkAbortSignal? abortSignal,
  }) async* {
    final RunConfig config = runConfig ?? RunConfig();
    if (abortSignal?.aborted ?? false) {
      return;
    }
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
      session = await _getOrCreateSession(
        userId: userId,
        sessionId: sessionId,
        getSessionConfig: config.getSessionConfig,
      );
      if (abortSignal?.aborted ?? false) {
        return;
      }
    }

    final InvocationContext context = _newInvocationContext(
      session,
      liveRequestQueue: liveRequestQueue,
      runConfig: config,
      abortSignal: abortSignal,
    );

    context.agent = _findAgentToRun(context.session, agent);
    if (context.isAborted) {
      return;
    }

    final Set<BaseToolset> toolsets = _collectToolsets(agent);
    try {
      await for (final Event event in _execWithPlugin(
        invocationContext: context,
        session: session,
        execute: (InvocationContext ctx) => ctx.agent.runLive(ctx),
        isLiveCall: true,
      )) {
        yield event;
      }
    } finally {
      await _cleanupToolsets(toolsets, ignoreErrors: true);
    }
  }

  /// Runs one or more debug user messages and returns collected events.
  Future<List<Event>> runDebug(
    Object userMessages, {
    String userId = 'debug_user_id',
    String sessionId = 'debug_session_id',
    RunConfig? runConfig,
    bool quiet = false,
  }) async {
    final RunConfig config = runConfig ?? RunConfig();
    Session? session = await sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config.getSessionConfig,
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
        runConfig: config,
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
    AdkAbortSignal? abortSignal,
  }) async {
    final InvocationContext context = _newInvocationContext(
      session,
      newMessage: newMessage,
      runConfig: runConfig,
      abortSignal: abortSignal,
    );

    await _handleNewMessage(
      session: session,
      newMessage: newMessage,
      context: context,
      runConfig: runConfig,
      stateDelta: stateDelta,
    );
    if (context.isAborted) {
      return context;
    }

    context.agent = _findAgentToRun(context.session, agent);
    return context;
  }

  Future<InvocationContext> _setupContextForResumedInvocation({
    required Session session,
    required String invocationId,
    required Content? newMessage,
    required RunConfig runConfig,
    Map<String, Object?>? stateDelta,
    AdkAbortSignal? abortSignal,
  }) async {
    if (!resumabilityConfigOrDefault) {
      throw StateError(
        'invocationId is provided but the app is not resumable.',
      );
    }

    if (session.events.isEmpty) {
      throw StateError('Session ${session.id} has no events to resume.');
    }

    final Content? originalUserContent = _findUserMessageForInvocation(
      session.events,
      invocationId,
    );
    final Content? contextUserContent = originalUserContent ?? newMessage;
    if (contextUserContent == null) {
      throw StateError(
        'No user message available for invocation: $invocationId',
      );
    }

    final InvocationContext context = _newInvocationContext(
      session,
      invocationId: invocationId,
      newMessage: contextUserContent,
      runConfig: runConfig,
      abortSignal: abortSignal,
    );

    if (newMessage != null) {
      await _handleNewMessage(
        session: session,
        newMessage: newMessage,
        context: context,
        runConfig: runConfig,
        stateDelta: stateDelta,
      );
      if (originalUserContent != null) {
        context.userContent = originalUserContent.copyWith();
      }
      if (context.isAborted) {
        return context;
      }
    }

    context.populateInvocationAgentStates();
    if (!context.endOfAgents.containsKey(agent.name)) {
      context.agent = _findAgentToRun(context.session, agent);
    }

    return context;
  }

  /// Whether this runner should support invocation resumption.
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
    AdkAbortSignal? abortSignal,
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
      abortSignal: abortSignal,
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
    if (context.isAborted) {
      return;
    }
    if (stateDelta != null && stateDelta.isNotEmpty) {
      stateDelta.forEach((String key, Object? value) {
        session.state[key] = value;
      });
    }
    // Failures in these setup hooks (on_user_message_callback and the
    // user-event session append) are part of runner execution even though they
    // run before the main event loop, so notify on_run_error_callback.
    // Notification-only; the original exception is always re-raised.
    try {
      final Content? modifiedMessage = await context.pluginManager
          .runOnUserMessageCallback(
            userMessage: newMessage,
            invocationContext: context,
          );
      if (context.isAborted) {
        return;
      }

      final Content finalMessage = modifiedMessage ?? newMessage;
      context.userContent = finalMessage;

      await _appendNewMessageToSession(
        session: session,
        newMessage: finalMessage,
        context: context,
        stateDelta: stateDelta,
      );
    } catch (error) {
      await _notifyRunError(context.pluginManager, context, error);
      rethrow;
    }
  }

  Future<void> _appendNewMessageToSession({
    required Session session,
    required Content newMessage,
    required InvocationContext context,
    Map<String, Object?>? stateDelta,
  }) async {
    if (context.isAborted) {
      return;
    }
    if (newMessage.parts.isEmpty) {
      throw ArgumentError('No parts in the newMessage.');
    }
    // Reject user-authored function calls: they would bypass the LLM and
    // directly execute arbitrary registered tools.
    if (newMessage.parts.any((Part part) => part.functionCall != null)) {
      throw ArgumentError('User message cannot contain function calls.');
    }

    final Event event = Event(
      invocationId: context.invocationId,
      author: 'user',
      isolationScope: context.isolationScope,
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

    context.stampEventBranchContext(event);

    await _appendEventWithPersistBarrier(context, event);
  }

  Stream<Event> _execWithPlugin({
    required InvocationContext invocationContext,
    required Session session,
    required Stream<Event> Function(InvocationContext context) execute,
    required bool isLiveCall,
  }) async* {
    if (invocationContext.isAborted) {
      return;
    }

    // Buffer produced events so the error handler wraps only production (the
    // before_run callback, early-exit, and the main execution loop), not the
    // consumer-side yield. Failures here notify on_run_error_callback once and
    // re-raise; the notification is best-effort and never masks the error.
    final StreamController<Event> output = StreamController<Event>();

    Future<void> produce() async {
      try {
        final Content? earlyExit = await invocationContext.pluginManager
            .runBeforeRunCallback(invocationContext: invocationContext);
        if (invocationContext.isAborted) {
          return;
        }

        if (earlyExit != null) {
          final Event event = Event(
            invocationId: invocationContext.invocationId,
            author: 'model',
            branch: invocationContext.branch,
            isolationScope: invocationContext.isolationScope,
            content: earlyExit,
          );
          _applyRunConfigCustomMetadata(event, invocationContext.runConfig);
          if (invocationContext.isAborted) {
            return;
          }
          if (_shouldAppendEvent(event, isLiveCall)) {
            await _appendEventWithPersistBarrier(invocationContext, event);
          }
          if (invocationContext.isAborted) {
            return;
          }
          output.add(event);
        } else {
          PersistBarrier.enable(invocationContext);
          final List<({Event event, String? barrierEventId})> bufferedEvents =
              <({Event event, String? barrierEventId})>[];
          bool isTranscribing = false;

          await for (final Event event in execute(invocationContext)) {
            if (invocationContext.isAborted) {
              return;
            }
            event.isolationScope ??= invocationContext.isolationScope;
            _applyRunConfigCustomMetadata(event, invocationContext.runConfig);
            final Event? modified = await invocationContext.pluginManager
                .runOnEventCallback(
                  invocationContext: invocationContext,
                  event: event,
                );
            if (invocationContext.isAborted) {
              return;
            }
            final Event outputEvent = _buildOutputEvent(
              originalEvent: event,
              modifiedEvent: modified,
              runConfig: invocationContext.runConfig,
            );

            if (isLiveCall) {
              if (event.partial == true && _isTranscription(event)) {
                isTranscribing = true;
              }

              if (isTranscribing && _isToolCallOrResponse(event)) {
                bufferedEvents.add((
                  event: outputEvent,
                  barrierEventId: event.id,
                ));
                continue;
              }

              if (event.partial != true) {
                if (_isTranscription(event) &&
                    (_hasNonEmptyTranscriptionText(event.inputTranscription) ||
                        _hasNonEmptyTranscriptionText(
                          event.outputTranscription,
                        ))) {
                  isTranscribing = false;
                  if (_shouldAppendEvent(outputEvent, isLiveCall)) {
                    await _appendEventWithPersistBarrier(
                      invocationContext,
                      outputEvent,
                      barrierEventId: event.id,
                    );
                    if (invocationContext.isAborted) {
                      return;
                    }
                  }

                  for (final buffered in bufferedEvents) {
                    if (invocationContext.isAborted) {
                      return;
                    }
                    if (_shouldAppendEvent(buffered.event, isLiveCall)) {
                      await _appendEventWithPersistBarrier(
                        invocationContext,
                        buffered.event,
                        barrierEventId: buffered.barrierEventId,
                      );
                      if (invocationContext.isAborted) {
                        return;
                      }
                    }
                    output.add(buffered.event);
                  }
                  bufferedEvents.clear();
                } else if (_shouldAppendEvent(outputEvent, isLiveCall)) {
                  await _appendEventWithPersistBarrier(
                    invocationContext,
                    outputEvent,
                    barrierEventId: event.id,
                  );
                  if (invocationContext.isAborted) {
                    return;
                  }
                }
              }
            } else if (event.partial != true &&
                _shouldAppendEvent(outputEvent, isLiveCall)) {
              await _appendEventWithPersistBarrier(
                invocationContext,
                outputEvent,
                barrierEventId: event.id,
              );
              if (invocationContext.isAborted) {
                return;
              }
            }

            if (invocationContext.isAborted) {
              return;
            }
            output.add(outputEvent);
          }
        }
      } catch (error) {
        // Notify plugins of the unhandled execution error. Covers failures in
        // before_run_callback, early-exit, and the main execution loop.
        // Notification-only; the original exception is always re-raised.
        await _notifyRunError(
          invocationContext.pluginManager,
          invocationContext,
          error,
        );
        rethrow;
      }
    }

    // Drive production and forward events as they arrive. Errors from the
    // producer surface through the stream after on_run_error notification.
    unawaited(
      produce().then(
        (_) => output.close(),
        onError: (Object error, StackTrace stackTrace) {
          output.addError(error, stackTrace);
          return output.close();
        },
      ),
    );

    yield* output.stream;

    if (invocationContext.isAborted) {
      return;
    }

    // Step: run the after_run callbacks (success path only). A failure here
    // (e.g. an after_run plugin raising, surfaced by PluginManager as a
    // PluginManagerException) is still an unhandled runner error, so notify
    // on_run_error_callback once and re-raise. on_run_error is
    // notification-only, so there is no recursive notification.
    try {
      await invocationContext.pluginManager.runAfterRunCallback(
        invocationContext: invocationContext,
      );
    } catch (error) {
      await _notifyRunError(
        invocationContext.pluginManager,
        invocationContext,
        error,
      );
      rethrow;
    }
    if (invocationContext.isAborted) {
      return;
    }
  }

  Future<void> _appendEventWithPersistBarrier(
    InvocationContext context,
    Event event, {
    String? barrierEventId,
  }) async {
    if (context.isAborted) {
      return;
    }
    try {
      await sessionService.appendEvent(session: context.session, event: event);
      PersistBarrier.markPersisted(context, event.id);
      if (barrierEventId != event.id) {
        PersistBarrier.markPersisted(context, barrierEventId);
      }
    } catch (error, stackTrace) {
      PersistBarrier.markFailed(context, event.id, error, stackTrace);
      if (barrierEventId != event.id) {
        PersistBarrier.markFailed(context, barrierEventId, error, stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Event _buildOutputEvent({
    required Event originalEvent,
    required Event? modifiedEvent,
    required RunConfig? runConfig,
  }) {
    if (modifiedEvent == null) {
      return originalEvent;
    }

    final Event outputEvent = originalEvent.copyWith(
      author: modifiedEvent.author.isEmpty
          ? originalEvent.author
          : modifiedEvent.author,
      actions: _isEmptyEventActions(modifiedEvent.actions)
          ? originalEvent.actions.copyWith()
          : modifiedEvent.actions.copyWith(),
      longRunningToolIds: modifiedEvent.longRunningToolIds == null
          ? (originalEvent.longRunningToolIds == null
                ? null
                : Set<String>.from(originalEvent.longRunningToolIds!))
          : Set<String>.from(modifiedEvent.longRunningToolIds!),
      branch: modifiedEvent.branch ?? originalEvent.branch,
      isolationScope:
          modifiedEvent.isolationScope ?? originalEvent.isolationScope,
      modelVersion: modifiedEvent.modelVersion ?? originalEvent.modelVersion,
      content: modifiedEvent.content?.copyWith() ?? originalEvent.content,
      partial: modifiedEvent.partial ?? originalEvent.partial,
      turnComplete: modifiedEvent.turnComplete ?? originalEvent.turnComplete,
      finishReason: modifiedEvent.finishReason ?? originalEvent.finishReason,
      errorCode: modifiedEvent.errorCode ?? originalEvent.errorCode,
      errorMessage: modifiedEvent.errorMessage ?? originalEvent.errorMessage,
      interrupted: modifiedEvent.interrupted ?? originalEvent.interrupted,
      customMetadata: modifiedEvent.customMetadata == null
          ? (originalEvent.customMetadata == null
                ? null
                : Map<String, dynamic>.from(originalEvent.customMetadata!))
          : Map<String, dynamic>.from(modifiedEvent.customMetadata!),
      usageMetadata: modifiedEvent.usageMetadata ?? originalEvent.usageMetadata,
      inputTranscription:
          modifiedEvent.inputTranscription ?? originalEvent.inputTranscription,
      outputTranscription:
          modifiedEvent.outputTranscription ??
          originalEvent.outputTranscription,
      avgLogprobs: modifiedEvent.avgLogprobs ?? originalEvent.avgLogprobs,
      logprobsResult:
          modifiedEvent.logprobsResult ?? originalEvent.logprobsResult,
      cacheMetadata: modifiedEvent.cacheMetadata ?? originalEvent.cacheMetadata,
      citationMetadata:
          modifiedEvent.citationMetadata ?? originalEvent.citationMetadata,
      groundingMetadata:
          modifiedEvent.groundingMetadata ?? originalEvent.groundingMetadata,
      interactionId: modifiedEvent.interactionId ?? originalEvent.interactionId,
      liveSessionId: modifiedEvent.liveSessionId ?? originalEvent.liveSessionId,
      liveSessionResumptionUpdate:
          modifiedEvent.liveSessionResumptionUpdate ??
          originalEvent.liveSessionResumptionUpdate,
      goAway: modifiedEvent.goAway ?? originalEvent.goAway,
    );
    _applyRunConfigCustomMetadata(outputEvent, runConfig);
    return outputEvent;
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
    if (_isLiveModelMediaEventWithInlineData(event)) {
      return false;
    }
    return true;
  }

  bool _isLiveModelMediaEventWithInlineData(Event event) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return false;
    }
    for (final Part part in content.parts) {
      final InlineData? inlineData = part.inlineData;
      if (inlineData != null && _isMediaMimeType(inlineData.mimeType)) {
        return true;
      }
    }
    return false;
  }

  bool _isMediaMimeType(String mimeType) {
    return mimeType.startsWith('audio/') ||
        mimeType.startsWith('video/') ||
        mimeType.startsWith('image/');
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

  Future<void> _cleanupToolsets(
    Set<BaseToolset> toolsets, {
    bool ignoreErrors = false,
  }) async {
    for (final BaseToolset toolset in toolsets) {
      if (!ignoreErrors) {
        await toolset.close();
        continue;
      }
      try {
        await toolset.close();
      } catch (_) {
        // Invocation cleanup should not mask agent execution results.
      }
    }
  }

  /// Closes toolsets and plugin manager resources.
  Future<void> close() async {
    await _cleanupToolsets(_collectToolsets(agent));
    await pluginManager.close();
    await sessionService.flush();
  }
}

/// Runner wired with in-memory session and artifact services.
class InMemoryRunner extends Runner {
  /// Creates an in-memory runner.
  InMemoryRunner({
    super.agent,
    String? appName,
    super.plugins,
    super.app,
    super.pluginCloseTimeout,
  }) : super(
         appName: app == null ? (appName ?? 'InMemoryRunner') : appName,
         artifactService: InMemoryArtifactService(),
         sessionService: InMemorySessionService(),
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
