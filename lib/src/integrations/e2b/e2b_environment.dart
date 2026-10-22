/// E2B sandbox execution environment integration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../tools/environment/base_environment.dart';

/// Default home directory inside E2B sandboxes.
const String e2bSandboxHome = '/home/user';

/// Default E2B API base URL.
const String defaultE2BApiBaseUrl = 'https://api.e2b.dev';

/// Exception thrown by an E2B sandbox command when it exits with a non-zero status.
///
/// [E2BEnvironment.execute] catches this exception and converts it into an
/// [EnvironmentExecutionResult] with the non-zero [exitCode].
class E2BCommandExitException implements Exception {
  /// Creates an [E2BCommandExitException].
  const E2BCommandExitException({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Process exit code returned by the sandbox command.
  final int exitCode;

  /// Standard output captured before exit.
  final String stdout;

  /// Standard error captured before exit.
  final String stderr;

  @override
  String toString() =>
      'E2BCommandExitException(exitCode: $exitCode, stderr: $stderr)';
}

/// Exception thrown when an E2B sandbox command exceeds its execution timeout.
///
/// [E2BEnvironment.execute] catches this exception and returns an
/// [EnvironmentExecutionResult] with `exitCode: -1` and `timedOut: true`.
class E2BTimeoutException implements Exception {
  /// Creates an [E2BTimeoutException].
  const E2BTimeoutException([this.message = 'Command execution timed out.']);

  /// Human-readable timeout message.
  final String message;

  @override
  String toString() => 'E2BTimeoutException: $message';
}

/// Abstract client interface for managing an E2B sandbox instance.
///
/// ```dart
/// final env = E2BEnvironment(
///   image: 'base',
///   timeout: 300,
///   client: HttpE2BSandboxClient(apiKey: 'e2b_...'),
/// );
/// ```
abstract interface class E2BSandboxClient {
  /// Creates or starts a sandbox with the given [image], [timeoutSeconds],
  /// [apiKey], and [envVars].
  Future<void> initialize({
    String image = 'base',
    int timeoutSeconds = 300,
    String? apiKey,
    Map<String, String>? envVars,
  });

  /// Returns `true` if the sandbox is currently alive and running.
  Future<bool> isRunning();

  /// Refreshes the sandbox TTL to [timeoutSeconds].
  Future<void> setTimeout(int timeoutSeconds);

  /// Executes [command] inside [cwd] with the given [timeout].
  Future<EnvironmentExecutionResult> execute(
    String command, {
    String cwd = e2bSandboxHome,
    Duration timeout = const Duration(seconds: 30),
  });

  /// Reads raw bytes from [path] in the sandbox filesystem.
  Future<List<int>> readFile(String path);

  /// Writes [content] to [path] in the sandbox filesystem.
  Future<void> writeFile(String path, String content);

  /// Writes raw [bytes] to [path] in the sandbox filesystem.
  Future<void> writeBytes(String path, List<int> bytes);

  /// Terminates the sandbox and releases its resources.
  Future<void> close();
}

/// Idiomatic Dart alias for [E2BSandboxClient].
typedef E2bSandboxClient = E2BSandboxClient;

/// Default HTTP / in-memory fallback implementation of [E2BSandboxClient].
///
/// When `baseUrl` and `httpClientFactory` are configured for a remote E2B REST
/// endpoint, requests are dispatched over HTTP; otherwise an in-memory sandbox
/// simulation is used when no network endpoint is provided.
///
/// ```dart
/// final client = HttpE2BSandboxClient(apiKey: 'e2b_test_key');
/// await client.initialize();
/// ```
class HttpE2BSandboxClient implements E2BSandboxClient {
  /// Creates an [HttpE2BSandboxClient].
  HttpE2BSandboxClient({
    this.apiKey,
    this.baseUrl = defaultE2BApiBaseUrl,
    this.useRemoteHttp = false,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Optional E2B API key.
  final String? apiKey;

  /// Base URL for the E2B control/sandbox API.
  final String baseUrl;

  /// Whether to send real HTTP calls to [baseUrl] (`true`) or use local state (`false`).
  final bool useRemoteHttp;

  final HttpClient Function() _httpClientFactory;

  bool _running = false;
  String? _sandboxId;
  int _timeoutSeconds = 300;
  final Map<String, List<int>> _files = <String, List<int>>{};

  /// Active sandbox identifier, if started.
  String? get sandboxId => _sandboxId;

  /// Current configured sandbox TTL in seconds.
  int get timeoutSeconds => _timeoutSeconds;

  @override
  Future<void> initialize({
    String image = 'base',
    int timeoutSeconds = 300,
    String? apiKey,
    Map<String, String>? envVars,
  }) async {
    _timeoutSeconds = timeoutSeconds;
    if (useRemoteHttp) {
      final Map<String, Object?> response = await _postJson(
        '/sandboxes',
        <String, Object?>{
          'templateID': image,
          'timeout': timeoutSeconds,
          'envVars': ?envVars,
        },
        overrideApiKey: apiKey,
      );
      _sandboxId = (response['sandboxID'] ?? response['id'] ?? 'sbx-default')
          .toString();
    } else {
      _sandboxId = 'sbx-${DateTime.now().microsecondsSinceEpoch}';
    }
    _running = true;
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<void> setTimeout(int timeoutSeconds) async {
    _timeoutSeconds = timeoutSeconds;
    if (useRemoteHttp && _sandboxId != null) {
      await _postJson(
        '/sandboxes/$_sandboxId/timeout',
        <String, Object?>{'timeout': timeoutSeconds},
      );
    }
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    String cwd = e2bSandboxHome,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_running) {
      throw StateError('Sandbox is not running.');
    }
    if (useRemoteHttp && _sandboxId != null) {
      final Map<String, Object?> response = await _postJson(
        '/sandboxes/$_sandboxId/commands',
        <String, Object?>{
          'cmd': command,
          'cwd': cwd,
          'timeout': timeout.inMilliseconds / 1000.0,
        },
      );
      return EnvironmentExecutionResult(
        exitCode: (response['exitCode'] as num?)?.toInt() ?? 0,
        stdout: (response['stdout'] as String?) ?? '',
        stderr: (response['stderr'] as String?) ?? '',
        timedOut: (response['timedOut'] as bool?) ?? false,
      );
    }
    return const EnvironmentExecutionResult(exitCode: 0);
  }

  @override
  Future<List<int>> readFile(String path) async {
    if (!_running) {
      throw StateError('Sandbox is not running.');
    }
    if (useRemoteHttp && _sandboxId != null) {
      final Map<String, Object?> response = await _postJson(
        '/sandboxes/$_sandboxId/files/read',
        <String, Object?>{'path': path},
      );
      final Object? content = response['content'];
      if (content is String) {
        return utf8.encode(content);
      }
      if (content is List) {
        return content.whereType<num>().map((num e) => e.toInt()).toList();
      }
    }
    final List<int>? data = _files[path];
    if (data == null) {
      throw FileSystemException('File not found in E2B sandbox', path);
    }
    return List<int>.from(data);
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await writeBytes(path, utf8.encode(content));
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (!_running) {
      throw StateError('Sandbox is not running.');
    }
    if (useRemoteHttp && _sandboxId != null) {
      await _postJson(
        '/sandboxes/$_sandboxId/files/write',
        <String, Object?>{
          'path': path,
          'content': base64Encode(bytes),
          'encoding': 'base64',
        },
      );
    }
    _files[path] = List<int>.from(bytes);
  }

  @override
  Future<void> close() async {
    if (useRemoteHttp && _sandboxId != null && _running) {
      await _postJson('/sandboxes/$_sandboxId/kill', <String, Object?>{});
    }
    _running = false;
    _sandboxId = null;
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body, {
    String? overrideApiKey,
  }) async {
    final HttpClient httpClient = _httpClientFactory();
    try {
      final String normalized = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final Uri uri = Uri.parse('$normalized$path');
      final HttpClientRequest request = await httpClient.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final String? effectiveKey =
          overrideApiKey ?? apiKey ?? Platform.environment['E2B_API_KEY'];
      if (effectiveKey != null && effectiveKey.isNotEmpty) {
        request.headers.set('X-API-Key', effectiveKey);
      }
      request.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse response = await request.close();
      final String responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'E2B API error (${response.statusCode}): $responseText',
          uri: uri,
        );
      }
      if (responseText.trim().isEmpty) {
        return <String, Object?>{};
      }
      final Object? decoded = jsonDecode(responseText);
      if (decoded is Map) {
        return decoded.map((Object? k, Object? v) => MapEntry('$k', v));
      }
      return <String, Object?>{'data': decoded};
    } finally {
      httpClient.close(force: false);
    }
  }
}

/// Idiomatic Dart alias for [HttpE2BSandboxClient].
typedef HttpE2bSandboxClient = HttpE2BSandboxClient;

/// Execution environment backed by an E2B cloud sandbox.
///
/// Provides isolated command execution and file operations via an E2B sandbox.
/// The sandbox is lazily created on [initialize] and destroyed on [close]. If
/// the sandbox expires between tool calls, it is automatically recreated.
///
/// ```dart
/// final env = E2BEnvironment(
///   image: 'base',
///   timeout: 300,
/// );
/// await env.initialize();
/// final result = await env.execute('echo "hello"');
/// await env.close();
/// ```
class E2BEnvironment extends BaseEnvironment {
  /// Creates an [E2BEnvironment].
  E2BEnvironment({
    this.image = 'base',
    this.timeout = 300,
    this.apiKey,
    Map<String, String>? envVars,
    E2BSandboxClient? client,
    super.workingDirectory,
  }) : envVars = envVars == null
           ? null
           : Map<String, String>.unmodifiable(envVars),
       _client = client ?? HttpE2BSandboxClient(apiKey: apiKey),
       _hasExplicitWorkingDir = workingDirectory != null;

  /// E2B sandbox template name or ID.
  final String image;

  /// Sandbox time-to-live (TTL) in seconds, refreshed before each operation.
  final int timeout;

  /// Optional E2B API key (defaults to `E2B_API_KEY` environment variable).
  final String? apiKey;

  /// Environment variables injected into the sandbox on creation.
  final Map<String, String>? envVars;

  final E2BSandboxClient _client;
  final bool _hasExplicitWorkingDir;
  bool _initialized = false;

  /// Underlying [E2BSandboxClient] used by this environment.
  E2BSandboxClient get client => _client;

  /// Returns `true` if the sandbox has been initialized and not yet closed.
  bool get isInitialized => _initialized;

  /// Returns the sandbox working directory (`/home/user` by default).
  ///
  /// Throws a [StateError] if [initialize] has not been called.
  Directory get workingDir {
    if (!_initialized) {
      throw StateError('Sandbox is not started. Call initialize() first.');
    }
    return Directory(_sandboxWorkingDirPath);
  }

  String get _sandboxWorkingDirPath =>
      _hasExplicitWorkingDir ? workingDirectory.path : e2bSandboxHome;

  String _resolvePath(Object path) {
    final String rawPath = switch (path) {
      File file => file.path,
      Directory dir => dir.path,
      Uri uri => uri.toFilePath(),
      _ => '$path',
    };
    if (rawPath.startsWith('/')) {
      return rawPath;
    }
    final String base = _sandboxWorkingDirPath.endsWith('/')
        ? _sandboxWorkingDirPath.substring(0, _sandboxWorkingDirPath.length - 1)
        : _sandboxWorkingDirPath;
    return '$base/$rawPath';
  }

  Future<E2BSandboxClient> _ensureSandbox() async {
    if (!_initialized) {
      throw StateError('Sandbox is not started. Call initialize() first.');
    }
    if (!await _client.isRunning()) {
      await _client.initialize(
        image: image,
        timeoutSeconds: timeout,
        apiKey: apiKey,
        envVars: envVars,
      );
    } else {
      await _client.setTimeout(timeout);
    }
    return _client;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _client.initialize(
      image: image,
      timeoutSeconds: timeout,
      apiKey: apiKey,
      envVars: envVars,
    );
    _initialized = true;
  }

  @override
  Future<void> close() async {
    if (_initialized) {
      try {
        await _client.close();
      } finally {
        _initialized = false;
      }
    }
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final E2BSandboxClient sbx = await _ensureSandbox();
    try {
      return await sbx.execute(
        command,
        cwd: _sandboxWorkingDirPath,
        timeout: timeout,
      );
    } on E2BCommandExitException catch (error) {
      return EnvironmentExecutionResult(
        exitCode: error.exitCode,
        stdout: error.stdout,
        stderr: error.stderr,
      );
    } on E2BTimeoutException {
      return const EnvironmentExecutionResult(exitCode: -1, timedOut: true);
    } on TimeoutException {
      return const EnvironmentExecutionResult(exitCode: -1, timedOut: true);
    }
  }

  @override
  Future<List<int>> readFile(Object path) async {
    final E2BSandboxClient sbx = await _ensureSandbox();
    final String resolved = _resolvePath(path);
    return sbx.readFile(resolved);
  }

  @override
  Future<void> writeFile(Object path, String content) async {
    final E2BSandboxClient sbx = await _ensureSandbox();
    final String resolved = _resolvePath(path);
    await sbx.writeFile(resolved, content);
  }

  /// Writes raw [bytes] to [path] in the sandbox filesystem.
  Future<void> writeBytes(Object path, List<int> bytes) async {
    final E2BSandboxClient sbx = await _ensureSandbox();
    final String resolved = _resolvePath(path);
    await sbx.writeBytes(resolved, bytes);
  }
}

/// Idiomatic Dart alias for [E2BEnvironment].
typedef E2bEnvironment = E2BEnvironment;
