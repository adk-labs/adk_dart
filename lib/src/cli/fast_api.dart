import 'dart:io';

import 'adk_web_server.dart';

class FastApiApp {
  FastApiApp({
    required this.agentsDir,
    this.appName = '',
    this.port = 8000,
    this.host = '127.0.0.1',
  });

  final String agentsDir;
  final String appName;
  final int port;
  final String host;

  AdkWebServer? _server;

  Future<HttpServer> start() async {
    final AdkWebServer server = AdkWebServer(
      agentsDir: agentsDir,
      appName: appName,
      port: port,
      host: host,
    );
    _server = server;
    return server.start();
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
}

FastApiApp getFastApiApp({
  required String agentsDir,
  String appName = '',
  int port = 8000,
  String host = '127.0.0.1',
}) {
  return FastApiApp(
    agentsDir: agentsDir,
    appName: appName,
    port: port,
    host: host,
  );
}
