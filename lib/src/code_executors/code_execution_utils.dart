import 'dart:convert';

import '../types/content.dart';

class CodeExecutionFile {
  CodeExecutionFile({
    required this.name,
    required this.content,
    this.mimeType = 'text/plain',
  });

  String name;
  Object content;
  String mimeType;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'content': content,
      'mime_type': mimeType,
    };
  }

  factory CodeExecutionFile.fromJson(Map<String, Object?> json) {
    return CodeExecutionFile(
      name: '${json['name'] ?? ''}',
      content: json['content'] ?? '',
      mimeType: '${json['mime_type'] ?? 'text/plain'}',
    );
  }
}

class CodeExecutionInput {
  CodeExecutionInput({
    required this.code,
    List<CodeExecutionFile>? inputFiles,
    this.executionId,
  }) : inputFiles = inputFiles ?? <CodeExecutionFile>[];

  String code;
  List<CodeExecutionFile> inputFiles;
  String? executionId;
}

class CodeExecutionResult {
  CodeExecutionResult({
    this.stdout = '',
    this.stderr = '',
    List<CodeExecutionFile>? outputFiles,
    this.exitCode = 0,
    this.timedOut = false,
  }) : outputFiles = outputFiles ?? <CodeExecutionFile>[];

  String stdout;
  String stderr;
  List<CodeExecutionFile> outputFiles;
  int exitCode;
  bool timedOut;

  bool get isSuccess => exitCode == 0 && !timedOut && stderr.isEmpty;
}

class CodeExecutionUtils {
  static List<int> getEncodedFileContent(List<int> data) {
    try {
      final List<int> decoded = base64Decode(utf8.decode(data));
      final List<int> encoded = utf8.encode(base64Encode(decoded));
      if (_listEquals(encoded, data)) {
        return data;
      }
    } catch (_) {
      // Data was not valid base64; encode it below.
    }
    return utf8.encode(base64Encode(data));
  }

  static String? extractCodeAndTruncateContent(
    Content content,
    List<(String, String)> codeBlockDelimiters,
  ) {
    if (content.parts.isEmpty) {
      return null;
    }

    for (int i = 0; i < content.parts.length; i += 1) {
      final Part part = content.parts[i];
      final String? code = _extractExecutableCode(part.executableCode);
      final bool hasAssociatedResult =
          i + 1 < content.parts.length &&
          content.parts[i + 1].codeExecutionResult != null;
      if (code != null && !hasAssociatedResult) {
        content.parts = content.parts.sublist(0, i + 1);
        return code;
      }
    }

    final List<Part> textParts = content.parts
        .where((Part part) => part.text != null && part.text!.isNotEmpty)
        .toList(growable: false);
    if (textParts.isEmpty) {
      return null;
    }

    final String responseText = textParts
        .map((Part part) => part.text!)
        .join('\n');

    int? bestStart;
    int? bestEnd;
    String? bestCode;
    (String, String)? bestDelimiter;

    for (final (String leading, String trailing) in codeBlockDelimiters) {
      final int start = responseText.indexOf(leading);
      if (start < 0) {
        continue;
      }
      final int codeStart = start + leading.length;
      final int end = responseText.indexOf(trailing, codeStart);
      if (end < 0) {
        continue;
      }
      final String candidateCode = responseText.substring(codeStart, end);
      if (candidateCode.trim().isEmpty) {
        continue;
      }
      if (bestStart == null || start < bestStart) {
        bestStart = start;
        bestEnd = end;
        bestCode = candidateCode;
        bestDelimiter = (leading, trailing);
      }
    }

    if (bestStart == null ||
        bestEnd == null ||
        bestCode == null ||
        bestDelimiter == null) {
      return null;
    }

    final String prefix = responseText.substring(0, bestStart);
    content.parts = <Part>[];
    if (prefix.isNotEmpty) {
      final Part firstTextPart = textParts.first.copyWith(text: prefix);
      content.parts.add(firstTextPart);
    }

    content.parts.add(buildExecutableCodePart(bestCode));
    return bestCode;
  }

  static Part buildExecutableCodePart(String code) {
    return Part(
      executableCode: <String, Object?>{'code': code, 'language': 'PYTHON'},
    );
  }

  static Part buildCodeExecutionResultPart(CodeExecutionResult result) {
    if (result.stderr.isNotEmpty) {
      return Part(
        codeExecutionResult: <String, Object?>{
          'outcome': 'OUTCOME_FAILED',
          'output': result.stderr,
        },
      );
    }

    final List<String> finalResult = <String>[];
    if (result.stdout.isNotEmpty || result.outputFiles.isEmpty) {
      finalResult.add('Code execution result:\n${result.stdout}\n');
    }
    if (result.outputFiles.isNotEmpty) {
      final String fileNames = result.outputFiles
          .map((CodeExecutionFile file) => '`' + file.name + '`')
          .join(',');
      finalResult.add('Saved artifacts:\n$fileNames');
    }

    return Part(
      codeExecutionResult: <String, Object?>{
        'outcome': 'OUTCOME_OK',
        'output': finalResult.join('\n\n'),
      },
    );
  }

  static void convertCodeExecutionParts(
    Content content,
    (String, String) codeBlockDelimiter,
    (String, String) executionResultDelimiters,
  ) {
    if (content.parts.isEmpty) {
      return;
    }

    final Part trailing = content.parts.last;
    final String? executableCode = _extractExecutableCode(
      trailing.executableCode,
    );
    if (executableCode != null) {
      content.parts[content.parts.length - 1] = Part.text(
        '${codeBlockDelimiter.$1}$executableCode${codeBlockDelimiter.$2}',
      );
      return;
    }

    if (content.parts.length == 1 && trailing.codeExecutionResult != null) {
      final Map<String, Object?> result = _toObjectMap(
        trailing.codeExecutionResult,
      );
      final String output = '${result['output'] ?? ''}';
      content.parts[0] = Part.text(
        '${executionResultDelimiters.$1}$output${executionResultDelimiters.$2}',
      );
      content.role = 'user';
    }
  }
}

String? _extractExecutableCode(Object? executableCode) {
  if (executableCode is Map && executableCode['code'] is String) {
    final String code = executableCode['code'] as String;
    if (code.isNotEmpty) {
      return code;
    }
  }
  return null;
}

Map<String, Object?> _toObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? value) =>
          MapEntry<String, Object?>('${key ?? ''}', value),
    );
  }
  return <String, Object?>{};
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
