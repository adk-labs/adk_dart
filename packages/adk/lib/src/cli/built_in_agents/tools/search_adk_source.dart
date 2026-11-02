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

/// ADK source code search tool for Agent Builder Assistant.
library;

import 'dart:io';
import 'dart:math' as math;

import '../utils/adk_source_utils.dart';
import '../utils/resolve_root_directory.dart';

/// Searches ADK source code using regex [searchPattern].
///
/// This tool provides a regex-based search for finding specific code patterns,
/// class definitions, function signatures, and implementations in the ADK
/// source code.
Future<Map<String, dynamic>> searchAdkSource(
  String searchPattern, {
  List<String>? filePatterns,
  int maxResults = 20,
  int contextLines = 3,
  bool caseSensitive = false,
  // ignore: non_constant_identifier_names
  List<String>? file_patterns,
  // ignore: non_constant_identifier_names
  int? max_results,
  // ignore: non_constant_identifier_names
  int? context_lines,
  // ignore: non_constant_identifier_names
  bool? case_sensitive,
}) async {
  final List<String>? effectiveFilePatterns = file_patterns ?? filePatterns;
  final int effectiveMaxResults = max_results ?? maxResults;
  final int effectiveContextLines = context_lines ?? contextLines;
  final bool effectiveCaseSensitive = case_sensitive ?? caseSensitive;

  try {
    final String? adkSourcePath = findAdkSourceFolder();
    if (adkSourcePath == null || adkSourcePath.isEmpty) {
      return <String, dynamic>{
        'success': false,
        'pattern': searchPattern,
        'total_matches': 0,
        'files_searched': 0,
        'results': <Map<String, dynamic>>[],
        'errors': <String>[
          "ADK source directory not found. Make sure you're running from "
              'within the ADK project.',
        ],
      };
    }

    final Directory adkSrcDir = Directory(adkSourcePath);
    final List<Map<String, dynamic>> matchResults = <Map<String, dynamic>>[];
    final List<String> errors = <String>[];
    final Map<String, dynamic> result = <String, dynamic>{
      'success': false,
      'pattern': searchPattern,
      'total_matches': 0,
      'files_searched': 0,
      'results': matchResults,
      'errors': errors,
    };

    if (!adkSrcDir.existsSync()) {
      errors.add('ADK source directory not found: ${adkSrcDir.path}');
      return result;
    }

    final List<String> patterns =
        effectiveFilePatterns ?? _defaultFilePatterns(adkSrcDir);

    final RegExp regex;
    try {
      regex = RegExp(searchPattern, caseSensitive: effectiveCaseSensitive);
    } on FormatException catch (e) {
      errors.add('Invalid regex pattern: ${e.message}');
      return result;
    }

    final List<File> allSourceFiles = _listSourceFiles(adkSrcDir);
    final List<File> filesToSearch = <File>[];
    for (final String pattern in patterns) {
      if (_patternHasParentTraversal(pattern)) {
        errors.add(
          'File pattern must stay within the ADK source directory: $pattern',
        );
        continue;
      }
      for (final File candidate in allSourceFiles) {
        final String relPath = relativePathFromRoot(
          candidate.path,
          adkSrcDir.path,
        );
        if (_matchesGlobPattern(relPath, pattern)) {
          filesToSearch.add(candidate);
        }
      }
    }

    result['files_searched'] = filesToSearch.length;

    for (final File filePath in filesToSearch) {
      if ((result['total_matches'] as int) >= effectiveMaxResults) {
        break;
      }

      try {
        final List<String> lines = filePath.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if ((result['total_matches'] as int) >= effectiveMaxResults) {
            break;
          }

          final String lineText = lines[i].trimRight();
          if (regex.hasMatch(lineText)) {
            final int startLine = math.max(0, i - effectiveContextLines);
            final int endLine = math.min(
              lines.length,
              i + effectiveContextLines + 1,
            );

            final List<String> contextBefore = <String>[
              for (int j = startLine; j < i; j++) lines[j].trimRight(),
            ];
            final List<String> contextAfter = <String>[
              for (int j = i + 1; j < endLine; j++) lines[j].trimRight(),
            ];

            final String relFilePath = relativePathFromRoot(
              filePath.path,
              adkSrcDir.path,
            );
            final Map<String, dynamic> matchResult = <String, dynamic>{
              'file_path': relFilePath,
              'line_number': i + 1,
              'match_text': lineText,
              'context_before': contextBefore,
              'context_after': contextAfter,
              'full_match': <String>[
                ...contextBefore,
                '>>> $lineText',
                ...contextAfter,
              ].join('\n'),
            };

            matchResults.add(matchResult);
            result['total_matches'] = (result['total_matches'] as int) + 1;
          }
        }
      } catch (e) {
        errors.add('Error searching ${filePath.path}: $e');
        continue;
      }
    }

    result['success'] = true;
    return result;
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'pattern': searchPattern,
      'total_matches': 0,
      'files_searched': 0,
      'results': <Map<String, dynamic>>[],
      'errors': <String>['Search failed: $e'],
    };
  }
}

/// Snake-case alias for [searchAdkSource].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> search_adk_source(
  String searchPattern, {
  List<String>? filePatterns,
  int maxResults = 20,
  int contextLines = 3,
  bool caseSensitive = false,
  // ignore: non_constant_identifier_names
  List<String>? file_patterns,
  // ignore: non_constant_identifier_names
  int? max_results,
  // ignore: non_constant_identifier_names
  int? context_lines,
  // ignore: non_constant_identifier_names
  bool? case_sensitive,
}) => searchAdkSource(
  searchPattern,
  filePatterns: filePatterns,
  maxResults: maxResults,
  contextLines: contextLines,
  caseSensitive: caseSensitive,
  file_patterns: file_patterns,
  max_results: max_results,
  context_lines: context_lines,
  case_sensitive: case_sensitive,
);

List<String> _defaultFilePatterns(Directory adkSrcDir) {
  bool hasPy = false;
  bool hasDart = false;
  try {
    for (final FileSystemEntity entity in adkSrcDir.listSync(
      recursive: true,
      followLinks: true,
    )) {
      if (entity is File) {
        if (entity.path.endsWith('.py')) {
          hasPy = true;
        } else if (entity.path.endsWith('.dart')) {
          hasDart = true;
        }
      }
    }
  } catch (_) {}
  if (hasPy && !hasDart) {
    return <String>['*.py'];
  }
  if (hasDart && !hasPy) {
    return <String>['*.dart'];
  }
  return <String>['*.py', '*.dart'];
}

List<File> _listSourceFiles(Directory adkSrcDir) {
  final List<File> files = <File>[];
  try {
    for (final FileSystemEntity entity in adkSrcDir.listSync(
      recursive: true,
      followLinks: true,
    )) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Link) {
        try {
          final String resolvedTarget = entity.resolveSymbolicLinksSync();
          if (FileSystemEntity.isFileSync(resolvedTarget)) {
            files.add(File(entity.path));
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
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
