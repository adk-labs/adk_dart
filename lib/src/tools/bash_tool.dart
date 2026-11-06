/// Bash execution tool and command-policy models.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Policy controlling which bash commands may be executed.
///
/// Values for [maxMemoryBytes], [maxFileSizeBytes], and [maxChildProcesses]
/// are enforced on the spawned subprocess. `null` leaves a limit unset, while
/// `0` is enforced (for example, `maxFileSizeBytes: 0` lets the command write
/// no bytes to files).
class BashToolPolicy {
  /// Creates a bash policy with allowed command prefixes and execution guards.
  BashToolPolicy({
    List<String>? allowedCommandPrefixes,
    List<String>? blockedOperators,
    this.timeoutSeconds = 30,
    this.maxMemoryBytes,
    this.maxFileSizeBytes,
    this.maxChildProcesses,
  }) : allowedCommandPrefixes = allowedCommandPrefixes ?? <String>['*'],
       blockedOperators = blockedOperators ?? const <String>[];

  /// Allowed command prefixes. `*` allows all commands.
  final List<String> allowedCommandPrefixes;

  /// Shell operators that are explicitly blocked before execution.
  final List<String> blockedOperators;

  /// Command timeout in seconds. `null` disables the timeout.
  final int? timeoutSeconds;

  /// Maximum virtual memory (address space) in bytes (`RLIMIT_AS`).
  ///
  /// `null` leaves the limit unset; `0` enforces a zero-byte limit.
  final int? maxMemoryBytes;

  /// Maximum size of files the process may create in bytes (`RLIMIT_FSIZE`).
  ///
  /// `null` leaves the limit unset; `0` enforces a zero-byte limit.
  final int? maxFileSizeBytes;

  /// Maximum number of child processes (`RLIMIT_NPROC`).
  ///
  /// `null` leaves the limit unset; `0` enforces a zero-process limit.
  final int? maxChildProcesses;
}

/// Resource limit identifier constants matching Python `resource.RLIMIT_*`.
abstract final class ResourceLimit {
  /// Maximum size of a core file (`RLIMIT_CORE`).
  static const String rlimitCore = 'RLIMIT_CORE';

  /// Maximum area of address space (`RLIMIT_AS`).
  static const String rlimitAs = 'RLIMIT_AS';

  /// Maximum size of files created by the process (`RLIMIT_FSIZE`).
  static const String rlimitFsize = 'RLIMIT_FSIZE';

  /// Maximum number of processes (`RLIMIT_NPROC`).
  static const String rlimitNproc = 'RLIMIT_NPROC';
}

/// Callback invoked for each resource limit applied by [setResourceLimits].
typedef SetRlimitFn = void Function(String resource, (int, int) limits);

/// Applies resource limits from [policy] via [setrlimit].
///
/// Mirrors Python's `_set_resource_limits(policy)`: `null` leaves a limit
/// unset, whereas `0` is passed to [setrlimit] like any other non-null value.
void setResourceLimits(BashToolPolicy policy, [SetRlimitFn? setrlimit]) {
  if (Platform.isWindows || setrlimit == null) {
    return;
  }
  try {
    setrlimit(ResourceLimit.rlimitCore, (0, 0));
    if (policy.maxMemoryBytes != null) {
      setrlimit(
        ResourceLimit.rlimitAs,
        (policy.maxMemoryBytes!, policy.maxMemoryBytes!),
      );
    }
    if (policy.maxFileSizeBytes != null) {
      setrlimit(
        ResourceLimit.rlimitFsize,
        (policy.maxFileSizeBytes!, policy.maxFileSizeBytes!),
      );
    }
    if (policy.maxChildProcesses != null) {
      setrlimit(
        ResourceLimit.rlimitNproc,
        (policy.maxChildProcesses!, policy.maxChildProcesses!),
      );
    }
  } catch (_) {
    // Some platforms do not support all limits.
  }
}

String _buildUlimitPrefix(BashToolPolicy policy) {
  if (Platform.isWindows) {
    return '';
  }
  final List<String> commands = <String>['ulimit -c 0 2>/dev/null || true'];
  if (policy.maxFileSizeBytes != null) {
    final int blocks = policy.maxFileSizeBytes! <= 0
        ? 0
        : ((policy.maxFileSizeBytes! + 511) ~/ 512);
    commands.add('ulimit -S -H -f $blocks 2>/dev/null || ulimit -f $blocks');
  }
  if (policy.maxMemoryBytes != null && policy.maxMemoryBytes! > 0) {
    final int kb = (policy.maxMemoryBytes! + 1023) ~/ 1024;
    commands.add('ulimit -v $kb 2>/dev/null || true');
  }
  if (policy.maxChildProcesses != null && policy.maxChildProcesses! > 0) {
    commands.add('ulimit -u ${policy.maxChildProcesses!} 2>/dev/null || true');
  }
  return '${commands.join('; ')}; ';
}

List<String>? _splitShellTokens(String input) {
  final List<String> tokens = <String>[];
  final StringBuffer current = StringBuffer();
  bool hasCurrent = false;
  String? quote;
  bool escaped = false;

  for (int i = 0; i < input.length; i += 1) {
    final String ch = input[i];
    if (escaped) {
      current.write(ch);
      hasCurrent = true;
      escaped = false;
      continue;
    }
    if (ch == r'\' && quote != "'") {
      escaped = true;
      hasCurrent = true;
      continue;
    }
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        current.write(ch);
      }
      hasCurrent = true;
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
      hasCurrent = true;
      continue;
    }
    if (ch.trim().isEmpty) {
      if (hasCurrent) {
        tokens.add(current.toString());
        current.clear();
        hasCurrent = false;
      }
      continue;
    }
    current.write(ch);
    hasCurrent = true;
  }

  if (escaped || quote != null) {
    return null;
  }
  if (hasCurrent) {
    tokens.add(current.toString());
  }
  return tokens;
}

bool _matchesTokenPrefix(String command, String prefix) {
  final List<String>? commandTokens = _splitShellTokens(command);
  final List<String>? prefixTokens = _splitShellTokens(prefix);
  if (commandTokens == null ||
      prefixTokens == null ||
      prefixTokens.isEmpty ||
      commandTokens.length < prefixTokens.length) {
    return false;
  }
  for (int i = 0; i < prefixTokens.length; i += 1) {
    if (commandTokens[i] != prefixTokens[i]) {
      return false;
    }
  }
  return true;
}

String? _validateCommand(String command, BashToolPolicy policy) {
  final String stripped = command.trim();
  if (stripped.isEmpty) {
    return 'Command is required.';
  }
  for (final String operator in policy.blockedOperators) {
    if (operator.isNotEmpty && command.contains(operator)) {
      return 'Command contains blocked operator: $operator';
    }
  }
  if (policy.allowedCommandPrefixes.contains('*')) {
    return null;
  }
  if (_splitShellTokens(stripped) == null) {
    return 'Invalid command syntax: unclosed quotes or escape sequence.';
  }
  for (final String prefix in policy.allowedCommandPrefixes) {
    final String trimmedPrefix = prefix.trim();
    if (trimmedPrefix.isEmpty) {
      continue;
    }
    if (_matchesTokenPrefix(stripped, trimmedPrefix)) {
      return null;
    }
  }
  final String allowed = policy.allowedCommandPrefixes.isEmpty
      ? '<none>'
      : policy.allowedCommandPrefixes.join(', ');
  return 'Command blocked. Permitted prefixes are: $allowed';
}

/// Tool that executes bash commands after explicit user confirmation.
class ExecuteBashTool extends BaseTool {
  /// Creates a bash execution tool.
  ExecuteBashTool({
    Directory? workspace,
    BashToolPolicy? policy,
    SetRlimitFn? setrlimit,
  }) : _workspace = workspace ?? Directory.current,
       _policy = policy ?? BashToolPolicy(),
       _setrlimit = setrlimit,
       _descriptionHint = _buildAllowedHint(policy ?? BashToolPolicy()),
       super(
         name: 'execute_bash',
         description:
             'Executes a bash command with the working directory set to the workspace. '
             'Allowed: ${_buildAllowedHint(policy ?? BashToolPolicy())}. '
             'All commands require user confirmation.',
       );

  final Directory _workspace;
  final BashToolPolicy _policy;
  final SetRlimitFn? _setrlimit;
  final String _descriptionHint;

  static String _buildAllowedHint(BashToolPolicy policy) {
    if (policy.allowedCommandPrefixes.contains('*')) {
      return 'any command';
    }
    final String allowed = policy.allowedCommandPrefixes.isEmpty
        ? '<none>'
        : policy.allowedCommandPrefixes.join(', ');
    return 'commands matching prefixes: $allowed';
  }

  /// Returns the command-only function declaration schema.
  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description:
          'Executes a bash command with the working directory set to the workspace. '
          'Allowed: $_descriptionHint. All commands require user confirmation.',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'command': <String, Object?>{
            'type': 'string',
            'description': 'The bash command to execute.',
          },
        },
        'required': <String>['command'],
      },
    );
  }

  /// Executes one bash command when policy and confirmation checks pass.
  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawCommand = args['command'];
    final String command = rawCommand is String ? rawCommand.trim() : '';
    if (command.isEmpty) {
      return <String, Object?>{'error': 'Command is required.'};
    }

    final String? validationError = _validateCommand(command, _policy);
    if (validationError != null) {
      return <String, Object?>{'error': validationError};
    }

    final Object? confirmation = toolContext.toolConfirmation;
    if (confirmation == null) {
      toolContext.requestConfirmation(
        hint: 'Please approve or reject the bash command: $command',
      );
      toolContext.actions.skipSummarization = true;
      return <String, Object?>{
        'error':
            'This tool call requires confirmation, please approve or reject.',
      };
    }
    if (toolContext.toolConfirmation?.confirmed != true) {
      return <String, Object?>{'error': 'This tool call is rejected.'};
    }

    try {
      setResourceLimits(_policy, _setrlimit);
      final String effectiveCommand = '${_buildUlimitPrefix(_policy)}$command';
      final Process process = await Process.start('/bin/bash', <String>[
        '-lc',
        effectiveCommand,
      ], workingDirectory: _workspace.path);
      final Future<String> stdoutFuture = process.stdout
          .transform(utf8.decoder)
          .join();
      final Future<String> stderrFuture = process.stderr
          .transform(utf8.decoder)
          .join();

      int returnCode;
      try {
        final int? timeoutSeconds = _policy.timeoutSeconds;
        if (timeoutSeconds == null) {
          returnCode = await process.exitCode;
        } else {
          returnCode = await process.exitCode.timeout(
            Duration(seconds: timeoutSeconds),
          );
        }
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        final String stdout = await stdoutFuture;
        final String stderr = await stderrFuture;
        return <String, Object?>{
          'error': 'Command timed out after ${_policy.timeoutSeconds} seconds.',
          'stdout': _capturedOutputOrPlaceholder(
            stdout,
            placeholder: '<no stdout captured>',
          ),
          'stderr': _capturedOutputOrPlaceholder(
            stderr,
            placeholder: '<no stderr captured>',
          ),
          'returncode': -1,
        };
      }

      final String stdout = await stdoutFuture;
      final String stderr = await stderrFuture;
      return <String, Object?>{
        'stdout': _capturedOutputOrPlaceholder(
          stdout,
          placeholder: '<no stdout captured>',
        ),
        'stderr': _capturedOutputOrPlaceholder(
          stderr,
          placeholder: '<no stderr captured>',
        ),
        'returncode': returnCode,
      };
    } catch (error) {
      return <String, Object?>{
        'error': 'Execution failed: $error',
        'stdout': '<no stdout captured>',
        'stderr': '<no stderr captured>',
      };
    }
  }
}

String _capturedOutputOrPlaceholder(
  String value, {
  required String placeholder,
}) {
  return value.isEmpty ? placeholder : value;
}
