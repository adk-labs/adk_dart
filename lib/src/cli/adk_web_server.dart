import 'dart:io';

import '../dev/project.dart';
import '../dev/runtime.dart';
import '../dev/web_server.dart';

class AdkWebServer {
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

  final String agentsDir;
  final String appName;
  final int port;
  final String host;
  final List<String> allowOrigins;
  final String? sessionServiceUri;
  final String? artifactServiceUri;
  final String? memoryServiceUri;
  final bool useLocalStorage;
  final String? urlPrefix;
  final bool autoCreateSession;
  final bool enableWebUi;
  final String? logoText;
  final String? logoImageUrl;

  DevAgentRuntime? _runtime;
  HttpServer? _server;

  Future<HttpServer> start() async {
    final String projectDir = _resolveProjectDir();
    final DevProjectConfig config = await loadDevProjectConfig(projectDir);
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
