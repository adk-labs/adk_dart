/// OpenSandbox execution environment implementation for agent tools.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../tools/environment/base_environment.dart';

/// Client interface for communicating with an OpenSandbox instance.
abstract class OpenSandboxClient {
  /// Starts or attaches to an OpenSandbox instance and returns its sandbox ID.
  Future<String> createOrAttachSandbox({
    required String image,
    Duration? timeout,
    Map<String, String>? envVars,
  });

  /// Executes [command] inside [sandboxId].
  Future<EnvironmentExecutionResult> execute({
    required String sandboxId,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  });

  /// Reads raw bytes from [path] inside [sandboxId].
  Future<Uint8List> readFile({
    required String sandboxId,
    required String path,
  });

  /// Writes [bytes] to [path] inside [sandboxId].
  Future<void> writeFile({
    required String sandboxId,
    required String path,
    required List<int> bytes,
  });

  /// Destroys or detaches from [sandboxId].
  Future<void> closeSandbox(String sandboxId);
}

/// HTTP-backed [OpenSandboxClient] speaking the OpenSandbox REST API.
class HttpOpenSandboxClient implements OpenSandboxClient {
  /// Creates an HTTP client targeting [endpoint].
  HttpOpenSandboxClient({
    required this.endpoint,
    this.apiKey,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  /// Base URL of the OpenSandbox server.
  final Uri endpoint;

  /// Optional bearer or API key token for authentication.
  final String? apiKey;

  final HttpClient _httpClient;

  @override
  Future<String> createOrAttachSandbox({
    required String image,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async {
    final Map<String, Object?> response = await _postJson(
      '/v1/sandboxes',
      <String, Object?>{
        'image': image,
        if (timeout != null) 'timeout_seconds': timeout.inSeconds,
        if (envVars != null && envVars.isNotEmpty) 'env': envVars,
      },
    );
    final Object? id = response['sandbox_id'] ?? response['id'];
    if (id is String && id.isNotEmpty) {
      return id;
    }
    throw StateError('OpenSandbox server did not return a sandbox_id.');
  }

  @override
  Future<EnvironmentExecutionResult> execute({
    required String sandboxId,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async {
    final Map<String, Object?> response = await _postJson(
      '/v1/sandboxes/$sandboxId/commands',
      <String, Object?>{
        'command': command,
        'working_dir': ?workingDir,
        if (timeout != null) 'timeout_seconds': timeout.inSeconds,
        if (envVars != null && envVars.isNotEmpty) 'env': envVars,
      },
    );
    return EnvironmentExecutionResult(
      exitCode: (response['exit_code'] as num?)?.toInt() ?? 0,
      stdout: '${response['stdout'] ?? ''}',
      stderr: '${response['stderr'] ?? ''}',
      timedOut: response['timed_out'] == true,
    );
  }

  @override
  Future<Uint8List> readFile({
    required String sandboxId,
    required String path,
  }) async {
    final Map<String, Object?> response = await _postJson(
      '/v1/sandboxes/$sandboxId/files/read',
      <String, Object?>{'path': path},
    );
    if (response['content_b64'] is String) {
      return Uint8List.fromList(
        base64Decode(response['content_b64'] as String),
      );
    }
    return Uint8List.fromList(utf8.encode('${response['content'] ?? ''}'));
  }

  @override
  Future<void> writeFile({
    required String sandboxId,
    required String path,
    required List<int> bytes,
  }) async {
    await _postJson(
      '/v1/sandboxes/$sandboxId/files/write',
      <String, Object?>{
        'path': path,
        'content_b64': base64Encode(bytes),
      },
    );
  }

  @override
  Future<void> closeSandbox(String sandboxId) async {
    await _postJson(
      '/v1/sandboxes/$sandboxId/close',
      const <String, Object?>{},
    );
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final Uri uri = endpoint.resolve(path);
    final HttpClientRequest request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    if (apiKey != null && apiKey!.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    request.write(jsonEncode(body));
    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'OpenSandbox request failed (${response.statusCode}): $responseBody',
        uri: uri,
      );
    }
    if (responseBody.trim().isEmpty) {
      return const <String, Object?>{};
    }
    final Object? decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
    return const <String, Object?>{};
  }
}

/// Execution environment backed by an OpenSandbox container instance.
///
/// ```dart
/// final env = OpenSandboxEnvironment(
///   image: 'ubuntu:22.04',
///   endpoint: Uri.parse('http://localhost:8080'),
/// );
/// await env.initialize();
/// ```
class OpenSandboxEnvironment extends BaseEnvironment {
  /// Creates an OpenSandbox execution environment.
  OpenSandboxEnvironment({
    this.image = 'ubuntu:latest',
    this.workingDir = '/workspace',
    this.sandboxId,
    this.timeout = const Duration(minutes: 10),
    this.envVars = const <String, String>{},
    Uri? endpoint,
    String? apiKey,
    OpenSandboxClient? client,
    super.workingDirectory,
  }) : _client =
           client ??
           HttpOpenSandboxClient(
             endpoint: endpoint ?? Uri.parse('http://localhost:8080'),
             apiKey: apiKey,
           );

  /// Container image used when creating a new sandbox.
  final String image;

  /// Default working directory inside the sandbox.
  final String workingDir;

  /// Optional pre-existing sandbox identifier to attach to.
  final String? sandboxId;

  /// Default sandbox lifecycle timeout.
  final Duration timeout;

  /// Default environment variables injected into the sandbox.
  final Map<String, String> envVars;

  final OpenSandboxClient _client;
  String? _activeSandboxId;
  bool _initialized = false;

  /// Currently active sandbox ID after [initialize] has completed.
  String? get activeSandboxId => _activeSandboxId;

  /// Whether this environment has been initialized.
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _activeSandboxId =
        sandboxId ??
        await _client.createOrAttachSandbox(
          image: image,
          timeout: timeout,
          envVars: envVars,
        );
    _initialized = true;
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    String? workingDir,
    Map<String, String>? envVars,
  }) async {
    await initialize();
    final Map<String, String> mergedEnv = <String, String>{
      ...this.envVars,
      ...?envVars,
    };
    return _client.execute(
      sandboxId: _activeSandboxId!,
      command: command,
      workingDir: workingDir ?? this.workingDir,
      timeout: timeout,
      envVars: mergedEnv.isEmpty ? null : mergedEnv,
    );
  }

  @override
  Future<List<int>> readFile(Object path) async {
    await initialize();
    final String resolved = _resolvePath('$path');
    return _client.readFile(sandboxId: _activeSandboxId!, path: resolved);
  }

  @override
  Future<void> writeFile(Object path, String content) async {
    await writeBytes(path, utf8.encode(content));
  }

  /// Writes raw [bytes] to [path] inside the sandbox.
  Future<void> writeBytes(Object path, List<int> bytes) async {
    await initialize();
    final String resolved = _resolvePath('$path');
    await _client.writeFile(
      sandboxId: _activeSandboxId!,
      path: resolved,
      bytes: bytes,
    );
  }

  @override
  Future<void> close() async {
    if (!_initialized) {
      return;
    }
    final String? id = _activeSandboxId;
    _initialized = false;
    _activeSandboxId = null;
    if (id != null && sandboxId == null) {
      await _client.closeSandbox(id);
    }
  }

  String _resolvePath(String path) {
    final String normalized = path.replaceAll(r'\', '/');
    if (normalized.startsWith('/')) {
      return normalized;
    }
    final String base = workingDir.replaceAll(RegExp(r'/+$'), '');
    return '$base/$normalized';
  }
}
