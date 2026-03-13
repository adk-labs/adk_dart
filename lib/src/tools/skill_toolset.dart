/// Toolset that exposes local skill loading and execution tools.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import '../agents/readonly_context.dart';
import '../code_executors/base_code_executor.dart';
import '../code_executors/code_execution_utils.dart';
import '../models/llm_request.dart';
import '../skills/skill_runtime.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'base_toolset.dart';
import 'tool_context.dart';

const int _defaultScriptTimeout = 300;
const int _maxSkillPayloadBytes = 16 * 1024 * 1024;
const String _binaryFileDetectedMsg =
    'Binary file detected. The runtime will attach it to the next model request.';

/// Default system instruction injected when skill tools are enabled.
const String defaultSkillSystemInstruction =
    """You can use specialized 'skills' to help you with complex tasks. You MUST use the skill tools to interact with these skills.

Skills are folders of instructions and resources that extend your capabilities for specialized tasks. Each skill folder contains:
- **SKILL.md** (required): The main instruction file with skill metadata and detailed markdown instructions.
- **references/** (Optional): Additional documentation or examples for skill usage.
- **assets/** (Optional): Templates, scripts or other resources used by the skill.
- **scripts/** (Optional): Executable scripts that can be run via bash.

This is very important:

1. If a skill seems relevant to the current user query, you MUST use the `load_skill` tool with `name="<SKILL_NAME>"` to read its full instructions before proceeding.
2. Once you have read the instructions, follow them exactly as documented before replying to the user. For example, If the instruction lists multiple steps, please make sure you complete all of them in order.
3. The `load_skill_resource` tool is for viewing files within a skill's directory (e.g., `references/*`, `assets/*`, `scripts/*`). Do NOT use other tools to access these files.
""";

const String _runSkillScriptInstruction =
    "4. Use `run_skill_script` to run scripts from a skill's `scripts/` directory. Use `load_skill_resource` to view script content first if needed.";

class _ListSkillsTool extends BaseTool {
  _ListSkillsTool(this._toolset)
    : super(
        name: 'list_skills',
        description:
            'Lists all available skills with their names and descriptions.',
      );

  final SkillToolset _toolset;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return formatSkillsAsXml(_toolset._listSkills());
  }
}

class _LoadSkillTool extends BaseTool {
  _LoadSkillTool(this._toolset)
    : super(
        name: 'load_skill',
        description: 'Loads the SKILL.md instructions for a given skill.',
      );

  final SkillToolset _toolset;

  String _activationStateKey(String agentName) {
    return '_adk_activated_skill_$agentName';
  }

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{
            'type': 'string',
            'description': 'The name of the skill to load.',
          },
        },
        'required': <String>['name'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? skillName = args['name'];
    if (skillName is! String || skillName.trim().isEmpty) {
      return <String, Object?>{
        'error': 'Skill name is required.',
        'error_code': 'MISSING_SKILL_NAME',
      };
    }

    final Skill? skill = _toolset._getSkill(skillName.trim());
    if (skill == null) {
      return <String, Object?>{
        'error': "Skill '${skillName.trim()}' not found.",
        'error_code': 'SKILL_NOT_FOUND',
      };
    }

    final String stateKey = _activationStateKey(toolContext.agentName);
    final List<Object?> activated = List<Object?>.from(
      toolContext.state[stateKey] as List? ?? const <Object?>[],
    );
    final List<String> activatedSkillNames = activated
        .whereType<String>()
        .toList(growable: true);
    if (!activatedSkillNames.contains(skill.name)) {
      activatedSkillNames.add(skill.name);
      toolContext.state[stateKey] = activatedSkillNames;
    }

    return <String, Object?>{
      'skill_name': skillName.trim(),
      'instructions': skill.instructions,
      'frontmatter': skill.frontmatter.toMap(),
    };
  }
}

class _LoadSkillResourceTool extends BaseTool {
  _LoadSkillResourceTool(this._toolset)
    : super(
        name: 'load_skill_resource',
        description:
            'Loads a resource file (from references/, assets/, or scripts/) from within a skill.',
      );

  final SkillToolset _toolset;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'skill_name': <String, Object?>{
            'type': 'string',
            'description': 'The name of the skill.',
          },
          'path': <String, Object?>{
            'type': 'string',
            'description':
                "The relative path to the resource (e.g., 'references/my_doc.md', 'assets/template.txt', or 'scripts/setup.sh').",
          },
        },
        'required': <String>['skill_name', 'path'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawSkillName = args['skill_name'];
    final Object? rawPath = args['path'];

    if (rawSkillName is! String || rawSkillName.trim().isEmpty) {
      return <String, Object?>{
        'error': 'Skill name is required.',
        'error_code': 'MISSING_SKILL_NAME',
      };
    }
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return <String, Object?>{
        'error': 'Resource path is required.',
        'error_code': 'MISSING_RESOURCE_PATH',
      };
    }

    final String skillName = rawSkillName.trim();
    final String resourcePath = rawPath.trim();
    final Skill? skill = _toolset._getSkill(skillName);
    if (skill == null) {
      return <String, Object?>{
        'error': "Skill '$skillName' not found.",
        'error_code': 'SKILL_NOT_FOUND',
      };
    }

    Object? content;
    if (resourcePath.startsWith('references/')) {
      final String referenceName = resourcePath.substring('references/'.length);
      content = skill.resources.getReferenceData(referenceName);
    } else if (resourcePath.startsWith('assets/')) {
      final String assetName = resourcePath.substring('assets/'.length);
      content = skill.resources.getAssetData(assetName);
    } else if (resourcePath.startsWith('scripts/')) {
      final String scriptName = resourcePath.substring('scripts/'.length);
      final Script? script = skill.resources.getScript(scriptName);
      if (script != null) {
        content = script.src;
      }
    } else {
      return <String, Object?>{
        'error':
            "Path must start with 'references/', 'assets/', or 'scripts/'.",
        'error_code': 'INVALID_RESOURCE_PATH',
      };
    }

    if (content == null) {
      return <String, Object?>{
        'error': "Resource '$resourcePath' not found in skill '$skillName'.",
        'error_code': 'RESOURCE_NOT_FOUND',
      };
    }

    if (content is List<int>) {
      return <String, Object?>{
        'skill_name': skillName,
        'path': resourcePath,
        'status': _binaryFileDetectedMsg,
      };
    }

    return <String, Object?>{
      'skill_name': skillName,
      'path': resourcePath,
      'content': content,
    };
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );

    if (llmRequest.contents.isEmpty) {
      return;
    }

    for (final Part part in llmRequest.contents.last.parts) {
      final FunctionResponse? functionResponse = part.functionResponse;
      if (functionResponse == null || functionResponse.name != name) {
        continue;
      }
      final Map<String, dynamic> response = functionResponse.response;
      if (response['status'] != _binaryFileDetectedMsg) {
        continue;
      }

      final String? skillName = response['skill_name'] as String?;
      final String? resourcePath = response['path'] as String?;
      if (skillName == null || resourcePath == null) {
        continue;
      }

      final Skill? skill = _toolset._getSkill(skillName);
      if (skill == null) {
        continue;
      }

      List<int>? bytes;
      if (resourcePath.startsWith('references/')) {
        bytes = skill.resources.getReferenceBytes(
          resourcePath.substring('references/'.length),
        );
      } else if (resourcePath.startsWith('assets/')) {
        bytes = skill.resources.getAssetBytes(
          resourcePath.substring('assets/'.length),
        );
      }
      if (bytes == null) {
        continue;
      }

      llmRequest.contents.add(
        Content(
          role: 'user',
          parts: <Part>[
            Part.text("The content of binary file '$resourcePath' is:"),
            Part.fromInlineData(
              mimeType: _guessMimeType(resourcePath),
              data: bytes,
            ),
          ],
        ),
      );
    }
  }
}

class _SkillScriptCodeExecutor {
  _SkillScriptCodeExecutor({
    required BaseCodeExecutor baseExecutor,
    required int scriptTimeout,
  }) : _baseExecutor = baseExecutor,
       _scriptTimeout = scriptTimeout;

  final BaseCodeExecutor _baseExecutor;
  final int _scriptTimeout;

  Future<Map<String, Object?>> executeScript({
    required ToolContext toolContext,
    required Skill skill,
    required String scriptPath,
    required Map<String, Object?> scriptArgs,
  }) async {
    final String? code = _buildWrapperCode(
      skill: skill,
      scriptPath: scriptPath,
      scriptArgs: scriptArgs,
    );
    if (code == null) {
      final String extMsg = scriptPath.contains('.')
          ? "'.${scriptPath.split('.').last}'"
          : '(no extension)';
      return <String, Object?>{
        'error':
            'Unsupported script type $extMsg. Supported types: .py, .sh, .bash',
        'error_code': 'UNSUPPORTED_SCRIPT_TYPE',
      };
    }

    try {
      final CodeExecutionResult result = await _baseExecutor.executeCode(
        toolContext.invocationContext,
        CodeExecutionInput(code: code),
      );

      String stdout = result.stdout;
      String stderr = result.stderr;
      int returnCode = result.exitCode;
      final String loweredPath = scriptPath.toLowerCase();
      final bool isShell =
          loweredPath.endsWith('.sh') || loweredPath.endsWith('.bash');

      if (isShell && stdout.isNotEmpty) {
        try {
          final Object? parsed = jsonDecode(stdout);
          if (parsed is Map && parsed['__shell_result__'] == true) {
            stdout = '${parsed['stdout'] ?? ''}';
            stderr = '${parsed['stderr'] ?? ''}';
            returnCode = _toInt(parsed['returncode']) ?? returnCode;
            if (returnCode != 0 && stderr.isEmpty) {
              stderr = 'Exit code $returnCode';
            }
          }
        } catch (_) {
          // Fall back to original stdout/stderr payload.
        }
      }

      String status = 'success';
      if (returnCode != 0) {
        status = 'error';
      } else if (stderr.isNotEmpty && stdout.isEmpty) {
        status = 'error';
      } else if (stderr.isNotEmpty) {
        status = 'warning';
      }

      return <String, Object?>{
        'skill_name': skill.name,
        'script_path': scriptPath,
        'stdout': stdout,
        'stderr': stderr,
        'status': status,
      };
    } catch (error, stackTrace) {
      developer.log(
        "Error executing script '$scriptPath' from skill '${skill.name}'",
        name: 'adk_dart.skill_toolset',
        error: error,
        stackTrace: stackTrace,
      );
      String shortMessage = '$error';
      if (shortMessage.length > 200) {
        shortMessage = '${shortMessage.substring(0, 200)}...';
      }
      return <String, Object?>{
        'error':
            "Failed to execute script '$scriptPath':\n${error.runtimeType}: $shortMessage",
        'error_code': 'EXECUTION_ERROR',
      };
    }
  }

  String? _buildWrapperCode({
    required Skill skill,
    required String scriptPath,
    required Map<String, Object?> scriptArgs,
  }) {
    final String normalizedScriptPath = scriptPath.startsWith('scripts/')
        ? scriptPath
        : 'scripts/$scriptPath';

    final String extension = scriptPath.contains('.')
        ? scriptPath.split('.').last.toLowerCase()
        : '';
    if (extension != 'py' && extension != 'sh' && extension != 'bash') {
      return null;
    }

    final Map<String, Object> files = <String, Object>{};
    for (final String referenceName in skill.resources.listReferences()) {
      final Object? content = skill.resources.getReferenceData(referenceName);
      if (content != null) {
        files['references/$referenceName'] = content;
      }
    }
    for (final String assetName in skill.resources.listAssets()) {
      final Object? content = skill.resources.getAssetData(assetName);
      if (content != null) {
        files['assets/$assetName'] = content;
      }
    }
    for (final String scriptName in skill.resources.listScripts()) {
      final Script? script = skill.resources.getScript(scriptName);
      if (script != null) {
        files['scripts/$scriptName'] = script.src;
      }
    }

    int totalSize = 0;
    for (final Object value in files.values) {
      if (value is String) {
        totalSize += value.codeUnits.length;
      } else if (value is List<int>) {
        totalSize += value.length;
      }
    }
    if (totalSize > _maxSkillPayloadBytes) {
      developer.log(
        "Skill '${skill.name}' resources total $totalSize bytes, exceeding the recommended limit of $_maxSkillPayloadBytes bytes.",
        name: 'adk_dart.skill_toolset',
      );
    }

    final String filesJson = jsonEncode(files);
    final List<String> lines = <String>[
      'import os',
      'import tempfile',
      'import sys',
      'import json as _json',
      'import subprocess',
      'import runpy',
      '_files = _json.loads(${jsonEncode(filesJson)})',
      'def _materialize_and_run():',
      '  _orig_cwd = os.getcwd()',
      '  with tempfile.TemporaryDirectory() as td:',
      '    for rel_path, content in _files.items():',
      '      full_path = os.path.join(td, rel_path)',
      '      os.makedirs(os.path.dirname(full_path), exist_ok=True)',
      "      mode = 'wb' if isinstance(content, bytes) else 'w'",
      '      with open(full_path, mode) as f:',
      '        f.write(content)',
      '    os.chdir(td)',
      '    try:',
    ];

    if (extension == 'py') {
      final List<String> argv = <String>[normalizedScriptPath];
      scriptArgs.forEach((String key, Object? value) {
        argv.add('--$key');
        argv.add('$value');
      });
      lines.addAll(<String>[
        '      sys.argv = ${jsonEncode(argv)}',
        '      try:',
        "        runpy.run_path(${jsonEncode(normalizedScriptPath)}, run_name='__main__')",
        '      except SystemExit as e:',
        '        if e.code is not None and e.code != 0:',
        '          raise e',
      ]);
    } else {
      final List<String> command = <String>['bash', normalizedScriptPath];
      scriptArgs.forEach((String key, Object? value) {
        command.add('--$key');
        command.add('$value');
      });
      lines.addAll(<String>[
        '      try:',
        '        _r = subprocess.run(',
        '          ${jsonEncode(command)},',
        '          capture_output=True, text=True,',
        '          timeout=$_scriptTimeout, cwd=td,',
        '        )',
        '        print(_json.dumps({',
        "            '__shell_result__': True,",
        "            'stdout': _r.stdout,",
        "            'stderr': _r.stderr,",
        "            'returncode': _r.returncode,",
        '        }))',
        '      except subprocess.TimeoutExpired as _e:',
        '        print(_json.dumps({',
        "            '__shell_result__': True,",
        "            'stdout': _e.stdout or '',",
        "            'stderr': 'Timed out after $_scriptTimeout s',",
        "            'returncode': -1,",
        '        }))',
      ]);
    }

    lines.addAll(<String>[
      '    finally:',
      '      os.chdir(_orig_cwd)',
      '_materialize_and_run()',
    ]);

    return lines.join('\n');
  }
}

class _RunSkillScriptTool extends BaseTool {
  _RunSkillScriptTool(this._toolset)
    : super(
        name: 'run_skill_script',
        description: "Executes a script from a skill's scripts/ directory.",
      );

  final SkillToolset _toolset;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'skill_name': <String, Object?>{
            'type': 'string',
            'description': 'The name of the skill.',
          },
          'script_path': <String, Object?>{
            'type': 'string',
            'description':
                "The relative path to the script (e.g., 'scripts/setup.py').",
          },
          'args': <String, Object?>{
            'type': 'object',
            'description':
                'Optional arguments to pass to the script as key-value pairs.',
          },
        },
        'required': <String>['skill_name', 'script_path'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawSkillName = args['skill_name'];
    final Object? rawScriptPath = args['script_path'];
    final Object? rawScriptArgs = args['args'] ?? <String, Object?>{};

    if (rawScriptArgs is! Map) {
      return <String, Object?>{
        'error':
            "'args' must be a JSON object (key-value pairs), got ${rawScriptArgs.runtimeType}.",
        'error_code': 'INVALID_ARGS_TYPE',
      };
    }

    if (rawSkillName is! String || rawSkillName.trim().isEmpty) {
      return <String, Object?>{
        'error': 'Skill name is required.',
        'error_code': 'MISSING_SKILL_NAME',
      };
    }
    if (rawScriptPath is! String || rawScriptPath.trim().isEmpty) {
      return <String, Object?>{
        'error': 'Script path is required.',
        'error_code': 'MISSING_SCRIPT_PATH',
      };
    }

    final String skillName = rawSkillName.trim();
    final String scriptPath = rawScriptPath.trim();
    final Skill? skill = _toolset._getSkill(skillName);
    if (skill == null) {
      return <String, Object?>{
        'error': "Skill '$skillName' not found.",
        'error_code': 'SKILL_NOT_FOUND',
      };
    }

    final Script? script = scriptPath.startsWith('scripts/')
        ? skill.resources.getScript(scriptPath.substring('scripts/'.length))
        : skill.resources.getScript(scriptPath);
    if (script == null) {
      return <String, Object?>{
        'error': "Script '$scriptPath' not found in skill '$skillName'.",
        'error_code': 'SCRIPT_NOT_FOUND',
      };
    }

    BaseCodeExecutor? codeExecutor = _toolset._codeExecutor;
    if (codeExecutor == null) {
      final dynamic agent = toolContext.invocationContext.agent;
      try {
        final Object? agentCodeExecutor = agent.codeExecutor;
        if (agentCodeExecutor is BaseCodeExecutor) {
          codeExecutor = agentCodeExecutor;
        }
      } catch (_) {
        // Ignore missing property and keep searching fallback.
      }
    }
    if (codeExecutor == null) {
      return <String, Object?>{
        'error':
            'No code executor configured. A code executor is required to run scripts.',
        'error_code': 'NO_CODE_EXECUTOR',
      };
    }

    final _SkillScriptCodeExecutor scriptExecutor = _SkillScriptCodeExecutor(
      baseExecutor: codeExecutor,
      scriptTimeout: _toolset._scriptTimeout,
    );
    return scriptExecutor.executeScript(
      toolContext: toolContext,
      skill: skill,
      scriptPath: scriptPath,
      scriptArgs: rawScriptArgs.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      ),
    );
  }
}

/// Toolset exposing skill-discovery, loading, and script-execution tools.
class SkillToolset extends BaseToolset {
  /// Creates a toolset that exposes skill discovery/loading/script tools.
  SkillToolset({
    required List<Skill> skills,
    List<Object>? additionalTools,
    BaseCodeExecutor? codeExecutor,
    int scriptTimeout = _defaultScriptTimeout,
  }) : _codeExecutor = codeExecutor,
       _scriptTimeout = scriptTimeout {
    final Set<String> seen = <String>{};
    for (final Skill skill in skills) {
      if (seen.contains(skill.name)) {
        throw ArgumentError("Duplicate skill name '${skill.name}'.");
      }
      seen.add(skill.name);
    }
    _skills = <String, Skill>{
      for (final Skill skill in skills) skill.name: skill,
    };
    _tools = <BaseTool>[
      _ListSkillsTool(this),
      _LoadSkillTool(this),
      _LoadSkillResourceTool(this),
      _RunSkillScriptTool(this),
    ];
    _providedToolsByName = <String, BaseTool>{};
    _providedToolsets = <BaseToolset>[];
    for (final Object toolUnion in additionalTools ?? const <Object>[]) {
      if (toolUnion is BaseToolset) {
        _providedToolsets.add(toolUnion);
        continue;
      }
      if (toolUnion is BaseTool) {
        _providedToolsByName[toolUnion.name] = toolUnion;
        continue;
      }
      throw ArgumentError(
        'SkillToolset.additionalTools only supports BaseTool and BaseToolset values.',
      );
    }
  }

  late final Map<String, Skill> _skills;
  late final List<BaseTool> _tools;
  late final Map<String, BaseTool> _providedToolsByName;
  late final List<BaseToolset> _providedToolsets;
  final BaseCodeExecutor? _codeExecutor;
  final int _scriptTimeout;

  @override
  /// Returns skill tools filtered by [toolFilter], if configured.
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> dynamicTools = await _resolveAdditionalToolsFromState(
      readonlyContext,
    );
    return <BaseTool>[..._tools, ...dynamicTools]
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  Skill? _getSkill(String name) => _skills[name];

  List<Skill> _listSkills() => _skills.values.toList(growable: false);

  Future<List<BaseTool>> _resolveAdditionalToolsFromState(
    ReadonlyContext? readonlyContext,
  ) async {
    if (readonlyContext == null) {
      return const <BaseTool>[];
    }

    final String stateKey = '_adk_activated_skill_${readonlyContext.agentName}';
    final List<Object?> activated = List<Object?>.from(
      readonlyContext.state[stateKey] as List? ?? const <Object?>[],
    );
    if (activated.isEmpty) {
      return const <BaseTool>[];
    }

    final Set<String> additionalToolNames = <String>{};
    for (final Object? skillName in activated) {
      if (skillName is! String) {
        continue;
      }
      final Skill? skill = _skills[skillName];
      if (skill == null) {
        continue;
      }
      final Object? metadataValue =
          skill.frontmatter.metadata['adk_additional_tools'];
      if (metadataValue is String && metadataValue.isNotEmpty) {
        additionalToolNames.add(metadataValue);
        continue;
      }
      if (metadataValue is List) {
        for (final Object? item in metadataValue) {
          if (item is String && item.isNotEmpty) {
            additionalToolNames.add(item);
          }
        }
      }
    }

    if (additionalToolNames.isEmpty) {
      return const <BaseTool>[];
    }

    final Map<String, BaseTool> candidateTools = <String, BaseTool>{
      ..._providedToolsByName,
    };
    if (_providedToolsets.isNotEmpty) {
      for (final BaseToolset toolset in _providedToolsets) {
        final List<BaseTool> provided = await toolset.getToolsWithPrefix(
          readonlyContext: readonlyContext,
        );
        for (final BaseTool tool in provided) {
          candidateTools[tool.name] = tool;
        }
      }
    }

    final Set<String> existingToolNames = _tools
        .map((BaseTool tool) => tool.name)
        .toSet();
    final List<BaseTool> resolved = <BaseTool>[];
    final List<String> sortedNames = additionalToolNames.toList()..sort();
    for (final String toolName in sortedNames) {
      final BaseTool? tool = candidateTools[toolName];
      if (tool == null) {
        continue;
      }
      if (existingToolNames.contains(tool.name)) {
        developer.log(
          "Tool name collision: tool '${tool.name}' already exists.",
          name: 'adk_dart.skill_toolset',
        );
        continue;
      }
      resolved.add(tool);
      existingToolNames.add(tool.name);
    }
    return resolved;
  }

  @override
  /// Appends skill guidance and catalog XML to [llmRequest].
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final bool includeRunSkillScriptLine = _tools.any(
      (BaseTool tool) =>
          tool.name == 'run_skill_script' && isToolSelected(tool, null),
    );
    final String systemInstruction = includeRunSkillScriptLine
        ? '$defaultSkillSystemInstruction\n$_runSkillScriptInstruction'
        : defaultSkillSystemInstruction;
    final List<String> instructions = <String>[
      systemInstruction,
      formatSkillsAsXml(_listSkills()),
    ];
    llmRequest.appendInstructions(instructions);
  }
}

const Map<String, String> _skillResourceMimeTypes = <String, String>{
  '.gif': 'image/gif',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.json': 'application/json',
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain',
  '.wav': 'audio/wav',
};

String _guessMimeType(String path) {
  final String normalized = path.toLowerCase();
  for (final MapEntry<String, String> entry
      in _skillResourceMimeTypes.entries) {
    if (normalized.endsWith(entry.key)) {
      return entry.value;
    }
  }
  return 'application/octet-stream';
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
