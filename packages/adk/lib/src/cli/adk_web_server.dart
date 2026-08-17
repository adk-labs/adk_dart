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
    this.useLocalStorage = true,
    this.urlPrefix,
    this.autoCreateSession = false,
    this.enableWebUi = true,
    this.logoText,
    this.logoImageUrl,
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
      useLocalStorage: useLocalStorage,
      urlPrefix: urlPrefix,
      autoCreateSession: autoCreateSession,
      enableWebUi: enableWebUi,
      logoText: logoText,
      logoImageUrl: logoImageUrl,
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
  bool useLocalStorage = true,
  String? urlPrefix,
  bool autoCreateSession = false,
  bool enableWebUi = true,
  String? logoText,
  String? logoImageUrl,
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
    useLocalStorage: useLocalStorage,
    urlPrefix: urlPrefix,
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
    logoText: logoText,
    logoImageUrl: logoImageUrl,
  );
  return server.start();
}
