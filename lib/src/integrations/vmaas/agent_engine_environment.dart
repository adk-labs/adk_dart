/// Vertex AI Agent Engine (VMaaS) sandbox execution environment and computer-use integration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../tools/computer_use/base_computer.dart';
import '../../tools/environment/base_environment.dart';
import '../../tools/tool_context.dart';

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
class ShellBackedAgentEngineSandboxClient
    implements AgentEngineEnvironmentClient {
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

// ============================================================================
// VMaaS Computer Use: SandboxClient, SandboxManager, AgentEngineSandboxComputer
// ============================================================================

/// Session state key used by [AgentEngineSandboxComputer] to persist the sandbox resource name.
const String vmaasSandboxStateKey = '_adk_vmaas_sandbox_name';

/// Chrome DevTools Protocol (CDP) special key definitions keyed by lowercase name.
const Map<String, Map<String, Object>> cdpSpecialKeys =
    <String, Map<String, Object>>{
      'enter': <String, Object>{
        'key': 'Enter',
        'code': 'Enter',
        'windowsVirtualKeyCode': 13,
      },
      'return': <String, Object>{
        'key': 'Enter',
        'code': 'Enter',
        'windowsVirtualKeyCode': 13,
      },
      'backspace': <String, Object>{
        'key': 'Backspace',
        'code': 'Backspace',
        'windowsVirtualKeyCode': 8,
      },
      'tab': <String, Object>{
        'key': 'Tab',
        'code': 'Tab',
        'windowsVirtualKeyCode': 9,
      },
      'space': <String, Object>{
        'key': ' ',
        'code': 'Space',
        'windowsVirtualKeyCode': 32,
      },
      ' ': <String, Object>{
        'key': ' ',
        'code': 'Space',
        'windowsVirtualKeyCode': 32,
      },
      'escape': <String, Object>{
        'key': 'Escape',
        'code': 'Escape',
        'windowsVirtualKeyCode': 27,
      },
      'esc': <String, Object>{
        'key': 'Escape',
        'code': 'Escape',
        'windowsVirtualKeyCode': 27,
      },
      'delete': <String, Object>{
        'key': 'Delete',
        'code': 'Delete',
        'windowsVirtualKeyCode': 46,
      },
      'arrowup': <String, Object>{
        'key': 'ArrowUp',
        'code': 'ArrowUp',
        'windowsVirtualKeyCode': 38,
      },
      'up': <String, Object>{
        'key': 'ArrowUp',
        'code': 'ArrowUp',
        'windowsVirtualKeyCode': 38,
      },
      'arrowdown': <String, Object>{
        'key': 'ArrowDown',
        'code': 'ArrowDown',
        'windowsVirtualKeyCode': 40,
      },
      'down': <String, Object>{
        'key': 'ArrowDown',
        'code': 'ArrowDown',
        'windowsVirtualKeyCode': 40,
      },
      'arrowleft': <String, Object>{
        'key': 'ArrowLeft',
        'code': 'ArrowLeft',
        'windowsVirtualKeyCode': 37,
      },
      'left': <String, Object>{
        'key': 'ArrowLeft',
        'code': 'ArrowLeft',
        'windowsVirtualKeyCode': 37,
      },
      'arrowright': <String, Object>{
        'key': 'ArrowRight',
        'code': 'ArrowRight',
        'windowsVirtualKeyCode': 39,
      },
      'right': <String, Object>{
        'key': 'ArrowRight',
        'code': 'ArrowRight',
        'windowsVirtualKeyCode': 39,
      },
      'home': <String, Object>{
        'key': 'Home',
        'code': 'Home',
        'windowsVirtualKeyCode': 36,
      },
      'end': <String, Object>{
        'key': 'End',
        'code': 'End',
        'windowsVirtualKeyCode': 35,
      },
      'pageup': <String, Object>{
        'key': 'PageUp',
        'code': 'PageUp',
        'windowsVirtualKeyCode': 33,
      },
      'pagedown': <String, Object>{
        'key': 'PageDown',
        'code': 'PageDown',
        'windowsVirtualKeyCode': 34,
      },
      'control': <String, Object>{
        'key': 'Control',
        'code': 'ControlLeft',
        'windowsVirtualKeyCode': 17,
      },
      'ctrl': <String, Object>{
        'key': 'Control',
        'code': 'ControlLeft',
        'windowsVirtualKeyCode': 17,
      },
      'alt': <String, Object>{
        'key': 'Alt',
        'code': 'AltLeft',
        'windowsVirtualKeyCode': 18,
      },
      'shift': <String, Object>{
        'key': 'Shift',
        'code': 'ShiftLeft',
        'windowsVirtualKeyCode': 16,
      },
      'meta': <String, Object>{
        'key': 'Meta',
        'code': 'MetaLeft',
        'windowsVirtualKeyCode': 91,
      },
      'command': <String, Object>{
        'key': 'Meta',
        'code': 'MetaLeft',
        'windowsVirtualKeyCode': 91,
      },
      'cmd': <String, Object>{
        'key': 'Meta',
        'code': 'MetaLeft',
        'windowsVirtualKeyCode': 91,
      },
      'f1': <String, Object>{
        'key': 'F1',
        'code': 'F1',
        'windowsVirtualKeyCode': 112,
      },
      'f2': <String, Object>{
        'key': 'F2',
        'code': 'F2',
        'windowsVirtualKeyCode': 113,
      },
      'f3': <String, Object>{
        'key': 'F3',
        'code': 'F3',
        'windowsVirtualKeyCode': 114,
      },
      'f4': <String, Object>{
        'key': 'F4',
        'code': 'F4',
        'windowsVirtualKeyCode': 115,
      },
      'f5': <String, Object>{
        'key': 'F5',
        'code': 'F5',
        'windowsVirtualKeyCode': 116,
      },
      'f6': <String, Object>{
        'key': 'F6',
        'code': 'F6',
        'windowsVirtualKeyCode': 117,
      },
      'f7': <String, Object>{
        'key': 'F7',
        'code': 'F7',
        'windowsVirtualKeyCode': 118,
      },
      'f8': <String, Object>{
        'key': 'F8',
        'code': 'F8',
        'windowsVirtualKeyCode': 119,
      },
      'f9': <String, Object>{
        'key': 'F9',
        'code': 'F9',
        'windowsVirtualKeyCode': 120,
      },
      'f10': <String, Object>{
        'key': 'F10',
        'code': 'F10',
        'windowsVirtualKeyCode': 121,
      },
      'f11': <String, Object>{
        'key': 'F11',
        'code': 'F11',
        'windowsVirtualKeyCode': 122,
      },
      'f12': <String, Object>{
        'key': 'F12',
        'code': 'F12',
        'windowsVirtualKeyCode': 123,
      },
    };

/// CDP modifier bitflags (`Alt=1`, `Ctrl=2`, `Meta=4`, `Shift=8`).
const Map<String, int> cdpModifierBitflags = <String, int>{
  'alt': 1,
  'control': 2,
  'ctrl': 2,
  'meta': 4,
  'command': 4,
  'cmd': 4,
  'shift': 8,
};

/// Client for communicating with a Vertex AI Agent Engine browser sandbox via
/// Chrome DevTools Protocol (CDP) over the `ExecuteSandboxEnvironment` endpoint.
///
/// ```dart
/// final client = SandboxClient(
///   accessToken: 'ya29.example',
///   endpoint: 'https://us-central1-aiplatform.googleapis.com',
/// );
/// await client.navigate(sandboxName, 'https://www.google.com');
/// ```
class SandboxClient {
  /// Creates a [SandboxClient].
  SandboxClient({
    required String accessToken,
    String endpoint = 'https://us-central1-aiplatform.googleapis.com',
    this.actionWaitDelay = Duration.zero,
    Future<List<Map<String, Object?>>> Function({
      required String sandboxName,
      required List<Map<String, Object?>> commands,
      required String accessToken,
      required String baseUrl,
    })?
    cdpTransport,
    HttpClient Function()? httpClientFactory,
  }) : _accessToken = accessToken,
       baseUrl = endpoint.startsWith('https://')
           ? endpoint
           : 'https://$endpoint',
       _cdpTransport = cdpTransport,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  String _accessToken;

  /// Normalized `https://` base URL for the Vertex AI regional endpoint.
  final String baseUrl;

  /// Optional delay waited after browser navigation/interaction commands.
  final Duration actionWaitDelay;

  final Future<List<Map<String, Object?>>> Function({
    required String sandboxName,
    required List<Map<String, Object?>> commands,
    required String accessToken,
    required String baseUrl,
  })?
  _cdpTransport;

  final HttpClient Function() _httpClientFactory;

  /// Recorded CDP command batches dispatched through this client.
  final List<({String sandboxName, List<Map<String, Object?>> commands})>
  recordedBatches =
      <({String sandboxName, List<Map<String, Object?>> commands})>[];

  /// Current bearer access token.
  String get accessToken => _accessToken;

  /// Updates the bearer access token used for subsequent requests.
  void updateAccessToken(String newToken) {
    _accessToken = newToken;
  }

  /// Sends a single CDP command (`method` + `params`) to [sandboxName].
  Future<Map<String, Object?>> makeCdpRequest(
    String sandboxName,
    String method, [
    Map<String, Object?>? params,
  ]) async {
    final List<Map<String, Object?>> results = await makeCdpBatchRequest(
      sandboxName,
      <Map<String, Object?>>[
        <String, Object?>{
          'method': method,
          'params': params ?? <String, Object?>{},
        },
      ],
    );
    return results.isNotEmpty ? results.first : <String, Object?>{};
  }

  /// Sends a batch of CDP [commands] in a single `execute` request to [sandboxName].
  Future<List<Map<String, Object?>>> makeCdpBatchRequest(
    String sandboxName,
    List<Map<String, Object?>> commands,
  ) async {
    recordedBatches.add((
      sandboxName: sandboxName,
      commands: List<Map<String, Object?>>.from(commands),
    ));

    if (_cdpTransport != null) {
      return _cdpTransport(
        sandboxName: sandboxName,
        commands: commands,
        accessToken: _accessToken,
        baseUrl: baseUrl,
      );
    }

    final List<Map<String, Object?>> payloadCommands = <Map<String, Object?>>[];
    for (int i = 0; i < commands.length; i++) {
      final Map<String, Object?> cmd = commands[i];
      payloadCommands.add(<String, Object?>{
        'id': i + 1,
        'method': cmd['method'],
        'params': cmd['params'] ?? <String, Object?>{},
      });
    }

    final Map<String, Object?> cdpBatchJson = <String, Object?>{
      'commands': payloadCommands,
    };
    final String b64Data = base64Encode(utf8.encode(jsonEncode(cdpBatchJson)));
    final Map<String, Object?> requestBody = <String, Object?>{
      'inputs': <Map<String, Object?>>[
        <String, Object?>{
          'mimeType': 'application/json;type=cdp',
          'data': b64Data,
        },
      ],
    };

    final HttpClient httpClient = _httpClientFactory();
    try {
      final Uri uri = Uri.parse('$baseUrl/v1beta1/$sandboxName:execute');
      final HttpClientRequest request = await httpClient.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(requestBody)));
      final HttpClientResponse response = await request.close();
      final String responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'ExecuteSandboxEnvironment failed (${response.statusCode}): $responseText',
          uri: uri,
        );
      }
      if (responseText.trim().isEmpty) {
        return <Map<String, Object?>>[];
      }
      final Object? decoded = jsonDecode(responseText);
      if (decoded is! Map) {
        return <Map<String, Object?>>[];
      }
      final Object? outputs = decoded['outputs'];
      if (outputs is List && outputs.isNotEmpty) {
        final Object? firstOutput = outputs.first;
        if (firstOutput is Map && firstOutput['data'] is String) {
          final String decodedOutput = utf8.decode(
            base64Decode(firstOutput['data'] as String),
          );
          final Object? parsed = jsonDecode(decodedOutput);
          if (parsed is Map && parsed['responses'] is List) {
            return (parsed['responses'] as List)
                .whereType<Map<Object?, Object?>>()
                .map(
                  (Map<Object?, Object?> item) =>
                      item.map((Object? k, Object? v) => MapEntry('$k', v)),
                )
                .toList();
          }
          if (parsed is Map) {
            return <Map<String, Object?>>[
              parsed.map((Object? k, Object? v) => MapEntry('$k', v)),
            ];
          }
        }
      }
      return <Map<String, Object?>>[];
    } finally {
      httpClient.close(force: false);
    }
  }

  /// Captures a PNG screenshot from [sandboxName] via `Page.captureScreenshot`.
  Future<Uint8List?> getScreenshot(String sandboxName) async {
    final Map<String, Object?> res = await makeCdpRequest(
      sandboxName,
      'Page.captureScreenshot',
      <String, Object?>{'format': 'png'},
    );
    final Object? result = res['result'];
    if (result is Map && result['data'] is String) {
      return Uint8List.fromList(base64Decode(result['data'] as String));
    }
    return null;
  }

  /// Retrieves the current `window.location.href` from [sandboxName].
  Future<String> getCurrentUrl(String sandboxName) async {
    final Map<String, Object?> res = await makeCdpRequest(
      sandboxName,
      'Runtime.evaluate',
      <String, Object?>{
        'expression': 'window.location.href',
        'returnByValue': true,
      },
    );
    final Object? outerResult = res['result'];
    if (outerResult is Map) {
      final Object? innerResult = outerResult['result'];
      if (innerResult is Map && innerResult['value'] is String) {
        return innerResult['value'] as String;
      }
    }
    return '';
  }

  /// Navigates [sandboxName] to [url], prepending `https://` when no scheme is present.
  Future<void> navigate(String sandboxName, String url) async {
    final String normalizedUrl =
        (url.startsWith('http://') || url.startsWith('https://'))
        ? url
        : 'https://$url';
    await makeCdpRequest(
      sandboxName,
      'Page.navigate',
      <String, Object?>{'url': normalizedUrl},
    );
    if (actionWaitDelay > Duration.zero) {
      await Future<void>.delayed(actionWaitDelay);
    }
  }

  /// Performs a left mouse click at `(x, y)`.
  Future<void> clickAt(String sandboxName, int x, int y) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 1,
          'clickCount': 1,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 0,
          'clickCount': 1,
        },
      },
    ]);
    if (actionWaitDelay > Duration.zero) {
      await Future<void>.delayed(actionWaitDelay);
    }
  }

  /// Moves the mouse cursor to `(x, y)` without clicking.
  Future<void> hoverAt(String sandboxName, int x, int y) async {
    await makeCdpRequest(
      sandboxName,
      'Input.dispatchMouseEvent',
      <String, Object?>{'type': 'mouseMoved', 'x': x, 'y': y},
    );
  }

  /// Moves the mouse cursor to `(x, y)`.
  Future<void> move(String sandboxName, int x, int y) =>
      hoverAt(sandboxName, x, y);

  /// Presses and holds the left mouse button at `(x, y)`.
  Future<void> mouseDown(String sandboxName, int x, int y) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 1,
          'clickCount': 1,
        },
      },
    ]);
  }

  /// Releases the left mouse button at `(x, y)`.
  Future<void> mouseUp(String sandboxName, int x, int y) async {
    await makeCdpRequest(
      sandboxName,
      'Input.dispatchMouseEvent',
      <String, Object?>{
        'type': 'mouseReleased',
        'x': x,
        'y': y,
        'button': 'left',
        'buttons': 0,
        'clickCount': 1,
      },
    );
  }

  /// Performs a right-click (context click) at `(x, y)`.
  Future<void> contextClick(String sandboxName, int x, int y) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'right',
          'buttons': 2,
          'clickCount': 1,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'right',
          'buttons': 0,
          'clickCount': 1,
        },
      },
    ]);
  }

  /// Performs a double-click at `(x, y)`.
  Future<void> doubleClick(String sandboxName, int x, int y) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 1,
          'clickCount': 1,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 0,
          'clickCount': 1,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 1,
          'clickCount': 2,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 0,
          'clickCount': 2,
        },
      },
    ]);
  }

  /// Performs a triple-click at `(x, y)`.
  Future<void> tripleClick(String sandboxName, int x, int y) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      for (int count = 1; count <= 3; count++) ...<Map<String, Object?>>[
        <String, Object?>{
          'method': 'Input.dispatchMouseEvent',
          'params': <String, Object?>{
            'type': 'mousePressed',
            'x': x,
            'y': y,
            'button': 'left',
            'buttons': 1,
            'clickCount': count,
          },
        },
        <String, Object?>{
          'method': 'Input.dispatchMouseEvent',
          'params': <String, Object?>{
            'type': 'mouseReleased',
            'x': x,
            'y': y,
            'button': 'left',
            'buttons': 0,
            'clickCount': count,
          },
        },
      ],
    ]);
  }

  /// Performs a middle mouse button click at `(x, y)`.
  Future<void> middleClick(String sandboxName, int x, int y) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'middle',
          'buttons': 4,
          'clickCount': 1,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'middle',
          'buttons': 0,
          'clickCount': 1,
        },
      },
    ]);
  }

  /// Types [text] into the currently focused element in [sandboxName].
  Future<void> typeText(
    String sandboxName,
    String text, {
    bool pressEnter = false,
  }) async {
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.insertText',
        'params': <String, Object?>{'text': text},
      },
    ];
    if (pressEnter) {
      final Map<String, Object> enterSpec = cdpSpecialKeys['enter']!;
      commands.addAll(<Map<String, Object?>>[
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{'type': 'keyDown', ...enterSpec},
        },
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{'type': 'keyUp', ...enterSpec},
        },
      ]);
    }
    await makeCdpBatchRequest(sandboxName, commands);
  }

  /// Clicks at `(x, y)`, optionally clears existing input, and types [text].
  Future<void> typeTextAt(
    String sandboxName,
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) async {
    await clickAt(sandboxName, x, y);
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
    if (clearBeforeTyping) {
      final Map<String, Object> backSpec = cdpSpecialKeys['backspace']!;
      commands.addAll(<Map<String, Object?>>[
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{
            'type': 'keyDown',
            'modifiers': 2,
            'key': 'a',
            'code': 'KeyA',
            'windowsVirtualKeyCode': 65,
          },
        },
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{
            'type': 'keyUp',
            'modifiers': 0,
            'key': 'a',
            'code': 'KeyA',
            'windowsVirtualKeyCode': 65,
          },
        },
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{'type': 'keyDown', ...backSpec},
        },
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{'type': 'keyUp', ...backSpec},
        },
      ]);
    }
    commands.add(<String, Object?>{
      'method': 'Input.insertText',
      'params': <String, Object?>{'text': text},
    });
    if (pressEnter) {
      final Map<String, Object> enterSpec = cdpSpecialKeys['enter']!;
      commands.addAll(<Map<String, Object?>>[
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{'type': 'keyDown', ...enterSpec},
        },
        <String, Object?>{
          'method': 'Input.dispatchKeyEvent',
          'params': <String, Object?>{'type': 'keyUp', ...enterSpec},
        },
      ]);
    }
    await makeCdpBatchRequest(sandboxName, commands);
  }

  Map<String, Object?> _buildKeyParams(
    String key,
    String eventType, {
    int modifiers = 0,
  }) {
    final String kLower = key.toLowerCase();
    final Map<String, Object?> params = <String, Object?>{
      'type': eventType,
      'modifiers': modifiers,
    };
    if (cdpSpecialKeys.containsKey(kLower)) {
      params.addAll(cdpSpecialKeys[kLower]!);
    } else if (key.length == 1) {
      params['key'] = key;
      if (eventType == 'keyDown' && modifiers == 0) {
        params['text'] = key;
      }
      if (RegExp(r'^[a-zA-Z]$').hasMatch(key)) {
        params['code'] = 'Key${key.toUpperCase()}';
        params['windowsVirtualKeyCode'] = key.toUpperCase().codeUnitAt(0);
      } else if (RegExp(r'^[0-9]$').hasMatch(key)) {
        params['code'] = 'Digit$key';
        params['windowsVirtualKeyCode'] = key.codeUnitAt(0);
      }
    } else {
      params['key'] = key;
    }
    return params;
  }

  /// Presses and releases a single [key].
  Future<void> pressKey(String sandboxName, String key) async {
    await makeCdpBatchRequest(sandboxName, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchKeyEvent',
        'params': _buildKeyParams(key, 'keyDown'),
      },
      <String, Object?>{
        'method': 'Input.dispatchKeyEvent',
        'params': _buildKeyParams(key, 'keyUp'),
      },
    ]);
  }

  /// Presses and holds a single [key].
  Future<void> keyDown(String sandboxName, String key) async {
    await makeCdpRequest(
      sandboxName,
      'Input.dispatchKeyEvent',
      _buildKeyParams(key, 'keyDown'),
    );
  }

  /// Releases a single [key].
  Future<void> keyUp(String sandboxName, String key) async {
    await makeCdpRequest(
      sandboxName,
      'Input.dispatchKeyEvent',
      _buildKeyParams(key, 'keyUp'),
    );
  }

  /// Scrolls at `(x, y)` in [direction] (`up`, `down`, `left`, `right`) by [magnitude].
  Future<void> scrollAt(
    String sandboxName,
    int x,
    int y,
    String direction,
    int magnitude,
  ) async {
    int dx = 0;
    int dy = 0;
    switch (direction.toLowerCase()) {
      case 'down':
        dy = magnitude;
      case 'up':
        dy = -magnitude;
      case 'right':
        dx = magnitude;
      case 'left':
        dx = -magnitude;
    }
    await makeCdpRequest(
      sandboxName,
      'Input.dispatchMouseEvent',
      <String, Object?>{
        'type': 'mouseWheel',
        'x': x,
        'y': y,
        'deltaX': dx,
        'deltaY': dy,
      },
    );
  }

  /// Navigates one step back in the browser history.
  Future<void> goBack(String sandboxName) async {
    await makeCdpRequest(
      sandboxName,
      'Runtime.evaluate',
      <String, Object?>{'expression': 'window.history.back()'},
    );
  }

  /// Navigates one step forward in the browser history.
  Future<void> goForward(String sandboxName) async {
    await makeCdpRequest(
      sandboxName,
      'Runtime.evaluate',
      <String, Object?>{'expression': 'window.history.forward()'},
    );
  }

  /// Dispatches a chord of [keys] (e.g. `['Control', 'c']`).
  Future<void> keyCombination(String sandboxName, List<String> keys) async {
    int currentModifiers = 0;
    final List<Map<String, Object?>> downEvents = <Map<String, Object?>>[];
    final List<Map<String, Object?>> upEvents = <Map<String, Object?>>[];

    for (final String k in keys) {
      final String kLower = k.toLowerCase();
      final int modBit = cdpModifierBitflags[kLower] ?? 0;
      final Map<String, Object?> downParams = _buildKeyParams(
        k,
        'keyDown',
        modifiers: currentModifiers,
      );
      currentModifiers |= modBit;
      downEvents.add(<String, Object?>{
        'method': 'Input.dispatchKeyEvent',
        'params': downParams,
      });

      final Map<String, Object?> upParams = _buildKeyParams(
        k,
        'keyUp',
        modifiers: currentModifiers & ~modBit,
      );
      upEvents.insert(0, <String, Object?>{
        'method': 'Input.dispatchKeyEvent',
        'params': upParams,
      });
    }

    final List<Map<String, Object?>> allEvents = <Map<String, Object?>>[
      ...downEvents,
      ...upEvents,
    ];
    if (allEvents.isNotEmpty) {
      await makeCdpBatchRequest(sandboxName, allEvents);
    }
  }

  /// Drags from `(x, y)` to `(destinationX, destinationY)`.
  Future<void> dragAndDrop(
    String sandboxName,
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) async {
    const int steps = 10;
    final List<Map<String, Object?>> commands = <Map<String, Object?>>[
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseMoved',
          'x': x,
          'y': y,
          'button': 'none',
          'buttons': 0,
        },
      },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'buttons': 1,
          'clickCount': 1,
        },
      },
      for (int i = 1; i <= steps; i++)
        <String, Object?>{
          'method': 'Input.dispatchMouseEvent',
          'params': <String, Object?>{
            'type': 'mouseMoved',
            'x': (x + (destinationX - x) * i / steps).toInt(),
            'y': (y + (destinationY - y) * i / steps).toInt(),
            'button': 'left',
            'buttons': 1,
          },
        },
      <String, Object?>{
        'method': 'Input.dispatchMouseEvent',
        'params': <String, Object?>{
          'type': 'mouseReleased',
          'x': destinationX,
          'y': destinationY,
          'button': 'left',
          'buttons': 0,
          'clickCount': 1,
        },
      },
    ];
    await makeCdpBatchRequest(sandboxName, commands);
  }

  /// Performs a browser health check on [sandboxName].
  Future<bool> healthCheck(String sandboxName) async {
    try {
      final Map<String, Object?> res = await makeCdpRequest(
        sandboxName,
        'Browser.getVersion',
      );
      return res['result'] is Map;
    } on Object {
      return false;
    }
  }
}

/// Idiomatic alias for [SandboxClient].
typedef VmaasSandboxClient = SandboxClient;

/// Interface for Vertex AI Agent Engine control-plane operations used by [SandboxManager].
abstract interface class VmaasVertexAiControlClient {
  /// Lists existing Agent Engines (`reasoningEngines`).
  Future<List<Map<String, Object?>>> listAgentEngines();

  /// Creates an Agent Engine with [displayName] and returns its resource name.
  Future<String> createAgentEngine({required String displayName});

  /// Lists sandbox environment templates under [agentEngineName].
  Future<List<Map<String, Object?>>> listSandboxTemplates(
    String agentEngineName,
  );

  /// Creates a sandbox environment template under [agentEngineName].
  Future<String> createSandboxTemplate({
    required String agentEngineName,
    required String displayName,
    required Map<String, Object?> config,
  });

  /// Creates a sandbox environment under [agentEngineName].
  Future<String> createSandbox({
    required String agentEngineName,
    required String displayName,
    required Map<String, Object?> spec,
    String? serviceAccountEmail,
    Duration? ttl,
  });

  /// Gets the metadata map for [sandboxName] (including `'state'`).
  Future<Map<String, Object?>> getSandbox(String sandboxName);

  /// Pauses [sandboxName].
  Future<void> pauseSandbox(String sandboxName);

  /// Resumes [sandboxName].
  Future<void> resumeSandbox(String sandboxName);

  /// Deletes [sandboxName].
  Future<void> deleteSandbox(String sandboxName);

  /// Executes a bash command inside [sandboxName].
  Future<({String stdout, String stderr})> executeBash({
    required String sandboxName,
    required String command,
  });
}

/// Default in-memory implementation of [VmaasVertexAiControlClient].
class InMemoryVmaasVertexAiControlClient implements VmaasVertexAiControlClient {
  /// Creates an [InMemoryVmaasVertexAiControlClient].
  InMemoryVmaasVertexAiControlClient({
    this.projectId = 'test-project',
    this.location = 'us-central1',
  });

  /// Google Cloud project ID.
  final String projectId;

  /// Google Cloud region.
  final String location;

  final List<Map<String, Object?>> _engines = <Map<String, Object?>>[];
  final Map<String, List<Map<String, Object?>>> _templatesByEngine =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Map<String, Object?>> _sandboxes =
      <String, Map<String, Object?>>{};
  int _counter = 0;

  @override
  Future<List<Map<String, Object?>>> listAgentEngines() async =>
      List<Map<String, Object?>>.from(_engines);

  @override
  Future<String> createAgentEngine({required String displayName}) async {
    _counter += 1;
    final String name =
        'projects/$projectId/locations/$location/reasoningEngines/engine_$_counter';
    _engines.add(<String, Object?>{'name': name, 'displayName': displayName});
    return name;
  }

  @override
  Future<List<Map<String, Object?>>> listSandboxTemplates(
    String agentEngineName,
  ) async {
    return List<Map<String, Object?>>.from(
      _templatesByEngine[agentEngineName] ?? const <Map<String, Object?>>[],
    );
  }

  @override
  Future<String> createSandboxTemplate({
    required String agentEngineName,
    required String displayName,
    required Map<String, Object?> config,
  }) async {
    _counter += 1;
    final String name =
        '$agentEngineName/sandboxEnvironmentTemplates/tmpl_$_counter';
    _templatesByEngine
        .putIfAbsent(agentEngineName, () => <Map<String, Object?>>[])
        .add(<String, Object?>{
          'name': name,
          'displayName': displayName,
          'config': config,
        });
    return name;
  }

  @override
  Future<String> createSandbox({
    required String agentEngineName,
    required String displayName,
    required Map<String, Object?> spec,
    String? serviceAccountEmail,
    Duration? ttl,
  }) async {
    _counter += 1;
    final String name = '$agentEngineName/sandboxEnvironments/sbx_$_counter';
    _sandboxes[name] = <String, Object?>{
      'name': name,
      'displayName': displayName,
      'state': 'STATE_RUNNING',
      'spec': spec,
      'serviceAccountEmail': ?serviceAccountEmail,
      if (ttl != null) 'ttlSeconds': ttl.inSeconds,
    };
    return name;
  }

  @override
  Future<Map<String, Object?>> getSandbox(String sandboxName) async {
    final Map<String, Object?>? sbx = _sandboxes[sandboxName];
    if (sbx == null) {
      throw StateError('Sandbox not found: $sandboxName');
    }
    return Map<String, Object?>.from(sbx);
  }

  @override
  Future<void> pauseSandbox(String sandboxName) async {
    final Map<String, Object?> sbx = await getSandbox(sandboxName);
    sbx['state'] = 'STATE_PAUSED';
    _sandboxes[sandboxName] = sbx;
  }

  @override
  Future<void> resumeSandbox(String sandboxName) async {
    final Map<String, Object?> sbx = await getSandbox(sandboxName);
    sbx['state'] = 'STATE_RUNNING';
    _sandboxes[sandboxName] = sbx;
  }

  @override
  Future<void> deleteSandbox(String sandboxName) async {
    _sandboxes.remove(sandboxName);
  }

  @override
  Future<({String stdout, String stderr})> executeBash({
    required String sandboxName,
    required String command,
  }) async {
    await getSandbox(sandboxName);
    return (stdout: '', stderr: '');
  }
}

/// Manages the lifecycle of Vertex AI Agent Engine sandboxes, templates, and
/// parent engines for computer-use and container workloads.
///
/// ```dart
/// final manager = SandboxManager(
///   projectId: 'my-project',
///   location: 'us-central1',
/// );
/// final sandboxName = await manager.createSandbox();
/// ```
class SandboxManager {
  /// Creates a [SandboxManager].
  SandboxManager({
    this.projectId,
    this.location = 'us-central1',
    this.serviceAccountEmail,
    this.agentEngineName = 'computer_use_engine',
    this.shellTemplateName = 'shell_template',
    this.customContainerTemplateName = 'computer_use_template',
    this.imageUri,
    VmaasVertexAiControlClient? controlClient,
  }) : _controlClient =
           controlClient ??
           InMemoryVmaasVertexAiControlClient(
             projectId: projectId ?? 'default-project',
             location: location,
           );

  /// Google Cloud project ID.
  final String? projectId;

  /// Google Cloud region.
  final String location;

  /// Optional service account email attached to created sandboxes.
  final String? serviceAccountEmail;

  /// Display name of the default parent Agent Engine.
  final String agentEngineName;

  /// Display name of the default shell template.
  final String shellTemplateName;

  /// Display name of the default custom container template.
  final String customContainerTemplateName;

  /// Optional custom container image URI.
  final String? imageUri;

  final VmaasVertexAiControlClient _controlClient;

  /// Underlying [VmaasVertexAiControlClient].
  VmaasVertexAiControlClient get controlClient => _controlClient;

  /// Finds or creates an Agent Engine matching [agentEngineName].
  Future<String> getAgentEngineName() async {
    final List<Map<String, Object?>> engines = await _controlClient
        .listAgentEngines();
    for (final Map<String, Object?> engine in engines) {
      if (engine['displayName'] == agentEngineName &&
          engine['name'] is String) {
        return engine['name'] as String;
      }
    }
    return _controlClient.createAgentEngine(displayName: agentEngineName);
  }

  /// Finds or creates a shell sandbox template under [engineName].
  Future<String> getShellTemplateName(String engineName) async {
    final List<Map<String, Object?>> templates = await _controlClient
        .listSandboxTemplates(engineName);
    for (final Map<String, Object?> tmpl in templates) {
      if (tmpl['displayName'] == shellTemplateName && tmpl['name'] is String) {
        return tmpl['name'] as String;
      }
    }
    return _controlClient.createSandboxTemplate(
      agentEngineName: engineName,
      displayName: shellTemplateName,
      config: <String, Object?>{
        'shellEnvironment': <String, Object?>{},
        'warmPoolConfig': <String, Object?>{'targetCount': 0},
      },
    );
  }

  /// Finds or creates a custom container sandbox template under [engineName].
  Future<String> getCustomContainerTemplateName(String engineName) async {
    final List<Map<String, Object?>> templates = await _controlClient
        .listSandboxTemplates(engineName);
    for (final Map<String, Object?> tmpl in templates) {
      if (tmpl['displayName'] == customContainerTemplateName &&
          tmpl['name'] is String) {
        return tmpl['name'] as String;
      }
    }
    if (imageUri == null || imageUri!.isEmpty) {
      throw ArgumentError(
        'Cannot create a new CustomContainerTemplate without an imageUri. '
        'Either provide an existing sandboxTemplateName or specify an imageUri.',
      );
    }
    return _controlClient.createSandboxTemplate(
      agentEngineName: engineName,
      displayName: customContainerTemplateName,
      config: <String, Object?>{
        'customContainerEnvironment': <String, Object?>{'imageUri': imageUri},
        'warmPoolConfig': <String, Object?>{'targetCount': 0},
      },
    );
  }

  /// Creates a new sandbox and returns its resource name.
  Future<String> createSandbox({
    String? sandboxTemplateName,
    String? sandboxSnapshotName,
    int ttlSeconds = 3600,
    bool useShell = false,
  }) async {
    String? engineName;
    if (sandboxTemplateName != null &&
        sandboxTemplateName.contains('/sandboxEnvironmentTemplates/')) {
      engineName = sandboxTemplateName
          .split('/sandboxEnvironmentTemplates/')
          .first;
    } else {
      engineName = await getAgentEngineName();
    }

    final String templateName =
        sandboxTemplateName ??
        (useShell
            ? await getShellTemplateName(engineName)
            : await getCustomContainerTemplateName(engineName));

    final Map<String, Object?> spec = <String, Object?>{
      'sandboxEnvironmentTemplate': templateName,
      'sandboxEnvironmentSnapshot': ?sandboxSnapshotName,
    };

    return _controlClient.createSandbox(
      agentEngineName: engineName,
      displayName: useShell ? 'shell_sandbox' : 'computer_use_sandbox',
      spec: spec,
      serviceAccountEmail: serviceAccountEmail,
      ttl: Duration(seconds: ttlSeconds),
    );
  }

  /// Returns the current lifecycle state of [sandboxName] (e.g. `'STATE_RUNNING'`).
  Future<String> getSandboxState(String sandboxName) async {
    final Map<String, Object?> sandbox = await _controlClient.getSandbox(
      sandboxName,
    );
    return (sandbox['state'] as String?) ?? 'STATE_UNSPECIFIED';
  }

  /// Pauses [sandboxName].
  Future<void> pauseSandbox(String sandboxName) =>
      _controlClient.pauseSandbox(sandboxName);

  /// Resumes [sandboxName] if it is currently paused, waiting until it reaches `'STATE_RUNNING'`.
  Future<bool> resumeSandboxIfPaused(String sandboxName) async {
    try {
      final String state = await getSandboxState(sandboxName);
      if (state == 'STATE_RUNNING') {
        return true;
      }
      if (state == 'STATE_PAUSED' || state == 'STATE_PAUSING') {
        if (state == 'STATE_PAUSING') {
          await waitUntilState(sandboxName, 'STATE_PAUSED');
        }
        await _controlClient.resumeSandbox(sandboxName);
        return await waitUntilRunning(sandboxName);
      }
      if (state == 'STATE_RESUMING') {
        return await waitUntilRunning(sandboxName);
      }
      return false;
    } on Object {
      return false;
    }
  }

  /// Deletes [sandboxName].
  Future<void> deleteSandbox(String sandboxName) =>
      _controlClient.deleteSandbox(sandboxName);

  /// Returns `true` if [sandboxName] exists.
  Future<bool> sandboxExists(String sandboxName) async {
    try {
      await _controlClient.getSandbox(sandboxName);
      return true;
    } on Object {
      return false;
    }
  }

  /// Polls until [sandboxName] reaches `'STATE_RUNNING'`.
  Future<bool> waitUntilRunning(
    String sandboxName, {
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 1),
  }) {
    return waitUntilState(
      sandboxName,
      'STATE_RUNNING',
      timeout: timeout,
      pollInterval: pollInterval,
    );
  }

  /// Polls until [sandboxName] reaches [targetState].
  Future<bool> waitUntilState(
    String sandboxName,
    String targetState, {
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final String state = await getSandboxState(sandboxName);
      if (state == targetState) {
        return true;
      }
      if (pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
    }
    return false;
  }

  /// Executes [command] inside [sandboxName] and returns `(stdout, stderr)`.
  Future<({String stdout, String stderr})> executeBash(
    String sandboxName,
    String command,
  ) {
    return _controlClient.executeBash(
      sandboxName: sandboxName,
      command: command,
    );
  }
}

/// Idiomatic alias for [SandboxManager].
typedef VmaasSandboxManager = SandboxManager;

/// [BaseComputer] implementation backed by a Vertex AI Agent Engine (VMaaS)
/// browser sandbox via Chrome DevTools Protocol (CDP).
///
/// ```dart
/// final computer = AgentEngineSandboxComputer(
///   projectId: 'my-project',
///   sandboxName:
///       'projects/my-project/locations/us-central1/reasoningEngines/1/sandboxEnvironments/2',
/// );
/// ```
class AgentEngineSandboxComputer extends BaseComputer {
  /// Creates an [AgentEngineSandboxComputer].
  AgentEngineSandboxComputer({
    this.projectId,
    this.location = 'us-central1',
    this.serviceAccountEmail,
    String? sandboxName,
    this.sandboxTemplateName,
    this.sandboxSnapshotName,
    this.sandboxTtlSeconds = 3600,
    this.searchEngineUrl = 'https://www.google.com',
    this.viewportSize = (1280, 720),
    SandboxManager? sandboxManager,
    SandboxClient? sandboxClient,
  }) : _sandboxName = sandboxName,
       _createdByUs = sandboxName == null,
       _sandboxManager =
           sandboxManager ??
           SandboxManager(
             projectId: projectId,
             location: location,
             serviceAccountEmail: serviceAccountEmail,
           ),
       _sandboxClient =
           sandboxClient ??
           SandboxClient(
             accessToken: '',
             endpoint: 'https://$location-aiplatform.googleapis.com',
             cdpTransport: _defaultInMemoryCdpTransport,
           );

  /// Google Cloud project ID.
  final String? projectId;

  /// Google Cloud region.
  final String location;

  /// Optional service account email for sandbox creation.
  final String? serviceAccountEmail;

  /// Optional sandbox template resource name.
  final String? sandboxTemplateName;

  /// Optional sandbox snapshot resource name.
  final String? sandboxSnapshotName;

  /// Sandbox TTL in seconds when creating new sandboxes.
  final int sandboxTtlSeconds;

  /// URL navigated to when [search] or [openWebBrowser] is invoked.
  final String searchEngineUrl;

  /// Screen viewport dimensions `(width, height)`.
  final (int, int) viewportSize;

  String? _sandboxName;
  bool _createdByUs;
  final SandboxManager _sandboxManager;
  final SandboxClient _sandboxClient;

  /// Active sandbox resource name, if initialized.
  String? get sandboxName => _sandboxName;

  /// Underlying [SandboxManager].
  SandboxManager get sandboxManager => _sandboxManager;

  /// Underlying [SandboxClient].
  SandboxClient get sandboxClient => _sandboxClient;

  static Future<List<Map<String, Object?>>> _defaultInMemoryCdpTransport({
    required String sandboxName,
    required List<Map<String, Object?>> commands,
    required String accessToken,
    required String baseUrl,
  }) async {
    return commands.map((Map<String, Object?> cmd) {
      final String? method = cmd['method'] as String?;
      if (method == 'Page.captureScreenshot') {
        return <String, Object?>{
          'result': <String, Object?>{'data': base64Encode(const <int>[137, 80, 78, 71])},
        };
      }
      if (method == 'Runtime.evaluate') {
        return <String, Object?>{
          'result': <String, Object?>{
            'result': <String, Object?>{'value': 'https://www.google.com/'},
          },
        };
      }
      if (method == 'Browser.getVersion') {
        return <String, Object?>{
          'result': <String, Object?>{'product': 'Chrome/Headless'},
        };
      }
      return <String, Object?>{'result': <String, Object?>{}};
    }).toList();
  }

  @override
  Future<void> prepare(ToolContext toolContext) async {
    final Object? savedName = toolContext.state[vmaasSandboxStateKey];
    if (savedName is String && savedName.isNotEmpty) {
      if (_sandboxName != savedName) {
        _sandboxName = savedName;
        _createdByUs = true;
      }
      final bool isAlive = await _sandboxManager.resumeSandboxIfPaused(
        _sandboxName!,
      );
      if (isAlive) {
        return;
      }
      _sandboxName = null;
    }

    if (_sandboxName != null && !_createdByUs) {
      final bool isAlive = await _sandboxManager.resumeSandboxIfPaused(
        _sandboxName!,
      );
      if (!isAlive) {
        throw StateError(
          'Explicitly provided sandbox $_sandboxName is invalid or terminated.',
        );
      }
      return;
    }

    _sandboxName = await _sandboxManager.createSandbox(
      sandboxTemplateName: sandboxTemplateName,
      sandboxSnapshotName: sandboxSnapshotName,
      ttlSeconds: sandboxTtlSeconds,
    );
    _createdByUs = true;
    toolContext.state[vmaasSandboxStateKey] = _sandboxName;
  }

  @override
  Future<void> initialize() async {
    if (_sandboxName == null || _sandboxName!.isEmpty) {
      _sandboxName = await _sandboxManager.createSandbox(
        sandboxTemplateName: sandboxTemplateName,
        sandboxSnapshotName: sandboxSnapshotName,
        ttlSeconds: sandboxTtlSeconds,
      );
      _createdByUs = true;
    } else {
      await _sandboxManager.resumeSandboxIfPaused(_sandboxName!);
    }
  }

  Future<String> _ensureSandbox() async {
    if (_sandboxName == null || _sandboxName!.isEmpty) {
      await initialize();
    }
    return _sandboxName!;
  }

  @override
  Future<(int, int)> screenSize() async => viewportSize;

  @override
  Future<ComputerEnvironment> environment() async =>
      ComputerEnvironment.environmentBrowser;

  @override
  Future<ComputerState> currentState() async {
    final String sbx = await _ensureSandbox();
    final Uint8List? screenshotBytes = await _sandboxClient.getScreenshot(sbx);
    final String url = await _sandboxClient.getCurrentUrl(sbx);
    return ComputerState(screenshot: screenshotBytes, url: url);
  }

  /// Captures a raw PNG screenshot from the browser sandbox.
  Future<Uint8List?> takeScreenshot() async {
    final String sbx = await _ensureSandbox();
    return _sandboxClient.getScreenshot(sbx);
  }

  @override
  Future<ComputerState> openWebBrowser() async {
    final String sbx = await _ensureSandbox();
    final String url = await _sandboxClient.getCurrentUrl(sbx);
    if (url.isEmpty || url == 'about:blank') {
      await _sandboxClient.navigate(sbx, searchEngineUrl);
    }
    return currentState();
  }

  @override
  Future<ComputerState> clickAt(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.clickAt(sbx, x, y);
    return currentState();
  }

  @override
  Future<ComputerState> hoverAt(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.hoverAt(sbx, x, y);
    return currentState();
  }

  /// Moves the mouse cursor to `(x, y)` and returns the updated [ComputerState].
  Future<ComputerState> move(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.move(sbx, x, y);
    return currentState();
  }

  /// Presses and holds the left mouse button at `(x, y)`.
  Future<ComputerState> mouseDown(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.mouseDown(sbx, x, y);
    return currentState();
  }

  /// Releases the left mouse button at `(x, y)`.
  Future<ComputerState> mouseUp(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.mouseUp(sbx, x, y);
    return currentState();
  }

  /// Performs a right-click (context click) at `(x, y)`.
  Future<ComputerState> contextClick(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.contextClick(sbx, x, y);
    return currentState();
  }

  /// Performs a double-click at `(x, y)`.
  Future<ComputerState> doubleClick(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.doubleClick(sbx, x, y);
    return currentState();
  }

  /// Performs a triple-click at `(x, y)`.
  Future<ComputerState> tripleClick(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.tripleClick(sbx, x, y);
    return currentState();
  }

  /// Performs a middle-click at `(x, y)`.
  Future<ComputerState> middleClick(int x, int y) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.middleClick(sbx, x, y);
    return currentState();
  }

  @override
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.dragAndDrop(sbx, x, y, destinationX, destinationY);
    return currentState();
  }

  @override
  Future<ComputerState> scrollDocument(String direction) {
    final (int width, int height) = viewportSize;
    return scrollAt(width ~/ 2, height ~/ 2, direction, 500);
  }

  @override
  Future<ComputerState> scrollAt(
    int x,
    int y,
    String direction,
    int magnitude,
  ) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.scrollAt(sbx, x, y, direction, magnitude);
    return currentState();
  }

  @override
  Future<ComputerState> typeText(String text, {bool pressEnter = false}) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.typeText(sbx, text, pressEnter: pressEnter);
    return currentState();
  }

  @override
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.typeTextAt(
      sbx,
      x,
      y,
      text,
      pressEnter: pressEnter,
      clearBeforeTyping: clearBeforeTyping,
    );
    return currentState();
  }

  /// Presses and releases [key].
  Future<ComputerState> pressKey(String key) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.pressKey(sbx, key);
    return currentState();
  }

  /// Presses and holds [key].
  Future<ComputerState> keyDown(String key) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.keyDown(sbx, key);
    return currentState();
  }

  /// Releases [key].
  Future<ComputerState> keyUp(String key) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.keyUp(sbx, key);
    return currentState();
  }

  @override
  Future<ComputerState> wait(int seconds) async {
    if (seconds > 0) {
      await Future<void>.delayed(Duration(seconds: seconds));
    }
    return currentState();
  }

  @override
  Future<ComputerState> keyCombination(List<String> keys) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.keyCombination(sbx, keys);
    return currentState();
  }

  @override
  Future<ComputerState> navigate(String url) async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.navigate(sbx, url);
    return currentState();
  }

  @override
  Future<ComputerState> goBack() async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.goBack(sbx);
    return currentState();
  }

  @override
  Future<ComputerState> goForward() async {
    final String sbx = await _ensureSandbox();
    await _sandboxClient.goForward(sbx);
    return currentState();
  }

  @override
  Future<ComputerState> search() => navigate(searchEngineUrl);

  @override
  Future<void> close() async {
    if (_sandboxName != null && _createdByUs) {
      try {
        await _sandboxManager.deleteSandbox(_sandboxName!);
      } on Object {
        // Ignore deletion errors during cleanup.
      } finally {
        _sandboxName = null;
      }
    }
  }
}

/// Idiomatic alias for [AgentEngineSandboxComputer].
typedef VmaasSandboxComputer = AgentEngineSandboxComputer;
