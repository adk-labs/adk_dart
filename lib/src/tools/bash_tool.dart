/// Bash execution tool and command-policy models.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Policy controlling which bash commands may be executed.
class BashToolPolicy {
  /// Creates a bash policy with allowed command prefixes and execution guards.
  BashToolPolicy({
    List<String>? allowedCommandPrefixes,
    List<String>? blockedOperators,
    this.timeoutSeconds = 30,
  }) : allowedCommandPrefixes = allowedCommandPrefixes ?? <String>['*'],
       blockedOperators = blockedOperators ?? const <String>[];

  /// Allowed command prefixes. `*` allows all commands.
  final List<String> allowedCommandPrefixes;

  /// Shell operators that are explicitly blocked before execution.
  final List<String> blockedOperators;

  /// Command timeout in seconds. `null` disables the timeout.
  final int? timeoutSeconds;
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
  for (final String prefix in policy.allowedCommandPrefixes) {
    if (stripped.startsWith(prefix)) {
      return null;
    }
  }
  final String allowed = policy.allowedCommandPrefixes.join(', ');
  return 'Command blocked. Permitted prefixes are: $allowed';
}

/// Tool that executes bash commands after explicit user confirmation.
class ExecuteBashTool extends BaseTool {
  /// Creates a bash execution tool.
  ExecuteBashTool({Directory? workspace, BashToolPolicy? policy})
    : _workspace = workspace ?? Directory.current,
      _policy = policy ?? BashToolPolicy(),
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
  final String _descriptionHint;

  static String _buildAllowedHint(BashToolPolicy policy) {
    if (policy.allowedCommandPrefixes.contains('*')) {
      return 'any command';
    }
    return 'commands matching prefixes: ${policy.allowedCommandPrefixes.join(', ')}';
  }

  @override
  /// Returns the command-only function declaration schema.
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

  @override
  /// Executes one bash command when policy and confirmation checks pass.
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
      final Process process = await Process.start('/bin/bash', <String>[
        '-lc',
        command,
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
