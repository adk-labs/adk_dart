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
    this.useLocalStorage = true,
    this.urlPrefix,
    this.autoCreateSession = false,
    this.enableWebUi = true,
    this.logoText,
    this.logoImageUrl,
  });

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

  /// Whether local storage-backed services are enabled.
  final bool useLocalStorage;

  /// Optional URL prefix used for mounted deployments.
  final String? urlPrefix;

  /// Whether missing sessions are created automatically.
  final bool autoCreateSession;

  /// Whether the browser UI is served alongside API endpoints.
  final bool enableWebUi;

  /// Optional text shown in the web UI logo area.
  final String? logoText;

  /// Optional image URL shown in the web UI logo area.
  final String? logoImageUrl;

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
      useLocalStorage: useLocalStorage,
      urlPrefix: urlPrefix,
      autoCreateSession: autoCreateSession,
      enableWebUi: enableWebUi,
      logoText: logoText,
      logoImageUrl: logoImageUrl,
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
  bool useLocalStorage = true,
  String? urlPrefix,
  bool autoCreateSession = false,
  bool enableWebUi = true,
  String? logoText,
  String? logoImageUrl,
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
    useLocalStorage: useLocalStorage,
    urlPrefix: urlPrefix,
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
    logoText: logoText,
    logoImageUrl: logoImageUrl,
  );
}
