/// Wrapper for starting and stopping the ADK development web server.
library;

import 'dart:io';

import '../dev/project.dart';
import '../dev/runtime.dart';
import '../dev/web_server.dart';

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
  });

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

  DevAgentRuntime? _runtime;
  HttpServer? _server;

  /// Starts the server and returns the bound [HttpServer].
  Future<HttpServer> start() async {
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
    );
    _runtime = runtime;
    _server = server;
    return server;
  }

  /// Stops the running server and releases runtime resources.
  Future<void> stop() async {
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
