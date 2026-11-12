/// Remote workspace sandbox execution environment backed by Daytona.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../agents/context.dart';
import '../../environment/base_environment.dart';
import '../../features/_feature_registry.dart';

/// A persistent remote workspace sandbox backed by Daytona.
///
/// Provides isolated remote shell execution and file CRUD operations in the cloud.
class DaytonaEnvironment extends BaseEnvironment {
  /// Creates a Daytona execution environment.
  DaytonaEnvironment({
    this.apiKey,
    this.apiUrl,
    this.image,
    this.timeout = const Duration(seconds: 300),
    this.envVars,
    Directory? workingDir,
    http.Client? httpClient,
  }) : _httpClient = httpClient,
       super(workingDirectory: workingDir ?? Directory('/home/daytona'));

  /// Daytona API key. If null, resolved from `DAYTONA_API_KEY` env var.
  final String? apiKey;

  /// Daytona API URL endpoint. Defaults to `https://app.daytona.io/api`.
  final String? apiUrl;

  /// Sandbox image or template identifier.
  final String? image;

  /// Sandbox execution timeout.
  final Duration timeout;

  /// Environment variables configured inside the sandbox.
  final Map<String, String>? envVars;

  final http.Client? _httpClient;
  String? _sandboxId;

  /// Active Daytona sandbox identifier, if initialized.
  String? get sandboxId => _sandboxId;

  String get _effectiveApiKey =>
      apiKey ?? Platform.environment['DAYTONA_API_KEY'] ?? '';

  String get _effectiveApiUrl =>
      apiUrl ??
      Platform.environment['DAYTONA_SERVER_URL'] ??
      'https://app.daytona.io/api';

  Map<String, String> get _headers => <String, String>{
    'Content-Type': 'application/json',
    if (_effectiveApiKey.isNotEmpty)
      'Authorization': 'Bearer $_effectiveApiKey',
  };

  @override
  Future<void> initialize({Context? ctx}) async {
    isFeatureEnabled(FeatureName.daytonaEnvironment);
    if (isInitialized && _sandboxId != null) {
      return;
    }

    final http.Client client = _httpClient ?? http.Client();
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        if (image != null) 'image': image,
        if (envVars != null) 'env': envVars,
      };

      final http.Response response = await client.post(
        Uri.parse('$_effectiveApiUrl/sandbox'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map && data.containsKey('id')) {
          _sandboxId = data['id'] as String;
        } else {
          _sandboxId = 'daytona-${DateTime.now().millisecondsSinceEpoch}';
        }
      } else {
        _sandboxId = 'daytona-${DateTime.now().millisecondsSinceEpoch}';
      }
      isInitialized = true;
    } catch (_) {
      _sandboxId = 'daytona-${DateTime.now().millisecondsSinceEpoch}';
      isInitialized = true;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<void> close() async {
    if (_sandboxId == null) {
      isInitialized = false;
      return;
    }

    final http.Client client = _httpClient ?? http.Client();
    try {
      await client.delete(
        Uri.parse('$_effectiveApiUrl/sandbox/$_sandboxId'),
        headers: _headers,
      );
    } catch (_) {
    } finally {
      _sandboxId = null;
      isInitialized = false;
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<ExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async {
    await initialize(ctx: ctx);

    final http.Client client = _httpClient ?? http.Client();
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'command': command,
        'timeout': timeout.inSeconds,
      };

      final http.Response response = await client.post(
        Uri.parse('$_effectiveApiUrl/sandbox/$_sandboxId/execute'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map) {
          return ExecutionResult(
            exitCode: (data['exitCode'] ?? data['exit_code'] ?? 0) as int,
            stdout: (data['stdout'] ?? '') as String,
            stderr: (data['stderr'] ?? '') as String,
            timedOut: (data['timedOut'] ?? data['timed_out'] ?? false) as bool,
          );
        }
      }

      return ExecutionResult(
        exitCode: response.statusCode >= 200 && response.statusCode < 300
            ? 0
            : 1,
        stdout: response.body,
      );
    } catch (error) {
      return ExecutionResult(exitCode: -1, stderr: error.toString());
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<Uint8List> readFile(Object path, {Context? ctx}) async {
    await initialize(ctx: ctx);
    final String pathStr = _resolvePath(path);
    final http.Client client = _httpClient ?? http.Client();
    try {
      final http.Response response = await client.get(
        Uri.parse('$_effectiveApiUrl/sandbox/$_sandboxId/file?path=$pathStr'),
        headers: _headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      throw HttpException('Failed to read file $pathStr: ${response.body}');
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<void> writeFile(Object path, Object content, {Context? ctx}) async {
    if (content is! String && content is! List<int>) {
      throw ArgumentError(
        'content must be str or bytes, got ${content.runtimeType}',
      );
    }
    await initialize(ctx: ctx);
    final Uint8List data = encodeWriteFileContent(content);
    final String pathStr = _resolvePath(path);
    final http.Client client = _httpClient ?? http.Client();
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'path': pathStr,
        'content': content is String ? content : base64Encode(data),
        if (content is! String) 'encoding': 'base64',
      };
      final http.Response response = await client.post(
        Uri.parse('$_effectiveApiUrl/sandbox/$_sandboxId/file'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Failed to write file $pathStr: ${response.body}');
      }
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  String _resolvePath(Object path) {
    final String raw = path is FileSystemEntity ? path.path : path.toString();
    if (raw.startsWith('/')) {
      return raw;
    }
    final String root = workingDirectory.path.endsWith('/')
        ? workingDirectory.path.substring(0, workingDirectory.path.length - 1)
        : workingDirectory.path;
    return '$root/$raw';
  }
}
