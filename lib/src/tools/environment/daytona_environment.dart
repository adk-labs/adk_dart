/// Remote workspace sandbox execution environment backed by Daytona.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/_feature_registry.dart';
import 'base_environment.dart';

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
    http.Client? httpClient,
  }) : _httpClient = httpClient,
       super(workingDirectory: Directory('/workspaces'));

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
  bool _isInitialized = false;

  String get _effectiveApiKey =>
      apiKey ?? Platform.environment['DAYTONA_API_KEY'] ?? '';

  String get _effectiveApiUrl =>
      apiUrl ??
      Platform.environment['DAYTONA_SERVER_URL'] ??
      'https://app.daytona.io/api';

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (_effectiveApiKey.isNotEmpty) 'Authorization': 'Bearer $_effectiveApiKey',
      };

  @override
  Future<void> initialize() async {
    isFeatureEnabled(FeatureName.daytonaEnvironment);
    if (_isInitialized && _sandboxId != null) {
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
        // Fallback to synthetic sandbox identifier if mocking/local proxy
        _sandboxId = 'daytona-${DateTime.now().millisecondsSinceEpoch}';
      }
      _isInitialized = true;
    } catch (_) {
      _sandboxId = 'daytona-${DateTime.now().millisecondsSinceEpoch}';
      _isInitialized = true;
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<void> close() async {
    if (_sandboxId == null) {
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
      _isInitialized = false;
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await initialize();

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
          return EnvironmentExecutionResult(
            exitCode: (data['exitCode'] ?? data['exit_code'] ?? 0) as int,
            stdout: (data['stdout'] ?? '') as String,
            stderr: (data['stderr'] ?? '') as String,
            timedOut: (data['timedOut'] ?? data['timed_out'] ?? false) as bool,
          );
        }
      }

      return EnvironmentExecutionResult(
        exitCode: response.statusCode >= 200 && response.statusCode < 300 ? 0 : 1,
        stdout: response.body,
      );
    } catch (error) {
      return EnvironmentExecutionResult(
        exitCode: -1,
        stderr: error.toString(),
      );
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<List<int>> readFile(Object path) async {
    await initialize();
    final String pathStr = path.toString();
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
  Future<void> writeFile(Object path, String content) async {
    await initialize();
    final String pathStr = path.toString();
    final http.Client client = _httpClient ?? http.Client();
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'path': pathStr,
        'content': content,
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
}
