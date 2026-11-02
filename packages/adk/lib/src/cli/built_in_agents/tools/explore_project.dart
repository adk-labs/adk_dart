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

/// Project explorer tool for analyzing structure and suggesting file paths.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import '../utils/resolve_root_directory.dart';

/// Analyzes project structure and suggests optimal file paths for ADK agents.
///
/// This tool performs comprehensive project analysis to understand the existing
/// structure and recommend appropriate locations for new agent configurations,
/// tools, and related files following ADK best practices.
Future<Map<String, dynamic>> exploreProject(Object? toolContext) async {
  try {
    final Map<String, Object?>? sessionState = extractSessionState(toolContext);
    final File resolvedPath = resolveFilePath('.', sessionState);
    final String rootPathStr = canonicalizePath(resolvedPath.path);
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      rootPathStr,
      followLinks: true,
    );

    if (entityType == FileSystemEntityType.notFound) {
      return <String, dynamic>{
        'success': false,
        'error': 'Project directory does not exist: $rootPathStr',
      };
    }

    if (entityType != FileSystemEntityType.directory) {
      return <String, dynamic>{
        'success': false,
        'error': 'Path is not a directory: $rootPathStr',
      };
    }

    final Directory rootDir = Directory(rootPathStr);
    final Map<String, dynamic> projectInfo = _analyzeProjectInfo(rootDir);
    final List<Map<String, dynamic>> existingConfigs = _findExistingConfigs(
      rootDir,
    );
    final Map<String, dynamic> directoryStructure = _buildDirectoryTree(rootDir);
    final Map<String, dynamic> suggestions = _generatePathSuggestions(
      rootDir,
      existingConfigs,
    );
    final Map<String, dynamic> conventions = _getNamingConventions();

    return <String, dynamic>{
      'success': true,
      'project_info': projectInfo,
      'existing_configs': existingConfigs,
      'directory_structure': directoryStructure,
      'suggestions': suggestions,
      'conventions': conventions,
    };
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == 13) {
      return <String, dynamic>{
        'success': false,
        'error': 'Permission denied accessing project directory',
      };
    }
    return <String, dynamic>{
      'success': false,
      'error': 'Error exploring project: $e',
    };
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'error': 'Error exploring project: $e',
    };
  }
}

/// Snake-case alias for [exploreProject].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> explore_project(Object? toolContext) =>
    exploreProject(toolContext);

Map<String, dynamic> _analyzeProjectInfo(Directory rootDir) {
  bool isEmpty = true;
  try {
    isEmpty = rootDir.listSync(followLinks: false).isEmpty;
  } catch (_) {}

  final Map<String, dynamic> info = <String, dynamic>{
    'name': _entityBaseName(rootDir.path),
    'absolute_path': rootDir.path,
    'is_empty': isEmpty,
    'total_files': 0,
    'total_directories': 0,
    'has_python_files': false,
    'has_yaml_files': false,
    'has_tools_directory': false,
    'has_callbacks_directory': false,
  };

  try {
    for (final FileSystemEntity item in rootDir.listSync(
      recursive: true,
      followLinks: true,
    )) {
      if (item is File) {
        info['total_files'] = (info['total_files'] as int) + 1;
        final String lower = item.path.toLowerCase();
        if (lower.endsWith('.py')) {
          info['has_python_files'] = true;
        } else if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
          info['has_yaml_files'] = true;
        }
      } else if (item is Directory) {
        info['total_directories'] = (info['total_directories'] as int) + 1;
        final String name = _entityBaseName(item.path);
        if (canonicalizePath(item.parent.path) ==
            canonicalizePath(rootDir.path)) {
          if (name == 'tools') {
            info['has_tools_directory'] = true;
          } else if (name == 'callbacks') {
            info['has_callbacks_directory'] = true;
          }
        }
      }
    }
  } catch (_) {
    // Continue with partial information if traversal fails.
  }

  return info;
}

List<Map<String, dynamic>> _findExistingConfigs(Directory rootDir) {
  final List<Map<String, dynamic>> configs = <Map<String, dynamic>>[];

  try {
    for (final FileSystemEntity entity in rootDir.listSync(followLinks: true)) {
      if (entity is! File) {
        continue;
      }
      final String lower = entity.path.toLowerCase();
      if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
        configs.add(_analyzeConfigFile(entity, rootDir));
      }
    }
    configs.sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          ('${a['filename']}').compareTo('${b['filename']}'),
    );
  } catch (_) {
    // Return partial results if scanning fails.
  }

  return configs;
}

Map<String, dynamic> _analyzeConfigFile(File configFile, Directory rootDir) {
  final String filename = _entityBaseName(configFile.path);
  String relativePath;
  try {
    relativePath = relativePathFromRoot(configFile.path, rootDir.path);
  } catch (_) {
    relativePath = filename;
  }

  final Map<String, dynamic> info = <String, dynamic>{
    'filename': filename,
    'relative_path': relativePath,
    'size': 0,
    'is_valid_yaml': false,
    'agent_name': null,
    'agent_class': null,
    'has_sub_agents': false,
    'has_tools': false,
  };

  try {
    info['size'] = configFile.lengthSync();
    final Object? decoded = loadYaml(configFile.readAsStringSync());
    if (decoded is Map) {
      info['is_valid_yaml'] = true;
      info['agent_name'] = decoded['name'];
      info['agent_class'] = decoded['agent_class'] ?? 'LlmAgent';
      final Object? subAgents = decoded['sub_agents'];
      final Object? tools = decoded['tools'];
      info['has_sub_agents'] = subAgents is List && subAgents.isNotEmpty;
      info['has_tools'] = tools is List && tools.isNotEmpty;
    }
  } catch (_) {
    // File exists but couldn't be parsed.
  }

  return info;
}

Map<String, dynamic> _buildDirectoryTree(
  Directory rootDir, {
  int maxDepth = 3,
}) {
  Map<String, dynamic> buildTreeRecursive(
    FileSystemEntity entity,
    int currentDepth,
  ) {
    if (currentDepth > maxDepth) {
      return <String, dynamic>{'truncated': true};
    }

    final bool isDir = entity is Directory;
    String relPath;
    try {
      relPath = relativePathFromRoot(entity.path, rootDir.path);
    } catch (_) {
      relPath = _entityBaseName(entity.path);
    }

    final Map<String, dynamic> tree = <String, dynamic>{
      'name': _entityBaseName(entity.path),
      'type': isDir ? 'directory' : 'file',
      'path': relPath,
    };

    if (entity is Directory) {
      final List<Map<String, dynamic>> children = <Map<String, dynamic>>[];
      try {
        final List<FileSystemEntity> entries = entity.listSync(
          followLinks: false,
        )..sort(
          (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
        );
        for (final FileSystemEntity child in entries) {
          final String childName = _entityBaseName(child.path);
          if (!childName.startsWith('.') &&
              childName != '__pycache__' &&
              childName != 'node_modules') {
            children.add(buildTreeRecursive(child, currentDepth + 1));
          }
        }
        tree['children'] = children;
      } on FileSystemException {
        tree['error'] = 'Permission denied';
      }
    } else if (entity is File) {
      tree['size'] = entity.existsSync() ? entity.lengthSync() : 0;
    }

    return tree;
  }

  return buildTreeRecursive(rootDir, 0);
}

Map<String, dynamic> _generatePathSuggestions(
  Directory rootDir,
  List<Map<String, dynamic>> existingConfigs,
) {
  List<String> rootAgentSuggestions = <String>[];
  final bool hasCandidateRoot = existingConfigs.any(
    (Map<String, dynamic> config) =>
        config['agent_class'] != 'LlmAgent' ||
        !(config['has_sub_agents'] as bool? ?? false),
  );
  if (!hasCandidateRoot) {
    rootAgentSuggestions = <String>['root_agent.yaml'];
  }

  final String sep = Platform.pathSeparator;
  final Map<String, dynamic> directories = <String, dynamic>{
    'tools': <String, dynamic>{
      'path': 'tools',
      'exists': Directory('${rootDir.path}${sep}tools').existsSync(),
      'purpose': 'Custom tool implementations',
      'example_files': <String>['custom_email.py', 'database_connector.py'],
    },
    'callbacks': <String, dynamic>{
      'path': 'callbacks',
      'exists': Directory('${rootDir.path}${sep}callbacks').existsSync(),
      'purpose': 'Custom callback functions',
      'example_files': <String>['logging.py', 'security.py'],
    },
  };

  return <String, dynamic>{
    'root_agent_configs': rootAgentSuggestions,
    'sub_agent_patterns': <String>[
      '{purpose}_agent.yaml',
      '{domain}_{action}_agent.yaml',
      '{workflow_step}_agent.yaml',
    ],
    'directories': directories,
  };
}

Map<String, dynamic> _getNamingConventions() {
  return <String, dynamic>{
    'agent_files': <String, dynamic>{
      'format': 'snake_case with .yaml extension',
      'examples': <String>['main_agent.yaml', 'email_processor.yaml'],
      'location': 'Root directory of the project',
      'avoid': <String>['camelCase.yaml', 'spaces in names.yaml', 'UPPERCASE.yaml'],
    },
    'agent_names': <String, dynamic>{
      'format': 'snake_case, descriptive, no spaces',
      'examples': <String>['customer_service_coordinator', 'email_classifier'],
      'avoid': <String>['Agent1', 'my agent', 'CustomerServiceAgent'],
    },
    'directory_structure': <String, dynamic>{
      'recommended': <String, dynamic>{
        'root': 'All .yaml agent configuration files',
        'tools/': 'Custom tool implementations (.py files)',
        'callbacks/': 'Custom callback functions (.py files)',
      },
    },
  };
}

String _entityBaseName(String path) {
  final String sep = Platform.pathSeparator;
  final String trimmed = path.length > 1 && path.endsWith(sep)
      ? path.substring(0, path.length - 1)
      : path;
  final int idx = trimmed.lastIndexOf(sep);
  return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
}
