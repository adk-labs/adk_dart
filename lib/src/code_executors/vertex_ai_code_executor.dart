import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/invocation_context.dart';
import 'base_code_executor.dart';
import 'code_execution_utils.dart';

const List<String> _supportedImageTypes = <String>['png', 'jpg', 'jpeg'];
const List<String> _supportedDataFileTypes = <String>['csv'];

const String _importedLibraries = '''
import io
import math
import re

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import scipy


def crop(s: str, max_chars: int = 64) -> str:
  return s[: max_chars - 3] + '...' if len(s) > max_chars else s


def explore_df(df: pd.DataFrame) -> None:
  with pd.option_context('display.max_columns', None, 'display.expand_frame_repr', False):
    df_dtypes = df.dtypes
    df_nulls = (len(df) - df.isnull().sum()).apply(lambda x: f'{x} / {df.shape[0]} non-null')
    df_unique_count = df.apply(lambda x: len(x.unique()))
    df_unique = df.apply(lambda x: crop(str(list(x.unique()))))
    df_info = pd.concat((
      df_dtypes.rename('Dtype'),
      df_nulls.rename('Non-Null Count'),
      df_unique_count.rename('Unique Values Count'),
      df_unique.rename('Unique Values')
    ), axis=1)
    df_info.index.name = 'Columns'
    print(f'Total rows: {df.shape[0]}\\nTotal columns: {df.shape[1]}\\n\\n{df_info}')
''';

abstract class VertexCodeInterpreterClient {
  Future<Map<String, Object?>> execute({
    required String code,
    List<CodeExecutionFile>? inputFiles,
    String? sessionId,
  });
}

class VertexAiCodeExecutor extends BaseCodeExecutor {
  VertexAiCodeExecutor({this.resourceName, VertexCodeInterpreterClient? client})
    : _client = client;

  final String? resourceName;
  final VertexCodeInterpreterClient? _client;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    if (_client != null) {
      final Map<String, Object?> response = await _executeCodeInterpreter(
        _getCodeWithImports(request.command),
      );
      return _parseInterpreterResponse(response);
    }

    final ProcessResult result = await Process.run(
      _pythonBinary(),
      <String>['-c', _getCodeWithImports(request.command)],
      workingDirectory: request.workingDirectory,
      environment: request.environment,
    );

    return CodeExecutionResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    if (_client != null) {
      final Map<String, Object?> response = await _executeCodeInterpreter(
        _getCodeWithImports(codeExecutionInput.code),
        codeExecutionInput.inputFiles,
        codeExecutionInput.executionId,
      );
      return _parseInterpreterResponse(response);
    }

    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'adk_vertex_exec_',
    );

    final Set<String> inputNames = <String>{};
    try {
      for (final CodeExecutionFile inputFile in codeExecutionInput.inputFiles) {
        inputNames.add(inputFile.name);
        final File output = File('${tempDirectory.path}/${inputFile.name}');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(_contentToBytes(inputFile.content));
      }

      final ProcessResult result = await Process.run(_pythonBinary(), <String>[
        '-c',
        _getCodeWithImports(codeExecutionInput.code),
      ], workingDirectory: tempDirectory.path);

      final List<CodeExecutionFile> outputFiles = <CodeExecutionFile>[];
      await for (final FileSystemEntity entity in tempDirectory.list(
        recursive: true,
      )) {
        if (entity is! File) {
          continue;
        }
        final String relativeName = entity.path.substring(
          tempDirectory.path.length + 1,
        );
        if (inputNames.contains(relativeName)) {
          continue;
        }
        final List<int> bytes = await entity.readAsBytes();
        outputFiles.add(
          CodeExecutionFile(
            name: relativeName,
            content: bytes,
            mimeType: _detectMimeType(relativeName),
          ),
        );
      }

      return CodeExecutionResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
        outputFiles: outputFiles,
      );
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  }

  Future<Map<String, Object?>> _executeCodeInterpreter(
    String code, [
    List<CodeExecutionFile>? inputFiles,
    String? sessionId,
  ]) async {
    final VertexCodeInterpreterClient? client = _client;
    if (client == null) {
      throw StateError('VertexCodeInterpreterClient is not configured.');
    }
    return client.execute(
      code: code,
      inputFiles: inputFiles,
      sessionId: sessionId,
    );
  }

  CodeExecutionResult _parseInterpreterResponse(Map<String, Object?> response) {
    final String stdout = _asString(response['execution_result']);
    final String stderr = _asString(response['execution_error']);

    final List<CodeExecutionFile> savedFiles = <CodeExecutionFile>[];
    final List<Object?> outputFiles = _asObjectList(response['output_files']);
    for (final Object? outputFile in outputFiles) {
      final Map<String, Object?> output = _asMap(outputFile);
      final String fileName = _asString(output['name']);
      final Object contents = output['contents'] ?? <int>[];
      final String explicitMimeType = _asString(output['mimeType']);
      final String mimeType = explicitMimeType.isEmpty
          ? _detectMimeType(fileName)
          : explicitMimeType;
      savedFiles.add(
        CodeExecutionFile(
          name: fileName,
          content: contents,
          mimeType: mimeType,
        ),
      );
    }

    return CodeExecutionResult(
      stdout: stdout,
      stderr: stderr,
      outputFiles: savedFiles,
    );
  }

  String _getCodeWithImports(String code) {
    return '\n$_importedLibraries\n\n$code\n';
  }

  String _detectMimeType(String fileName) {
    final String extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (_supportedImageTypes.contains(extension)) {
      return 'image/$extension';
    }
    if (_supportedDataFileTypes.contains(extension)) {
      return 'text/$extension';
    }
    if (extension == 'txt') {
      return 'text/plain';
    }
    if (extension == 'json') {
      return 'application/json';
    }
    if (extension == 'html') {
      return 'text/html';
    }
    return 'application/octet-stream';
  }

  String _pythonBinary() {
    for (final String candidate in <String>['python3', 'python']) {
      try {
        final ProcessResult probe = Process.runSync(candidate, <String>[
          '--version',
        ]);
        if (probe.exitCode == 0) {
          return candidate;
        }
      } catch (_) {
        // Try next candidate.
      }
    }
    return 'python3';
  }
}

String _asString(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is List<int>) {
    return utf8.decode(value, allowMalformed: true);
  }
  return '$value';
}

List<Object?> _asObjectList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry<String, Object?>(key.toString(), item),
    );
  }
  return <String, Object?>{};
}

List<int> _contentToBytes(Object content) {
  if (content is List<int>) {
    return content;
  }
  if (content is String) {
    try {
      return base64Decode(content);
    } catch (_) {
      return utf8.encode(content);
    }
  }
  return utf8.encode('$content');
}
