/// Toolset that exposes command execution and file I/O through an environment.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../agents/context.dart';
import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../tool_context.dart';
import 'base_environment.dart';

const int _defaultTimeoutSeconds = 30;
const int _defaultMaxOutputChars = 30000;

/// System-instruction header template reporting the active environment directory.
const String environmentWorkingDirInstruction =
    'Your environment is at {working_dir}/\n';

/// System-instruction rules injected by [EnvironmentToolset].
const String environmentInstruction = '''# Environment Rules

DO:
- Chain sequential, dependent commands with `&&` in a single `Execute` call
- To read existing files, always use the `ReadFile` tool. Use `EditFile` to modify existing files.

DON'T:
- Use `Execute` to run cat, head, or tail when `ReadFile` tools can do the job
- Combine `EditFile` or `ReadFile` with `Execute` in the same response (Instead, call the file tool first, then `Execute` in the next turn)
- Use multiple `Execute` calls for dependent commands (they run in parallel)
''';

/// Exception thrown when an operation waiting on an environment lock is cancelled.
class EnvironmentLockCancelledException implements Exception {
  /// Creates a lock-cancellation exception.
  const EnvironmentLockCancelledException();

  @override
  String toString() =>
      'EnvironmentLockCancelledException: Environment lock acquisition was cancelled.';
}

class _EnvironmentLockTicket {
  final Completer<void> ready = Completer<void>();
  bool cancelled = false;
}

class _AsyncEnvironmentLock {
  bool _locked = false;
  final Queue<_EnvironmentLockTicket> _waiters =
      Queue<_EnvironmentLockTicket>();

  Future<T> synchronized<T>(
    Future<T> Function() action, {
    Future<void>? cancelSignal,
  }) async {
    if (!_locked) {
      _locked = true;
      try {
        return await action();
      } finally {
        _release();
      }
    }

    final _EnvironmentLockTicket ticket = _EnvironmentLockTicket();
    _waiters.addLast(ticket);

    if (cancelSignal != null) {
      bool settled = false;
      final Completer<void> race = Completer<void>();
      unawaited(
        ticket.ready.future.then((_) {
          if (!settled) {
            settled = true;
            race.complete();
          }
        }),
      );
      unawaited(
        cancelSignal.then((_) {
          if (!settled) {
            settled = true;
            ticket.cancelled = true;
            _waiters.remove(ticket);
            if (ticket.ready.isCompleted) {
              _release();
            }
            race.completeError(const EnvironmentLockCancelledException());
          }
        }),
      );
      await race.future;
    } else {
      await ticket.ready.future;
    }

    try {
      return await action();
    } finally {
      _release();
    }
  }

  void _release() {
    while (_waiters.isNotEmpty) {
      final _EnvironmentLockTicket next = _waiters.removeFirst();
      if (!next.cancelled) {
        next.ready.complete();
        return;
      }
    }
    _locked = false;
  }
}

final Expando<_AsyncEnvironmentLock> _envLocks = Expando<_AsyncEnvironmentLock>(
  'adkEnvironmentLocks',
);

_AsyncEnvironmentLock _lockFor(BaseEnvironment environment) {
  _AsyncEnvironmentLock? lock = _envLocks[environment];
  if (lock == null) {
    lock = _AsyncEnvironmentLock();
    _envLocks[environment] = lock;
  }
  return lock;
}

/// Returns `true` when [environment] currently has a weak per-environment lock entry.
bool hasEnvironmentLock(BaseEnvironment environment) =>
    _envLocks[environment] != null;

/// Initializes [environment] under a per-environment lock with calling [ctx].
///
/// Runs [BaseEnvironment.initialize] one call at a time for [environment] and
/// marks [BaseEnvironment.isInitialized] `true` if the implementation did not
/// already update its own flag.
Future<void> ensureInitialized(
  BaseEnvironment environment, [
  Context? ctx,
  Future<void>? cancelSignal,
]) async {
  await _lockFor(environment).synchronized<void>(() async {
    await environment.initialize(ctx: ctx);
    if (!environment.isInitialized) {
      try {
        environment.isInitialized = true;
      } on UnsupportedError {
        // Subclass manages a read-only `isInitialized` getter on its own.
      }
    }
  }, cancelSignal: cancelSignal);
}

/// Closes [environment] under its per-environment lock if currently initialized.
Future<void> closeIfInitialized(
  BaseEnvironment environment, {
  Future<void>? cancelSignal,
}) async {
  await _lockFor(environment).synchronized<void>(() async {
    if (environment.isInitialized) {
      await environment.close();
      if (environment.isInitialized) {
        try {
          environment.isInitialized = false;
        } on UnsupportedError {
          // Subclass manages a read-only `isInitialized` getter on its own.
        }
      }
    }
  }, cancelSignal: cancelSignal);
}

String _truncateOutput(String text, {int limit = _defaultMaxOutputChars}) {
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

/// Returns `true` when [value] is an integer.
///
/// `bool` values are rejected: Dart's `bool` is not a subtype of `int`, so
/// this already excludes them (unlike Python, where `bool` is an `int`
/// subclass and needs an explicit exclusion).
bool _isValidLineNumber(Object? value) {
  return value is int;
}

String _trimTrailingSeparator(String path) {
  if (path.length <= 1) {
    return path;
  }
  while ((path.endsWith(Platform.pathSeparator) || path.endsWith('/')) &&
      path.length > 1) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

RegExp _oldStringPattern(String oldString) {
  final String normalizedOld = oldString
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final String pattern = normalizedOld
      .split('\n')
      .map(RegExp.escape)
      .join(r'\r?\n');
  return RegExp(pattern);
}

/// Decodes [bytes] using UTF-8 with Python's `surrogateescape` error handler:
/// invalid bytes `0x80..0xFF` are mapped to lone low surrogates `0xDC80..0xDCFF`.
String _decodeUtf8SurrogateEscape(List<int> bytes) {
  final List<int> codeUnits = <int>[];
  int i = 0;
  final int n = bytes.length;
  while (i < n) {
    final int b0 = bytes[i] & 0xFF;
    if (b0 <= 0x7F) {
      codeUnits.add(b0);
      i += 1;
      continue;
    }
    if (b0 >= 0xC2 && b0 <= 0xDF && i + 1 < n) {
      final int b1 = bytes[i + 1] & 0xFF;
      if (b1 >= 0x80 && b1 <= 0xBF) {
        codeUnits.add(((b0 & 0x1F) << 6) | (b1 & 0x3F));
        i += 2;
        continue;
      }
    } else if (b0 >= 0xE0 && b0 <= 0xEF && i + 2 < n) {
      final int b1 = bytes[i + 1] & 0xFF;
      final int b2 = bytes[i + 2] & 0xFF;
      final bool validB1 = switch (b0) {
        0xE0 => b1 >= 0xA0 && b1 <= 0xBF,
        0xED => b1 >= 0x80 && b1 <= 0x9F,
        _ => b1 >= 0x80 && b1 <= 0xBF,
      };
      if (validB1 && b2 >= 0x80 && b2 <= 0xBF) {
        codeUnits.add(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F));
        i += 3;
        continue;
      }
    } else if (b0 >= 0xF0 && b0 <= 0xF4 && i + 3 < n) {
      final int b1 = bytes[i + 1] & 0xFF;
      final int b2 = bytes[i + 2] & 0xFF;
      final int b3 = bytes[i + 3] & 0xFF;
      final bool validB1 = switch (b0) {
        0xF0 => b1 >= 0x90 && b1 <= 0xBF,
        0xF4 => b1 >= 0x80 && b1 <= 0x8F,
        _ => b1 >= 0x80 && b1 <= 0xBF,
      };
      if (validB1 &&
          b2 >= 0x80 &&
          b2 <= 0xBF &&
          b3 >= 0x80 &&
          b3 <= 0xBF) {
        final int cp =
            ((b0 & 0x07) << 18) |
            ((b1 & 0x3F) << 12) |
            ((b2 & 0x3F) << 6) |
            (b3 & 0x3F);
        final int offset = cp - 0x10000;
        codeUnits.add(0xD800 + (offset >> 10));
        codeUnits.add(0xDC00 + (offset & 0x3FF));
        i += 4;
        continue;
      }
    }
    codeUnits.add(0xDC00 | b0);
    i += 1;
  }
  return String.fromCharCodes(codeUnits);
}

/// Encodes [text] using UTF-8 with Python's `surrogateescape` error handler:
/// lone low surrogates `0xDC80..0xDCFF` are mapped back to raw bytes `0x80..0xFF`.
Uint8List _encodeUtf8SurrogateEscape(String text) {
  final BytesBuilder out = BytesBuilder(copy: false);
  for (int i = 0; i < text.length; i++) {
    final int cu = text.codeUnitAt(i);
    if (cu <= 0x7F) {
      out.addByte(cu);
    } else if (cu <= 0x7FF) {
      out.addByte(0xC0 | (cu >> 6));
      out.addByte(0x80 | (cu & 0x3F));
    } else if (cu >= 0xD800 && cu <= 0xDBFF) {
      if (i + 1 >= text.length) {
        throw const FormatException('Unpaired high surrogate in text.');
      }
      final int low = text.codeUnitAt(i + 1);
      if (low < 0xDC00 || low > 0xDFFF) {
        throw const FormatException('Unpaired high surrogate in text.');
      }
      final int cp = 0x10000 + ((cu - 0xD800) << 10) + (low - 0xDC00);
      out.addByte(0xF0 | (cp >> 18));
      out.addByte(0x80 | ((cp >> 12) & 0x3F));
      out.addByte(0x80 | ((cp >> 6) & 0x3F));
      out.addByte(0x80 | (cp & 0x3F));
      i += 1;
    } else if (cu >= 0xDC80 && cu <= 0xDCFF) {
      out.addByte(cu - 0xDC00);
    } else if (cu >= 0xDC00 && cu <= 0xDC7F) {
      throw const FormatException('Unpaired low surrogate in text.');
    } else {
      out.addByte(0xE0 | (cu >> 12));
      out.addByte(0x80 | ((cu >> 6) & 0x3F));
      out.addByte(0x80 | (cu & 0x3F));
    }
  }
  return out.takeBytes();
}

Future<({List<Uint8List> selected, int total})> _readLineRange(
  Stream<List<int>> stream,
  int start,
  int? end, {
  required int maxBytes,
}) async {
  final BytesBuilder buf = BytesBuilder(copy: false);
  final List<Uint8List> selected = <Uint8List>[];
  int total = 0;
  int collectedBytes = 0;
  bool hasTrailingBytes = false;

  await for (final List<int> chunk in stream) {
    if (chunk.isEmpty) {
      continue;
    }
    int pos = 0;
    while (true) {
      int nl = -1;
      for (int idx = pos; idx < chunk.length; idx++) {
        if (chunk[idx] == 0x0A) {
          nl = idx;
          break;
        }
      }
      if (nl == -1) {
        break;
      }
      total += 1;
      final bool inRange = start <= total && (end == null || total <= end);
      if (inRange && collectedBytes < maxBytes) {
        buf.add(chunk.sublist(pos, nl));
        final Uint8List lineBytes = buf.takeBytes();
        selected.add(lineBytes);
        collectedBytes += lineBytes.length + 1;
      } else if (buf.isNotEmpty) {
        buf.clear();
      }
      pos = nl + 1;
    }
    hasTrailingBytes = pos < chunk.length;
    final bool inNext = start <= total + 1 && (end == null || total + 1 <= end);
    if (inNext && collectedBytes < maxBytes) {
      if (pos < chunk.length) {
        buf.add(chunk.sublist(pos));
      }
    } else if (buf.isNotEmpty) {
      buf.clear();
    }
  }

  if (buf.isNotEmpty || hasTrailingBytes) {
    total += 1;
    if (buf.isNotEmpty &&
        start <= total &&
        (end == null || total <= end) &&
        collectedBytes < maxBytes) {
      selected.add(buf.takeBytes());
    }
  }

  return (selected: selected, total: total);
}

/// Experimental toolset for command execution and file I/O.
class EnvironmentToolset extends BaseToolset {
  /// Creates an environment toolset backed by [environment].
  EnvironmentToolset({
    required BaseEnvironment environment,
    int? maxOutputChars,
    super.toolFilter,
    super.toolNamePrefix,
  }) : _maxOutputChars = maxOutputChars,
       _environment = environment;

  /// Environment used to execute commands and perform file I/O.
  final BaseEnvironment _environment;

  /// Optional character limit for command and file output truncation.
  final int? _maxOutputChars;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> allTools = <BaseTool>[
      ExecuteTool(_environment, maxOutputChars: _maxOutputChars),
      ReadFileTool(_environment, maxOutputChars: _maxOutputChars),
      EditFileTool(_environment),
      WriteFileTool(_environment),
    ];
    return allTools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    String instruction = environmentInstruction;
    if (_environment.isInitialized) {
      final String workingDir = environmentWorkingDirInstruction.replaceAll(
        '{working_dir}',
        _trimTrailingSeparator(_environment.workingDirectory.path),
      );
      instruction = '$workingDir\n$instruction';
    }
    llmRequest.appendInstructions(<String>[instruction]);
  }

  @override
  Future<void> close() async {
    await closeIfInitialized(_environment);
    await super.close();
  }
}

/// Tool that runs shell commands in an environment.
class ExecuteTool extends BaseTool {
  /// Creates an execute tool backed by [environment].
  ExecuteTool(BaseEnvironment environment, {int? maxOutputChars})
    : _environment = environment,
      _maxOutputChars = maxOutputChars,
      super(
        name: 'Execute',
        description:
            'Run a shell command in the environment. Use this for programs, tests, '
            'and build commands. Do not use it for file reading; prefer ReadFile.',
      );

  final BaseEnvironment _environment;
  final int? _maxOutputChars;

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
      await ensureInitialized(_environment, toolContext);
      final EnvironmentExecutionResult result = await _environment.execute(
        command,
        timeout: const Duration(seconds: _defaultTimeoutSeconds),
        ctx: toolContext,
      );
      final Map<String, Object?> payload = <String, Object?>{'status': 'ok'};
      if (result.stdout.isNotEmpty) {
        payload['stdout'] = _truncateOutput(
          result.stdout,
          limit: _maxOutputChars ?? _defaultMaxOutputChars,
        );
      }
      if (result.stderr.isNotEmpty) {
        payload['stderr'] = _truncateOutput(
          result.stderr,
          limit: _maxOutputChars ?? _defaultMaxOutputChars,
        );
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

/// Tool that reads file contents from an environment with line numbers.
class ReadFileTool extends BaseTool {
  /// Creates a read-file tool backed by [environment].
  ReadFileTool(BaseEnvironment environment, {int? maxOutputChars})
    : _environment = environment,
      _maxOutputChars = maxOutputChars,
      super(
        name: 'ReadFile',
        description:
            'Read the contents of a file in the environment and return numbered lines.',
      );

  final BaseEnvironment _environment;
  final int? _maxOutputChars;

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

    for (final MapEntry<String, Object?> entry in <String, Object?>{
      'start_line': args['start_line'],
      'end_line': args['end_line'],
    }.entries) {
      if (entry.value != null && !_isValidLineNumber(entry.value)) {
        return <String, Object?>{
          'status': 'error',
          'error': '`${entry.key}` must be an integer if provided.',
        };
      }
    }

    final int? rawStart = _readIntArg(args['start_line']);
    final int? rawEnd = _readIntArg(args['end_line']);
    final int start = math.max(1, rawStart == null || rawStart == 0 ? 1 : rawStart);
    final int? endLine = (rawEnd == null || rawEnd == 0) ? null : rawEnd;
    if (endLine != null && endLine < start) {
      return <String, Object?>{
        'status': 'error',
        'error': '`start_line` ($start) is after `end_line` ($endLine).',
      };
    }

    final int maxOutputChars = _maxOutputChars ?? _defaultMaxOutputChars;
    final int maxBytes = maxOutputChars * 4;

    try {
      await ensureInitialized(_environment, toolContext);
      final ({List<Uint8List> selected, int total}) lineRange =
          await _readLineRange(
            _environment.readFileStream(path, ctx: toolContext),
            start,
            endLine,
            maxBytes: maxBytes + 1,
          );
      final int total = lineRange.total;
      final List<Uint8List> selected = lineRange.selected;
      final int end = endLine == null ? total : math.min(total, endLine);
      if (total == 0 && start == 1 && end == 0) {
        return <String, Object?>{'status': 'ok', 'content': ''};
      }
      if (start > total) {
        return <String, Object?>{
          'status': 'error',
          'error': '`start_line` $start exceeds file length ($total lines).',
          'total_lines': total,
        };
      }

      String numbered = List<String>.generate(selected.length, (int i) {
        final int lineNumber = start + i;
        final String decodedLine = utf8
            .decode(selected[i], allowMalformed: true)
            .replaceFirst(RegExp(r'\r$'), '');
        return '${lineNumber.toString().padLeft(6)}\t$decodedLine';
      }).join('\n');
      if (numbered.length > maxOutputChars) {
        numbered =
            '${numbered.substring(0, maxOutputChars)}\n... (truncated, $total total lines)';
      }

      return <String, Object?>{
        'status': 'ok',
        'content': numbered,
        if (start > 1 || end < total) 'total_lines': total,
      };
    } on FileSystemException catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}

/// Tool that creates or overwrites a file in an environment.
class WriteFileTool extends BaseTool {
  /// Creates a write-file tool backed by [environment].
  WriteFileTool(BaseEnvironment environment)
    : _environment = environment,
      super(
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
      await ensureInitialized(_environment, toolContext);
      await _environment.writeFile(path, content, ctx: toolContext);
      return <String, Object?>{'status': 'ok', 'message': 'Wrote $path'};
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}

/// Tool that performs an exact text replacement in an environment file.
class EditFileTool extends BaseTool {
  /// Creates an edit-file tool backed by [environment].
  EditFileTool(BaseEnvironment environment)
    : _environment = environment,
      super(
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
      await ensureInitialized(_environment, toolContext);
      final List<int> raw = await _environment.readFile(path, ctx: toolContext);
      final String content = _decodeUtf8SurrogateEscape(raw);
      final RegExp pattern = _oldStringPattern(oldString);
      final int occurrences = pattern.allMatches(content).length;
      if (occurrences == 0) {
        if (oldString.contains('\ufffd') &&
            pattern.hasMatch(utf8.decode(raw, allowMalformed: true))) {
          return <String, Object?>{
            'status': 'error',
            'error':
                'The file has bytes that are not valid UTF-8 near this text. '
                'Choose an `old_string` that does not include them.',
          };
        }
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

      if (hasLoneUtf16Surrogates(newString)) {
        return <String, Object?>{
          'status': 'error',
          'error':
              '`new_string` contains characters that cannot be encoded. '
              'The file was not modified.',
        };
      }

      final String updated = content.replaceFirstMapped(
        pattern,
        (_) => newString,
      );
      final Uint8List encoded = _encodeUtf8SurrogateEscape(updated);
      try {
        await _environment.writeFile(path, encoded, ctx: toolContext);
      } on TypeError {
        await _environment.writeFile(path, updated, ctx: toolContext);
      }
      return <String, Object?>{'status': 'ok', 'message': 'Edited $path'};
    } on FileSystemException catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    } catch (error) {
      return <String, Object?>{'status': 'error', 'error': '$error'};
    }
  }
}
