/// Wrapper for starting and stopping the ADK development web server.
library;

import 'dart:async';
import 'dart:io';

import 'package:adk_dart/src/evaluation/eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/eval_sets_manager.dart';

import '../dev/project.dart';
import '../dev/runtime.dart';
import '../dev/web_server.dart';
import 'fast_api.dart';
import 'utils/agent_change_handler.dart';
import 'utils/agent_loader.dart';
import 'utils/base_agent_loader.dart';

export '../dev/web_server.dart'
    show decodeDataUrlTextContentUtf8, defaultEvalManagerSentinel;
export 'api_server.dart';
export 'dev_server.dart';

/// File system watcher for agent source reloads, mirroring `watchdog.observers.Observer`.
///
/// Does not open any OS directory watcher in its constructor; underlying
/// [Directory.watch] subscriptions are only opened when [start] is called.
class AgentsFileObserver {
  /// Creates an idle [AgentsFileObserver].
  AgentsFileObserver();

  final List<(AgentChangeEventHandler handler, String path, bool recursive)>
  _scheduled =
      <(AgentChangeEventHandler, String, bool)>[];
  final List<StreamSubscription<FileSystemEvent>> _subscriptions =
      <StreamSubscription<FileSystemEvent>>[];
  final List<Future<void>> _pendingCancels = <Future<void>>[];

  bool _isRunning = false;
  bool _isStopped = false;
  bool _isJoined = false;
  int _startCallCount = 0;
  int _stopCallCount = 0;
  int _joinCallCount = 0;

  /// Whether [start] has been called and [stop] has not yet been called.
  bool get isRunning => _isRunning;

  /// Whether [stop] has been called.
  bool get isStopped => _isStopped;

  /// Whether [join] has been called.
  bool get isJoined => _isJoined;

  /// Number of times [start] was invoked.
  int get startCallCount => _startCallCount;

  /// Number of times [stop] was invoked.
  int get stopCallCount => _stopCallCount;

  /// Number of times [join] was invoked.
  int get joinCallCount => _joinCallCount;

  /// Read-only view of scheduled `(handler, path, recursive)` watches.
  List<(AgentChangeEventHandler, String, bool)> get scheduledWatches =>
      List<(AgentChangeEventHandler, String, bool)>.unmodifiable(_scheduled);

  /// Schedules [handler] to receive modification events under [path].
  void schedule(
    AgentChangeEventHandler handler,
    String path, {
    bool recursive = true,
  }) {
    final (AgentChangeEventHandler, String, bool) entry = (
      handler,
      path,
      recursive,
    );
    _scheduled.add(entry);
    if (_isRunning) {
      _watchEntry(entry);
    }
  }

  /// Starts watching all scheduled directories.
  void start() {
    _startCallCount += 1;
    if (_isRunning) {
      return;
    }
    _isRunning = true;
    _isStopped = false;
    for (final (AgentChangeEventHandler, String, bool) entry in _scheduled) {
      _watchEntry(entry);
    }
  }

  void _watchEntry((AgentChangeEventHandler, String, bool) entry) {
    final Directory dir = Directory(entry.$2);
    if (!dir.existsSync()) {
      return;
    }
    try {
      final StreamSubscription<FileSystemEvent> sub = dir
          .watch(recursive: entry.$3)
          .listen(
            (FileSystemEvent event) {
              entry.$1.onModified(event.path);
            },
            onError: (_) {
              // Ignore transient filesystem watcher errors on shutdown.
            },
          );
      _subscriptions.add(sub);
    } on FileSystemException {
      // Ignore platforms/filesystems that do not support Directory.watch.
    }
  }

  /// Stops watching all scheduled directories.
  void stop() {
    _stopCallCount += 1;
    _isRunning = false;
    _isStopped = true;
    for (final StreamSubscription<FileSystemEvent> sub in _subscriptions) {
      _pendingCancels.add(sub.cancel());
    }
    _subscriptions.clear();
  }

  /// Waits for any active watcher subscriptions to finish closing.
  Future<void> join() async {
    _joinCallCount += 1;
    _isJoined = true;
    if (_pendingCancels.isNotEmpty) {
      final List<Future<void>> pending = List<Future<void>>.from(
        _pendingCancels,
      );
      _pendingCancels.clear();
      await Future.wait(pending);
    }
  }

  /// Releases underlying OS subscriptions without invoking [stop]/[join] counters.
  Future<void> cancelSubscriptionsQuietly() async {
    _isRunning = false;
    if (_subscriptions.isEmpty) {
      return;
    }
    final List<Future<void>> cancels = <Future<void>>[
      for (final StreamSubscription<FileSystemEvent> sub in _subscriptions)
        sub.cancel(),
    ];
    _subscriptions.clear();
    await Future.wait(cancels);
  }
}

/// Factory signature for constructing an [AgentsFileObserver].
typedef AgentsFileObserverFactory = AgentsFileObserver Function();

/// Optional testing override used to intercept [AgentsFileObserver] construction.
AgentsFileObserverFactory? agentsFileObserverFactoryTestingOverride;

/// Callback invoked to configure and start an [AgentsFileObserver].
typedef SetupObserverCallback =
    FutureOr<void> Function(AgentsFileObserver observer, AdkWebServer server);

/// Callback invoked on server shutdown to stop and join an [AgentsFileObserver].
typedef TearDownObserverCallback =
    FutureOr<void> Function(AgentsFileObserver observer, AdkWebServer server);

/// Configurable wrapper that starts and stops the ADK dev web server.
class AdkWebServer {
  /// Creates a web server launcher for [agentsDir].
  AdkWebServer({
    required this.agentsDir,
    this.appName = '',
    this.port = 8000,
    this.host = '127.0.0.1',
    this.allowOrigins = const <String>[],
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    this.evalStorageUri,
    this.useLocalStorage = true,
    this.urlPrefix,
    this.autoCreateSession = false,
    this.enableWebUi = true,
    this.logoText,
    this.logoImageUrl,
    this.avatarConfig,
    this.maxLlmCalls,
    this.defaultLlmModel,
    this.reload = false,
    this.reloadAgents = false,
    this.traceToCloud = false,
    this.otelToCloud = false,
    this.a2a = false,
    this.extraPlugins = const <String>[],
    this.triggerSources = const <String>[],
    this.triggerOidcAudience,
    this.triggerOidcServiceAccounts = const <String>[],
    this.geminiEnterpriseAppName,
    this.expressMode = false,
    this.maxLiveMessageBytes = 16 * 1024 * 1024,
    this.liveKeepaliveTimeout = const Duration(seconds: 40),
    this.maxLiveSessions = 0,
    this.agentLoader,
    this.environment,
    this.setupObserver,
    this.tearDownObserver,
    Object? evalSetsManager = defaultEvalManagerSentinel,
    Object? evalSetResultsManager = defaultEvalManagerSentinel,
  }) : _evalSetsManagerArg = evalSetsManager,
       _evalSetResultsManagerArg = evalSetResultsManager;

  /// Root directory containing one or more app folders.
  final String agentsDir;

  /// Preferred app folder name when [agentsDir] contains multiple apps.
  final String appName;

  /// TCP port to bind.
  final int port;

  /// Host address to bind.
  final String host;

  /// CORS allow-list entries.
  final List<String> allowOrigins;

  /// Optional session service URI.
  final String? sessionServiceUri;

  /// Optional artifact service URI.
  final String? artifactServiceUri;

  /// Optional memory service URI.
  final String? memoryServiceUri;

  /// Optional eval storage URI.
  final String? evalStorageUri;

  /// Whether to persist local `.adk` state when service URIs are unset.
  final bool useLocalStorage;

  /// Optional URL path prefix, for example `/adk`.
  final String? urlPrefix;

  /// Whether to create missing sessions automatically on `/run`.
  final bool autoCreateSession;

  /// Whether to serve the Dev UI in addition to API routes.
  final bool enableWebUi;

  /// Optional custom header text for the Dev UI.
  final String? logoText;

  /// Optional image URL for the Dev UI logo.
  final String? logoImageUrl;

  /// Optional mapping of agent names to avatar URLs for the Dev UI.
  final Map<String, String>? avatarConfig;

  /// Optional maximum number of LLM calls per invocation.
  final int? maxLlmCalls;

  /// Optional default LLM model name for agents that do not specify one.
  final String? defaultLlmModel;

  /// Whether server auto-reload is enabled.
  final bool reload;

  /// Whether local agent definitions are reloaded on change.
  final bool reloadAgents;

  /// Whether Cloud Trace export is enabled.
  final bool traceToCloud;

  /// Whether OpenTelemetry Google Cloud export is enabled.
  final bool otelToCloud;

  /// Whether A2A protocol endpoints are enabled.
  final bool a2a;

  /// Extra plugin specifications loaded at startup.
  final List<String> extraPlugins;

  /// Event trigger sources to enable (`pubsub`, `eventarc`).
  final List<String> triggerSources;

  /// Expected OIDC audience for authenticating `/apps/{app_name}/trigger/*` requests.
  final String? triggerOidcAudience;

  /// Optional allowlist of service account emails permitted as OIDC token subjects.
  final List<String> triggerOidcServiceAccounts;

  /// Resource name of the Gemini Enterprise App to read settings from.
  final String? geminiEnterpriseAppName;

  /// Whether Gemini Enterprise Express Mode is enabled.
  final bool expressMode;

  /// Maximum allowed `/run_live` WebSocket message size in bytes (`< 0` disables).
  final int maxLiveMessageBytes;

  /// Keepalive timeout for `/run_live` WebSocket connections (`<= Duration.zero` disables).
  final Duration liveKeepaliveTimeout;

  /// Maximum concurrent `/run_live` WebSocket sessions (`<= 0` means unlimited).
  final int maxLiveSessions;

  /// Optional custom [BaseAgentLoader] used instead of the default filesystem loader.
  final BaseAgentLoader? agentLoader;

  /// Optional environment map override (defaults to `Platform.environment`).
  final Map<String, String>? environment;

  /// Optional callback for setting up the agents file watcher.
  ///
  /// Defaults to `null`; no [AgentsFileObserver] is created when both
  /// [setupObserver] is `null` and [reloadAgents] is `false`.
  final SetupObserverCallback? setupObserver;

  /// Optional callback for tearing down the agents file watcher on shutdown.
  final TearDownObserverCallback? tearDownObserver;

  /// App names marked dirty by [AgentChangeEventHandler] for runner reload.
  final Set<String> runnersToClean = <String>{};

  final Object? _evalSetsManagerArg;
  final Object? _evalSetResultsManagerArg;

  /// Explicitly configured [EvalSetsManager], or `null` when unset/default.
  EvalSetsManager? get evalSetsManager =>
      identical(_evalSetsManagerArg, defaultEvalManagerSentinel)
          ? null
          : _evalSetsManagerArg as EvalSetsManager?;

  /// Explicitly configured [EvalSetResultsManager], or `null` when unset/default.
  EvalSetResultsManager? get evalSetResultsManager =>
      identical(_evalSetResultsManagerArg, defaultEvalManagerSentinel)
          ? null
          : _evalSetResultsManagerArg as EvalSetResultsManager?;

  DevAgentRuntime? _runtime;
  HttpServer? _server;
  AgentsFileObserver? _observer;
  TearDownObserverCallback? _effectiveTearDownObserver;

  /// Active [AgentsFileObserver] when agent file watching is enabled, or `null`.
  AgentsFileObserver? get activeObserver => _observer;

  void _ensureObserverConfigured({
    SetupObserverCallback? setupObserverOverride,
    TearDownObserverCallback? tearDownObserverOverride,
    bool includeReloadAgentsDefault = true,
  }) {
    if (_observer != null) {
      return;
    }
    SetupObserverCallback? effectiveSetup =
        setupObserverOverride ?? setupObserver;
    TearDownObserverCallback? effectiveTearDown =
        tearDownObserverOverride ?? tearDownObserver;

    if (effectiveSetup == null && includeReloadAgentsDefault && reloadAgents) {
      effectiveSetup = (AgentsFileObserver obs, AdkWebServer srv) {
        final BaseAgentLoader loader =
            srv.agentLoader ??
            AgentLoader(srv.agentsDir, enableDevProjectFallback: false);
        final AgentChangeEventHandler handler = AgentChangeEventHandler(
          agentLoader: loader,
          runnersToClean: srv.runnersToClean,
          agentsDir: srv.agentsDir,
        );
        obs.schedule(handler, srv.agentsDir, recursive: true);
        obs.start();
      };
      effectiveTearDown ??= (AgentsFileObserver obs, AdkWebServer _) async {
        obs.stop();
        await obs.join();
      };
    }

    // Only construct the file observer when setupObserver is provided.
    if (effectiveSetup != null) {
      final AgentsFileObserver obs =
          (agentsFileObserverFactoryTestingOverride ??
              AgentsFileObserver.new)();
      _observer = obs;
      _effectiveTearDownObserver = effectiveTearDown;
      effectiveSetup(obs, this);
    }
  }

  /// Tears down any active [AgentsFileObserver] configured for this server.
  Future<void> disposeObserver() async {
    final AgentsFileObserver? obs = _observer;
    final TearDownObserverCallback? tearDown = _effectiveTearDownObserver;
    _observer = null;
    _effectiveTearDownObserver = null;
    if (obs != null) {
      if (tearDown != null) {
        await tearDown(obs, this);
      } else {
        await obs.cancelSubscriptionsQuietly();
      }
    }
  }

  /// Builds a [FastApiApp] bound to this server instance, matching
  /// `ApiServer.get_fast_api_app` in `google.adk.cli.api_server`.
  ///
  /// Both [setupObserver] and [tearDownObserver] default to `null`, and no
  /// [AgentsFileObserver] is created when [setupObserver] is `null` (unless
  /// [reloadAgents] is enabled on this server).
  FastApiApp getFastApiApp({
    List<String>? allowOrigins,
    SetupObserverCallback? setupObserver,
    TearDownObserverCallback? tearDownObserver,
    bool? withUi,
  }) {
    _ensureObserverConfigured(
      setupObserverOverride: setupObserver,
      tearDownObserverOverride: tearDownObserver,
      includeReloadAgentsDefault: reloadAgents,
    );
    return FastApiApp.bound(
      server: this,
      allowOrigins: allowOrigins ?? this.allowOrigins,
      withUi: withUi ?? enableWebUi,
    );
  }

  /// Starts the server and returns the bound [HttpServer].
  Future<HttpServer> start() async {
    _ensureObserverConfigured();
    final String projectDir = _resolveProjectDir();
    final DevProjectConfig config = await loadDevProjectConfig(
      projectDir,
      validateProjectDir: true,
    );
    final DevAgentRuntime runtime = DevAgentRuntime(config: config);
    final HttpServer server = await startAdkDevWebServer(
      runtime: runtime,
      project: config,
      agentsDir: projectDir,
      port: port,
      host: InternetAddress.tryParse(host) ?? InternetAddress.loopbackIPv4,
      allowOrigins: allowOrigins,
      sessionServiceUri: sessionServiceUri,
      artifactServiceUri: artifactServiceUri,
      memoryServiceUri: memoryServiceUri,
      evalStorageUri: evalStorageUri,
      useLocalStorage: useLocalStorage,
      urlPrefix: urlPrefix,
      autoCreateSession: autoCreateSession,
      enableWebUi: enableWebUi,
      logoText: logoText,
      logoImageUrl: logoImageUrl,
      avatarConfig: avatarConfig,
      maxLlmCalls: maxLlmCalls,
      defaultLlmModel: defaultLlmModel,
      reload: reload,
      reloadAgents: reloadAgents,
      traceToCloud: traceToCloud,
      otelToCloud: otelToCloud,
      a2a: a2a,
      extraPlugins: extraPlugins,
      triggerSources: triggerSources,
      triggerOidcAudience: triggerOidcAudience,
      triggerOidcServiceAccounts: triggerOidcServiceAccounts,
      geminiEnterpriseAppName: geminiEnterpriseAppName,
      expressMode: expressMode,
      maxLiveMessageBytes: maxLiveMessageBytes,
      liveKeepaliveTimeout: liveKeepaliveTimeout,
      maxLiveSessions: maxLiveSessions,
      agentLoader: agentLoader,
      environment: environment,
      evalSetsManager: _evalSetsManagerArg,
      evalSetResultsManager: _evalSetResultsManagerArg,
    );
    _runtime = runtime;
    _server = server;
    return server;
  }

  /// Stops the running server and releases runtime resources.
  Future<void> stop() async {
    await disposeObserver();
    await _server?.close(force: true);
    await _runtime?.runner.close();
    _runtime = null;
    _server = null;
  }

  String _resolveProjectDir() {
    final Directory base = Directory(agentsDir).absolute;
    final String preferred = appName.trim();
    if (preferred.isNotEmpty) {
      final Directory candidate = Directory(
        '${base.path}${Platform.pathSeparator}$preferred',
      );
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return base.path;
  }
}

/// Starts an [AdkWebServer] with one call.
///
/// Returns the bound [HttpServer].
Future<HttpServer> startAdkWebServer({
  required String agentsDir,
  String appName = '',
  int port = 8000,
  String host = '127.0.0.1',
  List<String> allowOrigins = const <String>[],
  String? sessionServiceUri,
  String? artifactServiceUri,
  String? memoryServiceUri,
  String? evalStorageUri,
  bool useLocalStorage = true,
  String? urlPrefix,
  bool autoCreateSession = false,
  bool enableWebUi = true,
  String? logoText,
  String? logoImageUrl,
  Map<String, String>? avatarConfig,
  int? maxLlmCalls,
  String? defaultLlmModel,
  bool reload = false,
  bool reloadAgents = false,
  bool traceToCloud = false,
  bool otelToCloud = false,
  bool a2a = false,
  List<String> extraPlugins = const <String>[],
  List<String> triggerSources = const <String>[],
  String? triggerOidcAudience,
  List<String> triggerOidcServiceAccounts = const <String>[],
  String? geminiEnterpriseAppName,
  bool expressMode = false,
  int maxLiveMessageBytes = 16 * 1024 * 1024,
  Duration liveKeepaliveTimeout = const Duration(seconds: 40),
  int maxLiveSessions = 0,
}) async {
  final AdkWebServer server = AdkWebServer(
    agentsDir: agentsDir,
    appName: appName,
    port: port,
    host: host,
    allowOrigins: allowOrigins,
    sessionServiceUri: sessionServiceUri,
    artifactServiceUri: artifactServiceUri,
    memoryServiceUri: memoryServiceUri,
    evalStorageUri: evalStorageUri,
    useLocalStorage: useLocalStorage,
    urlPrefix: urlPrefix,
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
    logoText: logoText,
    logoImageUrl: logoImageUrl,
    avatarConfig: avatarConfig,
    maxLlmCalls: maxLlmCalls,
    defaultLlmModel: defaultLlmModel,
    reload: reload,
    reloadAgents: reloadAgents,
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    a2a: a2a,
    extraPlugins: extraPlugins,
    triggerSources: triggerSources,
    triggerOidcAudience: triggerOidcAudience,
    triggerOidcServiceAccounts: triggerOidcServiceAccounts,
    geminiEnterpriseAppName: geminiEnterpriseAppName,
    expressMode: expressMode,
    maxLiveMessageBytes: maxLiveMessageBytes,
    liveKeepaliveTimeout: liveKeepaliveTimeout,
    maxLiveSessions: maxLiveSessions,
  );
  return server.start();
}
