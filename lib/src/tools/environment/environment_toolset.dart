/// Toolset that exposes command execution and file I/O through an environment.
library;

import 'dart:convert';
import 'dart:io';

import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../tool_context.dart';
import 'base_environment.dart';

const int _defaultTimeoutSeconds = 30;
const int _maxOutputChars = 30000;
const String _environmentInstructionTemplate = '''
Your environment is at {working_dir}/

# Environment Rules

DO:
- Chain sequential, dependent commands with `&&` in a single `Execute` call
- To read existing files, always use the `ReadFile` tool. Use `EditFile` to modify existing files.

DON'T:
- Use `Execute` to run cat, head, or tail when `ReadFile` tools can do the job
- Combine `EditFile` or `ReadFile` with `Execute` in the same response (Instead, call the file tool first, then `Execute` in the next turn)
- Use multiple `Execute` calls for dependent commands (they run in parallel)
''';

String _truncateOutput(String text, {int limit = _maxOutputChars}) {
  if (text.length <= limit) {
    return text;
  }
  return '${text.substring(0, limit)}\n... (truncated, ${text.length} total chars)';
}

int? _readIntArg(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

String _trimTrailingSeparator(String path) {
  if (path.length <= 1) {
    return path;
  }
  while (path.endsWith(Platform.pathSeparator) && path.length > 1) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// Experimental toolset for command execution and file I/O.
class EnvironmentToolset extends BaseToolset {
  /// Creates an environment toolset backed by [environment].
  EnvironmentToolset({required BaseEnvironment environment})
    : _environment = environment,
      super();

  final BaseEnvironment _environment;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await _environment.initialize();
    _initialized = true;
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    await _ensureInitialized();
    return <BaseTool>[
      _ExecuteTool(_environment),
      _ReadFileTool(_environment),
      _EditFileTool(_environment),
      _WriteFileTool(_environment),
    ];
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    await _ensureInitialized();
    final String instruction = _environmentInstructionTemplate.replaceAll(
      '{working_dir}',
      _trimTrailingSeparator(_environment.workingDirectory.path),
    );
    llmRequest.appendInstructions(<String>[instruction]);
  }

  @override
  Future<void> close() async {
    if (!_initialized) {
      return;
    }
    await _environment.close();
    _initialized = false;
  }
}

class _ExecuteTool extends BaseTool {
  _ExecuteTool(this._environment)
    : super(
        name: 'Execute',
        description:
            'Run a shell command in the environment. Use this for programs, tests, '
            'and build commands. Do not use it for file reading; prefer ReadFile.',
      );

  final BaseEnvironment _environment;

  @override
  FunctionDeclaration getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'command': <String, Object?>{
            'type': 'string',
            'description':
                'The shell command to execute. Chain dependent commands with &&.',
          },
        },
        'required': <String>['command'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String command = '${args['command'] ?? ''}'.trim();
    if (command.isEmpty) {
      return <String, Object?>{
        'status': 'error',
        'error': '`command` is required.',
      };
    }

    try {
      final EnvironmentExecutionResult result = await _environment.execute(
        command,
        timeout: const Duration(seconds: _defaultTimeoutSeconds),
      );
      final Map<String, Object?> payload = <String, Object?>{'status': 'ok'};
      if (result.stdout.isNotEmpty) {
        payload['stdout'] = _truncateOutput(result.stdout);
      }
      if (result.stderr.isNotEmpty) {
        payload['stderr'] = _truncateOutput(result.stderr);
      }
      if (result.exitCode != 0) {
        payload['status'] = 'error';
        payload['exit_code'] = result.exitCode;
      }
      if (result.timedOut) {
        payload['status'] = 'error';
        payload['error'] =
            'Command timed out after ${_defaultTimeoutSeconds}s.';
      }
      return payload;
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}

class _ReadFileTool extends BaseTool {
  _ReadFileTool(this._environment)
    : super(
        name: 'ReadFile',
        description:
            'Read the contents of a file in the environment and return numbered lines.',
      );

  final BaseEnvironment _environment;

  @override
  FunctionDeclaration getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{
            'type': 'string',
            'description': 'Path of the file to read within the environment.',
          },
          'start_line': <String, Object?>{
            'type': 'integer',
            'description': 'First line to return (1-based, inclusive).',
          },
          'end_line': <String, Object?>{
            'type': 'integer',
            'description': 'Last line to return (1-based, inclusive).',
          },
        },
        'required': <String>['path'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String path = '${args['path'] ?? ''}'.trim();
    if (path.isEmpty) {
      return <String, Object?>{
        'status': 'error',
        'error': '`path` is required.',
      };
    }

    final int start = _readIntArg(args['start_line']) ?? 1;
    final int? end = _readIntArg(args['end_line']);
    if (start < 1) {
      return <String, Object?>{
        'status': 'error',
        'error': '`start_line` must be >= 1.',
      };
    }
    if (end != null && end < start) {
      return <String, Object?>{
        'status': 'error',
        'error': '`start_line` ($start) is after `end_line` ($end).',
      };
    }

    try {
      final String text = utf8.decode(
        await _environment.readFile(path),
        allowMalformed: true,
      );
      List<String> lines = text.isEmpty ? <String>[] : text.split('\n');
      if (lines.isNotEmpty && lines.last.isEmpty) {
        lines = lines.sublist(0, lines.length - 1);
      }
      final int total = lines.length;
      if (total == 0) {
        return <String, Object?>{'status': 'ok', 'content': ''};
      }
      if (start > total) {
        return <String, Object?>{
          'status': 'error',
          'error': '`start_line` $start exceeds file length ($total lines).',
          'total_lines': total,
        };
      }

      final int boundedEnd = end == null || end > total ? total : end;
      final List<String> selected = lines.sublist(start - 1, boundedEnd);
      final String numbered = List<String>.generate(selected.length, (int i) {
        final int lineNumber = start + i;
        return '${lineNumber.toString().padLeft(6)}\t${selected[i].replaceFirst(RegExp(r'\r$'), '')}';
      }).join('\n');

      return <String, Object?>{
        'status': 'ok',
        'content': _truncateOutput(numbered),
        if (start > 1 || boundedEnd < total) 'total_lines': total,
      };
    } on FileSystemException catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}

class _WriteFileTool extends BaseTool {
  _WriteFileTool(this._environment)
    : super(
        name: 'WriteFile',
        description:
            'Create or overwrite a file in the environment. Use this for new files or full rewrites.',
      );

  final BaseEnvironment _environment;

  @override
  FunctionDeclaration getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{
            'type': 'string',
            'description': 'Path to the file within the environment.',
          },
          'content': <String, Object?>{
            'type': 'string',
            'description': 'The full file content to write.',
          },
        },
        'required': <String>['path', 'content'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String path = '${args['path'] ?? ''}'.trim();
    if (path.isEmpty) {
      return <String, Object?>{
        'status': 'error',
        'error': '`path` is required.',
      };
    }

    final String content = '${args['content'] ?? ''}';
    try {
      await _environment.writeFile(path, content);
      return <String, Object?>{'status': 'ok', 'message': 'Wrote $path'};
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}

class _EditFileTool extends BaseTool {
  _EditFileTool(this._environment)
    : super(
        name: 'EditFile',
        description:
            'Replace an exact substring in an existing file. The old_string must appear exactly once.',
      );

  final BaseEnvironment _environment;

  @override
  FunctionDeclaration getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{
            'type': 'string',
            'description': 'Path of the file to edit within the environment.',
          },
          'old_string': <String, Object?>{
            'type': 'string',
            'description': 'The exact text to find and replace.',
          },
          'new_string': <String, Object?>{
            'type': 'string',
            'description': 'The replacement text.',
          },
        },
        'required': <String>['path', 'old_string', 'new_string'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String path = '${args['path'] ?? ''}'.trim();
    if (path.isEmpty) {
      return <String, Object?>{
        'status': 'error',
        'error': '`path` is required.',
      };
    }

    final String oldString = '${args['old_string'] ?? ''}';
    if (oldString.isEmpty) {
      return <String, Object?>{
        'status': 'error',
        'error':
            '`old_string` cannot be empty. To create a new file, use the WriteFile tool.',
      };
    }
    final String newString = '${args['new_string'] ?? ''}';

    try {
      final String content = utf8.decode(
        await _environment.readFile(path),
        allowMalformed: true,
      );
      final int occurrences = content.split(oldString).length - 1;
      if (occurrences == 0) {
        return <String, Object?>{
          'status': 'error',
          'error':
              '`old_string` not found in file. Read the file first to verify contents.',
        };
      }
      if (occurrences > 1) {
        return <String, Object?>{
          'status': 'error',
          'error':
              '`old_string` appears $occurrences times. Provide more surrounding context to make it unique.',
        };
      }

      await _environment.writeFile(
        path,
        content.replaceFirst(oldString, newString),
      );
      return <String, Object?>{'status': 'ok', 'message': 'Edited $path'};
    } on FileSystemException catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}
