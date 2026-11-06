/// Base abstractions for local or remote execution environments.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Returns `true` when [value] contains any unpaired UTF-16 surrogate code unit.
bool hasLoneUtf16Surrogates(String value) {
  for (int i = 0; i < value.length; i++) {
    final int unit = value.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= value.length) {
        return true;
      }
      final int next = value.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) {
        return true;
      }
      i += 1;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

/// Normalizes [content] (`String` or `List<int>`) into raw bytes for [BaseEnvironment.writeFile].
///
/// Throws a [FormatException] when a [String] contains lone UTF-16 surrogates,
/// or an [ArgumentError] when [content] is neither a [String] nor a `List<int>`.
Uint8List encodeWriteFileContent(Object content) {
  if (content is Uint8List) {
    return content;
  }
  if (content is List<int>) {
    return Uint8List.fromList(content);
  }
  if (content is String) {
    if (hasLoneUtf16Surrogates(content)) {
      throw const FormatException(
        'Cannot UTF-8 encode string containing lone UTF-16 surrogates.',
      );
    }
    return Uint8List.fromList(utf8.encode(content));
  }
  throw ArgumentError.value(
    content,
    'content',
    'content must be String or List<int>, got ${content.runtimeType}',
  );
}

/// Result of one command execution inside an environment.
class EnvironmentExecutionResult {
  /// Creates an execution result.
  const EnvironmentExecutionResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
  });

  /// Process exit code.
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  /// Whether the process exceeded its timeout and was terminated.
  final bool timedOut;
}

/// Contract for environments that expose shell execution and file I/O.
abstract class BaseEnvironment {
  /// Creates an environment rooted at [workingDirectory].
  BaseEnvironment({Directory? workingDirectory})
    : workingDirectory = (workingDirectory ?? Directory.current).absolute;

  /// Workspace root used by environment operations.
  final Directory workingDirectory;

  /// Performs any one-time setup required before tool calls.
  Future<void> initialize() async {}

  /// Releases any resources retained by the environment.
  Future<void> close() async {}

  /// Executes [command] within [workingDirectory].
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  });

  /// Reads bytes from a file relative to [workingDirectory].
  Future<List<int>> readFile(Object path);

  /// Streams raw byte chunks from a file relative to [workingDirectory].
  ///
  /// The default implementation reads the full file via [readFile] and yields
  /// it as a single chunk when non-empty. Subclasses may override this to stream
  /// in fixed-size chunks without buffering the entire file in memory.
  Stream<List<int>> readFileStream(Object path) async* {
    final List<int> data = await readFile(path);
    if (data.isNotEmpty) {
      yield data;
    }
  }

  /// Writes [content] (`String` or `List<int>`) to a file relative to [workingDirectory].
  Future<void> writeFile(Object path, covariant Object content);
}
