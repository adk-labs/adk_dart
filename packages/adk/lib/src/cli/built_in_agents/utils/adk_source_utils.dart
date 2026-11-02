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

/// Utilities for finding the ADK source folder dynamically and loading schema.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'resolve_root_directory.dart';

Map<String, dynamic>? _schemaCache;

/// Optional override hook for [findAdkSourceFolder] used in testing.
String? Function([String? startPath])? findAdkSourceFolderOverride;

/// Optional override hook for [getAdkSchemaPath] used in testing.
String? Function([String? startPath])? getAdkSchemaPathOverride;

/// Finds the ADK source folder by searching up the directory tree.
///
/// Searches for `'src/google/adk'`, `'google/adk'`, `'lib/src'`, or
/// `'adk_dart/lib/src'` directories starting from [startPath] (or the current
/// directory / resolved `adk_dart` package location when [startPath] is null)
/// and moving up the directory tree until the root.
///
/// Returns the absolute path to the ADK source folder if found, or `null`
/// otherwise.
String? findAdkSourceFolder([String? startPath]) {
  if (findAdkSourceFolderOverride != null) {
    return findAdkSourceFolderOverride!(startPath);
  }

  final String effectiveStart = startPath ?? Directory.current.path;
  Directory currentDir = Directory(canonicalizePath(effectiveStart));

  const List<String> searchPatterns = <String>[
    'src/google/adk',
    'google/adk',
    'lib/src',
    'adk_dart/lib/src',
  ];

  developer.log(
    'Searching for ADK source from directory: ${currentDir.path}',
    name: 'google_adk.adk_source_utils',
  );

  while (true) {
    for (final String pattern in searchPatterns) {
      final Directory candidateDir = Directory(
        _joinPattern(currentDir.path, pattern),
      );
      if (candidateDir.existsSync() && _verifyAdkSourceFolder(candidateDir)) {
        return candidateDir.path;
      }
    }
    final Directory parentDir = currentDir.parent;
    if (parentDir.path == currentDir.path) {
      break;
    }
    currentDir = parentDir;
  }

  // If no explicit startPath was provided, fall back to resolving package:adk_dart.
  if (startPath == null) {
    try {
      final Uri? packageUri = Isolate.resolvePackageUriSync(
        Uri.parse('package:adk_dart/adk_dart.dart'),
      );
      if (packageUri != null && packageUri.scheme == 'file') {
        final Directory libDir = File.fromUri(packageUri).parent;
        final Directory srcDir = Directory(
          _joinPattern(libDir.path, 'src'),
        );
        if (srcDir.existsSync() && _verifyAdkSourceFolder(srcDir)) {
          return canonicalizePath(srcDir.path);
        }
      }
    } catch (_) {
      // Ignore package resolution errors and return null.
    }
  }

  return null;
}

/// Snake-case alias for [findAdkSourceFolder].
// ignore: non_constant_identifier_names
String? find_adk_source_folder([String? startPath]) =>
    findAdkSourceFolder(startPath);

bool _verifyAdkSourceFolder(Directory directory) {
  const List<String> expectedItems = <String>[
    'agents/config_schemas/AgentConfig.json',
  ];

  int foundItems = 0;
  for (final String item in expectedItems) {
    final File expectedFile = File(_joinPattern(directory.path, item));
    if (expectedFile.existsSync()) {
      foundItems += 1;
    }
  }
  return foundItems == expectedItems.length;
}

/// Finds the path to the ADK `AgentConfig.json` schema file.
///
/// Returns the absolute path to `AgentConfig.json` if found, or `null`
/// otherwise.
String? getAdkSchemaPath([String? startPath]) {
  if (getAdkSchemaPathOverride != null) {
    return getAdkSchemaPathOverride!(startPath);
  }

  final String? adkSourcePath = findAdkSourceFolder(startPath);
  if (adkSourcePath == null || adkSourcePath.isEmpty) {
    return null;
  }

  final File schemaFile = File(
    _joinPattern(adkSourcePath, 'agents/config_schemas/AgentConfig.json'),
  );
  if (schemaFile.existsSync()) {
    return schemaFile.path;
  }
  return null;
}

/// Snake-case alias for [getAdkSchemaPath].
// ignore: non_constant_identifier_names
String? get_adk_schema_path([String? startPath]) => getAdkSchemaPath(startPath);

/// Loads the ADK `AgentConfig.json` schema with formatting options.
///
/// If [rawFormat] is `false` (default), returns the parsed schema as a
/// `Map<String, dynamic>`. If [rawFormat] is `true`, returns the formatted
/// JSON string, optionally with `{` and `}` escaped as `{{` and `}}` when
/// [escapeBraces] is `true`.
///
/// Throws a [FileSystemException] if the `AgentConfig.json` schema file is not
/// found.
Object loadAgentConfigSchema({
  bool rawFormat = false,
  bool escapeBraces = false,
}) {
  if (_schemaCache == null) {
    final String? schemaPathStr = getAdkSchemaPath();
    if (schemaPathStr == null || schemaPathStr.isEmpty) {
      throw const FileSystemException(
        "AgentConfig.json schema not found. Make sure you're running from "
        'within the ADK project.',
      );
    }

    final File schemaFile = File(schemaPathStr);
    if (!schemaFile.existsSync()) {
      throw FileSystemException(
        'AgentConfig.json schema not found at ${schemaFile.path}',
        schemaFile.path,
      );
    }

    final Object? decoded = jsonDecode(schemaFile.readAsStringSync());
    if (decoded is! Map) {
      throw FormatException(
        'AgentConfig.json did not decode as a JSON object.',
        schemaFile.path,
      );
    }
    _schemaCache = _deepCastMap(decoded);
  }

  if (!rawFormat) {
    return _schemaCache!;
  }

  String schemaStr = const JsonEncoder.withIndent('  ').convert(_schemaCache);
  if (escapeBraces) {
    schemaStr = schemaStr.replaceAll('{', '{{').replaceAll('}', '}}');
  }
  return schemaStr;
}

/// Typed helper that returns the parsed `AgentConfig.json` schema as a map.
Map<String, dynamic> loadAgentConfigSchemaMap() {
  return loadAgentConfigSchema(rawFormat: false) as Map<String, dynamic>;
}

/// Snake-case alias for [loadAgentConfigSchema].
// ignore: non_constant_identifier_names
Object load_agent_config_schema({
  // ignore: non_constant_identifier_names
  bool raw_format = false,
  // ignore: non_constant_identifier_names
  bool escape_braces = false,
}) => loadAgentConfigSchema(rawFormat: raw_format, escapeBraces: escape_braces);

/// Clears the cached schema data.
void clearSchemaCache() {
  _schemaCache = null;
}

/// Snake-case alias for [clearSchemaCache].
// ignore: non_constant_identifier_names
void clear_schema_cache() => clearSchemaCache();

String _joinPattern(String base, String relativePattern) {
  final String sep = Platform.pathSeparator;
  final List<String> segments = relativePattern
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  if (base.endsWith(sep)) {
    return '$base${segments.join(sep)}';
  }
  return '$base$sep${segments.join(sep)}';
}

Map<String, dynamic> _deepCastMap(Map<Object?, Object?> source) {
  final Map<String, dynamic> result = <String, dynamic>{};
  source.forEach((Object? key, Object? value) {
    result['$key'] = _deepCastValue(value);
  });
  return result;
}

Object? _deepCastValue(Object? value) {
  if (value is Map) {
    return _deepCastMap(value);
  }
  if (value is List) {
    return value.map(_deepCastValue).toList();
  }
  return value;
}
