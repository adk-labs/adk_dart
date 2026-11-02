// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// File reading tool for Agent Builder Assistant.
library;

import 'dart:io';

import '../utils/resolve_root_directory.dart';

/// Reads content from multiple files at [filePaths].
///
/// This tool reads content from multiple files and returns their contents.
/// It is designed for reading Python/Dart tools, configuration files, and
/// other text files.
Future<Map<String, dynamic>> readFiles(
  List<String> filePaths,
  Object? toolContext,
) async {
  try {
    final Map<String, Object?>? sessionState = extractSessionState(toolContext);
    final List<File> resolvedPaths = resolveFilePaths(filePaths, sessionState);

    final Map<String, dynamic> filesResult = <String, dynamic>{};
    final Map<String, dynamic> result = <String, dynamic>{
      'success': true,
      'files': filesResult,
      'successful_reads': 0,
      'total_files': filePaths.length,
      'errors': <String>[],
    };

    for (final File resolvedPath in resolvedPaths) {
      final File filePathObj = File(canonicalizePath(resolvedPath.path));
      final Map<String, dynamic> fileInfo = <String, dynamic>{
        'content': '',
        'file_size': 0,
        'exists': false,
        'error': null,
      };

      try {
        if (!filePathObj.existsSync()) {
          fileInfo['error'] = 'File does not exist: ${filePathObj.path}';
        } else {
          fileInfo['exists'] = true;
          fileInfo['file_size'] = filePathObj.lengthSync();
          fileInfo['content'] = filePathObj.readAsStringSync();
          result['successful_reads'] = (result['successful_reads'] as int) + 1;
        }
      } catch (e) {
        fileInfo['error'] = 'Failed to read ${filePathObj.path}: $e';
        result['success'] = false;
      }

      filesResult[filePathObj.path] = fileInfo;
    }

    return result;
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'files': <String, dynamic>{},
      'successful_reads': 0,
      'total_files': filePaths.length,
      'errors': <String>['Read operation failed: $e'],
    };
  }
}

/// Snake-case alias for [readFiles].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> read_files(
  List<String> filePaths,
  Object? toolContext,
) => readFiles(filePaths, toolContext);
