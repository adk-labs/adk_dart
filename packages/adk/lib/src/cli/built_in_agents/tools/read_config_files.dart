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

/// Configuration file reader tool for existing YAML configs.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

import 'read_files.dart';

/// Reads multiple YAML configuration files at [filePaths] and extracts metadata.
Future<Map<String, dynamic>> readConfigFiles(
  List<String> filePaths,
  Object? toolContext,
) async {
  final Map<String, dynamic> readResult = await readFiles(
    filePaths,
    toolContext,
  );

  final Map<String, dynamic> filesResult = <String, dynamic>{};
  final Map<String, dynamic> result = <String, dynamic>{
    'success': true,
    'total_files': filePaths.length,
    'successful_reads': 0,
    'files': filesResult,
    'errors': <String>[],
  };

  final Map<String, dynamic> rawFiles =
      (readResult['files'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  for (final MapEntry<String, dynamic> entry in rawFiles.entries) {
    final String filePath = entry.key;
    final Map<String, dynamic> fileInfo = entry.value is Map<String, dynamic>
        ? entry.value as Map<String, dynamic>
        : <String, dynamic>{};

    final Map<String, dynamic> fileAnalysis = <String, dynamic>{
      'success': false,
      'file_path': filePath,
      'file_size': fileInfo['file_size'] ?? 0,
      'line_count': 0,
      'error': null,
    };

    if (fileInfo['error'] != null) {
      fileAnalysis['error'] = fileInfo['error'];
      filesResult[filePath] = fileAnalysis;
      result['success'] = false;
      continue;
    }

    final String lowerPath = filePath.toLowerCase();
    if (!lowerPath.endsWith('.yaml') && !lowerPath.endsWith('.yml')) {
      fileAnalysis['error'] = 'File is not a YAML file: $filePath';
      filesResult[filePath] = fileAnalysis;
      result['success'] = false;
      continue;
    }

    final String rawYaml = (fileInfo['content'] as String?) ?? '';
    fileAnalysis['line_count'] = rawYaml.split('\n').length;

    Object? decoded;
    try {
      decoded = _yamlToPlainObject(loadYaml(rawYaml));
    } catch (e) {
      fileAnalysis['error'] = 'Invalid YAML syntax: $e';
      fileAnalysis['raw_yaml'] = rawYaml;
      filesResult[filePath] = fileAnalysis;
      result['success'] = false;
      continue;
    }

    if (decoded is! Map<String, dynamic>) {
      fileAnalysis['error'] = 'YAML content is not a valid object/dictionary';
      fileAnalysis['raw_yaml'] = rawYaml;
      filesResult[filePath] = fileAnalysis;
      result['success'] = false;
      continue;
    }

    try {
      final Map<String, dynamic> agentInfo = _extractAgentInfo(decoded);
      final List<Object?> subAgents = _extractSubAgents(decoded);
      final List<Object?> tools = _extractTools(decoded);

      fileAnalysis.addAll(<String, dynamic>{
        'success': true,
        'content': decoded,
        'agent_info': agentInfo,
        'sub_agents': subAgents,
        'tools': tools,
      });

      result['successful_reads'] = (result['successful_reads'] as int) + 1;
    } catch (e) {
      fileAnalysis['error'] = 'Error extracting metadata: $e';
      result['success'] = false;
    }

    filesResult[filePath] = fileAnalysis;
  }

  return result;
}

/// Snake-case alias for [readConfigFiles].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> read_config_files(
  List<String> filePaths,
  Object? toolContext,
) => readConfigFiles(filePaths, toolContext);

Map<String, dynamic> _extractAgentInfo(Map<String, dynamic> content) {
  final String instruction = (content['instruction'] as String?) ?? '';
  return <String, dynamic>{
    'name': content['name'] ?? 'unknown',
    'agent_class': content['agent_class'] ?? 'LlmAgent',
    'description': content['description'] ?? '',
    'model': content['model'] ?? '',
    'has_instruction': instruction.trim().isNotEmpty,
    'instruction_length': instruction.length,
    'has_memory': _isTruthy(content['memory']),
    'has_state': _isTruthy(content['state']),
  };
}

List<Object?> _extractSubAgents(Map<String, dynamic> content) {
  final Object? subAgents = content['sub_agents'];
  if (subAgents is! List) {
    return <Object?>[];
  }

  final List<Object?> extracted = <Object?>[];
  for (final Object? subAgent in subAgents) {
    if (subAgent is Map) {
      final String configPath = (subAgent['config_path'] as String?) ?? '';
      final String code = (subAgent['code'] as String?) ?? '';
      final Map<String, dynamic> agentRef = <String, dynamic>{
        'config_path': configPath,
        'code': code,
        'type': subAgent.containsKey('config_path') ? 'config_path' : 'code',
      };
      if (configPath.isNotEmpty) {
        agentRef['file_exists'] = _checkFileExists(configPath);
      }
      extracted.add(agentRef);
    } else if (subAgent is String) {
      extracted.add(<String, dynamic>{
        'config_path': subAgent,
        'code': '',
        'type': 'config_path',
        'file_exists': _checkFileExists(subAgent),
      });
    }
  }

  return extracted;
}

List<Object?> _extractTools(Map<String, dynamic> content) {
  final Object? tools = content['tools'];
  if (tools is! List) {
    return <Object?>[];
  }

  final List<Object?> extracted = <Object?>[];
  for (final Object? tool in tools) {
    if (tool is Map) {
      final Object? rawArgs = tool['args'];
      final int argsCount = switch (rawArgs) {
        final List<Object?> list => list.length,
        final Map<Object?, Object?> map => map.length,
        _ => 0,
      };
      extracted.add(<String, dynamic>{
        'name': tool['name'] ?? '',
        'type': 'object',
        'has_args': _isTruthy(rawArgs),
        'args_count': argsCount,
        'raw': tool,
      });
    } else if (tool is String) {
      extracted.add(<String, dynamic>{
        'name': tool,
        'type': 'string',
        'has_args': false,
        'args_count': 0,
        'raw': tool,
      });
    }
  }

  return extracted;
}

bool _checkFileExists(String configPath) {
  try {
    if (configPath.isEmpty) {
      return false;
    }

    final File file = File(configPath);
    if (!file.isAbsolute) {
      final String sep = Platform.pathSeparator;
      final File currentDirPath = File('${Directory.current.path}$sep$configPath');
      if (currentDirPath.existsSync()) {
        return true;
      }

      for (final String potentialDir in const <String>[
        '.',
        './agents',
        '../agents',
      ]) {
        final File potentialPath = File('$potentialDir$sep$configPath');
        if (potentialPath.existsSync()) {
          return true;
        }
      }
    }

    return file.existsSync();
  } catch (_) {
    return false;
  }
}

bool _isTruthy(Object? value) {
  if (value == null || value == false) {
    return false;
  }
  if (value is String) {
    return value.isNotEmpty;
  }
  if (value is Iterable) {
    return value.isNotEmpty;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  if (value is num) {
    return value != 0;
  }
  return true;
}

Object? _yamlToPlainObject(Object? node) {
  if (node is Map) {
    final Map<String, dynamic> map = <String, dynamic>{};
    node.forEach((Object? key, Object? value) {
      map['$key'] = _yamlToPlainObject(value);
    });
    return map;
  }
  if (node is Iterable) {
    return node.map(_yamlToPlainObject).toList();
  }
  return node;
}
