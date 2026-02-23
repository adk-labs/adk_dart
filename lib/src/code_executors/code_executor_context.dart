import 'dart:convert';

import 'code_execution_utils.dart';

const String _contextKey = '_code_execution_context';
const String _sessionIdKey = 'execution_session_id';
const String _processedFileNamesKey = 'processed_input_files';
const String _inputFileKey = '_code_executor_input_files';
const String _errorCountKey = '_code_executor_error_counts';
const String _codeExecutionResultsKey = '_code_execution_results';

class CodeExecutorContext {
  CodeExecutorContext(this._sessionState)
    : _context = _getCodeExecutorContext(_sessionState);

  final Map<String, Object?> _sessionState;
  final Map<String, Object?> _context;

  Map<String, Object?> getStateDelta() {
    return <String, Object?>{_contextKey: _deepCopyMap(_context)};
  }

  String? getExecutionId() {
    final Object? value = _context[_sessionIdKey];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  void setExecutionId(String sessionId) {
    _context[_sessionIdKey] = sessionId;
  }

  List<String> getProcessedFileNames() {
    final Object? value = _context[_processedFileNamesKey];
    if (value is List) {
      return value.map((Object? item) => '$item').toList();
    }
    return <String>[];
  }

  void addProcessedFileNames(List<String> fileNames) {
    final List<String> current = getProcessedFileNames();
    current.addAll(fileNames);
    _context[_processedFileNamesKey] = current;
  }

  List<CodeExecutionFile> getInputFiles() {
    final Object? value = _sessionState[_inputFileKey];
    if (value is! List) {
      return <CodeExecutionFile>[];
    }

    final List<CodeExecutionFile> files = <CodeExecutionFile>[];
    for (final Object? item in value) {
      if (item is Map<String, Object?>) {
        files.add(CodeExecutionFile.fromJson(item));
      } else if (item is Map) {
        files.add(
          CodeExecutionFile.fromJson(
            item.map(
              (Object? key, Object? value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          ),
        );
      }
    }
    return files;
  }

  void addInputFiles(List<CodeExecutionFile> inputFiles) {
    final Object? existing = _sessionState[_inputFileKey];
    final List<Map<String, Object?>> files = <Map<String, Object?>>[];

    if (existing is List) {
      for (final Object? item in existing) {
        if (item is Map<String, Object?>) {
          files.add(Map<String, Object?>.from(item));
        } else if (item is Map) {
          files.add(
            item.map(
              (Object? key, Object? value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          );
        }
      }
    }

    for (final CodeExecutionFile inputFile in inputFiles) {
      files.add(inputFile.toJson());
    }

    _sessionState[_inputFileKey] = files;
  }

  void clearInputFiles() {
    _sessionState[_inputFileKey] = <Map<String, Object?>>[];
    _context[_processedFileNamesKey] = <String>[];
  }

  int getErrorCount(String invocationId) {
    final Object? raw = _sessionState[_errorCountKey];
    if (raw is! Map) {
      return 0;
    }
    final Object? count = raw[invocationId];
    if (count is int) {
      return count;
    }
    if (count is num) {
      return count.toInt();
    }
    return 0;
  }

  void incrementErrorCount(String invocationId) {
    final Map<String, Object?> counts = _getOrCreateMap(
      _sessionState,
      _errorCountKey,
    );
    counts[invocationId] = getErrorCount(invocationId) + 1;
  }

  void resetErrorCount(String invocationId) {
    final Object? raw = _sessionState[_errorCountKey];
    if (raw is Map<String, Object?>) {
      raw.remove(invocationId);
      return;
    }
    if (raw is Map) {
      raw.remove(invocationId);
    }
  }

  void updateCodeExecutionResult(
    String invocationId,
    String code,
    String resultStdout,
    String resultStderr,
  ) {
    final Map<String, Object?> results = _getOrCreateMap(
      _sessionState,
      _codeExecutionResultsKey,
    );

    final Object? existing = results[invocationId];
    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];

    if (existing is List) {
      for (final Object? entry in existing) {
        if (entry is Map<String, Object?>) {
          entries.add(Map<String, Object?>.from(entry));
        } else if (entry is Map) {
          entries.add(
            entry.map(
              (Object? key, Object? value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          );
        }
      }
    }

    entries.add(<String, Object?>{
      'code': code,
      'result_stdout': resultStdout,
      'result_stderr': resultStderr,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });

    results[invocationId] = entries;
  }

  static Map<String, Object?> _getCodeExecutorContext(
    Map<String, Object?> sessionState,
  ) {
    final Object? value = sessionState[_contextKey];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      final Map<String, Object?> mapped = value.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
      sessionState[_contextKey] = mapped;
      return mapped;
    }

    final Map<String, Object?> created = <String, Object?>{};
    sessionState[_contextKey] = created;
    return created;
  }
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> value) {
  final String encoded = jsonEncode(value);
  final Object? decoded = jsonDecode(encoded);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  return <String, Object?>{};
}

Map<String, Object?> _getOrCreateMap(Map<String, Object?> map, String key) {
  final Object? existing = map[key];
  if (existing is Map<String, Object?>) {
    return existing;
  }
  if (existing is Map) {
    final Map<String, Object?> converted = existing.map(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );
    map[key] = converted;
    return converted;
  }

  final Map<String, Object?> created = <String, Object?>{};
  map[key] = created;
  return created;
}
