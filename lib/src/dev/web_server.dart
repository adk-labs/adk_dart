import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../a2a/utils/agent_card_builder.dart';
import '../agents/live_request_queue.dart';
import '../agents/run_config.dart';
import '../apps/app.dart';
import '../artifacts/base_artifact_service.dart';
import '../cli/utils/agent_loader.dart';
import '../cli/utils/base_agent_loader.dart';
import '../cli/utils/service_factory.dart';
import '../events/event.dart';
import '../events/event_actions.dart';
import '../memory/base_memory_service.dart';
import '../plugins/base_plugin.dart';
import '../plugins/context_filter_plugin.dart';
import '../plugins/debug_logging_plugin.dart';
import '../plugins/global_instruction_plugin.dart';
import '../plugins/logging_plugin.dart';
import '../plugins/multimodal_tool_results_plugin.dart';
import '../plugins/reflect_retry_tool_plugin.dart';
import '../plugins/save_files_as_artifacts_plugin.dart';
import '../runners/runner.dart';
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../sessions/schemas/v0.dart';
import '../telemetry/google_cloud.dart';
import '../telemetry/setup.dart';
import '../types/content.dart';
import '../version.dart';
import 'project.dart';
import 'runtime.dart';

Future<HttpServer> startAdkDevWebServer({
  required DevAgentRuntime runtime,
  required DevProjectConfig project,
  String agentsDir = '.',
  int port = 8000,
  InternetAddress? host,
  List<String> allowOrigins = const <String>[],
  String? sessionServiceUri,
  String? artifactServiceUri,
  String? memoryServiceUri,
  bool useLocalStorage = true,
  String? urlPrefix,
  bool autoCreateSession = false,
  bool enableWebUi = true,
  String? logoText,
  String? logoImageUrl,
  bool reload = true,
  bool reloadAgents = false,
  bool traceToCloud = false,
  bool otelToCloud = false,
  bool a2a = false,
  List<String> extraPlugins = const <String>[],
  Map<String, String>? environment,
}) async {
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'Port must be between 0 and 65535');
  }

  final _AdkDevWebContext context = await _AdkDevWebContext.create(
    runtime: runtime,
    project: project,
    agentsDir: agentsDir,
    allowOrigins: allowOrigins,
    sessionServiceUri: sessionServiceUri,
    artifactServiceUri: artifactServiceUri,
    memoryServiceUri: memoryServiceUri,
    useLocalStorage: useLocalStorage,
    urlPrefix: _normalizeUrlPrefix(urlPrefix),
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
    logoText: logoText,
    logoImageUrl: logoImageUrl,
    reload: reload,
    reloadAgents: reloadAgents,
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    a2a: a2a,
    extraPlugins: extraPlugins,
    environment: environment,
  );

  final InternetAddress resolvedHost = host ?? InternetAddress.loopbackIPv4;
  final HttpServer server = await HttpServer.bind(resolvedHost, port);
  unawaited(_handleRequests(server, context));
  return server;
}

class _ExtraPluginSpec {
  _ExtraPluginSpec({required this.raw, required this.normalizedName});

  final String raw;
  final String normalizedName;
}

class _AdkDevWebContext {
  _AdkDevWebContext({
    required this.runtime,
    required this.project,
    required this.agentsDir,
    required this.agentLoader,
    required this.sessionService,
    required this.artifactService,
    required this.memoryService,
    required this.allowOrigins,
    required this.urlPrefix,
    required this.autoCreateSession,
    required this.enableWebUi,
    required this.logoText,
    required this.logoImageUrl,
    required this.reload,
    required this.reloadAgents,
    required this.traceToCloud,
    required this.otelToCloud,
    required this.a2a,
    required this.extraPluginSpecs,
    required this.webAssetsDir,
  });

  final DevAgentRuntime runtime;
  final DevProjectConfig project;
  final String agentsDir;
  final AgentLoader agentLoader;
  final BaseSessionService sessionService;
  final BaseArtifactService artifactService;
  final BaseMemoryService memoryService;
  final List<String> allowOrigins;
  final String? urlPrefix;
  final bool autoCreateSession;
  final bool enableWebUi;
  final String? logoText;
  final String? logoImageUrl;
  final bool reload;
  final bool reloadAgents;
  final bool traceToCloud;
  final bool otelToCloud;
  final bool a2a;
  final List<_ExtraPluginSpec> extraPluginSpecs;
  final Directory? webAssetsDir;

  final Map<String, Runner> _runners = <String, Runner>{};

  static Future<_AdkDevWebContext> create({
    required DevAgentRuntime runtime,
    required DevProjectConfig project,
    required String agentsDir,
    required List<String> allowOrigins,
    required String? sessionServiceUri,
    required String? artifactServiceUri,
    required String? memoryServiceUri,
    required bool useLocalStorage,
    required String? urlPrefix,
    required bool autoCreateSession,
    required bool enableWebUi,
    required String? logoText,
    required String? logoImageUrl,
    required bool reload,
    required bool reloadAgents,
    required bool traceToCloud,
    required bool otelToCloud,
    required bool a2a,
    required List<String> extraPlugins,
    Map<String, String>? environment,
  }) async {
    final Directory agentsRoot = Directory(agentsDir).absolute;
    final Map<String, String> appNameToDir = _buildAppNameToDir(
      agentsRoot,
      fallbackAppName: project.appName,
    );

    final BaseSessionService sessionService = createSessionServiceFromOptions(
      baseDir: agentsRoot.path,
      sessionServiceUri: sessionServiceUri,
      appNameToDir: appNameToDir,
      useLocalStorage: useLocalStorage,
    );

    final BaseArtifactService artifactService =
        createArtifactServiceFromOptions(
          baseDir: agentsRoot.path,
          artifactServiceUri: artifactServiceUri,
          strictUri: true,
          useLocalStorage: useLocalStorage,
        );

    final BaseMemoryService memoryService = createMemoryServiceFromOptions(
      baseDir: agentsRoot.path,
      memoryServiceUri: memoryServiceUri,
    );

    final Directory? webAssetsDir = enableWebUi
        ? await _resolveWebAssetsDir()
        : null;
    final List<_ExtraPluginSpec> parsedExtraPlugins = _parseExtraPluginSpecs(
      extraPlugins,
    );
    _configureCloudTelemetry(
      traceToCloud: traceToCloud,
      otelToCloud: otelToCloud,
      environment: environment ?? Platform.environment,
    );

    return _AdkDevWebContext(
      runtime: runtime,
      project: project,
      agentsDir: agentsRoot.path,
      agentLoader: AgentLoader(agentsRoot.path),
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      allowOrigins: allowOrigins,
      urlPrefix: urlPrefix,
      autoCreateSession: autoCreateSession,
      enableWebUi: enableWebUi,
      logoText: logoText,
      logoImageUrl: logoImageUrl,
      reload: reload,
      reloadAgents: reloadAgents,
      traceToCloud: traceToCloud,
      otelToCloud: otelToCloud,
      a2a: a2a,
      extraPluginSpecs: parsedExtraPlugins,
      webAssetsDir: webAssetsDir,
    );
  }

  String get defaultAppName => project.appName;
  String get defaultUserId => project.userId;

  Future<Runner> getRunner(String? appName) async {
    final String resolvedAppName = (appName == null || appName.trim().isEmpty)
        ? defaultAppName
        : appName.trim();

    final bool shouldReload = reload || reloadAgents;
    if (!shouldReload) {
      final Runner? cached = _runners[resolvedAppName];
      if (cached != null) {
        return cached;
      }
    } else {
      final Runner? stale = _runners.remove(resolvedAppName);
      if (stale != null) {
        await stale.close();
      }
    }

    final Runner runner = _createRunner(resolvedAppName);
    _runners[resolvedAppName] = runner;
    return runner;
  }

  Runner _createRunner(String appName) {
    final List<BasePlugin> extraPlugins = _instantiateExtraPlugins(
      extraPluginSpecs,
      baseDir: agentsDir,
    );
    final Object loaded;
    try {
      loaded = agentLoader.loadAgent(appName);
    } on StateError {
      if (appName != defaultAppName) {
        rethrow;
      }

      return Runner(
        appName: appName,
        agent: runtime.runner.agent,
        sessionService: sessionService,
        artifactService: artifactService,
        memoryService: memoryService,
        plugins: extraPlugins,
        autoCreateSession: autoCreateSession,
      );
    }

    if (loaded is App) {
      return Runner(
        app: loaded,
        appName: appName,
        sessionService: sessionService,
        artifactService: artifactService,
        memoryService: memoryService,
        plugins: extraPlugins,
        autoCreateSession: autoCreateSession,
      );
    }

    return Runner(
      appName: appName,
      agent: asBaseAgent(loaded),
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      plugins: extraPlugins,
      autoCreateSession: autoCreateSession,
    );
  }

  List<String> listAppNames() {
    final Set<String> names = agentLoader.listAgents().toSet();
    names.add(defaultAppName);
    final List<String> sorted = names.toList()..sort();
    return sorted;
  }

  List<Map<String, Object?>> listAppDetails() {
    final List<Map<String, Object?>> details = agentLoader
        .listAgentsDetailed()
        .map((Map<String, Object?> value) {
          return Map<String, Object?>.from(value);
        })
        .toList(growable: true);

    final Set<String> knownNames = details
        .map((Map<String, Object?> value) => '${value['name'] ?? ''}')
        .where((String value) => value.isNotEmpty)
        .toSet();

    if (!knownNames.contains(defaultAppName)) {
      details.add(<String, Object?>{
        'name': defaultAppName,
        'root_agent_name': runtime.config.agentName,
        'description': runtime.config.description,
        'language': 'dart',
        'is_computer_use': false,
      });
    }

    details.sort((Map<String, Object?> a, Map<String, Object?> b) {
      final String left = '${a['name'] ?? ''}';
      final String right = '${b['name'] ?? ''}';
      return left.compareTo(right);
    });
    return details;
  }

  Future<void> close() async {
    for (final Runner runner in _runners.values) {
      await runner.close();
    }
    _runners.clear();
  }
}

Future<void> _handleRequests(
  HttpServer server,
  _AdkDevWebContext context,
) async {
  try {
    await for (final HttpRequest request in server) {
      try {
        await _handleRequest(request, context);
      } on FormatException catch (error) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: error.message,
        );
      } on ArgumentError catch (error) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: '${error.message}',
        );
      } on StateError catch (error) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: error.message,
        );
      } catch (_) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.internalServerError,
          message: 'Internal server error.',
        );
      }
    }
  } finally {
    await context.close();
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String? routedPath = _stripPrefix(request.uri.path, context.urlPrefix);
  if (routedPath == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Not found.',
    );
    return;
  }

  if (request.method == 'OPTIONS') {
    await _writeJson(request, context, payload: const <String, Object?>{});
    return;
  }

  if (context.a2a &&
      request.method == 'GET' &&
      (routedPath == '/.well-known/agent.json' ||
          routedPath == '/a2a/agent-card')) {
    await _handleA2aAgentCard(request, context);
    return;
  }

  if (context.a2a && request.method == 'GET') {
    final String? scopedAppName = _extractA2aScopedAppName(routedPath);
    if (scopedAppName != null) {
      await _handleA2aAgentCard(
        request,
        context,
        appNameFromPath: scopedAppName,
      );
      return;
    }
  }

  if (await _handleWebUi(request, context, routedPath)) {
    return;
  }

  if (routedPath == '/health' && request.method == 'GET') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'status': 'ok',
        'service': 'adk_dart_web',
        'appName': context.defaultAppName,
      },
    );
    return;
  }

  if (routedPath == '/version' && request.method == 'GET') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'version': adkVersion,
        'language': 'dart',
        'language_version': Platform.version.split(' ').first,
      },
    );
    return;
  }

  if (routedPath == '/list-apps' && request.method == 'GET') {
    final bool detailed = _isTruthy(request.uri.queryParameters['detailed']);
    if (detailed) {
      await _writeJson(
        request,
        context,
        payload: <String, Object?>{'apps': context.listAppDetails()},
      );
    } else {
      await _writeJson(request, context, payload: context.listAppNames());
    }
    return;
  }

  if (routedPath == '/api/info' && request.method == 'GET') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'name': 'adk_dart',
        'ui': context.enableWebUi ? 'development' : 'disabled',
        'appName': context.defaultAppName,
        'agentName': context.project.agentName,
        'description': context.project.description,
        'a2a': context.a2a,
        'extra_plugins': context.extraPluginSpecs
            .map((_ExtraPluginSpec spec) => spec.raw)
            .toList(growable: false),
        'trace_to_cloud': context.traceToCloud,
        'otel_to_cloud': context.otelToCloud,
      },
    );
    return;
  }

  if (routedPath == '/api/sessions' && request.method == 'POST') {
    await _handleLegacyCreateSession(request, context);
    return;
  }

  if (routedPath == '/api/sessions' && request.method == 'GET') {
    await _handleLegacyListSessions(request, context);
    return;
  }

  if (routedPath == '/run' && request.method == 'POST') {
    await _handleRun(request, context);
    return;
  }

  if (routedPath == '/run_sse' && request.method == 'POST') {
    await _handleRunSse(request, context);
    return;
  }

  if (routedPath == '/run_live' && request.method == 'GET') {
    await _handleRunLive(request, context);
    return;
  }

  final List<String> segments = Uri(
    path: routedPath,
  ).pathSegments.where((String s) => s.isNotEmpty).toList();

  if (segments.length == 4 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions' &&
      segments[3] == 'messages' &&
      request.method == 'POST') {
    await _handleLegacyPostMessage(request, context, sessionId: segments[2]);
    return;
  }

  if (segments.length == 4 &&
      segments[0] == 'api' &&
      segments[1] == 'sessions' &&
      segments[3] == 'events' &&
      request.method == 'GET') {
    await _handleLegacyGetEvents(request, context, sessionId: segments[2]);
    return;
  }

  if (await _handlePythonStyleRoutes(request, context, segments)) {
    return;
  }

  await _writeError(
    request,
    context,
    statusCode: HttpStatus.notFound,
    message: 'Not found.',
  );
}

Future<bool> _handlePythonStyleRoutes(
  HttpRequest request,
  _AdkDevWebContext context,
  List<String> segments,
) async {
  if (segments.length < 5) {
    return false;
  }
  if (segments[0] != 'apps' || segments[2] != 'users') {
    return false;
  }

  final String appName = segments[1];
  final String userId = segments[3];

  if (segments[4] == 'memory' &&
      segments.length == 5 &&
      request.method == 'PATCH') {
    await _handlePatchMemory(
      request,
      context,
      appName: appName,
      userId: userId,
    );
    return true;
  }

  if (segments[4] != 'sessions') {
    return false;
  }

  if (segments.length == 5) {
    if (request.method == 'GET') {
      await _handleListSessions(
        request,
        context,
        appName: appName,
        userId: userId,
      );
      return true;
    }
    if (request.method == 'POST') {
      await _handleCreateSession(
        request,
        context,
        appName: appName,
        userId: userId,
      );
      return true;
    }
    return false;
  }

  final String sessionId = segments[5];
  if (segments.length == 6) {
    if (request.method == 'GET') {
      await _handleGetSession(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    if (request.method == 'DELETE') {
      await _handleDeleteSession(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    if (request.method == 'POST') {
      await _handleCreateSessionWithId(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    if (request.method == 'PATCH') {
      await _handleUpdateSession(
        request,
        context,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      return true;
    }
    return false;
  }

  if (segments.length >= 7 && segments[6] == 'artifacts') {
    await _handleArtifactsRoute(
      request,
      context,
      segments,
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    return true;
  }

  return false;
}

Future<void> _handleLegacyCreateSession(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String userId = _readString(payload, const <String>[
    'userId',
    'user_id',
  ], fallback: context.defaultUserId);
  final Session session = await context.sessionService.createSession(
    appName: context.defaultAppName,
    userId: userId,
  );

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'session': _sessionToLegacyJson(session),
      'events': <Object?>[],
    },
  );
}

Future<void> _handleLegacyListSessions(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String userId =
      request.uri.queryParameters['userId'] ?? context.defaultUserId;
  final ListSessionsResponse sessions = await context.sessionService
      .listSessions(appName: context.defaultAppName, userId: userId);

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'sessions': sessions.sessions
          .map<Map<String, Object?>>(_sessionToLegacyJson)
          .toList(growable: false),
    },
  );
}

Future<void> _handleLegacyPostMessage(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String userId = _readString(payload, const <String>[
    'userId',
    'user_id',
  ], fallback: context.defaultUserId);
  final String text = _readString(payload, const <String>[
    'text',
  ], fallback: '').trim();

  if (text.isEmpty) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Message text is required.',
    );
    return;
  }

  final Runner runner = await context.getRunner(context.defaultAppName);
  final List<Event> events = await runner
      .runAsync(
        userId: userId,
        sessionId: sessionId,
        newMessage: Content.userText(text),
      )
      .toList();

  final String reply = _extractReplyText(
    events,
    fallbackAuthor: context.project.agentName,
  );

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'sessionId': sessionId,
      'userId': userId,
      'events': events.map<Map<String, Object?>>(_eventToLegacyJson).toList(),
      if (reply.isNotEmpty) 'reply': reply,
    },
  );
}

Future<void> _handleLegacyGetEvents(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String sessionId,
}) async {
  final String userId =
      request.uri.queryParameters['userId'] ?? context.defaultUserId;
  final Session? session = await context.sessionService.getSession(
    appName: context.defaultAppName,
    userId: userId,
    sessionId: sessionId,
  );

  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found.',
    );
    return;
  }

  await _writeJson(
    request,
    context,
    payload: <String, Object?>{
      'session': _sessionToLegacyJson(session),
      'events': session.events
          .map<Map<String, Object?>>(_eventToLegacyJson)
          .toList(),
    },
  );
}

Future<void> _handleGetSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(session, includeEvents: true),
  );
}

Future<void> _handleListSessions(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
}) async {
  final ListSessionsResponse response = await context.sessionService
      .listSessions(appName: appName, userId: userId);

  await _writeJson(
    request,
    context,
    payload: response.sessions
        .map<Map<String, Object?>>((Session value) => _sessionToApiJson(value))
        .toList(growable: false),
  );
}

Future<void> _handleCreateSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String? requestedSessionId = _nullableString(payload, const <String>[
    'session_id',
    'sessionId',
  ]);
  final Map<String, Object?>? state = _readObjectMap(payload, const <String>[
    'state',
  ]);

  final Session session = await context.sessionService.createSession(
    appName: appName,
    userId: userId,
    sessionId: requestedSessionId,
    state: state,
  );

  final List<Event> seedEvents = _readEventsFromPayload(
    payload,
    appName: appName,
    userId: userId,
    sessionId: session.id,
  );
  for (final Event event in seedEvents) {
    await context.sessionService.appendEvent(session: session, event: event);
  }

  final Session? updated = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: session.id,
  );

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(updated ?? session, includeEvents: true),
  );
}

Future<void> _handleCreateSessionWithId(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final Map<String, Object?>? state = _readObjectMap(payload, const <String>[
    'state',
  ]);

  final Session session = await context.sessionService.createSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
    state: state,
  );

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(session, includeEvents: true),
  );
}

Future<void> _handleDeleteSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  await context.sessionService.deleteSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleUpdateSession(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final Map<String, Object?> stateDelta =
      _readObjectMap(payload, const <String>['state_delta', 'stateDelta']) ??
      <String, Object?>{};

  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  final Event updateEvent = Event(
    invocationId: 'invocation_${DateTime.now().microsecondsSinceEpoch}',
    author: 'user',
    actions: EventActions(stateDelta: stateDelta),
  );
  await context.sessionService.appendEvent(
    session: session,
    event: updateEvent,
  );

  final Session? updated = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );

  await _writeJson(
    request,
    context,
    payload: _sessionToApiJson(updated ?? session, includeEvents: true),
  );
}

Future<void> _handlePatchMemory(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String appName,
  required String userId,
}) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final String sessionId = _readString(payload, const <String>[
    'session_id',
    'sessionId',
  ], required: true);

  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );
  if (session == null) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: 'Session not found',
    );
    return;
  }

  await context.memoryService.addSessionToMemory(session);
  await _writeJson(request, context, payload: const <String, Object?>{});
}

Future<void> _handleArtifactsRoute(
  HttpRequest request,
  _AdkDevWebContext context,
  List<String> segments, {
  required String appName,
  required String userId,
  required String sessionId,
}) async {
  if (segments.length == 7) {
    if (request.method == 'GET') {
      final List<String> names = await context.artifactService.listArtifactKeys(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      await _writeJson(request, context, payload: names);
      return;
    }

    if (request.method == 'POST') {
      final Map<String, dynamic> payload = await _readJsonBody(request);
      final String filename = _readString(payload, const <String>[
        'filename',
      ], required: true);

      final Object? artifactRaw = payload['artifact'];
      if (artifactRaw is! Map) {
        throw const FormatException('artifact must be a JSON object.');
      }
      final Part artifact = _partFromJson(_toDynamicMap(artifactRaw));
      final Map<String, Object?>? customMetadata = _readObjectMap(
        payload,
        const <String>['custom_metadata', 'customMetadata'],
      );

      final int version = await context.artifactService.saveArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: filename,
        artifact: artifact,
        customMetadata: customMetadata,
      );

      final ArtifactVersion? metadata = await context.artifactService
          .getArtifactVersion(
            appName: appName,
            userId: userId,
            sessionId: sessionId,
            filename: filename,
            version: version,
          );
      if (metadata == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.internalServerError,
          message: 'Artifact metadata unavailable',
        );
        return;
      }

      await _writeJson(
        request,
        context,
        payload: _artifactVersionToJson(metadata),
      );
      return;
    }

    await _writeError(
      request,
      context,
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed.',
    );
    return;
  }

  final String artifactName = segments[7];

  if (segments.length == 8) {
    if (request.method == 'GET') {
      final int? version = int.tryParse(
        request.uri.queryParameters['version'] ?? '',
      );
      final Part? artifact = await context.artifactService.loadArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
        version: version,
      );
      if (artifact == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Artifact not found',
        );
        return;
      }
      await _writeJson(request, context, payload: _partToJson(artifact));
      return;
    }

    if (request.method == 'DELETE') {
      await context.artifactService.deleteArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
      );
      await _writeJson(request, context, payload: const <String, Object?>{});
      return;
    }

    await _writeError(
      request,
      context,
      statusCode: HttpStatus.methodNotAllowed,
      message: 'Method not allowed.',
    );
    return;
  }

  if (segments.length >= 9 && segments[8] == 'versions') {
    if (segments.length == 9 && request.method == 'GET') {
      final List<int> versions = await context.artifactService.listVersions(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
      );
      await _writeJson(request, context, payload: versions);
      return;
    }

    if (segments.length == 10 &&
        segments[9] == 'metadata' &&
        request.method == 'GET') {
      final List<ArtifactVersion> metadata = await context.artifactService
          .listArtifactVersions(
            appName: appName,
            userId: userId,
            sessionId: sessionId,
            filename: artifactName,
          );
      await _writeJson(
        request,
        context,
        payload: metadata
            .map<Map<String, Object?>>(_artifactVersionToJson)
            .toList(growable: false),
      );
      return;
    }

    if (segments.length == 10 && request.method == 'GET') {
      final int? versionId = int.tryParse(segments[9]);
      if (versionId == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid version id: ${segments[9]}',
        );
        return;
      }

      final Part? artifact = await context.artifactService.loadArtifact(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        filename: artifactName,
        version: versionId,
      );
      if (artifact == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Artifact not found',
        );
        return;
      }
      await _writeJson(request, context, payload: _partToJson(artifact));
      return;
    }

    if (segments.length == 11 &&
        segments[10] == 'metadata' &&
        request.method == 'GET') {
      final int? versionId = int.tryParse(segments[9]);
      if (versionId == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid version id: ${segments[9]}',
        );
        return;
      }

      final ArtifactVersion? metadata = await context.artifactService
          .getArtifactVersion(
            appName: appName,
            userId: userId,
            sessionId: sessionId,
            filename: artifactName,
            version: versionId,
          );
      if (metadata == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Artifact version not found',
        );
        return;
      }

      await _writeJson(
        request,
        context,
        payload: _artifactVersionToJson(metadata),
      );
      return;
    }
  }

  await _writeError(
    request,
    context,
    statusCode: HttpStatus.notFound,
    message: 'Not found.',
  );
}

Future<void> _handleRun(HttpRequest request, _AdkDevWebContext context) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final _RunRequest runRequest = _parseRunRequest(payload, context);
  final Runner runner = await context.getRunner(runRequest.appName);

  final List<Event> events;
  try {
    events = await runner
        .runAsync(
          userId: runRequest.userId,
          sessionId: runRequest.sessionId,
          newMessage: runRequest.newMessage,
          stateDelta: runRequest.stateDelta,
          invocationId: runRequest.invocationId,
        )
        .toList();
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.notFound,
      message: error.message,
    );
    return;
  }

  await _writeJson(
    request,
    context,
    payload: events
        .map<Map<String, Object?>>(
          (Event event) => _eventToApiJson(
            event,
            appName: runRequest.appName,
            userId: runRequest.userId,
            sessionId: runRequest.sessionId,
          ),
        )
        .toList(growable: false),
  );
}

Future<void> _handleRunSse(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final Map<String, dynamic> payload = await _readJsonBody(request);
  final _RunRequest runRequest = _parseRunRequest(payload, context);
  final Runner runner = await context.getRunner(runRequest.appName);

  if (!runner.autoCreateSession) {
    final Session? session = await context.sessionService.getSession(
      appName: runRequest.appName,
      userId: runRequest.userId,
      sessionId: runRequest.sessionId,
    );
    if (session == null) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Session not found: ${runRequest.sessionId}',
      );
      return;
    }
  }

  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  response.headers.set('Cache-Control', 'no-cache');
  response.headers.set('Connection', 'keep-alive');

  try {
    await for (final Event event in runner.runAsync(
      userId: runRequest.userId,
      sessionId: runRequest.sessionId,
      newMessage: runRequest.newMessage,
      stateDelta: runRequest.stateDelta,
      invocationId: runRequest.invocationId,
      runConfig: RunConfig(
        streamingMode: runRequest.streaming
            ? StreamingMode.sse
            : StreamingMode.none,
      ),
    )) {
      final String data = jsonEncode(
        _eventToApiJson(
          event,
          appName: runRequest.appName,
          userId: runRequest.userId,
          sessionId: runRequest.sessionId,
        ),
      );
      response.write('data: $data\n\n');
      await response.flush();
    }
  } catch (error) {
    response.write(
      'data: ${jsonEncode(<String, Object?>{'error': '$error'})}\n\n',
    );
  }

  await response.close();
}

Future<void> _handleRunLive(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String appName = _readRequiredQuery(request, 'app_name');
  final String userId = _readRequiredQuery(request, 'user_id');
  final String sessionId = _readRequiredQuery(request, 'session_id');

  final Session? session = await context.sessionService.getSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );

  final WebSocket socket = await WebSocketTransformer.upgrade(request);
  if (session == null) {
    await socket.close(WebSocketStatus.protocolError, 'Session not found');
    return;
  }

  final LiveRequestQueue liveQueue = LiveRequestQueue();
  final Runner runner = await context.getRunner(appName);
  final RunConfig runConfig = RunConfig(
    responseModalities: _parseModalities(
      request.uri.queryParameters['modalities'],
    ),
  );

  Future<void> forwardEvents() async {
    await for (final Event event in runner.runLive(
      liveRequestQueue: liveQueue,
      session: session,
      runConfig: runConfig,
    )) {
      socket.add(
        jsonEncode(
          _eventToApiJson(
            event,
            appName: appName,
            userId: userId,
            sessionId: sessionId,
          ),
        ),
      );
    }
  }

  Future<void> processMessages() async {
    await for (final dynamic data in socket) {
      if (data is String) {
        final Object? decoded = jsonDecode(data);
        if (decoded is! Map) {
          continue;
        }
        liveQueue.send(_liveRequestFromJson(_toDynamicMap(decoded)));
      } else {
        liveQueue.sendRealtime(data);
      }
    }
  }

  final Future<void> forwardTask = forwardEvents();
  final Future<void> messageTask = processMessages();

  try {
    await Future.any(<Future<void>>[forwardTask, messageTask]);
  } finally {
    liveQueue.close();
    await socket.close();
  }
}

Future<bool> _handleWebUi(
  HttpRequest request,
  _AdkDevWebContext context,
  String routedPath,
) async {
  if (!context.enableWebUi || context.webAssetsDir == null) {
    return false;
  }

  if (request.method != 'GET' && request.method != 'HEAD') {
    return false;
  }

  final String prefix = context.urlPrefix ?? '';

  if (routedPath == '/') {
    await _redirect(request, context, '$prefix/dev-ui/');
    return true;
  }

  if (routedPath == '/dev-ui/config') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'logo_text': context.logoText,
        'logo_image_url': context.logoImageUrl,
      },
    );
    return true;
  }

  if (routedPath == '/dev-ui') {
    await _redirect(request, context, '$prefix/dev-ui/');
    return true;
  }

  if (!routedPath.startsWith('/dev-ui/')) {
    return false;
  }

  final String relativeRaw = routedPath.substring('/dev-ui/'.length);
  final String relative = Uri.decodeComponent(relativeRaw);

  if (relative.contains('..')) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Invalid path.',
    );
    return true;
  }

  final File file = relative.isEmpty
      ? File('${context.webAssetsDir!.path}${Platform.pathSeparator}index.html')
      : File('${context.webAssetsDir!.path}${Platform.pathSeparator}$relative');

  if (await file.exists()) {
    await _writeFile(request, context, file);
    return true;
  }

  final bool isLikelySpaRoute = !relative.contains('.');
  if (isLikelySpaRoute) {
    final File index = File(
      '${context.webAssetsDir!.path}${Platform.pathSeparator}index.html',
    );
    if (await index.exists()) {
      await _writeFile(request, context, index);
      return true;
    }
  }

  await _writeError(
    request,
    context,
    statusCode: HttpStatus.notFound,
    message: 'Not found.',
  );
  return true;
}

Future<void> _redirect(
  HttpRequest request,
  _AdkDevWebContext context,
  String location,
) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.movedTemporarily;
  response.headers.set(HttpHeaders.locationHeader, location);
  await response.close();
}

Future<void> _writeFile(
  HttpRequest request,
  _AdkDevWebContext context,
  File file,
) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);

  final String extension = file.path.split('.').last.toLowerCase();
  final ContentType contentType = switch (extension) {
    'html' => ContentType.html,
    'js' => ContentType('application', 'javascript', charset: 'utf-8'),
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'svg' => ContentType('image', 'svg+xml'),
    'json' => ContentType.json,
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'webp' => ContentType('image', 'webp'),
    'woff2' => ContentType('font', 'woff2'),
    _ => ContentType.binary,
  };

  response.statusCode = HttpStatus.ok;
  response.headers.contentType = contentType;
  await response.addStream(file.openRead());
  await response.close();
}

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  if (request.method == 'GET' || request.method == 'HEAD') {
    return <String, dynamic>{};
  }

  final String body = await utf8.decoder.bind(request).join();
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }

  final Object? decoded = jsonDecode(body);
  if (decoded is Map) {
    return _toDynamicMap(decoded);
  }

  throw const FormatException('Request JSON body must be an object.');
}

Future<void> _writeError(
  HttpRequest request,
  _AdkDevWebContext context, {
  required int statusCode,
  required String message,
}) async {
  await _writeJson(
    request,
    context,
    statusCode: statusCode,
    payload: <String, Object?>{'error': message},
  );
}

Future<void> _writeJson(
  HttpRequest request,
  _AdkDevWebContext context, {
  required Object payload,
  int statusCode = HttpStatus.ok,
}) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}

void _setCorsHeaders(
  HttpRequest request,
  HttpResponse response,
  _AdkDevWebContext context,
) {
  if (context.allowOrigins.isEmpty) {
    response.headers.set('Access-Control-Allow-Origin', '*');
  } else {
    final String? origin = request.headers.value('origin');
    if (origin != null && _originAllowed(origin, context.allowOrigins)) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Vary', 'Origin');
    }
  }

  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );
  response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PATCH, DELETE, OPTIONS',
  );
}

bool _originAllowed(String origin, List<String> allowOrigins) {
  for (final String allowed in allowOrigins) {
    if (allowed == origin) {
      return true;
    }
    if (allowed.startsWith('regex:')) {
      final String pattern = allowed.substring('regex:'.length);
      if (pattern.isEmpty) {
        continue;
      }
      final RegExp regex = RegExp(pattern);
      if (regex.hasMatch(origin)) {
        return true;
      }
    }
  }
  return false;
}

String? _stripPrefix(String path, String? urlPrefix) {
  if (urlPrefix == null || urlPrefix.isEmpty) {
    return path;
  }
  if (path == urlPrefix) {
    return '/';
  }
  if (path.startsWith('$urlPrefix/')) {
    return path.substring(urlPrefix.length);
  }
  return null;
}

String? _normalizeUrlPrefix(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final String trimmed = value.trim();
  if (!trimmed.startsWith('/')) {
    throw ArgumentError.value(trimmed, 'urlPrefix', 'Must start with "/".');
  }
  if (trimmed == '/') {
    return null;
  }
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

bool _isTruthy(String? raw) {
  if (raw == null) {
    return false;
  }
  switch (raw.toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'y':
      return true;
    default:
      return false;
  }
}

Map<String, Object?> _sessionToLegacyJson(Session session) {
  return <String, Object?>{
    'id': session.id,
    'appName': session.appName,
    'userId': session.userId,
    'lastUpdateTime': session.lastUpdateTime,
  };
}

Map<String, Object?> _sessionToApiJson(
  Session session, {
  bool includeEvents = false,
}) {
  return <String, Object?>{
    'id': session.id,
    'app_name': session.appName,
    'appName': session.appName,
    'user_id': session.userId,
    'userId': session.userId,
    'state': session.state,
    'last_update_time': session.lastUpdateTime,
    'lastUpdateTime': session.lastUpdateTime,
    if (includeEvents)
      'events': session.events
          .map<Map<String, Object?>>(
            (Event event) => _eventToApiJson(
              event,
              appName: session.appName,
              userId: session.userId,
              sessionId: session.id,
            ),
          )
          .toList(growable: false),
  };
}

Map<String, Object?> _eventToApiJson(
  Event event, {
  required String appName,
  required String userId,
  required String sessionId,
}) {
  final Session shadowSession = Session(
    id: sessionId,
    appName: appName,
    userId: userId,
  );
  final Map<String, Object?> snake = StorageEventV0.fromEvent(
    session: shadowSession,
    event: event,
  ).toJson();

  return <String, Object?>{
    ...snake,
    'invocationId': snake['invocation_id'],
    'appName': snake['app_name'],
    'userId': snake['user_id'],
    'sessionId': snake['session_id'],
    'customMetadata': snake['custom_metadata'],
    'usageMetadata': snake['usage_metadata'],
    'citationMetadata': snake['citation_metadata'],
    'groundingMetadata': snake['grounding_metadata'],
    'turnComplete': snake['turn_complete'],
    'finishReason': snake['finish_reason'],
    'errorCode': snake['error_code'],
    'errorMessage': snake['error_message'],
    'inputTranscription': snake['input_transcription'],
    'outputTranscription': snake['output_transcription'],
    'modelVersion': snake['model_version'],
    'avgLogprobs': snake['avg_logprobs'],
    'logprobsResult': snake['logprobs_result'],
    'cacheMetadata': snake['cache_metadata'],
    'interactionId': snake['interaction_id'],
  };
}

Map<String, Object?> _eventToLegacyJson(Event event) {
  return <String, Object?>{
    'id': event.id,
    'invocationId': event.invocationId,
    'author': event.author,
    'timestamp': event.timestamp,
    'partial': event.partial,
    'content': _contentToLegacyJson(event.content),
    'actions': <String, Object?>{
      'transferToAgent': event.actions.transferToAgent,
      'escalate': event.actions.escalate,
      'skipSummarization': event.actions.skipSummarization,
      'endOfAgent': event.actions.endOfAgent,
      'rewindBeforeInvocationId': event.actions.rewindBeforeInvocationId,
      'stateDelta': event.actions.stateDelta,
      'artifactDelta': event.actions.artifactDelta,
    },
  };
}

Map<String, Object?>? _contentToLegacyJson(Content? content) {
  if (content == null) {
    return null;
  }

  return <String, Object?>{
    'role': content.role,
    'parts': content.parts
        .map<Map<String, Object?>>((Part part) {
          return <String, Object?>{
            'text': part.text,
            'thought': part.thought,
            'functionCall': part.functionCall == null
                ? null
                : <String, Object?>{
                    'name': part.functionCall!.name,
                    'args': part.functionCall!.args,
                    'id': part.functionCall!.id,
                  },
            'functionResponse': part.functionResponse == null
                ? null
                : <String, Object?>{
                    'name': part.functionResponse!.name,
                    'response': part.functionResponse!.response,
                    'id': part.functionResponse!.id,
                  },
          };
        })
        .toList(growable: false),
  };
}

String _extractReplyText(List<Event> events, {required String fallbackAuthor}) {
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final Event event = events[i];
    if (event.author == 'user') {
      continue;
    }
    if (event.author != fallbackAuthor && fallbackAuthor.isNotEmpty) {
      // Keep best effort with arbitrary loaded agents.
    }
    final String text = _textFromContent(event.content);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

String _textFromContent(Content? content) {
  if (content == null) {
    return '';
  }

  final List<String> chunks = <String>[];
  for (final Part part in content.parts) {
    final String? text = part.text;
    if (text != null && text.trim().isNotEmpty) {
      chunks.add(text.trim());
    }
  }
  return chunks.join('\n');
}

Map<String, Object?> _artifactVersionToJson(ArtifactVersion value) {
  return <String, Object?>{
    'version': value.version,
    'canonical_uri': value.canonicalUri,
    'canonicalUri': value.canonicalUri,
    'custom_metadata': value.customMetadata,
    'customMetadata': value.customMetadata,
    'create_time': value.createTime,
    'createTime': value.createTime,
    'mime_type': value.mimeType,
    'mimeType': value.mimeType,
  };
}

Map<String, Object?> _partToJson(Part part) {
  final Map<String, Object?> json = <String, Object?>{};
  if (part.text != null) {
    json['text'] = part.text;
  }
  json['thought'] = part.thought;

  if (part.functionCall != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'name': part.functionCall!.name,
      'args': part.functionCall!.args,
      'id': part.functionCall!.id,
    };
    json['function_call'] = payload;
    json['functionCall'] = payload;
  }

  if (part.functionResponse != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'name': part.functionResponse!.name,
      'response': part.functionResponse!.response,
      'id': part.functionResponse!.id,
    };
    json['function_response'] = payload;
    json['functionResponse'] = payload;
  }

  if (part.inlineData != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'mimeType': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      'display_name': part.inlineData!.displayName,
      'displayName': part.inlineData!.displayName,
    };
    json['inline_data'] = payload;
    json['inlineData'] = payload;
  }

  if (part.fileData != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      'fileUri': part.fileData!.fileUri,
      'mime_type': part.fileData!.mimeType,
      'mimeType': part.fileData!.mimeType,
      'display_name': part.fileData!.displayName,
      'displayName': part.fileData!.displayName,
    };
    json['file_data'] = payload;
    json['fileData'] = payload;
  }

  return json;
}

Part _partFromJson(Map<String, dynamic> json) {
  final String? text = json['text'] as String?;
  final bool thought = json['thought'] as bool? ?? false;

  final Object? functionCallRaw = json['function_call'] ?? json['functionCall'];
  final Object? functionResponseRaw =
      json['function_response'] ?? json['functionResponse'];
  final Object? inlineDataRaw = json['inline_data'] ?? json['inlineData'];
  final Object? fileDataRaw = json['file_data'] ?? json['fileData'];

  if (functionCallRaw is Map) {
    final Map<String, dynamic> functionCall = _toDynamicMap(functionCallRaw);
    return Part.fromFunctionCall(
      name: '${functionCall['name'] ?? ''}',
      args: _toDynamicMap(
        functionCall['args'] as Object? ?? const <String, Object?>{},
      ),
      id: functionCall['id']?.toString(),
    );
  }

  if (functionResponseRaw is Map) {
    final Map<String, dynamic> functionResponse = _toDynamicMap(
      functionResponseRaw,
    );
    return Part.fromFunctionResponse(
      name: '${functionResponse['name'] ?? ''}',
      response: _toDynamicMap(
        functionResponse['response'] as Object? ?? const <String, Object?>{},
      ),
      id: functionResponse['id']?.toString(),
    );
  }

  if (inlineDataRaw is Map) {
    final Map<String, dynamic> inlineData = _toDynamicMap(inlineDataRaw);
    final Object? dataRaw = inlineData['data'];
    List<int> bytes = <int>[];
    if (dataRaw is String && dataRaw.isNotEmpty) {
      try {
        bytes = base64Decode(dataRaw);
      } on FormatException {
        bytes = utf8.encode(dataRaw);
      }
    } else if (dataRaw is List) {
      bytes = dataRaw.map((Object? item) => (item as num).toInt()).toList();
    }

    return Part.fromInlineData(
      mimeType:
          '${inlineData['mime_type'] ?? inlineData['mimeType'] ?? 'application/octet-stream'}',
      data: bytes,
      displayName: (inlineData['display_name'] ?? inlineData['displayName'])
          ?.toString(),
    );
  }

  if (fileDataRaw is Map) {
    final Map<String, dynamic> fileData = _toDynamicMap(fileDataRaw);
    return Part.fromFileData(
      fileUri: '${fileData['file_uri'] ?? fileData['fileUri'] ?? ''}',
      mimeType: (fileData['mime_type'] ?? fileData['mimeType'])?.toString(),
      displayName: (fileData['display_name'] ?? fileData['displayName'])
          ?.toString(),
    );
  }

  return Part(text: text, thought: thought);
}

Content _contentFromJson(Map<String, dynamic> json) {
  final String? role = (json['role'] as String?)?.trim();
  final Object? partsRaw = json['parts'];
  if (partsRaw is! List) {
    final String text = (json['text'] as String?) ?? '';
    if (text.isNotEmpty) {
      return Content(role: role, parts: <Part>[Part.text(text)]);
    }
    return Content(role: role, parts: <Part>[]);
  }

  final List<Part> parts = <Part>[];
  for (final Object? item in partsRaw) {
    if (item is! Map) {
      continue;
    }
    parts.add(_partFromJson(_toDynamicMap(item)));
  }
  return Content(role: role, parts: parts);
}

List<Event> _readEventsFromPayload(
  Map<String, dynamic> payload, {
  required String appName,
  required String userId,
  required String sessionId,
}) {
  final Object? eventsRaw = payload['events'];
  if (eventsRaw is! List) {
    return const <Event>[];
  }

  final List<Event> events = <Event>[];
  for (final Object? item in eventsRaw) {
    if (item is! Map) {
      continue;
    }
    final Map<String, dynamic> map = _toDynamicMap(item);
    final Map<String, Object?> enriched = <String, Object?>{
      ...map,
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      'invocation_id':
          map['invocation_id'] ??
          map['invocationId'] ??
          'inv_${DateTime.now().microsecondsSinceEpoch}',
      'author': map['author'] ?? 'user',
    };
    events.add(StorageEventV0.fromJson(enriched).toEvent());
  }
  return events;
}

_RunRequest _parseRunRequest(
  Map<String, dynamic> payload,
  _AdkDevWebContext context,
) {
  final String appName = _readString(payload, const <String>[
    'app_name',
    'appName',
  ], fallback: context.defaultAppName);
  final String userId = _readString(payload, const <String>[
    'user_id',
    'userId',
  ], fallback: context.defaultUserId);
  final String sessionId = _readString(payload, const <String>[
    'session_id',
    'sessionId',
  ], required: true);

  final Object? messageRaw = payload['new_message'] ?? payload['newMessage'];
  Content? newMessage;
  if (messageRaw is Map) {
    newMessage = _contentFromJson(_toDynamicMap(messageRaw));
  } else if (messageRaw is String && messageRaw.trim().isNotEmpty) {
    newMessage = Content.userText(messageRaw.trim());
  } else {
    final String text = _readString(payload, const <String>[
      'text',
    ], fallback: '');
    if (text.trim().isNotEmpty) {
      newMessage = Content.userText(text.trim());
    }
  }

  return _RunRequest(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
    newMessage: newMessage,
    streaming: payload['streaming'] as bool? ?? false,
    stateDelta: _readObjectMap(payload, const <String>[
      'state_delta',
      'stateDelta',
    ]),
    invocationId: _nullableString(payload, const <String>[
      'invocation_id',
      'invocationId',
    ]),
  );
}

String _readRequiredQuery(HttpRequest request, String key) {
  final String? raw = request.uri.queryParameters[key];
  if (raw == null || raw.trim().isEmpty) {
    throw FormatException('Missing required query parameter: $key');
  }
  return raw.trim();
}

List<String>? _parseModalities(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final List<String> values = raw
      .split(',')
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  return values.isEmpty ? null : values;
}

LiveRequest _liveRequestFromJson(Map<String, dynamic> payload) {
  if (payload['close'] == true) {
    return LiveRequest(close: true);
  }

  if (payload['activity_start'] == true || payload['activityStart'] == true) {
    return LiveRequest(activityStart: const LiveActivityStart());
  }
  if (payload['activity_end'] == true || payload['activityEnd'] == true) {
    return LiveRequest(activityEnd: const LiveActivityEnd());
  }

  final Object? contentRaw = payload['content'];
  if (contentRaw is Map) {
    return LiveRequest(content: _contentFromJson(_toDynamicMap(contentRaw)));
  }

  if (payload.containsKey('blob')) {
    return LiveRequest(blob: payload['blob']);
  }

  return LiveRequest();
}

String _readString(
  Map<String, dynamic> payload,
  List<String> keys, {
  String? fallback,
  bool required = false,
}) {
  for (final String key in keys) {
    final Object? value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }

  if (fallback != null) {
    return fallback;
  }
  if (required) {
    throw FormatException('Missing required field: ${keys.first}');
  }
  return '';
}

String? _nullableString(Map<String, dynamic> payload, List<String> keys) {
  for (final String key in keys) {
    final Object? value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

Map<String, Object?>? _readObjectMap(
  Map<String, dynamic> payload,
  List<String> keys,
) {
  for (final String key in keys) {
    final Object? value = payload[key];
    if (value is Map) {
      return value.map(
        (Object? mapKey, Object? mapValue) => MapEntry('$mapKey', mapValue),
      );
    }
  }
  return null;
}

Map<String, dynamic> _toDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? val) => MapEntry('$key', val));
  }
  return <String, dynamic>{};
}

Map<String, String> _buildAppNameToDir(
  Directory agentsRoot, {
  required String fallbackAppName,
}) {
  final Map<String, String> result = <String, String>{};

  if (agentsRoot.existsSync()) {
    for (final FileSystemEntity entity in agentsRoot.listSync(
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }
      final String name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments[entity.uri.pathSegments.length - 2]
          : '';
      if (name.isEmpty || name.startsWith('.')) {
        continue;
      }
      result[name] = entity.path;
    }
  }

  if (_isSingleAppRoot(agentsRoot)) {
    result.putIfAbsent(fallbackAppName, () => agentsRoot.path);
  }
  result.putIfAbsent(fallbackAppName, () => agentsRoot.path);

  return result;
}

bool _isSingleAppRoot(Directory root) {
  final String path = root.path;
  final String sep = Platform.pathSeparator;
  return File('$path${sep}adk.json').existsSync() ||
      File('$path${sep}agent.dart').existsSync() ||
      File('$path${sep}root_agent.yaml').existsSync();
}

Future<Directory?> _resolveWebAssetsDir() async {
  final Uri? resolved = await Isolate.resolvePackageUri(
    Uri.parse('package:adk_dart/src/cli/browser/index.html'),
  );
  if (resolved == null || resolved.scheme != 'file') {
    return null;
  }

  final File file = File.fromUri(resolved);
  if (!await file.exists()) {
    return null;
  }
  return file.parent;
}

List<_ExtraPluginSpec> _parseExtraPluginSpecs(List<String> extraPlugins) {
  final List<_ExtraPluginSpec> specs = <_ExtraPluginSpec>[];
  for (final String raw in extraPlugins) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    specs.add(
      _ExtraPluginSpec(
        raw: trimmed,
        normalizedName: _normalizePluginName(trimmed),
      ),
    );
  }
  return specs;
}

String _normalizePluginName(String raw) {
  final String canonical = raw.toLowerCase().trim();
  final String base = canonical.split('.').last;
  final String left = base.split(':').first.split('=').first.trim();
  if (left.endsWith('contextfilterplugin') || left == 'context_filter_plugin') {
    return 'context_filter_plugin';
  }
  if (left.endsWith('debugloggingplugin') || left == 'debug_logging_plugin') {
    return 'debug_logging_plugin';
  }
  if (left.endsWith('globalinstructionplugin') ||
      left == 'global_instruction_plugin') {
    return 'global_instruction_plugin';
  }
  if (left.endsWith('loggingplugin') || left == 'logging_plugin') {
    return 'logging_plugin';
  }
  if (left.endsWith('multimodaltoolresultsplugin') ||
      left == 'multimodal_tool_results_plugin') {
    return 'multimodal_tool_results_plugin';
  }
  if (left.endsWith('reflectandretrytoolplugin') ||
      left == 'reflect_retry_tool_plugin') {
    return 'reflect_retry_tool_plugin';
  }
  if (left.endsWith('savefilesasartifactsplugin') ||
      left == 'save_files_as_artifacts_plugin') {
    return 'save_files_as_artifacts_plugin';
  }
  return left;
}

List<BasePlugin> _instantiateExtraPlugins(
  List<_ExtraPluginSpec> specs, {
  required String baseDir,
}) {
  final List<BasePlugin> plugins = <BasePlugin>[];
  for (final _ExtraPluginSpec spec in specs) {
    final BasePlugin? plugin = switch (spec.normalizedName) {
      'context_filter_plugin' => ContextFilterPlugin(),
      'debug_logging_plugin' => DebugLoggingPlugin(
        outputPath: '$baseDir${Platform.pathSeparator}adk_debug.yaml',
      ),
      'global_instruction_plugin' => GlobalInstructionPlugin(),
      'logging_plugin' => LoggingPlugin(),
      'multimodal_tool_results_plugin' => MultimodalToolResultsPlugin(),
      'reflect_retry_tool_plugin' => ReflectAndRetryToolPlugin(),
      'save_files_as_artifacts_plugin' => SaveFilesAsArtifactsPlugin(),
      _ => null,
    };

    if (plugin != null) {
      plugins.add(plugin);
    } else {
      stderr.writeln(
        'Unsupported extra plugin "${
            spec.raw
          }"; ignoring. Supported plugins are built-in ADK plugins only.',
      );
    }
  }
  return plugins;
}

void _configureCloudTelemetry({
  required bool traceToCloud,
  required bool otelToCloud,
  required Map<String, String> environment,
}) {
  final bool hasOtelEnv =
      _hasValue(environment, otelExporterOtlpEndpoint) ||
      _hasValue(environment, otelExporterOtlpTracesEndpoint) ||
      _hasValue(environment, otelExporterOtlpMetricsEndpoint) ||
      _hasValue(environment, otelExporterOtlpLogsEndpoint);

  if (!traceToCloud && !otelToCloud && !hasOtelEnv) {
    return;
  }

  final List<OTelHooks> hooks = <OTelHooks>[];
  OTelResource? resource;

  if (traceToCloud || otelToCloud) {
    final String? projectId = environment['GOOGLE_CLOUD_PROJECT'];
    final OTelHooks gcpHooks = getGcpExporters(
      enableCloudTracing: traceToCloud || otelToCloud,
      enableCloudMetrics: false,
      enableCloudLogging: otelToCloud,
      googleAuth: GoogleAuthResult(
        credentials: Object(),
        projectId: projectId,
      ),
      environment: environment,
    );
    if (gcpHooks.spanProcessors.isNotEmpty ||
        gcpHooks.metricReaders.isNotEmpty ||
        gcpHooks.logRecordProcessors.isNotEmpty) {
      hooks.add(gcpHooks);
      resource = getGcpResource(projectId: projectId, environment: environment);
    }
  }

  maybeSetOtelProviders(
    otelHooksToSetup: hooks,
    otelResource: resource,
    environment: environment,
  );
}

bool _hasValue(Map<String, String> environment, String key) {
  final String? value = environment[key];
  return value != null && value.isNotEmpty;
}

Future<void> _handleA2aAgentCard(
  HttpRequest request,
  _AdkDevWebContext context, {
  String? appNameFromPath,
}) async {
  final String fromQuery =
      request.uri.queryParameters['app_name'] ??
      request.uri.queryParameters['appName'] ??
      '';
  final String resolvedAppName = appNameFromPath?.trim().isNotEmpty == true
      ? appNameFromPath!.trim()
      : (fromQuery.trim().isNotEmpty ? fromQuery.trim() : context.defaultAppName);

  final Map<String, Object?>? diskCard = await _loadA2aAgentCardFromDisk(
    context,
    resolvedAppName,
  );
  if (diskCard != null) {
    await _writeJson(request, context, payload: diskCard);
    return;
  }

  final Runner runner = await context.getRunner(resolvedAppName);
  final Uri requested = request.requestedUri;
  final String authority = requested.authority;
  final String basePrefix = context.urlPrefix ?? '';
  final AgentCardBuilder cardBuilder = AgentCardBuilder(
    agent: runner.agent,
    rpcUrl: '${requested.scheme}://$authority$basePrefix/a2a/$resolvedAppName',
  );
  final dynamic card = await cardBuilder.build();
  await _writeJson(request, context, payload: card.toJson());
}

Future<Map<String, Object?>?> _loadA2aAgentCardFromDisk(
  _AdkDevWebContext context,
  String appName,
) async {
  final String sep = Platform.pathSeparator;
  final List<String> candidates = <String>[
    '${context.agentsDir}$sep$appName${sep}agent.json',
    if (appName == context.defaultAppName)
      '${context.agentsDir}${sep}agent.json',
  ];

  for (final String candidate in candidates) {
    final File file = File(candidate);
    if (!await file.exists()) {
      continue;
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        continue;
      }
      return decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    } on FormatException {
      continue;
    } on FileSystemException {
      continue;
    }
  }
  return null;
}

String? _extractA2aScopedAppName(String routedPath) {
  const String suffix = '/.well-known/agent.json';
  if (routedPath.startsWith('/a2a/') && routedPath.endsWith(suffix)) {
    final String raw = routedPath.substring(
      '/a2a/'.length,
      routedPath.length - suffix.length,
    );
    final String appName = Uri.decodeComponent(raw).trim();
    if (appName.isEmpty || appName.contains('/')) {
      return null;
    }
    return appName;
  }

  if (routedPath.startsWith('/a2a/') && routedPath.endsWith('/agent-card')) {
    final String raw = routedPath.substring(
      '/a2a/'.length,
      routedPath.length - '/agent-card'.length,
    );
    final String appName = Uri.decodeComponent(raw).trim();
    if (appName.isEmpty || appName.contains('/')) {
      return null;
    }
    return appName;
  }

  return null;
}

class _RunRequest {
  _RunRequest({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.newMessage,
    required this.streaming,
    required this.stateDelta,
    required this.invocationId,
  });

  final String appName;
  final String userId;
  final String sessionId;
  final Content? newMessage;
  final bool streaming;
  final Map<String, Object?>? stateDelta;
  final String? invocationId;
}
