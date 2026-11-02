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

/// Agent factory for creating Agent Builder Assistant with embedded schema.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:adk_dart/adk_dart.dart';

import 'tools/cleanup_unused_files.dart';
import 'tools/delete_files.dart';
import 'tools/explore_project.dart';
import 'tools/read_config_files.dart';
import 'tools/read_files.dart';
import 'tools/search_adk_source.dart';
import 'tools/write_config_files.dart';
import 'tools/write_files.dart';
import 'utils/__init__.dart';

/// Agent Builder Assistant factory for creating configured instances.
class AgentBuilderAssistant {
  /// Core schema `$defs` names surfaced in the embedded reference.
  static const List<String> coreSchemaDefNames = <String>[
    'LlmAgentConfig',
    'LoopAgentConfig',
    'ParallelAgentConfig',
    'SequentialAgentConfig',
    'BaseAgentConfig',
    'AgentRefConfig',
    'CodeConfig',
    'ToolArgsConfig',
    'google__adk__tools__tool_configs__ToolConfig',
  ];

  /// Alias for [coreSchemaDefNames] matching the Python constant name.
  // ignore: constant_identifier_names
  static const List<String> CORE_SCHEMA_DEF_NAMES = coreSchemaDefNames;

  /// Generation config fields surfaced in the embedded reference.
  static const List<String> genConfigFields = <String>[
    'temperature',
    'topP',
    'topK',
    'maxOutputTokens',
  ];

  /// Alias for [genConfigFields] matching the Python constant name.
  // ignore: constant_identifier_names
  static const List<String> GEN_CONFIG_FIELDS = genConfigFields;

  /// Create Agent Builder Assistant with embedded ADK `AgentConfig` schema.
  ///
  /// [model] specifies the model name or [BaseLlm] instance to use (defaults to
  /// `'gemini-2.5-pro'`).
  /// [workingDirectory] specifies an optional working directory for path
  /// resolution.
  static LlmAgent createAgent({
    Object model = 'gemini-2.5-pro',
    String? workingDirectory,
    // ignore: non_constant_identifier_names
    String? working_directory,
  }) {
    final String? resolvedWorkingDirectory =
        workingDirectory ?? working_directory;
    // Ignore unused parameter when path resolution uses session state.
    final _ = resolvedWorkingDirectory;

    final String Function(ReadonlyContext) instruction =
        loadInstructionWithSchema(model);

    final List<Object> customTools = <Object>[
      FunctionTool(
        func: readConfigFiles,
        name: 'read_config_files',
        description:
            'Read and parse multiple YAML configuration files with '
            'comprehensive error handling.',
      ),
      FunctionTool(
        func: writeConfigFiles,
        name: 'write_config_files',
        description:
            'Write multiple YAML configurations with comprehensive '
            'validation-before-write.',
      ),
      FunctionTool(
        func: exploreProject,
        name: 'explore_project',
        description:
            'Explore project structure and analyze existing ADK '
            'configurations.',
      ),
      FunctionTool(
        func: readFiles,
        name: 'read_files',
        description:
            'Read multiple general project files with metadata and content '
            'type detection.',
      ),
      FunctionTool(
        func: writeFiles,
        name: 'write_files',
        description:
            'Write multiple general project files with directory creation and '
            'backup options.',
      ),
      FunctionTool(
        func: deleteFiles,
        name: 'delete_files',
        description:
            'Delete multiple files within the project with safety validation.',
      ),
      FunctionTool(
        func: cleanupUnusedFiles,
        name: 'cleanup_unused_files',
        description:
            'Identify and optionally delete unused YAML config files in the '
            'project.',
      ),
      FunctionTool(
        func: searchAdkSource,
        name: 'search_adk_source',
        description:
            'Search ADK source code using regex patterns to discover classes '
            'and tools.',
      ),
    ];

    return LlmAgent(
      name: 'agent_builder_assistant',
      description:
          'Intelligent assistant for building ADK multi-agent systems '
          'using YAML configurations',
      instruction: instruction,
      model: model,
      tools: customTools,
      generateContentConfig: GenerateContentConfig(
        maxOutputTokens: 8192,
      ),
    );
  }

  /// Snake_case alias for [createAgent].
  // ignore: non_constant_identifier_names
  static LlmAgent create_agent({
    Object model = 'gemini-2.5-pro',
    // ignore: non_constant_identifier_names
    String? working_directory,
    String? workingDirectory,
  }) => createAgent(
    model: model,
    workingDirectory: workingDirectory ?? working_directory,
  );

  /// Load ADK `AgentConfig.json` schema content and format for YAML embedding.
  static String loadSchema() {
    final Object schemaObj = loadAgentConfigSchema(rawFormat: false);
    final Map<String, dynamic> schemaDict = schemaObj is Map<String, dynamic>
        ? schemaObj
        : <String, dynamic>{};
    final Map<String, dynamic> subset = extractCoreSchema(schemaDict);
    return buildSchemaReference(subset);
  }

  /// Snake_case alias for [loadSchema].
  // ignore: non_constant_identifier_names
  static String load_schema() => loadSchema();

  /// Create compact `AgentConfig` reference text for prompt embedding.
  static String buildSchemaReference(Map<String, dynamic> schema) {
    final Map<String, dynamic> defs = schema['\$defs'] is Map
        ? Map<String, dynamic>.from(schema['\$defs'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> topLevelFields = schema['properties'] is Map
        ? Map<String, dynamic>.from(schema['properties'] as Map)
        : <String, dynamic>{};
    final List<String> lines = <String>[];

    void add([String text = '', int indent = 0]) {
      if (text.isEmpty) {
        lines.add('');
        return;
      }
      final String indentStr = ' ' * indent;
      lines.addAll(_wrapText(text, width: 78, indent: indentStr));
    }

    add('ADK AgentConfig quick reference');
    add('--------------------------------');

    add();
    add('LlmAgent (agent_class: LlmAgent)');
    add(
      'Required fields: name, instruction. ADK best practice is to always set'
      ' model explicitly.',
      2,
    );
    add('Optional fields:', 2);
    add('agent_class: defaults to LlmAgent; keep for clarity.', 4);
    add('description: short summary string.', 4);
    add('sub_agents: list of AgentRef entries (see below).', 4);
    add(
      'before_agent_callbacks / after_agent_callbacks: list of CodeConfig '
      'entries that run before or after the agent loop.',
      4,
    );
    add('model: string model id (required in practice).', 4);
    add(
      'disallow_transfer_to_parent / disallow_transfer_to_peers: booleans to '
      'restrict automatic transfer.',
      4,
    );
    add(
      'input_schema / output_schema: JSON schema objects to validate inputs '
      'and outputs.',
      4,
    );
    add('output_key: name to store agent output in session context.', 4);
    add(
      'include_contents: bool; include tool/LLM contents in response.',
      4,
    );
    add('tools: list of ToolConfig entries (see below).', 4);
    add(
      'before_model_callbacks / after_model_callbacks: list of CodeConfig '
      'entries around LLM calls.',
      4,
    );
    add(
      'before_tool_callbacks / after_tool_callbacks: list of CodeConfig '
      'entries around tool calls.',
      4,
    );
    add(
      'generate_content_config: passes directly to google.genai '
      'GenerateContentConfig (supporting temperature, topP, topK, '
      'maxOutputTokens, safetySettings, responseSchema, routingConfig,'
      ' etc.).',
      4,
    );

    add();
    add('Workflow agents (LoopAgent, ParallelAgent, SequentialAgent)');
    add(
      'Share BaseAgent fields: agent_class, name, description, sub_agents, '
      'before/after_agent_callbacks. Never declare model, instruction, or '
      'tools on workflow orchestrators.',
      2,
    );
    add(
      'LoopAgent adds max_iterations (int) controlling iteration cap.',
      2,
    );

    add();
    add('AgentRef');
    add(
      'Used inside sub_agents lists. Provide either config_path (string path '
      'to another YAML file) or code (dotted Python reference) to locate the '
      'sub-agent definition.',
      2,
    );

    add();
    add('ToolConfig');
    add(
      'Items inside tools arrays. Required field name (string). For built-in '
      'tools use the exported short name, for custom tools use the dotted '
      'module path.',
      2,
    );
    add(
      'args: optional ToolArgsConfig of free key-value pairs forwarded to'
      " the tool's from_config().",
      2,
    );

    add();
    add('CodeConfig');
    add(
      'References Python code by fully qualified name (e.g.'
      ' my_library.my_module.my_function). The referenced object must'
      ' already be constructed in Python; YAML cannot pass constructor'
      ' arguments.',
      2,
    );

    add();
    add('GenerateContentConfig highlights');
    add(
      'Controls LLM generation behavior. Common fields: maxOutputTokens, '
      'temperature, topP, topK, candidateCount, responseMimeType, '
      'responseSchema/responseJsonSchema, automaticFunctionCalling, '
      'safetySettings, routingConfig; see Vertex AI GenAI docs for full '
      'semantics.',
      2,
    );

    add();
    add(
      'All other schema definitions in AgentConfig.json remain available but '
      'are rarely needed for typical agent setups. Refer to the source file '
      'for exhaustive field descriptions when implementing advanced configs.',
    );

    if (topLevelFields.isNotEmpty) {
      add();
      add('Top-level AgentConfig fields (from schema)');
      final List<String> sortedFields = topLevelFields.keys.toList()..sort();
      for (final String fieldName in sortedFields) {
        final Object? fieldInfo = topLevelFields[fieldName];
        final String description = fieldInfo is Map
            ? ((fieldInfo['description'] as String?) ?? '')
            : '';
        if (description.isNotEmpty) {
          add('$fieldName: $description', 2);
        } else {
          add(fieldName, 2);
        }
      }
    }

    if (defs.isNotEmpty) {
      add();
      add('Additional schema definitions');
      final List<String> sortedDefs = defs.keys.toList()..sort();
      for (final String defName in sortedDefs) {
        final Object? defInfo = defs[defName];
        final String description = defInfo is Map
            ? ((defInfo['description'] as String?) ?? '')
            : '';
        if (description.isNotEmpty) {
          add('$defName: $description', 2);
        } else {
          add(defName, 2);
        }
      }
    }

    return '```text\n${lines.join('\n')}\n```';
  }

  /// Snake_case alias for [buildSchemaReference].
  // ignore: non_constant_identifier_names
  static String build_schema_reference(Map<String, dynamic> schema) =>
      buildSchemaReference(schema);

  /// Return only the schema nodes surfaced by the assistant.
  static Map<String, dynamic> extractCoreSchema(Map<String, dynamic> schema) {
    final Map<String, dynamic> defs = schema['\$defs'] is Map
        ? Map<String, dynamic>.from(schema['\$defs'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> filteredDefs = <String, dynamic>{};
    for (final String key in coreSchemaDefNames) {
      if (defs.containsKey(key)) {
        filteredDefs[key] = defs[key];
      }
    }

    final Object? genConfigObj = defs['GenerateContentConfig'];
    if (genConfigObj is Map && genConfigObj.isNotEmpty) {
      final Map<String, dynamic> genConfig = Map<String, dynamic>.from(
        genConfigObj,
      );
      final Map<String, dynamic> properties = genConfig['properties'] is Map
          ? Map<String, dynamic>.from(genConfig['properties'] as Map)
          : <String, dynamic>{};
      filteredDefs['GenerateContentConfig'] = <String, dynamic>{
        'title': genConfig['title'] ?? 'GenerateContentConfig',
        'description':
            'Common LLM generation knobs exposed by the Agent Builder.',
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, dynamic>{
          for (final String key in genConfigFields)
            if (properties.containsKey(key)) key: properties[key],
        },
      };
    }

    return <String, dynamic>{
      '\$defs': filteredDefs,
      'properties': schema['properties'] is Map
          ? Map<String, dynamic>.from(schema['properties'] as Map)
          : <String, dynamic>{},
    };
  }

  /// Snake_case alias for [extractCoreSchema].
  // ignore: non_constant_identifier_names
  static Map<String, dynamic> extract_core_schema(
    Map<String, dynamic> schema,
  ) => extractCoreSchema(schema);

  /// Load instruction template and embed ADK `AgentConfig` schema content.
  static String Function(ReadonlyContext) loadInstructionWithSchema(
    Object model,
  ) {
    final String instructionTemplate = loadEmbeddedSchemaInstructionTemplate();
    final String schemaContent = loadSchema();
    final String modelStr = _resolveModelName(model);

    return (ReadonlyContext context) {
      final String projectFolderName = extractProjectFolderName(context);
      return _formatInstructionTemplate(
        instructionTemplate,
        schemaContent: schemaContent,
        defaultModel: modelStr,
        projectFolderName: projectFolderName,
      );
    };
  }

  /// Snake_case alias for [loadInstructionWithSchema].
  // ignore: non_constant_identifier_names
  static String Function(ReadonlyContext) load_instruction_with_schema(
    Object model,
  ) => loadInstructionWithSchema(model);

  /// Extract project folder name from session state using [resolveFilePath].
  static String extractProjectFolderName(ReadonlyContext context) {
    Map<String, Object?>? sessionState;
    try {
      sessionState = context.invocationContext.session.state;
    } catch (_) {
      try {
        sessionState = Map<String, Object?>.from(context.state);
      } catch (_) {
        sessionState = null;
      }
    }

    final File resolvedPath = resolveFilePath('.', sessionState);
    final String normalized = resolvedPath.path
        .replaceAll(RegExp(r'[/\\]+$'), '')
        .replaceAll(r'\', '/');
    final int lastSlash = normalized.lastIndexOf('/');
    String projectFolderName = lastSlash == -1
        ? normalized
        : normalized.substring(lastSlash + 1);
    if (projectFolderName.isEmpty || projectFolderName == '.') {
      projectFolderName = 'project';
    }
    return projectFolderName;
  }

  /// Snake_case alias for [extractProjectFolderName].
  // ignore: non_constant_identifier_names
  static String extract_project_folder_name(ReadonlyContext context) =>
      extractProjectFolderName(context);

  /// Load instruction template for embedded ADK `AgentConfig` schema mode.
  static String loadEmbeddedSchemaInstructionTemplate([File? templateFile]) {
    final File resolvedFile = templateFile ?? _resolveInstructionTemplateFile();
    if (!resolvedFile.existsSync()) {
      throw FileSystemException(
        'Instruction template not found at ${resolvedFile.path}',
        resolvedFile.path,
      );
    }
    return resolvedFile.readAsStringSync();
  }

  /// Snake_case alias for [loadEmbeddedSchemaInstructionTemplate].
  // ignore: non_constant_identifier_names
  static String load_embedded_schema_instruction_template([
    File? templateFile,
  ]) => loadEmbeddedSchemaInstructionTemplate(templateFile);

  static File _resolveInstructionTemplateFile() {
    try {
      final Uri? resolvedUri = Isolate.resolvePackageUriSync(
        Uri.parse(
          'package:adk/src/cli/built_in_agents/adk_agent_builder_assistant.dart',
        ),
      );
      if (resolvedUri != null && resolvedUri.scheme == 'file') {
        final File candidate = File(
          '${File.fromUri(resolvedUri).parent.path}${Platform.pathSeparator}instruction_embedded.template',
        );
        if (candidate.existsSync()) {
          return candidate;
        }
      }
    } catch (_) {
      // Fallback to directory search below.
    }

    Directory dir = Directory.current.absolute;
    for (int i = 0; i < 8; i++) {
      final List<String> relativeCandidates = <String>[
        'lib/src/cli/built_in_agents/instruction_embedded.template',
        'packages/adk/lib/src/cli/built_in_agents/instruction_embedded.template',
        'adk_dart/packages/adk/lib/src/cli/built_in_agents/instruction_embedded.template',
      ];
      for (final String rel in relativeCandidates) {
        final File f = File('${dir.path}${Platform.pathSeparator}$rel');
        if (f.existsSync()) {
          return f;
        }
      }
      final Directory parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }

    return File('instruction_embedded.template');
  }

  static String _resolveModelName(Object model) {
    if (model is String) {
      return model;
    }
    if (model is BaseLlm) {
      return model.model;
    }
    try {
      final dynamic dyn = model;
      final Object? modelName = dyn.model_name ?? dyn.modelName ?? dyn.model;
      if (modelName is String && modelName.isNotEmpty) {
        return modelName;
      }
    } catch (_) {
      // Ignore dynamic lookup errors.
    }
    return '$model';
  }

  static String _formatInstructionTemplate(
    String template, {
    required String schemaContent,
    required String defaultModel,
    required String projectFolderName,
  }) {
    const String leftBracePlaceholder = '\x00LEFT_BRACE\x00';
    const String rightBracePlaceholder = '\x00RIGHT_BRACE\x00';
    return template
        .replaceAll('{{', leftBracePlaceholder)
        .replaceAll('}}', rightBracePlaceholder)
        .replaceAll('{schema_content}', schemaContent)
        .replaceAll('{default_model}', defaultModel)
        .replaceAll('{project_folder_name}', projectFolderName)
        .replaceAll(leftBracePlaceholder, '{')
        .replaceAll(rightBracePlaceholder, '}');
  }

  static List<String> _wrapText(
    String text, {
    required int width,
    required String indent,
  }) {
    final List<String> words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return <String>[''];
    }

    final List<String> lines = <String>[];
    StringBuffer currentLine = StringBuffer(indent)..write(words.first);

    for (int i = 1; i < words.length; i++) {
      final String word = words[i];
      if (currentLine.length + 1 + word.length <= width) {
        currentLine
          ..write(' ')
          ..write(word);
      } else {
        lines.add(currentLine.toString());
        currentLine = StringBuffer(indent)..write(word);
      }
    }
    lines.add(currentLine.toString());
    return lines;
  }
}

/// Expose a module-level [rootAgent] so the AgentLoader can find this built-in
/// assistant when requested as `__adk_agent_builder_assistant`.
final LlmAgent rootAgent = AgentBuilderAssistant.createAgent();

/// Snake_case alias for [rootAgent].
// ignore: non_constant_identifier_names
final LlmAgent root_agent = rootAgent;
