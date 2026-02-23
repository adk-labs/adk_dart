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

class VertexAiCodeExecutor extends BaseCodeExecutor {
  VertexAiCodeExecutor({this.resourceName});

  final String? resourceName;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
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

  String _getCodeWithImports(String code) {
    return '\n$_importedLibraries\n\n$code\n';
  }

  String _detectMimeType(String fileName) {
    final String extension = fileName.split('.').last.toLowerCase();
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
