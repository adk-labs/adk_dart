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
  /// Creates a bash policy with allowed command prefixes.
  BashToolPolicy({List<String>? allowedCommandPrefixes})
    : allowedCommandPrefixes = allowedCommandPrefixes ?? <String>['*'];

  /// Allowed command prefixes. `*` allows all commands.
  final List<String> allowedCommandPrefixes;
}

String? _validateCommand(String command, BashToolPolicy policy) {
  final String stripped = command.trim();
  if (stripped.isEmpty) {
    return 'Command is required.';
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
      super(
        name: 'execute_bash',
        description:
            'Executes a bash command with the working directory set to the workspace. '
            'All commands require user confirmation.',
      );

  final Directory _workspace;
  final BashToolPolicy _policy;

  @override
  /// Returns the command-only function declaration schema.
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
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
        returnCode = await process.exitCode.timeout(
          const Duration(seconds: 30),
        );
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        final String stdout = await stdoutFuture;
        final String stderr = await stderrFuture;
        return <String, Object?>{
          'error': 'Command timed out after 30 seconds.',
          'stdout': stdout,
          'stderr': stderr,
          'returncode': -1,
        };
      }

      final String stdout = await stdoutFuture;
      final String stderr = await stderrFuture;
      return <String, Object?>{
        'stdout': stdout,
        'stderr': stderr,
        'returncode': returnCode,
      };
    } catch (error) {
      return <String, Object?>{'error': '$error'};
    }
  }
}
