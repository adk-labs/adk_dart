/// Vertex AI Agent Engine (VMaaS) sandbox execution environment for agent tools.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../tools/environment/base_environment.dart';

/// Exception thrown when an Agent Engine sandbox API call fails.
class AgentEngineSandboxApiException implements Exception {
  /// Creates an Agent Engine sandbox API exception.
  const AgentEngineSandboxApiException({
    this.code,
    this.status,
    required this.message,
  });

  /// Optional HTTP or RPC status code.
  final int? code;

  /// Optional status string (for example, `'FAILED_PRECONDITION'`, `'UNAVAILABLE'`, `'DEADLINE_EXCEEDED'`).
  final String? status;

  /// Human-readable error message.
  final String message;

  @override
  String toString() =>
      'AgentEngineSandboxApiException(code: $code, status: $status, message: $message)';
}

/// Client interface for interacting with a Vertex AI Agent Engine code execution sandbox.
abstract class AgentEngineEnvironmentClient {
  /// Creates a new sandbox inside [agentEngineResourceName] and returns its resource name.
  Future<String> createSandbox({
    required String agentEngineResourceName,
    String? sandboxConfig,
    Duration? ttl,
  });

  /// Executes [command] inside [sandboxResourceName].
  Future<EnvironmentExecutionResult> execute({
    required String sandboxResourceName,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  });

  /// Reads a file at [path] inside [sandboxResourceName].
  Future<Uint8List> readFile({
    required String sandboxResourceName,
    required String path,
  });

  /// Writes [bytes] to [path] inside [sandboxResourceName].
  Future<void> writeFile({
    required String sandboxResourceName,
    required String path,
    required List<int> bytes,
  });

  /// Deletes the sandbox identified by [sandboxResourceName].
  Future<void> deleteSandbox(String sandboxResourceName);

  /// Returns the lifecycle state of [sandboxResourceName] (defaults to `'STATE_RUNNING'`).
  Future<String> getSandboxState(String sandboxResourceName) async =>
      'STATE_RUNNING';

  /// Waits until [sandboxResourceName] transitions to `'STATE_RUNNING'`.
  Future<void> waitUntilRunning(String sandboxResourceName) async {}
}

/// Command-based [AgentEngineEnvironmentClient] that delegates file I/O over shell commands when direct file APIs are unavailable.
class ShellBackedAgentEngineSandboxClient implements AgentEngineEnvironmentClient {
  /// Creates a shell-backed Agent Engine sandbox client using [commandRunner].
  ShellBackedAgentEngineSandboxClient({
    required this.commandRunner,
    Future<String> Function({
      required String agentEngineResourceName,
      String? sandboxConfig,
      Duration? ttl,
    })?
    createSandboxFn,
    Future<void> Function(String sandboxResourceName)? deleteSandboxFn,
    Future<String> Function(String sandboxResourceName)? getSandboxStateFn,
    Future<void> Function(String sandboxResourceName)? waitUntilRunningFn,
  }) : _createSandboxFn = createSandboxFn,
       _deleteSandboxFn = deleteSandboxFn,
       _getSandboxStateFn = getSandboxStateFn,
       _waitUntilRunningFn = waitUntilRunningFn;

  /// Callback that executes a shell command in the remote Agent Engine sandbox.
  final Future<EnvironmentExecutionResult> Function({
    required String sandboxResourceName,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  })
  commandRunner;

  final Future<String> Function({
    required String agentEngineResourceName,
    String? sandboxConfig,
    Duration? ttl,
  })?
  _createSandboxFn;

  final Future<void> Function(String sandboxResourceName)? _deleteSandboxFn;
  final Future<String> Function(String sandboxResourceName)? _getSandboxStateFn;
  final Future<void> Function(String sandboxResourceName)? _waitUntilRunningFn;

  @override
  Future<String> createSandbox({
    required String agentEngineResourceName,
    String? sandboxConfig,
    Duration? ttl,
  }) async {
    if (_createSandboxFn != null) {
      return _createSandboxFn(
        agentEngineResourceName: agentEngineResourceName,
        sandboxConfig: sandboxConfig,
        ttl: ttl,
      );
    }
    return '$agentEngineResourceName/sandboxes/default';
  }

  @override
  Future<EnvironmentExecutionResult> execute({
    required String sandboxResourceName,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  }) {
    return commandRunner(
      sandboxResourceName: sandboxResourceName,
      command: command,
      workingDir: workingDir,
      timeout: timeout,
      envVars: envVars,
    );
  }

  @override
  Future<Uint8List> readFile({
    required String sandboxResourceName,
    required String path,
  }) async {
    final String quoted = _shellQuote(path);
    final EnvironmentExecutionResult res = await execute(
      sandboxResourceName: sandboxResourceName,
      command: 'base64 < $quoted',
    );
    if (res.exitCode != 0) {
      throw StateError(
        "Failed to read '$path' from Agent Engine sandbox: ${res.stderr}",
      );
    }
    final String cleaned = res.stdout.replaceAll(RegExp(r'\s+'), '');
    return Uint8List.fromList(base64Decode(cleaned));
  }

  @override
  Future<void> writeFile({
    required String sandboxResourceName,
    required String path,
    required List<int> bytes,
  }) async {
    final String parentDir = _parentDirectory(path);
    final String quotedPath = _shellQuote(path);
    final String quotedDir = _shellQuote(parentDir);
    final String encoded = base64Encode(bytes);
    final String command =
        'mkdir -p $quotedDir && printf %s ${_shellQuote(encoded)} | base64 -d > $quotedPath';
    final EnvironmentExecutionResult res = await execute(
      sandboxResourceName: sandboxResourceName,
      command: command,
    );
    if (res.exitCode != 0) {
      throw StateError(
        "Failed to write '$path' in Agent Engine sandbox: ${res.stderr}",
      );
    }
  }

  @override
  Future<void> deleteSandbox(String sandboxResourceName) async {
    if (_deleteSandboxFn != null) {
      await _deleteSandboxFn(sandboxResourceName);
    }
  }

  @override
  Future<String> getSandboxState(String sandboxResourceName) async {
    if (_getSandboxStateFn != null) {
      return _getSandboxStateFn(sandboxResourceName);
    }
    return AgentEngineEnvironment.sandboxStateRunning;
  }

  @override
  Future<void> waitUntilRunning(String sandboxResourceName) async {
    if (_waitUntilRunningFn != null) {
      await _waitUntilRunningFn(sandboxResourceName);
    }
  }
}

/// Execution environment backed by a Vertex AI Agent Engine (VMaaS) sandbox.
///
/// ```dart
/// final env = AgentEngineEnvironment(
///   agentEngineResourceName:
///       'projects/my-proj/locations/us-central1/reasoningEngines/123',
/// );
/// ```
class AgentEngineEnvironment extends BaseEnvironment {
  /// Creates an Agent Engine execution environment.
  AgentEngineEnvironment({
    this.agentEngineResourceName,
    this.sandboxResourceName,
    this.workingDir = '/workspace',
    this.ttl,
    this.sandboxConfig,
    this.deleteOnClose = false,
    this.maxUnreachableRetries = defaultMaxUnreachableRetries,
    this.unreachableRetryDelay = Duration.zero,
    AgentEngineEnvironmentClient? client,
    super.workingDirectory,
  }) : _client = client {
    if ((agentEngineResourceName == null ||
            agentEngineResourceName!.trim().isEmpty) &&
        (sandboxResourceName == null || sandboxResourceName!.trim().isEmpty)) {
      throw ArgumentError(
        'Either agentEngineResourceName or sandboxResourceName must be provided.',
      );
    }
  }

  /// Running lifecycle state constant returned by Agent Engine sandboxes.
  static const String sandboxStateRunning = 'STATE_RUNNING';

  /// Default maximum number of retries when a sandbox is temporarily unreachable.
  static const int defaultMaxUnreachableRetries = 5;

  /// Resource name of the parent Vertex AI Agent Engine (`reasoningEngines/*`).
  final String? agentEngineResourceName;

  /// Optional resource name of an existing Agent Engine sandbox.
  final String? sandboxResourceName;

  /// Default working directory inside the sandbox.
  final String workingDir;

  /// Optional time-to-live for newly created sandboxes.
  final Duration? ttl;

  /// Optional sandbox configuration identifier or template.
  final String? sandboxConfig;

  /// Whether a created sandbox should be deleted when [close] is called.
  final bool deleteOnClose;

  /// Maximum number of retries when the sandbox service reports an unreachable sandbox.
  final int maxUnreachableRetries;

  /// Delay between unreachable sandbox retry attempts.
  final Duration unreachableRetryDelay;

  final AgentEngineEnvironmentClient? _client;
  final Map<String, Uint8List> _inMemoryFallbackFiles = <String, Uint8List>{};
  String? _activeSandboxResourceName;
  bool _createdSandbox = false;
  bool _initialized = false;

  /// Active sandbox resource name once initialized.
  String? get activeSandboxResourceName => _activeSandboxResourceName;

  /// Whether this environment has been initialized.
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    if (sandboxResourceName != null && sandboxResourceName!.trim().isNotEmpty) {
      _activeSandboxResourceName = sandboxResourceName!.trim();
      _createdSandbox = false;
    } else if (_client != null) {
      _activeSandboxResourceName = await _client.createSandbox(
        agentEngineResourceName: agentEngineResourceName!.trim(),
        sandboxConfig: sandboxConfig,
        ttl: ttl,
      );
      _createdSandbox = true;
    } else {
      _activeSandboxResourceName =
          '${agentEngineResourceName!.trim()}/sandboxes/default';
      _createdSandbox = true;
    }
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
    final String effectiveWorkingDir = workingDir ?? this.workingDir;
    final String wrappedCommand = _wrapCommandWithEnvAndWorkingDir(
      command: command,
      workingDir: effectiveWorkingDir,
      envVars: envVars,
    );
    if (_client != null) {
      return _executeWithRetry(
        client: _client,
        sandboxName: _activeSandboxResourceName!,
        command: wrappedCommand,
        workingDir: effectiveWorkingDir,
        timeout: timeout,
        envVars: envVars,
      );
    }
    return const EnvironmentExecutionResult(exitCode: 0);
  }

  Future<EnvironmentExecutionResult> _executeWithRetry({
    required AgentEngineEnvironmentClient client,
    required String sandboxName,
    required String command,
    required String workingDir,
    required Duration timeout,
    required Map<String, String>? envVars,
  }) async {
    bool resumed = false;
    int unreachableRetries = 0;
    while (true) {
      try {
        return await client.execute(
          sandboxResourceName: sandboxName,
          command: command,
          workingDir: workingDir,
          timeout: timeout,
          envVars: envVars,
        );
      } catch (error) {
        if (_isTimeoutError(error)) {
          return const EnvironmentExecutionResult(
            exitCode: -1,
            timedOut: true,
          );
        }
        if (_isUnreachableError(error)) {
          if (unreachableRetries < maxUnreachableRetries) {
            unreachableRetries += 1;
            if (unreachableRetryDelay > Duration.zero) {
              await Future<void>.delayed(unreachableRetryDelay);
            }
            continue;
          }
          rethrow;
        }
        if (resumed || !_isPausedOrResumingError(error)) {
          rethrow;
        }
        final String state = await client.getSandboxState(sandboxName);
        if (state == sandboxStateRunning) {
          rethrow;
        }
        await client.waitUntilRunning(sandboxName);
        resumed = true;
        unreachableRetries = 0;
      }
    }
  }

  @override
  Future<List<int>> readFile(Object path) async {
    await initialize();
    final String resolved = _resolvePath('$path');
    if (_client != null) {
      return _client.readFile(
        sandboxResourceName: _activeSandboxResourceName!,
        path: resolved,
      );
    }
    final Uint8List? bytes = _inMemoryFallbackFiles[resolved];
    if (bytes == null) {
      throw StateError("File not found in AgentEngineEnvironment: '$resolved'");
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeFile(Object path, String content) async {
    await writeBytes(path, utf8.encode(content));
  }

  /// Writes raw [bytes] to [path] inside the Agent Engine sandbox.
  Future<void> writeBytes(Object path, List<int> bytes) async {
    await initialize();
    final String resolved = _resolvePath('$path');
    if (_client != null) {
      await _client.writeFile(
        sandboxResourceName: _activeSandboxResourceName!,
        path: resolved,
        bytes: bytes,
      );
      return;
    }
    _inMemoryFallbackFiles[resolved] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> close() async {
    if (!_initialized) {
      return;
    }
    final String? active = _activeSandboxResourceName;
    final bool shouldDelete = deleteOnClose && _createdSandbox;
    _initialized = false;
    _activeSandboxResourceName = null;
    _createdSandbox = false;
    _inMemoryFallbackFiles.clear();
    if (shouldDelete && active != null && _client != null) {
      await _client.deleteSandbox(active);
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

  String _wrapCommandWithEnvAndWorkingDir({
    required String command,
    required String workingDir,
    Map<String, String>? envVars,
  }) {
    final List<String> prefixes = <String>[];
    if (workingDir.isNotEmpty) {
      prefixes.add(
        'mkdir -p ${_shellQuote(workingDir)} && cd ${_shellQuote(workingDir)}',
      );
    }
    if (envVars != null && envVars.isNotEmpty) {
      final String exports = envVars.entries
          .map(
            (MapEntry<String, String> e) =>
                'export ${e.key}=${_shellQuote(e.value)}',
          )
          .join(' && ');
      prefixes.add(exports);
    }
    if (prefixes.isEmpty) {
      return command;
    }
    return '${prefixes.join(' && ')} && $command';
  }
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}

String _parentDirectory(String path) {
  final String normalized = path.replaceAll(r'\', '/');
  final int idx = normalized.lastIndexOf('/');
  if (idx <= 0) {
    return '/';
  }
  return normalized.substring(0, idx);
}

bool _isTimeoutError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is AgentEngineSandboxApiException) {
    return error.code == 504 ||
        error.status == 'DEADLINE_EXCEEDED' ||
        error.message.contains('DEADLINE_EXCEEDED');
  }
  final String text = '$error';
  return text.contains('DEADLINE_EXCEEDED');
}

bool _isUnreachableError(Object error) {
  final String message = error is AgentEngineSandboxApiException
      ? error.message
      : '$error';
  return message.contains('Unable to reach the sandbox environment');
}

bool _isPausedOrResumingError(Object error) {
  if (error is AgentEngineSandboxApiException) {
    return error.code == 503 ||
        error.status == 'UNAVAILABLE' ||
        error.status == 'FAILED_PRECONDITION' ||
        error.message.contains('UNAVAILABLE') ||
        error.message.contains('FAILED_PRECONDITION');
  }
  final String text = '$error';
  return text.contains('UNAVAILABLE') ||
      text.contains('FAILED_PRECONDITION') ||
      text.contains('503');
}
