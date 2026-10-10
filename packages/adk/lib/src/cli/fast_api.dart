/// FastAPI-style server adapter used by ADK CLI tooling.
library;

import 'dart:io';

import 'adk_web_server.dart';

/// Thin wrapper around [AdkWebServer] for web and API server modes.
class FastApiApp {
  /// Creates a FastAPI-compatible app wrapper.
  FastApiApp({
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
    bool? withUi,
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
  }) : withUi = withUi ?? enableWebUi;

  /// Root directory that contains ADK agent projects.
  final String agentsDir;

  /// Optional application name override.
  final String appName;

  /// HTTP port to bind.
  final int port;

  /// Host interface to bind.
  final String host;

  /// Allowed CORS origins.
  final List<String> allowOrigins;

  /// External session service URI override.
  final String? sessionServiceUri;

  /// External artifact service URI override.
  final String? artifactServiceUri;

  /// External memory service URI override.
  final String? memoryServiceUri;

  /// Optional eval storage URI override.
  final String? evalStorageUri;

  /// Whether local storage-backed services are enabled.
  final bool useLocalStorage;

  /// Optional URL prefix used for mounted deployments.
  final String? urlPrefix;

  /// Whether missing sessions are created automatically.
  final bool autoCreateSession;

  /// Whether the browser UI is served alongside API endpoints.
  final bool enableWebUi;

  /// Alias for [enableWebUi] matching `adk api_server --with_ui`.
  final bool withUi;

  /// Optional text shown in the web UI logo area.
  final String? logoText;

  /// Optional image URL shown in the web UI logo area.
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

  AdkWebServer? _server;

  /// Starts the wrapped [AdkWebServer] instance.
  Future<HttpServer> start() async {
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
      enableWebUi: withUi,
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
    );
    _server = server;
    return server.start();
  }

  /// Stops the running server instance, if one has been started.
  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
}

/// Creates a [FastApiApp] with the provided server options.
FastApiApp getFastApiApp({
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
  bool? withUi,
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
}) {
  return FastApiApp(
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
    enableWebUi: withUi ?? enableWebUi,
    withUi: withUi,
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
  );
}
