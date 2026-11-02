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

/// Cleanup unused files tool for Agent Builder Assistant.
library;

import 'dart:io';

import '../utils/resolve_root_directory.dart';

/// Identifies unused files in project directories that are not in [usedFiles].
///
/// This tool helps clean up unused tool files when agent configurations change.
/// It identifies files that match [filePatterns] (default `["*.py"]`) and do
/// not match [excludePatterns] (default `["__init__.py", "*_test.py", "test_*.py"]`),
/// excluding any files referenced in [usedFiles].
Future<Map<String, dynamic>> cleanupUnusedFiles(
  List<String> usedFiles,
  Object? toolContext, {
  List<String>? filePatterns,
  List<String>? excludePatterns,
  // ignore: non_constant_identifier_names
  List<String>? file_patterns,
  // ignore: non_constant_identifier_names
  List<String>? exclude_patterns,
}) async {
  final Map<String, Object?>? sessionState = extractSessionState(toolContext);
  final File rootFile = resolveFilePath('.', sessionState);

  try {
    final String rootPath = canonicalizePath(rootFile.path);
    final Directory rootDir = Directory(rootPath);
    final Set<String> resolvedUsedFiles = <String>{
      for (final File path in resolveFilePaths(usedFiles, sessionState))
        canonicalizePath(path.path),
    };

    final List<String> effectiveFilePatterns =
        file_patterns ?? filePatterns ?? <String>['*.py'];
    final List<String> effectiveExcludePatterns =
        exclude_patterns ??
        excludePatterns ??
        <String>['__init__.py', '*_test.py', 'test_*.py'];

    final List<String> errors = <String>[];
    final Map<String, dynamic> result = <String, dynamic>{
      'success': false,
      'unused_files': <String>[],
      'deleted_files': <String>[],
      'backup_files': <String>[],
      'errors': errors,
      'total_freed_space': 0,
    };

    if (!rootDir.existsSync()) {
      errors.add('Root directory does not exist: $rootPath');
      return result;
    }

    final List<File> allFiles = <File>[];
    final List<File> existingFiles = _listAllFilesRecursively(rootDir);

    for (final String pattern in effectiveFilePatterns) {
      if (_patternHasParentTraversal(pattern)) {
        errors.add(
          'File pattern must stay within the root directory: $pattern',
        );
        continue;
      }
      for (final File candidate in existingFiles) {
        final String relPath = relativePathFromRoot(candidate.path, rootPath);
        if (_matchesGlobPattern(relPath, pattern)) {
          final String resolvedCandidate = canonicalizePath(candidate.path);
          if (isPathRelativeTo(resolvedCandidate, rootPath)) {
            allFiles.add(candidate);
          }
        }
      }
    }

    List<File> filteredFiles = allFiles;
    for (final String excludePattern in effectiveExcludePatterns) {
      filteredFiles = <File>[
        for (final File file in filteredFiles)
          if (!_matchesPathPattern(
            relativePathFromRoot(file.path, rootPath),
            excludePattern,
          ))
            file,
      ];
    }

    final List<String> unusedFiles = <String>[];
    for (final File filePath in filteredFiles) {
      final String resolved = canonicalizePath(filePath.path);
      if (!resolvedUsedFiles.contains(resolved)) {
        unusedFiles.add(filePath.path);
      }
    }

    result['unused_files'] = unusedFiles;
    result['success'] = true;
    return result;
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'unused_files': <String>[],
      'deleted_files': <String>[],
      'backup_files': <String>[],
      'errors': <String>['Cleanup scan failed: $e'],
      'total_freed_space': 0,
    };
  }
}

/// Snake-case alias for [cleanupUnusedFiles].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> cleanup_unused_files(
  List<String> usedFiles,
  Object? toolContext, {
  List<String>? filePatterns,
  List<String>? excludePatterns,
  // ignore: non_constant_identifier_names
  List<String>? file_patterns,
  // ignore: non_constant_identifier_names
  List<String>? exclude_patterns,
}) => cleanupUnusedFiles(
  usedFiles,
  toolContext,
  filePatterns: filePatterns,
  excludePatterns: excludePatterns,
  file_patterns: file_patterns,
  exclude_patterns: exclude_patterns,
);

List<File> _listAllFilesRecursively(Directory rootDir) {
  final List<File> files = <File>[];
  try {
    for (final FileSystemEntity entity in rootDir.listSync(
      recursive: true,
      followLinks: true,
    )) {
      if (entity is File) {
        files.add(entity);
      }
    }
  } on FileSystemException {
    // Return partial results if a directory entry cannot be read.
  }
  return files;
}

bool _patternHasParentTraversal(String pattern) {
  final List<String> parts = pattern.replaceAll(r'\', '/').split('/');
  return parts.contains('..');
}

bool _matchesGlobPattern(String relativePath, String pattern) {
  final String normalizedRel = relativePath.replaceAll(r'\', '/');
  final String normalizedPattern = pattern.replaceAll(r'\', '/');
  if (!normalizedPattern.contains('/')) {
    final String fileName = normalizedRel.split('/').last;
    return _globToRegExp(normalizedPattern).hasMatch(fileName);
  }
  return _globToRegExp(normalizedPattern).hasMatch(normalizedRel) ||
      _globToRegExp('**/$normalizedPattern').hasMatch(normalizedRel);
}

bool _matchesPathPattern(String relativePath, String pattern) {
  return _matchesGlobPattern(relativePath, pattern);
}

RegExp _globToRegExp(String pattern) {
  final StringBuffer buffer = StringBuffer('^');
  for (int i = 0; i < pattern.length; i++) {
    final String ch = pattern[i];
    if (ch == '*') {
      if (i + 1 < pattern.length && pattern[i + 1] == '*') {
        if (i + 2 < pattern.length && pattern[i + 2] == '/') {
          buffer.write('(?:.*/)?');
          i += 2;
        } else {
          buffer.write('.*');
          i += 1;
        }
      } else {
        buffer.write('[^/]*');
      }
    } else if (ch == '?') {
      buffer.write('[^/]');
    } else {
      buffer.write(RegExp.escape(ch));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}
