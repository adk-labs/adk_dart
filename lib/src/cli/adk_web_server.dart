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
  });

  final String agentsDir;
  final String appName;
  final int port;
  final String host;

  DevAgentRuntime? _runtime;
  HttpServer? _server;

  Future<HttpServer> start() async {
    final String projectDir = _resolveProjectDir();
    final DevProjectConfig config = await loadDevProjectConfig(projectDir);
    final DevAgentRuntime runtime = DevAgentRuntime(config: config);
    final HttpServer server = await startAdkDevWebServer(
      runtime: runtime,
      project: config,
      port: port,
      host: InternetAddress.tryParse(host) ?? InternetAddress.loopbackIPv4,
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
}) async {
  final AdkWebServer server = AdkWebServer(
    agentsDir: agentsDir,
    appName: appName,
    port: port,
    host: host,
  );
  return server.start();
}
