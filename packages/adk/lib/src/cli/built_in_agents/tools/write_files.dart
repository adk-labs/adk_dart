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

/// File writing tool for Agent Builder Assistant.
library;

import 'dart:io';

import '../utils/_adk_symbols.dart';
import '../utils/resolve_root_directory.dart';

/// Returns `google.adk.*` names imported by a Python file at [filePath] that
/// do not resolve in the installed ADK package.
///
/// Only imports are inspected, and only in `.py` files. An import is a hard
/// promise the name exists; an attribute deeper in the body may be guarded, so
/// flagging those would reject working code.
List<String> unknownAdkImports(String filePath, String content) {
  if (!filePath.endsWith('.py')) {
    return <String>[];
  }
  if (_hasPythonSyntaxError(content)) {
    return <String>[];
  }

  final List<String> names = <String>[];
  final List<String> logicalLines = _joinContinuedPythonLines(content);

  for (final String rawLine in logicalLines) {
    final String line = _stripPythonComment(rawLine).trim();
    if (line.isEmpty) {
      continue;
    }

    // Match `from google.adk... import a, b as c`
    final RegExpMatch? fromMatch = RegExp(
      r'^from\s+(google\.adk(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s+import\s+(.+)$',
    ).firstMatch(line);
    if (fromMatch != null) {
      final String module = fromMatch.group(1)!;
      String importedPart = fromMatch.group(2)!.trim();
      if (importedPart.startsWith('(') && importedPart.endsWith(')')) {
        importedPart = importedPart.substring(1, importedPart.length - 1);
      }
      for (final String clause in importedPart.split(',')) {
        final String trimmedClause = clause.trim();
        if (trimmedClause.isEmpty || trimmedClause == '*') {
          continue;
        }
        final String aliasName = trimmedClause.split(RegExp(r'\s+as\s+')).first.trim();
        if (aliasName.isNotEmpty && aliasName != '*') {
          names.add('$module.$aliasName');
        }
      }
      continue;
    }

    // Match `import google.adk...`
    final RegExpMatch? importMatch = RegExp(
      r'^import\s+(.+)$',
    ).firstMatch(line);
    if (importMatch != null) {
      final String importedPart = importMatch.group(1)!.trim();
      for (final String clause in importedPart.split(',')) {
        final String aliasName = clause
            .trim()
            .split(RegExp(r'\s+as\s+'))
            .first
            .trim();
        if (aliasName.startsWith('google.adk')) {
          names.add(aliasName);
        }
      }
    }
  }

  final List<String> unknown = <String>[];
  final Set<String> seen = <String>{};
  for (final String name in names) {
    if (!seen.add(name)) {
      continue;
    }
    if (!adkSymbolExists(name)) {
      unknown.add(name);
    }
  }
  return unknown;
}

/// Private-style snake_case alias for [unknownAdkImports] matching Python tests.
// ignore: non_constant_identifier_names, unused_element
List<String> _unknown_adk_imports(String filePath, String content) =>
    unknownAdkImports(filePath, content);

/// Public snake_case alias for [unknownAdkImports].
// ignore: non_constant_identifier_names
List<String> unknown_adk_imports(String filePath, String content) =>
    unknownAdkImports(filePath, content);

/// Writes content to multiple [files] with optional backup creation.
///
/// This tool writes content to multiple files. It is designed for creating
/// tool implementations, callbacks, configuration files, and other code files.
Future<Map<String, dynamic>> writeFiles(
  Map<String, String> files,
  Object? toolContext, {
  bool createBackup = false,
  bool createDirectories = true,
  // ignore: non_constant_identifier_names
  bool? create_backup,
  // ignore: non_constant_identifier_names
  bool? create_directories,
}) async {
  final bool effectiveCreateBackup = create_backup ?? createBackup;
  final bool effectiveCreateDirectories =
      create_directories ?? createDirectories;

  try {
    final Map<String, Object?>? sessionState = extractSessionState(toolContext);
    Directory? projectRoot;
    if (sessionState != null) {
      try {
        final File resolvedRoot = resolveFilePath('.', sessionState);
        projectRoot = Directory(canonicalizePath(resolvedRoot.path));
      } catch (_) {
        projectRoot = null;
      }
    }

    final Map<String, dynamic> filesResult = <String, dynamic>{};
    final List<String> errors = <String>[];
    final Map<String, dynamic> result = <String, dynamic>{
      'success': true,
      'files': filesResult,
      'successful_writes': 0,
      'total_files': files.length,
      'errors': errors,
    };

    for (final MapEntry<String, String> entry in files.entries) {
      final String filePath = entry.key;
      final String content = entry.value;

      final File resolvedPath = resolveFilePath(filePath, sessionState);
      final File filePathObj = File(canonicalizePath(resolvedPath.path));
      final Map<String, dynamic> fileInfo = <String, dynamic>{
        'file_size': 0,
        'existed_before': false,
        'backup_created': false,
        'backup_path': null,
        'error': null,
        'package_inits_created': <String>[],
      };

      final List<String> unknown = unknownAdkImports(filePath, content);
      if (unknown.isNotEmpty) {
        fileInfo['error'] =
            'Imports names that do not exist in the installed ADK: '
            '${unknown.join(', ')}'
            '. Check each with search_adk_source before using it.';
        result['success'] = false;
        result['failed_writes'] = ((result['failed_writes'] as int?) ?? 0) + 1;
        filesResult[filePath] = fileInfo;
        continue;
      }

      try {
        final bool existedBefore = filePathObj.existsSync();
        fileInfo['existed_before'] = existedBefore;

        if (effectiveCreateDirectories) {
          filePathObj.parent.createSync(recursive: true);
        }

        if (filePathObj.path.endsWith('.py') && projectRoot != null) {
          final List<String> createdInits = _ensurePackageInits(
            filePathObj,
            projectRoot,
          );
          if (createdInits.isNotEmpty) {
            fileInfo['package_inits_created'] = createdInits;
          }
        }

        if (effectiveCreateBackup && existedBefore) {
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

        filePathObj.writeAsStringSync(content);

        if (filePathObj.existsSync()) {
          fileInfo['file_size'] = filePathObj.lengthSync();
          result['successful_writes'] = (result['successful_writes'] as int) + 1;
        } else {
          fileInfo['error'] = 'File was not created successfully';
          result['success'] = false;
        }
      } catch (e) {
        fileInfo['error'] = 'Write failed: $e';
        result['success'] = false;
      }

      filesResult[filePathObj.path] = fileInfo;
    }

    return result;
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'files': <String, dynamic>{},
      'successful_writes': 0,
      'total_files': files.length,
      'errors': <String>['Write operation failed: $e'],
    };
  }
}

/// Snake-case alias for [writeFiles].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> write_files(
  Map<String, String> files,
  Object? toolContext, {
  bool createBackup = false,
  bool createDirectories = true,
  // ignore: non_constant_identifier_names
  bool? create_backup,
  // ignore: non_constant_identifier_names
  bool? create_directories,
}) => writeFiles(
  files,
  toolContext,
  createBackup: createBackup,
  createDirectories: createDirectories,
  create_backup: create_backup,
  create_directories: create_directories,
);

List<String> _ensurePackageInits(File filePath, Directory projectRoot) {
  final List<String> createdInits = <String>[];
  final String targetParent;
  final String rootPath;
  final String relativeParent;
  try {
    targetParent = canonicalizePath(filePath.parent.path);
    rootPath = canonicalizePath(projectRoot.path);
    relativeParent = relativePathFromRoot(targetParent, rootPath);
  } catch (_) {
    return createdInits;
  }

  void touchInit(Directory directory) {
    final File initFile = File(
      '${directory.path}${Platform.pathSeparator}__init__.py',
    );
    if (!initFile.existsSync()) {
      initFile.createSync(recursive: true);
      createdInits.add(initFile.path);
    }
  }

  Directory(rootPath).createSync(recursive: true);
  if (relativeParent.isEmpty || relativeParent == '.') {
    return createdInits;
  }

  String currentPath = rootPath;
  for (final String part in relativeParent.split(Platform.pathSeparator)) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    currentPath = '$currentPath${Platform.pathSeparator}$part';
    final Directory currentDir = Directory(currentPath);
    currentDir.createSync(recursive: true);
    touchInit(currentDir);
  }

  return createdInits;
}

bool _hasPythonSyntaxError(String content) {
  int parenDepth = 0;
  int bracketDepth = 0;
  int braceDepth = 0;

  for (final String rawLine in content.split('\n')) {
    final String line = _stripPythonComment(rawLine).trim();
    if (line.isEmpty) {
      continue;
    }
    // Detect malformed function/class headers like `def broken(:`
    if (RegExp(r'\b(?:def|class)\s+[A-Za-z_][A-Za-z0-9_]*\s*\(\s*:').hasMatch(line)) {
      return true;
    }
    for (int i = 0; i < line.length; i++) {
      final String ch = line[i];
      if (ch == '(') {
        parenDepth += 1;
      } else if (ch == ')') {
        parenDepth -= 1;
        if (parenDepth < 0) {
          return true;
        }
      } else if (ch == '[') {
        bracketDepth += 1;
      } else if (ch == ']') {
        bracketDepth -= 1;
        if (bracketDepth < 0) {
          return true;
        }
      } else if (ch == '{') {
        braceDepth += 1;
      } else if (ch == '}') {
        braceDepth -= 1;
        if (braceDepth < 0) {
          return true;
        }
      }
    }
  }

  return parenDepth != 0 || bracketDepth != 0 || braceDepth != 0;
}

List<String> _joinContinuedPythonLines(String content) {
  final List<String> result = <String>[];
  final StringBuffer current = StringBuffer();
  int parenDepth = 0;

  for (final String rawLine in content.split('\n')) {
    final String stripped = _stripPythonComment(rawLine);
    for (int i = 0; i < stripped.length; i++) {
      if (stripped[i] == '(') {
        parenDepth += 1;
      } else if (stripped[i] == ')' && parenDepth > 0) {
        parenDepth -= 1;
      }
    }
    if (stripped.trimRight().endsWith(r'\')) {
      final String withoutSlash = stripped.trimRight();
      current.write(withoutSlash.substring(0, withoutSlash.length - 1));
      current.write(' ');
      continue;
    }
    current.write(stripped);
    if (parenDepth == 0) {
      result.add(current.toString());
      current.clear();
    } else {
      current.write(' ');
    }
  }
  if (current.isNotEmpty) {
    result.add(current.toString());
  }
  return result;
}

String _stripPythonComment(String line) {
  bool inSingle = false;
  bool inDouble = false;
  for (int i = 0; i < line.length; i++) {
    final String ch = line[i];
    if (ch == r'\' && i + 1 < line.length) {
      i += 1;
      continue;
    }
    if (ch == "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (ch == '"' && !inSingle) {
      inDouble = !inDouble;
    } else if (ch == '#' && !inSingle && !inDouble) {
      return line.substring(0, i);
    }
  }
  return line;
}

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
