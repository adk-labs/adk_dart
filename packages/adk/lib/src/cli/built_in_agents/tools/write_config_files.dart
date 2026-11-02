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

/// Configuration file writer tool with validation-before-write.
library;

import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart' as adk_core;
import 'package:adk_dart/adk_dart.dart' show ToolContext;
import 'package:yaml/yaml.dart';

import '../utils/__init__.dart';
import '../utils/_adk_symbols.dart' as adk_symbols;
import 'write_files.dart';

/// Characters that cannot appear in generated filenames.
const Set<String> invalidFilenameCharacters = <String>{
  '<',
  '>',
  ':',
  '"',
  '/',
  r'\',
  '|',
  '?',
  '*',
};

/// Alias for [invalidFilenameCharacters] matching the Python constant name.
// ignore: constant_identifier_names
const Set<String> INVALID_FILENAME_CHARACTERS = invalidFilenameCharacters;

/// Internal key used to pass parsed config maps through validation results.
const String parsedConfigKey = '_parsed_config';

/// Alias for [parsedConfigKey] matching the Python constant name.
// ignore: constant_identifier_names
const String PARSED_CONFIG_KEY = parsedConfigKey;

/// Workflow agent class names that orchestrate sub-agents.
const Set<String> workflowAgentClasses = <String>{
  'SequentialAgent',
  'ParallelAgent',
  'LoopAgent',
};

/// Alias for [workflowAgentClasses] matching the Python constant name.
// ignore: constant_identifier_names
const Set<String> WORKFLOW_AGENT_CLASSES = workflowAgentClasses;

/// Valid identifier pattern for agent names.
final RegExp identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Alias for [identifierPattern] matching the Python constant name.
// ignore: non_constant_identifier_names
final RegExp IDENTIFIER_PATTERN = identifierPattern;

/// Callback field names on `AgentConfig`.
const List<String> callbackFieldNames = <String>[
  'before_agent_callbacks',
  'after_agent_callbacks',
  'before_model_callbacks',
  'after_model_callbacks',
  'before_tool_callbacks',
  'after_tool_callbacks',
];

/// Alias for [callbackFieldNames] matching the Python constant name.
// ignore: constant_identifier_names
const List<String> CALLBACK_FIELD_NAMES = callbackFieldNames;

const Set<String> _adkAgentClasses = <String>{
  'LlmAgent',
  'LoopAgent',
  'ParallelAgent',
  'SequentialAgent',
};

final RegExp _adkNamePattern = RegExp(
  r'google\.adk(?:\.[A-Za-z_][A-Za-z0-9_]*)+',
);

/// Write multiple YAML configurations with comprehensive validation-before-write.
///
/// This tool validates YAML syntax and `AgentConfig` schema compliance before
/// writing files to prevent invalid configurations from being saved. It
/// provides detailed error reporting and optional backup functionality.
Future<Map<String, dynamic>> writeConfigFiles(
  Map<String, String> configs,
  ToolContext? toolContext, {
  bool backupExisting = false,
  bool createDirectories = true,
}) async {
  final Map<String, dynamic> filesMap = <String, dynamic>{};
  final Map<String, dynamic> result = <String, dynamic>{
    'success': true,
    'total_files': configs.length,
    'successful_writes': 0,
    'files': filesMap,
    'errors': <dynamic>[],
  };

  final Map<String, Map<String, dynamic>> validatedConfigDicts =
      <String, Map<String, dynamic>>{};
  final Map<String, String> normalizedPathToOriginal = <String, String>{};
  final Map<String, String> canonicalPathToOriginal = <String, String>{};
  final Map<String, String> renameMap = <String, String>{};

  Map<String, Object?>? sessionState;
  try {
    sessionState = toolContext?.session.state;
  } catch (_) {
    sessionState = null;
  }

  String? projectFolderName;
  if (sessionState != null) {
    try {
      final File projectRoot = resolveFilePath('.', sessionState);
      final String baseName = _basename(projectRoot.path);
      projectFolderName = baseName.isEmpty ? null : baseName;
    } catch (_) {
      projectFolderName = null;
    }
  }

  // Step 1: Validate all configs before writing any files.
  for (final MapEntry<String, String> entry in configs.entries) {
    final String filePath = entry.key;
    final String configContent = entry.value;
    final String normalizedInputPath = sanitizeGeneratedFilePath(filePath);
    final Map<String, dynamic> fileResult = _validateSingleConfig(
      normalizedInputPath,
      configContent,
      projectFolderName,
    );
    filesMap[filePath] = fileResult;

    if (fileResult['success'] == true) {
      final Object? parsedConfigRaw = fileResult.remove(parsedConfigKey);
      if (parsedConfigRaw is! Map<String, dynamic>) {
        fileResult['success'] = false;
        fileResult['error_type'] = 'INTERNAL_VALIDATION_ERROR';
        fileResult['error'] = 'Failed to parse configuration content.';
        result['success'] = false;
        continue;
      }
      final Map<String, dynamic> parsedConfig = parsedConfigRaw;

      final String? agentName = fileResult['agent_name'] as String?;
      final (
        String targetPath,
        bool renameApplied,
        String? sanitizedName,
        String? renameWarning,
      ) = _determineTargetFilePath(normalizedInputPath, agentName);

      fileResult['target_file_path'] = targetPath;
      fileResult['rename_applied'] = renameApplied;
      if (renameWarning != null && renameWarning.isNotEmpty) {
        final List<String> warnings = List<String>.from(
          (fileResult['warnings'] as List<dynamic>?) ?? const <String>[],
        );
        warnings.add(renameWarning);
        fileResult['warnings'] = warnings;
      }

      if (renameApplied &&
          sanitizedName != null &&
          sanitizedName.isNotEmpty &&
          sanitizedName != agentName) {
        final List<String> warnings = List<String>.from(
          (fileResult['warnings'] as List<dynamic>?) ?? const <String>[],
        );
        warnings.add(
          'Agent name normalized for filesystem compatibility:'
          " '$agentName' -> '$sanitizedName'",
        );
        fileResult['warnings'] = warnings;
      }

      final String normalizedKey = targetPath;
      if (normalizedPathToOriginal.containsKey(normalizedKey)) {
        final String conflictSource = normalizedPathToOriginal[normalizedKey]!;
        fileResult['success'] = false;
        fileResult['error_type'] = 'FILE_PATH_CONFLICT';
        fileResult['error'] =
            'Multiple agent configs target the same file path after'
            " normalization: '$conflictSource' and '$filePath'";
        result['success'] = false;
        continue;
      }
      normalizedPathToOriginal[normalizedKey] = filePath;

      final String canonicalKey = _canonicalPathKey(
        normalizedKey,
        sessionState,
      );
      if (canonicalPathToOriginal.containsKey(canonicalKey)) {
        final String conflictSource = canonicalPathToOriginal[canonicalKey]!;
        fileResult['success'] = false;
        fileResult['error_type'] = 'FILE_PATH_CONFLICT';
        fileResult['error'] =
            'Multiple agent configs resolve to the same file path after'
            " normalization: '$conflictSource' and '$filePath'";
        result['success'] = false;
        continue;
      }
      canonicalPathToOriginal[canonicalKey] = filePath;

      if (normalizedKey != filePath) {
        renameMap[filePath] = normalizedKey;
      }

      validatedConfigDicts[normalizedKey] = parsedConfig;
    } else {
      result['success'] = false;
    }
  }

  if (result['success'] == true && validatedConfigDicts.isNotEmpty) {
    if (renameMap.isNotEmpty) {
      final Map<String, String> referenceMap = _buildReferenceMap(renameMap);
      for (final Map<String, dynamic> configDict
          in validatedConfigDicts.values) {
        _updateSubAgentReferences(configDict, referenceMap);
      }
    }

    final Map<String, String> validatedConfigs = <String, String>{};
    for (final MapEntry<String, Map<String, dynamic>> entry
        in validatedConfigDicts.entries) {
      validatedConfigs[entry.key] = _dumpYaml(entry.value);
    }

    final Map<String, dynamic> writeResult = await writeFiles(
      validatedConfigs,
      toolContext,
      createBackup: backupExisting,
      createDirectories: createDirectories,
    );

    final Map<String, dynamic> filesData =
        (writeResult['files'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in filesData.entries) {
      final String writtenPath = entry.key;
      final Object? writeInfoObj = entry.value;
      if (writeInfoObj is! Map) {
        continue;
      }
      final Map<String, dynamic> writeInfo = Map<String, dynamic>.from(
        writeInfoObj,
      );
      final String canonicalWrittenKey = _canonicalPathKey(
        writtenPath,
        sessionState,
      );
      final String? originalKey = canonicalPathToOriginal[canonicalWrittenKey];

      if (originalKey != null && filesMap.containsKey(originalKey)) {
        final Object? fileEntryObj = filesMap[originalKey];
        if (fileEntryObj is Map<String, dynamic>) {
          fileEntryObj['file_size'] = writeInfo['file_size'] ?? 0;
          fileEntryObj['backup_created'] =
              writeInfo['backup_created'] ?? false;
          fileEntryObj['backup_path'] = writeInfo['backup_path'];
          fileEntryObj['written_file_path'] = writtenPath;
          if (writeInfo['error'] != null) {
            fileEntryObj['success'] = false;
            fileEntryObj['error'] = writeInfo['error'];
            result['success'] = false;
          } else {
            result['successful_writes'] =
                (result['successful_writes'] as int) + 1;
          }
        }
      }
    }
  }

  return result;
}

/// Snake_case alias for [writeConfigFiles].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> write_config_files(
  Map<String, String> configs,
  ToolContext? toolContext, {
  // ignore: non_constant_identifier_names
  bool backup_existing = false,
  // ignore: non_constant_identifier_names
  bool create_directories = true,
}) => writeConfigFiles(
  configs,
  toolContext,
  backupExisting: backup_existing,
  createDirectories: create_directories,
);

Map<String, String> _buildReferenceMap(Map<String, String> renameMap) {
  final Map<String, String> referenceMap = <String, String>{};
  for (final MapEntry<String, String> entry in renameMap.entries) {
    final String original = entry.key;
    final String target = entry.value;
    final String originalNorm = _normalizePathString(original);
    final String targetNorm = _normalizePathString(target);
    final String originalPosix = originalNorm.replaceAll(r'\', '/');
    final String targetPosix = targetNorm.replaceAll(r'\', '/');
    final String originalName = _basename(originalNorm);
    final String targetName = _basename(targetNorm);

    final Map<String, String> candidates = <String, String>{
      original: target,
      originalNorm: targetNorm,
      originalPosix: targetPosix,
      originalName: targetName,
    };
    candidates.putIfAbsent(
      originalNorm.replaceAll(r'\', '/'),
      () => targetNorm.replaceAll(r'\', '/'),
    );

    referenceMap.addAll(candidates);
  }
  return referenceMap;
}

void _updateSubAgentReferences(
  Map<String, dynamic> configDict,
  Map<String, String> referenceMap,
) {
  if (referenceMap.isEmpty) {
    return;
  }

  final Object? subAgents = configDict['sub_agents'];
  if (subAgents is! List) {
    return;
  }

  for (final Object? subAgent in subAgents) {
    if (subAgent is! Map) {
      continue;
    }
    final Object? configPath = subAgent['config_path'];
    if (configPath is! String) {
      continue;
    }

    String? newPath = referenceMap[configPath];
    String? normalized;
    if (newPath == null) {
      normalized = _normalizePathString(configPath);
      newPath = referenceMap[normalized];
    }
    if (newPath == null && normalized != null) {
      newPath = referenceMap[normalized.replaceAll(r'\', '/')];
    }
    if (newPath == null) {
      final String baseName = _basename(configPath);
      newPath = referenceMap[baseName];
    }
    if (newPath != null && newPath.isNotEmpty) {
      subAgent['config_path'] = newPath;
    }
  }
}

String _canonicalPathKey(String path, Map<String, Object?>? sessionState) {
  File resolvedPath;
  try {
    resolvedPath = resolveFilePath(path, sessionState);
  } catch (_) {
    resolvedPath = File(path);
  }

  try {
    final String absPath = resolvedPath.absolute.path;
    return _stripTrailingSlash(Uri.file(absPath).toFilePath());
  } catch (_) {
    return _stripTrailingSlash(resolvedPath.path);
  }
}

Map<String, dynamic> _validateSingleConfig(
  String filePath,
  String configContent, [
  String? projectFolderName,
]) {
  try {
    final String absPath = _stripTrailingSlash(
      File(filePath).absolute.uri.toFilePath(),
    );

    // Step 1: Parse YAML content.
    Object? parsedYaml;
    try {
      parsedYaml = loadYaml(configContent);
    } on YamlException catch (e) {
      return <String, dynamic>{
        'success': false,
        'error_type': 'YAML_PARSE_ERROR',
        'error': 'Invalid YAML syntax: $e',
        'file_path': absPath,
        'validation_step': 'yaml_parsing',
      };
    } catch (e) {
      return <String, dynamic>{
        'success': false,
        'error_type': 'YAML_PARSE_ERROR',
        'error': 'Invalid YAML syntax: $e',
        'file_path': absPath,
        'validation_step': 'yaml_parsing',
      };
    }

    final Object? converted = _yamlToDart(parsedYaml);
    if (converted is! Map<String, dynamic>) {
      return <String, dynamic>{
        'success': false,
        'error_type': 'YAML_STRUCTURE_ERROR',
        'error': 'YAML content must be a dictionary/object',
        'file_path': absPath,
        'validation_step': 'yaml_structure',
      };
    }
    final Map<String, dynamic> configDict = converted;

    // Step 2: Validate against AgentConfig schema.
    final Map<String, dynamic> validationResult = validateAgainstSchema(
      configDict,
    );
    if (validationResult['valid'] != true) {
      final List<Map<String, dynamic>> validationErrors =
          List<Map<String, dynamic>>.from(
            (validationResult['errors'] as List<dynamic>?) ??
                const <Map<String, dynamic>>[],
          );
      return <String, dynamic>{
        'success': false,
        'error_type': 'SCHEMA_VALIDATION_ERROR',
        'error': 'Configuration does not comply with AgentConfig schema',
        'validation_errors': validationErrors,
        'file_path': absPath,
        'validation_step': 'schema_validation',
        'retry_suggestion': _generateRetrySuggestion(validationErrors),
      };
    }

    // Step 2b: Every google.adk.* name the config references must exist in the
    // installed ADK.
    final List<Map<String, String>> symbolErrors = validateAdkSymbols(
      configDict,
    );
    if (symbolErrors.isNotEmpty) {
      return <String, dynamic>{
        'success': false,
        'error_type': 'UNKNOWN_ADK_SYMBOL',
        'error':
            'Configuration references names that do not exist in the'
            ' installed ADK (${adkVersion()})',
        'validation_errors': symbolErrors,
        'file_path': absPath,
        'validation_step': 'symbol_resolution',
        'retry_suggestion':
            'Look each name up with search_adk_source before using it. If a'
            ' name is not in the installed package it does not exist in this'
            ' version, whatever it was called in an earlier release.',
      };
    }

    // Step 3: Additional structural validation.
    final String? nameWarning = _normalizeAgentNameField(configDict, absPath);
    final Map<String, dynamic> structuralValidation = _validateStructure(
      configDict,
      absPath,
    );
    final List<String> warnings = List<String>.from(
      (structuralValidation['warnings'] as List<dynamic>?) ?? const <String>[],
    );
    warnings.addAll(_stripWorkflowAgentFields(configDict));
    if (nameWarning != null && nameWarning.isNotEmpty) {
      warnings.add(nameWarning);
    }
    final Map<String, dynamic>? nameValidationError = _requireValidAgentName(
      configDict,
      absPath,
    );
    if (nameValidationError != null) {
      return nameValidationError;
    }
    final Map<String, dynamic>? modelValidationError = _requireLlmAgentModel(
      configDict,
      absPath,
    );
    if (modelValidationError != null) {
      return modelValidationError;
    }
    final Map<String, dynamic> projectScopeResult =
        _enforceProjectScopedReferences(
          configDict,
          projectFolderName,
          absPath,
        );
    warnings.addAll(
      List<String>.from(
        (projectScopeResult['warnings'] as List<dynamic>?) ?? const <String>[],
      ),
    );
    final Map<String, dynamic>? projectScopeError =
        projectScopeResult['error'] as Map<String, dynamic>?;
    if (projectScopeError != null) {
      return projectScopeError;
    }

    return <String, dynamic>{
      'success': true,
      'file_path': absPath,
      'agent_name': configDict['name'] ?? 'unknown',
      'agent_class': configDict['agent_class'] ?? 'LlmAgent',
      'warnings': warnings,
      parsedConfigKey: configDict,
    };
  } catch (e) {
    return <String, dynamic>{
      'success': false,
      'error_type': 'UNEXPECTED_ERROR',
      'error': 'Unexpected error during validation: $e',
      'file_path': filePath,
    };
  }
}

/// Select the one schema branch that applies to [configDict].
///
/// Dispatches on `agent_class` the way `AgentConfig`'s own discriminator does,
/// and validates against that single branch.
Map<String, dynamic> schemaBranch(
  Map<String, dynamic> schema,
  Map<String, dynamic> configDict,
) {
  final Object? branchesObj = schema['oneOf'] ?? schema['anyOf'];
  if (branchesObj is! List || branchesObj.isEmpty) {
    return _normalizeSchemaDefs(schema);
  }
  final Map<String, dynamic> rawDefs = schema['\$defs'] is Map
      ? Map<String, dynamic>.from(schema['\$defs'] as Map)
      : <String, dynamic>{};
  final Map<String, dynamic> defs = _normalizeDefsMap(rawDefs);
  final String rawAgentClass =
      (configDict['agent_class'] as String?) ?? 'LlmAgent';
  final String agentClass = rawAgentClass.split('.').last;
  final String wanted = _adkAgentClasses.contains(agentClass)
      ? '${agentClass}Config'
      : 'BaseAgentConfig';

  for (final Object? branch in branchesObj) {
    if (branch is Map) {
      final String ref = (branch['\$ref'] as String?) ?? '';
      final String refName = ref.split('/').last;
      if (refName == wanted && defs.containsKey(wanted)) {
        final Map<String, dynamic> targetBranch = Map<String, dynamic>.from(
          defs[wanted] as Map,
        );
        return <String, dynamic>{
          '\$defs': defs,
          ...targetBranch,
        };
      }
    }
  }
  return _normalizeSchemaDefs(schema);
}

/// Snake_case alias for [schemaBranch].
// ignore: non_constant_identifier_names
Map<String, dynamic> schema_branch(
  Map<String, dynamic> schema,
  Map<String, dynamic> configDict,
) => schemaBranch(schema, configDict);

Map<String, dynamic> _normalizeSchemaDefs(Map<String, dynamic> schema) {
  if (schema['\$defs'] is! Map) {
    return schema;
  }
  final Map<String, dynamic> copy = Map<String, dynamic>.from(schema);
  copy['\$defs'] = _normalizeDefsMap(
    Map<String, dynamic>.from(schema['\$defs'] as Map),
  );
  return copy;
}

Map<String, dynamic> _normalizeDefsMap(Map<String, dynamic> defs) {
  final Map<String, dynamic> copy = Map<String, dynamic>.from(defs);
  // In ADK 2.x, CodeConfig only allows `name` (not `args`).
  if (copy['CodeConfig'] is Map) {
    final Map<String, dynamic> codeConfig = Map<String, dynamic>.from(
      copy['CodeConfig'] as Map,
    );
    codeConfig['additionalProperties'] = false;
    codeConfig['properties'] = <String, dynamic>{
      'name': <String, dynamic>{'title': 'Name', 'type': 'string'},
    };
    codeConfig['required'] = <String>['name'];
    copy['CodeConfig'] = codeConfig;
  }
  return copy;
}

/// Whether the runtime config models accept [configDict].
bool runtimeAccepts(Map<String, dynamic> configDict) {
  try {
    final String rawAgentClass =
        (configDict['agent_class'] as String?) ?? 'LlmAgent';
    final String agentClass = rawAgentClass.contains('.')
        ? (rawAgentClass.startsWith('google.adk.agents.')
              ? rawAgentClass.split('.').last
              : rawAgentClass)
        : rawAgentClass;

    // Validate 2.x CodeConfig strictness (only `name` is permitted on callbacks
    // and input_schema/output_schema).
    for (final String cbField in callbackFieldNames) {
      if (configDict.containsKey(cbField) && configDict[cbField] != null) {
        final Object? cbList = configDict[cbField];
        if (cbList is! List) {
          return false;
        }
        for (final Object? entry in cbList) {
          if (!_isValidCodeConfigMap(entry)) {
            return false;
          }
        }
      }
    }
    for (final String schemaField in const <String>[
      'input_schema',
      'output_schema',
    ]) {
      if (configDict.containsKey(schemaField) &&
          configDict[schemaField] != null) {
        if (!_isValidCodeConfigMap(configDict[schemaField])) {
          return false;
        }
      }
    }

    // Validate generate_content_config against GenerateContentConfig schema
    // allowing snake_case keys converted to camelCase.
    final Map<String, dynamic> configForRuntime = Map<String, dynamic>.from(
      configDict,
    );
    if (configForRuntime.containsKey('generate_content_config') &&
        configForRuntime['generate_content_config'] != null) {
      if (agentClass != 'LlmAgent') {
        return false;
      }
      final Object? genConfig = configForRuntime['generate_content_config'];
      if (genConfig is! Map) {
        return false;
      }
      final Object schemaObj = loadAgentConfigSchema(rawFormat: false);
      if (schemaObj is Map<String, dynamic>) {
        final Map<String, dynamic> defs = schemaObj['\$defs'] is Map
            ? Map<String, dynamic>.from(schemaObj['\$defs'] as Map)
            : <String, dynamic>{};
        final Object? genConfigSchema = defs['GenerateContentConfig'];
        if (genConfigSchema is Map<String, dynamic>) {
          final Map<String, dynamic> camelGenConfig = <String, dynamic>{};
          for (final MapEntry<Object?, Object?> entry in genConfig.entries) {
            if (entry.key is! String) {
              return false;
            }
            camelGenConfig[_snakeToCamel(entry.key as String)] = entry.value;
          }
          final _SchemaValidationIssue? issue = _validateSchemaNode(
            camelGenConfig,
            genConfigSchema,
            defs,
            const <String>['generate_content_config'],
          );
          if (issue != null) {
            return false;
          }
        }
      }
      configForRuntime.remove('generate_content_config');
    }

    switch (agentClass) {
      case 'LlmAgent':
        adk_core.LlmAgentConfig.fromJson(configForRuntime);
        return true;
      case 'LoopAgent':
        adk_core.LoopAgentConfig.fromJson(configForRuntime);
        return true;
      case 'ParallelAgent':
        adk_core.ParallelAgentConfig.fromJson(configForRuntime);
        return true;
      case 'SequentialAgent':
        adk_core.SequentialAgentConfig.fromJson(configForRuntime);
        return true;
      case 'BaseAgent':
        adk_core.BaseAgentConfig.fromJson(configForRuntime);
        return true;
      default:
        return false;
    }
  } catch (_) {
    return false;
  }
}

/// Snake_case alias for [runtimeAccepts].
// ignore: non_constant_identifier_names
bool runtime_accepts(Map<String, dynamic> configDict) =>
    runtimeAccepts(configDict);

bool _isValidCodeConfigMap(Object? value) {
  if (value is! Map) {
    return false;
  }
  if (value.length != 1 || !value.containsKey('name')) {
    return false;
  }
  return value['name'] is String;
}

String _snakeToCamel(String key) {
  if (!key.contains('_')) {
    return key;
  }
  final List<String> parts = key.split('_');
  final StringBuffer buffer = StringBuffer(parts.first);
  for (int i = 1; i < parts.length; i++) {
    final String part = parts[i];
    if (part.isEmpty) {
      continue;
    }
    buffer.write(part[0].toUpperCase());
    if (part.length > 1) {
      buffer.write(part.substring(1));
    }
  }
  return buffer.toString();
}

/// Validate [configDict] against the `AgentConfig.json` schema.
Map<String, dynamic> validateAgainstSchema(Map<String, dynamic> configDict) {
  try {
    final Object schema = loadAgentConfigSchema(rawFormat: false);
    if (schema is! Map<String, dynamic>) {
      return <String, dynamic>{
        'valid': false,
        'errors': <Map<String, dynamic>>[
          <String, dynamic>{
            'path': 'root',
            'message': 'AgentConfig schema did not load as an object',
            'invalid_value': null,
            'constraint': 'unknown',
          },
        ],
      };
    }

    final Map<String, dynamic> branch = schemaBranch(schema, configDict);
    final Map<String, dynamic> defs = branch['\$defs'] is Map
        ? Map<String, dynamic>.from(branch['\$defs'] as Map)
        : <String, dynamic>{};

    final _SchemaValidationIssue? issue = _validateSchemaNode(
      configDict,
      branch,
      defs,
      const <String>[],
    );

    if (issue == null) {
      return <String, dynamic>{'valid': true, 'errors': <dynamic>[]};
    }

    if (runtimeAccepts(configDict)) {
      return <String, dynamic>{'valid': true, 'errors': <dynamic>[]};
    }

    final String errorPath = issue.path.isEmpty
        ? 'root'
        : issue.path.join(' -> ');
    return <String, dynamic>{
      'valid': false,
      'errors': <Map<String, dynamic>>[
        <String, dynamic>{
          'path': errorPath,
          'message': issue.message,
          'invalid_value': issue.instance,
          'constraint': issue.constraint,
        },
      ],
    };
  } catch (e) {
    return <String, dynamic>{
      'valid': false,
      'errors': <Map<String, dynamic>>[
        <String, dynamic>{
          'path': 'validation',
          'message': 'Validation error: $e',
          'invalid_value': null,
          'constraint': 'validation_process',
        },
      ],
    };
  }
}

/// Snake_case alias for [validateAgainstSchema].
// ignore: non_constant_identifier_names
Map<String, dynamic> validate_against_schema(
  Map<String, dynamic> configDict,
) => validateAgainstSchema(configDict);

class _SchemaValidationIssue {
  const _SchemaValidationIssue({
    required this.path,
    required this.message,
    required this.instance,
    required this.constraint,
  });

  final List<String> path;
  final String message;
  final Object? instance;
  final Object constraint;
}

_SchemaValidationIssue? _validateSchemaNode(
  Object? instance,
  Map<String, dynamic> schema,
  Map<String, dynamic> defs,
  List<String> path,
) {
  if (schema.containsKey(r'$ref')) {
    final String ref = schema[r'$ref'] as String;
    final String defName = ref.split('/').last;
    final Object? resolved = defs[defName];
    if (resolved is Map<String, dynamic>) {
      return _validateSchemaNode(instance, resolved, defs, path);
    }
    if (resolved is Map) {
      return _validateSchemaNode(
        instance,
        Map<String, dynamic>.from(resolved),
        defs,
        path,
      );
    }
  }

  if (schema.containsKey('const')) {
    final Object? expected = schema['const'];
    if (instance != expected) {
      return _SchemaValidationIssue(
        path: path,
        message: '${jsonEncode(expected)} was expected',
        instance: instance,
        constraint: schema['type'] ?? schema['enum'] ?? 'unknown',
      );
    }
  }

  if (schema.containsKey('enum')) {
    final Object? enumValues = schema['enum'];
    if (enumValues is List && !enumValues.contains(instance)) {
      return _SchemaValidationIssue(
        path: path,
        message: "'$instance' is not one of $enumValues",
        instance: instance,
        constraint: enumValues,
      );
    }
  }

  if (schema.containsKey('anyOf') || schema.containsKey('oneOf')) {
    final bool isOneOf = schema.containsKey('oneOf');
    final List<dynamic> branches =
        (schema['oneOf'] ?? schema['anyOf']) as List<dynamic>;
    int matchCount = 0;
    _SchemaValidationIssue? bestIssue;

    for (final Object? branchRaw in branches) {
      if (branchRaw is! Map) {
        continue;
      }
      final Map<String, dynamic> branchMap = Map<String, dynamic>.from(
        branchRaw,
      );
      final _SchemaValidationIssue? branchIssue = _validateSchemaNode(
        instance,
        branchMap,
        defs,
        path,
      );
      if (branchIssue == null) {
        matchCount++;
        if (!isOneOf) {
          return null;
        }
      } else {
        // Prefer deeper or non-null-branch issues for clearer diagnostics.
        final bool isNullBranch = branchMap['type'] == 'null';
        if (!isNullBranch) {
          if (bestIssue == null ||
              branchIssue.path.length >= bestIssue.path.length) {
            bestIssue = branchIssue;
          }
        } else {
          bestIssue ??= branchIssue;
        }
      }
    }

    if (isOneOf && matchCount == 1) {
      return null;
    }
    if (bestIssue != null) {
      return bestIssue;
    }
    return _SchemaValidationIssue(
      path: path,
      message: '$instance is not valid under any of the given schemas',
      instance: instance,
      constraint: schema['type'] ?? schema['enum'] ?? 'unknown',
    );
  }

  if (schema.containsKey('type')) {
    final Object? expectedType = schema['type'];
    if (!_matchesJsonType(instance, expectedType)) {
      return _SchemaValidationIssue(
        path: path,
        message: '$instance is not of type "$expectedType"',
        instance: instance,
        constraint: expectedType ?? 'unknown',
      );
    }
  }

  if (instance is Map) {
    final Object? requiredList = schema['required'];
    if (requiredList is List) {
      for (final Object? reqKey in requiredList) {
        if (reqKey is String && !instance.containsKey(reqKey)) {
          return _SchemaValidationIssue(
            path: path,
            message: "'$reqKey' is a required property",
            instance: instance,
            constraint: schema['type'] ?? schema['enum'] ?? 'unknown',
          );
        }
      }
    }

    final Map<String, dynamic> properties = schema['properties'] is Map
        ? Map<String, dynamic>.from(schema['properties'] as Map)
        : <String, dynamic>{};
    final Object? additionalProperties = schema['additionalProperties'];

    if (additionalProperties == false) {
      final List<String> unexpectedKeys = <String>[];
      for (final Object? key in instance.keys) {
        final String keyStr = '$key';
        if (!properties.containsKey(keyStr)) {
          unexpectedKeys.add(keyStr);
        }
      }
      if (unexpectedKeys.isNotEmpty) {
        final String formatted = unexpectedKeys.map((String k) => "'$k'").join(
          ', ',
        );
        final String verb = unexpectedKeys.length == 1 ? 'was' : 'were';
        return _SchemaValidationIssue(
          path: path,
          message:
              'Additional properties are not allowed ($formatted $verb unexpected)',
          instance: instance,
          constraint: schema['type'] ?? schema['enum'] ?? 'unknown',
        );
      }
    }

    for (final MapEntry<Object?, Object?> entry in instance.entries) {
      final String key = '${entry.key}';
      final Object? value = entry.value;
      if (properties.containsKey(key)) {
        final Object? propSchema = properties[key];
        if (propSchema is Map) {
          final _SchemaValidationIssue? childIssue = _validateSchemaNode(
            value,
            Map<String, dynamic>.from(propSchema),
            defs,
            <String>[...path, key],
          );
          if (childIssue != null) {
            return childIssue;
          }
        }
      } else if (additionalProperties is Map) {
        final _SchemaValidationIssue? childIssue = _validateSchemaNode(
          value,
          Map<String, dynamic>.from(additionalProperties),
          defs,
          <String>[...path, key],
        );
        if (childIssue != null) {
          return childIssue;
        }
      }
    }
  } else if (instance is List) {
    final Object? itemsSchema = schema['items'];
    if (itemsSchema is Map) {
      final Map<String, dynamic> itemSchemaMap = Map<String, dynamic>.from(
        itemsSchema,
      );
      for (int i = 0; i < instance.length; i++) {
        final _SchemaValidationIssue? itemIssue = _validateSchemaNode(
          instance[i],
          itemSchemaMap,
          defs,
          <String>[...path, '$i'],
        );
        if (itemIssue != null) {
          return itemIssue;
        }
      }
    }
  }

  return null;
}

bool _matchesJsonType(Object? instance, Object? expectedType) {
  if (expectedType is List) {
    return expectedType.any((Object? t) => _matchesJsonType(instance, t));
  }
  switch (expectedType) {
    case 'object':
      return instance is Map;
    case 'array':
      return instance is List;
    case 'string':
      return instance is String;
    case 'boolean':
      return instance is bool;
    case 'integer':
      return instance is int;
    case 'number':
      return instance is num;
    case 'null':
      return instance == null;
    default:
      return true;
  }
}

/// Return the installed ADK version string.
String adkVersion() => adk_core.adkVersion;

/// Snake_case alias for [adkVersion].
// ignore: non_constant_identifier_names
String adk_version() => adkVersion();

/// Collect every unresolvable `google.adk.*` name in [config].
List<Map<String, String>> validateAdkSymbols(Object? config) {
  final List<Map<String, String>> errors = <Map<String, String>>[];
  final Set<String> seen = <String>{};

  void walk(Object? node, String path) {
    if (node is Map) {
      for (final MapEntry<Object?, Object?> entry in node.entries) {
        final String key = '${entry.key}';
        walk(entry.value, path.isEmpty ? key : '$path.$key');
      }
    } else if (node is List) {
      for (int index = 0; index < node.length; index++) {
        walk(node[index], '$path[$index]');
      }
    } else if (node is String) {
      for (final RegExpMatch match in _adkNamePattern.allMatches(node)) {
        final String name = match.group(0)!;
        if (!seen.add(name)) {
          continue;
        }
        if (!adk_symbols.adkSymbolExists(name)) {
          errors.add(<String, String>{
            'path': path.isEmpty ? 'root' : path,
            'message': "'$name' does not exist in the installed ADK",
            'invalid_value': name,
          });
        }
      }
    }
  }

  walk(config, '');
  return errors;
}

/// Snake_case alias for [validateAdkSymbols].
// ignore: non_constant_identifier_names
List<Map<String, String>> validate_adk_symbols(Object? config) =>
    validateAdkSymbols(config);

Map<String, dynamic> _validateStructure(
  Map<String, dynamic> config,
  String filePath,
) {
  final List<String> warnings = <String>[];

  final String instruction = ((config['instruction'] as String?) ?? '').trim();
  if ((config['agent_class'] ?? 'LlmAgent') == 'LlmAgent' &&
      instruction.isEmpty) {
    warnings.add(
      'LlmAgent has empty instruction which may result in poor performance',
    );
  }

  final Object? subAgents = config['sub_agents'];
  if (subAgents is List) {
    final String parentDir = File(filePath).parent.path;
    for (final Object? subAgent in subAgents) {
      if (subAgent is Map && subAgent.containsKey('config_path')) {
        final Object? configPathObj = subAgent['config_path'];
        if (configPathObj is String) {
          if (!configPathObj.startsWith('/')) {
            final File referencedFile = File(
              '$parentDir${Platform.pathSeparator}$configPathObj',
            );
            if (!referencedFile.existsSync()) {
              warnings.add(
                'Referenced sub-agent file may not exist: $configPathObj',
              );
            }
          }
          if (!configPathObj.endsWith('.yaml') &&
              !configPathObj.endsWith('.yml')) {
            warnings.add(
              'Sub-agent config_path should end with .yaml or .yml:'
              ' $configPathObj',
            );
          }
        }
      }
    }
  }

  final Object? tools = config['tools'];
  if (tools is List) {
    final bool hasObjectFormat = tools.any((Object? t) => t is Map);
    final bool hasStringFormat = tools.any((Object? t) => t is String);
    if (hasObjectFormat && hasStringFormat) {
      warnings.add(
        'Mixed tool formats detected - consider using consistent object format',
      );
    }
  }

  return <String, dynamic>{
    'warnings': warnings,
    'has_warnings': warnings.isNotEmpty,
  };
}

String _generateRetrySuggestion(List<Map<String, dynamic>> errors) {
  if (errors.isEmpty) {
    return '';
  }

  final List<String> suggestions = <String>[];
  for (final Map<String, dynamic> error in errors) {
    final String path = (error['path'] as String?) ?? '';
    final String message = (error['message'] as String?) ?? '';
    final String lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('required')) {
      if (message.contains('name')) {
        suggestions.add(
          "Add required 'name' field with a descriptive agent name",
        );
      } else if (message.contains('instruction')) {
        suggestions.add(
          "Add required 'instruction' field with clear agent instructions",
        );
      } else {
        suggestions.add(
          "Add missing required field mentioned in error at '$path'",
        );
      }
    } else if (lowerMessage.contains('enum') ||
        lowerMessage.contains('not one of')) {
      suggestions.add(
        "Use valid enum value for field '$path' - check schema for allowed"
        ' values',
      );
    } else if (lowerMessage.contains('type')) {
      if (message.contains('string')) {
        suggestions.add("Field '$path' should be a string value");
      } else if (message.contains('array')) {
        suggestions.add("Field '$path' should be a list/array");
      } else if (message.contains('object')) {
        suggestions.add("Field '$path' should be an object/dictionary");
      }
    } else if (lowerMessage.contains('additional properties')) {
      suggestions.add("Remove unrecognized field '$path' or check for typos");
    }
  }

  if (suggestions.isEmpty) {
    suggestions.add(
      'Please fix the validation errors and regenerate the configuration',
    );
  }

  return suggestions.take(3).join(' | ');
}

Map<String, dynamic>? _requireLlmAgentModel(
  Map<String, dynamic> config,
  String filePath,
) {
  final Object? agentClass = config['agent_class'] ?? 'LlmAgent';
  if (agentClass != 'LlmAgent') {
    return null;
  }

  final Object? model = config['model'];
  if (model is String && model.trim().isNotEmpty) {
    return null;
  }

  final Object agentName = config['name'] ?? 'unknown';
  return <String, dynamic>{
    'success': false,
    'error_type': 'LLM_AGENT_MODEL_REQUIRED',
    'error':
        "LlmAgent '$agentName' in '$filePath' must define a 'model' "
        'field. LlmAgents cannot rely on implicit defaults.',
    'file_path': filePath,
    'validation_step': 'structure_validation',
    'retry_suggestion':
        "Add a 'model' field with the user-confirmed model "
        "(for example, 'model: gemini-2.5-flash').",
  };
}

Map<String, dynamic>? _requireValidAgentName(
  Map<String, dynamic> config,
  String filePath,
) {
  final Object? agentName = config['name'];
  if (agentName is String && identifierPattern.hasMatch(agentName)) {
    return null;
  }

  return <String, dynamic>{
    'success': false,
    'error_type': 'INVALID_AGENT_NAME',
    'error':
        "Found invalid agent name: `$agentName` in '$filePath'. "
        'Names must start with a letter or underscore and contain only '
        'letters, digits, or underscores.',
    'file_path': filePath,
    'validation_step': 'structure_validation',
    'retry_suggestion':
        'Rename the agent using only letters, digits, and underscores '
        "(e.g., 'Paper_Analyzer').",
  };
}

String? _normalizeAgentNameField(
  Map<String, dynamic> config,
  String filePath,
) {
  final Object? agentName = config['name'];
  if (agentName is! String) {
    return null;
  }

  final (String sanitizedName, String? normalizationWarning) =
      _sanitizeAgentNameForFilename(agentName);
  if (sanitizedName.isEmpty) {
    return normalizationWarning;
  }

  if (sanitizedName != agentName) {
    config['name'] = sanitizedName;
    final String fileName = _basename(filePath);
    return 'Agent name normalized to snake_case in '
        "'$fileName': '$agentName' -> '$sanitizedName'";
  }

  return normalizationWarning;
}

List<String> _stripWorkflowAgentFields(Map<String, dynamic> config) {
  final List<String> warnings = <String>[];
  final Object? agentClass = config['agent_class'];
  if (agentClass is! String || !workflowAgentClasses.contains(agentClass)) {
    return warnings;
  }

  final List<String> removedFields = <String>[];
  for (final String field in const <String>['model', 'tools', 'instruction']) {
    if (config.containsKey(field)) {
      config.remove(field);
      removedFields.add(field);
    }
  }

  if (removedFields.isNotEmpty) {
    final String removedFieldsStr = removedFields.join(', ');
    final Object agentName = config['name'] ?? 'unknown';
    warnings.add(
      'Removed '
      '$removedFieldsStr'
      " from workflow agent '$agentName'. "
      'Workflow agents orchestrate sub-agents and must not define these '
      'fields.',
    );
  }

  return warnings;
}

Map<String, dynamic> _enforceProjectScopedReferences(
  Map<String, dynamic> config,
  String? projectFolderName,
  String filePath,
) {
  if (projectFolderName == null || projectFolderName.isEmpty) {
    return <String, dynamic>{'warnings': <String>[], 'error': null};
  }

  final String prefix = '$projectFolderName.';
  final List<String> warnings = <String>[];
  final List<String> errors = <String>[];

  (String, List<String>, List<String>) normalizeReferenceValue(
    String value,
    String descriptor,
  ) {
    final List<String> localWarnings = <String>[];
    final List<String> localErrors = <String>[];
    String newValue = value;

    if (!value.contains('.')) {
      return (newValue, localWarnings, localErrors);
    }

    if (value.startsWith(prefix)) {
      return (newValue, localWarnings, localErrors);
    }

    if (value.toLowerCase().startsWith(prefix.toLowerCase())) {
      localErrors.add(
        "$descriptor '$value' must use exact-case prefix '$prefix'.",
      );
      return (newValue, localWarnings, localErrors);
    }

    if (value.startsWith('callbacks.') || value.startsWith('tools.')) {
      newValue = '$prefix$value';
      localWarnings.add(
        "$descriptor '$value' updated to '$newValue' to include project "
        'prefix.',
      );
      return (newValue, localWarnings, localErrors);
    }

    if (value.contains('.callbacks.') || value.contains('.tools.')) {
      localErrors.add("$descriptor '$value' must start with '$prefix'.");
    }

    return (newValue, localWarnings, localErrors);
  }

  final Object? tools = config['tools'];
  if (tools is List) {
    for (int index = 0; index < tools.length; index++) {
      final Object? tool = tools[index];
      if (tool is String) {
        final (
          String updated,
          List<String> localWarnings,
          List<String> localErrors,
        ) = normalizeReferenceValue(tool, 'Tool reference');
        if (updated != tool) {
          tools[index] = updated;
        }
        warnings.addAll(localWarnings);
        errors.addAll(localErrors);
      } else if (tool is Map) {
        final Object? name = tool['name'];
        if (name is String) {
          final (
            String updated,
            List<String> localWarnings,
            List<String> localErrors,
          ) = normalizeReferenceValue(name, 'Tool reference');
          if (updated != name) {
            tool['name'] = updated;
          }
          warnings.addAll(localWarnings);
          errors.addAll(localErrors);
        }
      }
    }
  }

  for (final String fieldName in callbackFieldNames) {
    final Object? callbacksField = config[fieldName];
    if (callbacksField == null) {
      continue;
    }

    final List<Object?> items = callbacksField is List
        ? callbacksField
        : <Object?>[callbacksField];

    for (int idx = 0; idx < items.length; idx++) {
      final Object? item = items[idx];
      if (item is String) {
        final (
          String updated,
          List<String> localWarnings,
          List<String> localErrors,
        ) = normalizeReferenceValue(item, '$fieldName entry');
        if (updated != item) {
          if (callbacksField is List) {
            callbacksField[idx] = updated;
          } else {
            config[fieldName] = updated;
          }
        }
        warnings.addAll(localWarnings);
        errors.addAll(localErrors);
      } else if (item is Map) {
        final Object? name = item['name'];
        if (name is String) {
          final (
            String updated,
            List<String> localWarnings,
            List<String> localErrors,
          ) = normalizeReferenceValue(name, '$fieldName entry');
          if (updated != name) {
            item['name'] = updated;
          }
          warnings.addAll(localWarnings);
          errors.addAll(localErrors);
        }
      }
    }
  }

  if (errors.isNotEmpty) {
    return <String, dynamic>{
      'warnings': warnings,
      'error': <String, dynamic>{
        'success': false,
        'error_type': 'PROJECT_REFERENCE_ERROR',
        'error': errors.join(' | '),
        'file_path': filePath,
        'retry_suggestion':
            'Ensure all callback/tool references start with '
            "'$prefix' and that referenced directories contain "
            '__init__.py files (only for the package directories such as '
            "'callbacks/' or 'tools/') so they form importable packages.",
      },
    };
  }

  return <String, dynamic>{'warnings': warnings, 'error': null};
}

(String, bool, String?, String?) _determineTargetFilePath(
  String filePath,
  String? agentName,
) {
  if (agentName == null || agentName.trim().isEmpty) {
    return (filePath, false, null, null);
  }

  final String originalName = _basename(filePath);
  final String stem = _stem(originalName);

  // Preserve root_agent.yaml naming convention for root workflows.
  if (stem == 'root_agent') {
    return (filePath, false, null, null);
  }

  final (String sanitizedName, String? sanitizeWarning) =
      _sanitizeAgentNameForFilename(agentName);
  if (sanitizedName.isEmpty) {
    return (
      filePath,
      false,
      null,
      'Agent name could not be converted into a valid file name; original'
          ' path preserved',
    );
  }

  final String suffix = _extension(originalName).isEmpty
      ? '.yaml'
      : _extension(originalName);
  final String targetName = '$sanitizedName$suffix';
  final String targetPath = _replaceFileName(filePath, targetName);
  final bool renameApplied = originalName != targetName;

  return (targetPath, renameApplied, sanitizedName, sanitizeWarning);
}

String _toSnakeCase(String value) {
  String result = value.trim();
  if (result.isEmpty) {
    return '';
  }

  result = result.replaceAll(RegExp(r'[\s\-]+'), '_');
  result = result.replaceAllMapped(
    RegExp(r'(.)([A-Z][a-z]+)'),
    (Match m) => '${m.group(1)}_${m.group(2)}',
  );
  result = result.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (Match m) => '${m.group(1)}_${m.group(2)}',
  );
  result = result.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  result = result.replaceAll(RegExp(r'_+'), '_');
  result = result.toLowerCase().replaceAll(RegExp(r'^_+|_+$'), '');
  return result;
}

(String, String?) _sanitizeAgentNameForFilename(String agentName) {
  final String trimmedName = agentName.trim();
  if (trimmedName.isEmpty) {
    return ('', 'Agent name is empty after trimming whitespace');
  }

  final String snakeCase = _toSnakeCase(trimmedName);
  if (snakeCase.isEmpty) {
    return ('', 'Agent name is empty after normalization');
  }

  final StringBuffer sanitizedChars = StringBuffer();
  bool replacementsMade = snakeCase != trimmedName;

  for (int i = 0; i < snakeCase.length; i++) {
    final String char = snakeCase[i];
    if (invalidFilenameCharacters.contains(char)) {
      sanitizedChars.write('_');
      replacementsMade = true;
    } else if (RegExp(r'^[A-Za-z0-9_]$').hasMatch(char)) {
      sanitizedChars.write(char);
    } else {
      sanitizedChars.write('_');
      replacementsMade = true;
    }
  }

  String sanitizedName = sanitizedChars
      .toString()
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (sanitizedName.isEmpty) {
    return ('', 'Agent name is empty after removing unsupported characters');
  }

  if (RegExp(r'^[0-9]').hasMatch(sanitizedName)) {
    sanitizedName = '_$sanitizedName';
    replacementsMade = true;
  }

  String? warning;
  if (replacementsMade) {
    warning =
        'Agent name normalized to snake_case: '
        "'$agentName' -> '$sanitizedName'";
  }

  return (sanitizedName, warning);
}

Object? _yamlToDart(Object? node) {
  if (node is YamlMap) {
    final Map<String, dynamic> map = <String, dynamic>{};
    for (final MapEntry<Object?, Object?> entry in node.nodes.entries) {
      final Object? rawKey = entry.key is YamlNode
          ? (entry.key as YamlNode).value
          : entry.key;
      map['$rawKey'] = _yamlToDart(entry.value);
    }
    return map;
  }
  if (node is YamlList) {
    return node.nodes.map<Object?>((YamlNode item) => _yamlToDart(item)).toList();
  }
  if (node is YamlScalar) {
    return node.value;
  }
  if (node is Map) {
    return node.map<String, dynamic>(
      (Object? k, Object? v) => MapEntry<String, dynamic>('$k', _yamlToDart(v)),
    );
  }
  if (node is List) {
    return node.map<Object?>(_yamlToDart).toList();
  }
  return node;
}

String _dumpYaml(Object? value, [int indent = 0]) {
  final StringBuffer buffer = StringBuffer();
  _writeYamlNode(buffer, value, indent, topLevel: true);
  final String output = buffer.toString();
  return output.endsWith('\n') ? output : '$output\n';
}

void _writeYamlNode(
  StringBuffer buffer,
  Object? value,
  int indent, {
  bool topLevel = false,
}) {
  final String pad = ' ' * indent;
  if (value is Map) {
    if (value.isEmpty) {
      buffer.writeln('{}');
      return;
    }
    int index = 0;
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final String key = _formatYamlScalar('${entry.key}', isKey: true);
      final Object? val = entry.value;
      if (index > 0 || !topLevel) {
        buffer.write(pad);
      }
      if (val is Map) {
        if (val.isEmpty) {
          buffer.writeln('$key: {}');
        } else {
          buffer.writeln('$key:');
          _writeYamlNode(buffer, val, indent + 2);
        }
      } else if (val is List) {
        if (val.isEmpty) {
          buffer.writeln('$key: []');
        } else {
          buffer.writeln('$key:');
          _writeYamlList(buffer, val, indent);
        }
      } else {
        buffer.writeln('$key: ${_formatYamlScalar(val)}');
      }
      index++;
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      buffer.writeln('[]');
      return;
    }
    _writeYamlList(buffer, value, indent);
    return;
  }
  buffer.writeln('$pad${_formatYamlScalar(value)}');
}

void _writeYamlList(StringBuffer buffer, List<Object?> list, int indent) {
  final String pad = ' ' * indent;
  for (final Object? item in list) {
    if (item is Map) {
      if (item.isEmpty) {
        buffer.writeln('$pad- {}');
      } else {
        bool first = true;
        for (final MapEntry<Object?, Object?> entry in item.entries) {
          final String key = _formatYamlScalar('${entry.key}', isKey: true);
          final Object? val = entry.value;
          final String prefix = first ? '$pad- ' : '$pad  ';
          first = false;
          if (val is Map) {
            if (val.isEmpty) {
              buffer.writeln('$prefix$key: {}');
            } else {
              buffer.writeln('$prefix$key:');
              _writeYamlNode(buffer, val, indent + 4);
            }
          } else if (val is List) {
            if (val.isEmpty) {
              buffer.writeln('$prefix$key: []');
            } else {
              buffer.writeln('$prefix$key:');
              _writeYamlList(buffer, val, indent + 2);
            }
          } else {
            buffer.writeln('$prefix$key: ${_formatYamlScalar(val)}');
          }
        }
      }
    } else if (item is List) {
      buffer.writeln('$pad-');
      _writeYamlList(buffer, item, indent + 2);
    } else {
      buffer.writeln('$pad- ${_formatYamlScalar(item)}');
    }
  }
}

String _formatYamlScalar(Object? value, {bool isKey = false}) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return '$value';
  }
  final String str = '$value';
  if (str.isEmpty) {
    return "''";
  }
  if (isKey && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(str)) {
    return str;
  }
  final bool needsQuotes =
      str.contains('\n') ||
      str.contains(':') ||
      str.contains('#') ||
      str.startsWith(' ') ||
      str.endsWith(' ') ||
      str.startsWith("'") ||
      str.startsWith('"') ||
      str.startsWith('{') ||
      str.startsWith('[') ||
      str.startsWith('*') ||
      str.startsWith('&') ||
      str.startsWith('!') ||
      str.startsWith('|') ||
      str.startsWith('>') ||
      str.startsWith('%') ||
      str.startsWith('@') ||
      str.startsWith('`') ||
      const <String>{
        'true',
        'false',
        'null',
        'yes',
        'no',
        'on',
        'off',
        '~',
      }.contains(str.toLowerCase());
  if (!needsQuotes) {
    return str;
  }
  return jsonEncode(str);
}

String _stripTrailingSlash(String path) {
  if (path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

String _normalizePathString(String path) {
  final String trimmed = _stripTrailingSlash(path.trim());
  if (trimmed.isEmpty) {
    return '.';
  }
  return trimmed;
}

String _basename(String path) {
  final String normalized = _stripTrailingSlash(path).replaceAll(r'\', '/');
  final int idx = normalized.lastIndexOf('/');
  return idx == -1 ? normalized : normalized.substring(idx + 1);
}

String _stem(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot <= 0) {
    return fileName;
  }
  return fileName.substring(0, dot);
}

String _extension(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot <= 0) {
    return '';
  }
  return fileName.substring(dot);
}

String _replaceFileName(String path, String newFileName) {
  final int lastForward = path.lastIndexOf('/');
  final int lastBackward = path.lastIndexOf(r'\');
  final int splitIndex = lastForward > lastBackward
      ? lastForward
      : lastBackward;
  if (splitIndex == -1) {
    return newFileName;
  }
  return '${path.substring(0, splitIndex + 1)}$newFileName';
}
