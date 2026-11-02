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

/// File deletion tool for Agent Builder Assistant.
library;

import 'dart:io';

import '../utils/resolve_root_directory.dart';

/// Deletes multiple files at [filePaths] with optional backup creation.
///
/// This tool safely deletes multiple files with validation and optional backup
/// creation. It is designed for cleaning up unused tool files when agent
/// configurations change.
Future<Map<String, dynamic>> deleteFiles(
  List<String> filePaths,
  Object? toolContext, {
  bool createBackup = false,
  bool confirmDeletion = true,
  // ignore: non_constant_identifier_names
  bool? create_backup,
  // ignore: non_constant_identifier_names
  bool? confirm_deletion,
}) async {
  final bool effectiveCreateBackup = create_backup ?? createBackup;
  final bool effectiveConfirmDeletion = confirm_deletion ?? confirmDeletion;

  try {
    final Map<String, Object?>? sessionState = extractSessionState(toolContext);
    final List<File> resolvedPaths = resolveFilePaths(filePaths, sessionState);

    final Map<String, dynamic> filesResult = <String, dynamic>{};
    final List<String> errors = <String>[];
    final Map<String, dynamic> result = <String, dynamic>{
      'success': true,
      'files': filesResult,
      'successful_deletions': 0,
      'total_files': filePaths.length,
      'errors': errors,
    };

    if (!effectiveConfirmDeletion) {
      result['success'] = false;
      errors.add('Deletion not confirmed by user');
      return result;
    }

    for (final File resolvedPath in resolvedPaths) {
      final File filePathObj = File(canonicalizePath(resolvedPath.path));
      final Map<String, dynamic> fileInfo = <String, dynamic>{
        'existed': false,
        'backup_created': false,
        'backup_path': null,
        'error': null,
        'file_size': 0,
      };

      try {
        if (!filePathObj.existsSync()) {
          fileInfo['error'] = 'File does not exist: ${filePathObj.path}';
          filesResult[filePathObj.path] = fileInfo;
          result['successful_deletions'] =
              (result['successful_deletions'] as int) + 1;
          continue;
        }

        fileInfo['existed'] = true;
        fileInfo['file_size'] = filePathObj.lengthSync();

        if (effectiveCreateBackup) {
          final String timestamp = _formatBackupTimestamp(DateTime.now());
          final String backupPath = _withBackupSuffix(
            filePathObj.path,
            timestamp,
          );
          try {
            filePathObj.copySync(backupPath);
            fileInfo['backup_created'] = true;
            fileInfo['backup_path'] = backupPath;
          } catch (e) {
            fileInfo['error'] = 'Failed to create backup: $e';
            result['success'] = false;
            filesResult[filePathObj.path] = fileInfo;
            continue;
          }
        }

        filePathObj.deleteSync();
        result['successful_deletions'] =
            (result['successful_deletions'] as int) + 1;
      } catch (e) {
        fileInfo['error'] = 'Deletion failed: $e';
        result['success'] = false;
      }

      filesResult[filePathObj.path] = fileInfo;
    }

    return result;
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'files': <String, dynamic>{},
      'successful_deletions': 0,
      'total_files': filePaths.length,
      'errors': <String>['Delete operation failed: $e'],
    };
  }
}

/// Snake-case alias for [deleteFiles].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> delete_files(
  List<String> filePaths,
  Object? toolContext, {
  bool createBackup = false,
  bool confirmDeletion = true,
  // ignore: non_constant_identifier_names
  bool? create_backup,
  // ignore: non_constant_identifier_names
  bool? confirm_deletion,
}) => deleteFiles(
  filePaths,
  toolContext,
  createBackup: createBackup,
  confirmDeletion: confirmDeletion,
  create_backup: create_backup,
  confirm_deletion: confirm_deletion,
);

String _formatBackupTimestamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}${two(dt.month)}${two(dt.day)}_'
      '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
}

String _withBackupSuffix(String filePath, String timestamp) {
  final int sepIndex = filePath.lastIndexOf(Platform.pathSeparator);
  final int dotIndex = filePath.lastIndexOf('.');
  if (dotIndex > sepIndex + 1) {
    final String stem = filePath.substring(0, dotIndex);
    final String suffix = filePath.substring(dotIndex);
    return '$stem.backup_$timestamp$suffix';
  }
  return '$filePath.backup_$timestamp';
}
