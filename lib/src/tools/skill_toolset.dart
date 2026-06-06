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
const String _legacyBinaryFileDetectedMsg =
    'Binary file detected. The runtime will attach it to the next model request.';
const String _binaryFileDetectedMsg =
    'Binary file detected. The content has been injected into the conversation history for you to analyze.';

/// Default system instruction injected when skill tools are enabled.
const String defaultSkillSystemInstruction =
    """You can use specialized 'skills' to help you with complex tasks. You MUST use the skill tools to interact with these skills.

Skills are folders of instructions and resources that extend your capabilities for specialized tasks. Each skill folder contains:
- **SKILL.md** (required): The main instruction file with skill metadata and detailed markdown instructions.
- **references/** (Optional): Additional documentation or examples for skill usage.
- **assets/** (Optional): Templates, scripts or other resources used by the skill.
- **scripts/** (Optional): Executable scripts that can be run via bash.

This is very important:

1. If a skill seems relevant to the current user query, you MUST use the `load_skill` tool with `skill_name="<SKILL_NAME>"` to read its full instructions before proceeding.
2. Once you have read the instructions, follow them exactly as documented before replying to the user. For example, If the instruction lists multiple steps, please make sure you complete all of them in order.
3. The `load_skill_resource` tool is for viewing files within a skill's directory (e.g., `references/*`, `assets/*`, `scripts/*`). It is ONLY for skill-bundled files — do NOT use it to access documents or files provided by the user at runtime. Do NOT use other tools to access skill files.
4. Use `run_skill_script` to run scripts from a skill's `scripts/` directory. Use `load_skill_resource` to view script content first if needed.
5. If `load_skill_resource` returns any error, do not retry any path. Report the error to the user and stop.
""";

String _buildSkillSystemInstruction(String? prefix) {
  final String p = prefix == null || prefix.isEmpty ? '' : '${prefix}_';
  if (p.isEmpty) {
    return defaultSkillSystemInstruction;
  }

  return """You can use specialized 'skills' to help you with complex tasks. You MUST use the skill tools to interact with these skills.

Skills are folders of instructions and resources that extend your capabilities for specialized tasks. Each skill folder contains:
- **SKILL.md** (required): The main instruction file with skill metadata and detailed markdown instructions.
- **references/** (Optional): Additional documentation or examples for skill usage.
- **assets/** (Optional): Templates, scripts or other resources used by the skill.
- **scripts/** (Optional): Executable scripts that can be run via bash.

This is very important:

1. If a skill seems relevant to the current user query, you MUST use the `${p}load_skill` tool with `skill_name="<SKILL_NAME>"` to read its full instructions before proceeding.
2. Once you have read the instructions, follow them exactly as documented before replying to the user. For example, If the instruction lists multiple steps, please make sure you complete all of them in order.
3. The `${p}load_skill_resource` tool is for viewing files within a skill's directory (e.g., `references/*`, `assets/*`, `scripts/*`). It is ONLY for skill-bundled files — do NOT use it to access documents or files provided by the user at runtime. Do NOT use other tools to access skill files.
4. Use `${p}run_skill_script` to run scripts from a skill's `scripts/` directory. Use `${p}load_skill_resource` to view script content first if needed.
5. If `${p}load_skill_resource` returns any error, do not retry any path. Report the error to the user and stop.
""";
}

String? _detectSkillToolError(Object? response) {
  if (response is Map && response['error'] != null) {
    final Object? errorCode = response['error_code'];
    return errorCode is String && errorCode.isNotEmpty
        ? errorCode
        : 'TOOL_ERROR';
  }
  return null;
}

/// Tool to list all locally available skills.
class ListSkillsTool extends BaseTool {
  /// Creates a list-skills tool backed by [toolset].
  ListSkillsTool(this._toolset)
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

/// Tool to search a configured skill registry for relevant skills.
class SearchSkillsTool extends BaseTool {
  /// Creates a registry-backed skill search tool.
  SearchSkillsTool(this._toolset)
    : super(
        name: 'search_skills',
        description:
            _toolset._registry?.getSearchDescription() ??
            'Searches for relevant skills in the registry based on a semantic or keyword query.',
      ) {
    if (_toolset._registry == null) {
      throw ArgumentError('SearchSkillsTool requires a configured registry.');
    }
  }

  final SkillToolset _toolset;

  @override
  FunctionDeclaration? getDeclaration() {
    final Map<String, Object?> properties = <String, Object?>{
      'query': <String, Object?>{
        'type': 'string',
        'description': 'Semantic or keyword search query.',
      },
    };
    final Map<String, Object?>? filterSchema = _toolset._registry
        ?.getFilterSchema();
    if (filterSchema != null) {
      properties['filters'] = filterSchema;
    }
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': properties,
        'required': <String>['query'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? query = args['query'];
    if (query is! String || query.trim().isEmpty) {
      return <String, Object?>{
        'error': "Argument 'query' is required.",
        'error_code': 'INVALID_ARGUMENTS',
      };
    }
    final Object? rawFilters = args['filters'];
    final Map<String, Object?>? filters = rawFilters is Map
        ? rawFilters.map(
            (Object? key, Object? value) => MapEntry('$key', value),
          )
        : null;

    try {
      final List<Frontmatter> results = await _toolset._registry!.searchSkills(
        query: query.trim(),
        filters: filters,
      );
      final List<Map<String, Object?>> formatted = <Map<String, Object?>>[];
      for (final Frontmatter frontmatter in results) {
        if (_toolset._skills.containsKey(frontmatter.name)) {
          developer.log(
            "Skill naming conflict: skill '${frontmatter.name}' already exists locally. Registry skill is filtered.",
            name: 'adk_dart.skill_toolset',
          );
          continue;
        }
        formatted.add(frontmatter.toMap());
      }
      return formatted;
    } catch (error) {
      return <String, Object?>{
        'error': 'Failed to search skills from registry: $error',
        'error_code': 'REGISTRY_ERROR',
      };
    }
  }

  @override
  String? detectErrorInResponse(Object? response) {
    return _detectSkillToolError(response);
  }
}

/// Tool to load a skill's main instructions.
class LoadSkillTool extends BaseTool {
  /// Creates a load-skill tool backed by [toolset].
  LoadSkillTool(this._toolset)
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
          'skill_name': <String, Object?>{
            'type': 'string',
            'description': 'The name of the skill to load.',
          },
        },
        'required': <String>['skill_name'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? skillName = args['skill_name'] ?? args['name'];
    if (skillName is! String || skillName.trim().isEmpty) {
      return <String, Object?>{
        'error': "Argument 'skill_name' is required.",
        'error_code': 'INVALID_ARGUMENTS',
      };
    }

    Skill? skill;
    try {
      skill = await _toolset._getOrFetchSkill(
        skillName.trim(),
        invocationId: toolContext.invocationId,
      );
    } catch (error) {
      return <String, Object?>{
        'error':
            "Failed to fetch skill '${skillName.trim()}' from registry: $error",
        'error_code': 'REGISTRY_ERROR',
      };
    }
    if (skill == null) {
      return <String, Object?>{
        'error': "Skill '${skillName.trim()}' not found.",
        'error_code': 'SKILL_NOT_FOUND',
      };
    }

    final String stateKey = _activationStateKey(toolContext.agentName);
    final Object? rawActivated = toolContext.state[stateKey];
    final List<Object?> activated = rawActivated is List
        ? List<Object?>.from(rawActivated)
        : <Object?>[];
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

  @override
  String? detectErrorInResponse(Object? response) {
    return _detectSkillToolError(response);
  }
}

/// Tool to load a resource from a skill bundle.
class LoadSkillResourceTool extends BaseTool {
  /// Creates a load-skill-resource tool backed by [toolset].
  LoadSkillResourceTool(this._toolset)
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
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                "The relative path to the resource (e.g., 'references/my_doc.md', 'assets/template.txt', or 'scripts/setup.sh').",
          },
        },
        'required': <String>['skill_name', 'file_path'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawSkillName = args['skill_name'];
    final Object? rawPath = args['file_path'] ?? args['path'];

    final List<String> errors = <String>[];
    if (rawSkillName is! String || rawSkillName.trim().isEmpty) {
      errors.add("Argument 'skill_name' is required.");
    }
    if (rawPath is! String || rawPath.trim().isEmpty) {
      errors.add("Argument 'file_path' is required.");
    }
    if (errors.isNotEmpty) {
      return <String, Object?>{
        'error': errors.join('\n'),
        'error_code': 'INVALID_ARGUMENTS',
      };
    }

    final String skillName = (rawSkillName as String).trim();
    final String resourcePath = (rawPath as String).trim();
    Skill? skill;
    try {
      skill = await _toolset._getOrFetchSkill(
        skillName,
        invocationId: toolContext.invocationId,
      );
    } catch (error) {
      return <String, Object?>{
        'error': "Failed to fetch skill '$skillName' from registry: $error",
        'error_code': 'REGISTRY_ERROR',
      };
    }
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
      final String counterKey =
          'temp:_adk_skill_resource_not_found_count_${toolContext.invocationId}';
      final Object? rawCount = toolContext.state[counterKey];
      final int failCount = rawCount is num ? rawCount.toInt() + 1 : 1;
      toolContext.state[counterKey] = failCount;
      if (failCount > 1) {
        return <String, Object?>{
          'error':
              "Resource '$resourcePath' not found in skill '$skillName'. This is resource lookup failure #$failCount this invocation. Do not retry any path — report the error to the user and stop.",
          'error_code': 'RESOURCE_NOT_FOUND_FATAL',
        };
      }
      return <String, Object?>{
        'error': "Resource '$resourcePath' not found in skill '$skillName'.",
        'error_code': 'RESOURCE_NOT_FOUND',
      };
    }

    if (content is List<int>) {
      return <String, Object?>{
        'skill_name': skillName,
        'file_path': resourcePath,
        'status': _binaryFileDetectedMsg,
      };
    }

    return <String, Object?>{
      'skill_name': skillName,
      'file_path': resourcePath,
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
      final Object? status = response['status'];
      if (status != _binaryFileDetectedMsg &&
          status != _legacyBinaryFileDetectedMsg) {
        continue;
      }

      final String? skillName = response['skill_name'] as String?;
      final String? resourcePath =
          response['file_path'] as String? ?? response['path'] as String?;
      if (skillName == null || resourcePath == null) {
        continue;
      }

      Skill? skill;
      try {
        skill = await _toolset._getOrFetchSkill(
          skillName,
          invocationId: toolContext.invocationId,
        );
      } catch (error, stackTrace) {
        developer.log(
          "Failed to fetch skill '$skillName' from registry during LLM request processing.",
          name: 'adk_dart.skill_toolset',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
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

  @override
  String? detectErrorInResponse(Object? response) {
    return _detectSkillToolError(response);
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
    required Object? scriptArgs,
    required Map<String, Object?> shortOptions,
    required List<Object?> positionalArgs,
  }) async {
    final String? code = _buildWrapperCode(
      skill: skill,
      scriptPath: scriptPath,
      scriptArgs: scriptArgs,
      shortOptions: shortOptions,
      positionalArgs: positionalArgs,
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
        'file_path': scriptPath,
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
    required Object? scriptArgs,
    required Map<String, Object?> shortOptions,
    required List<Object?> positionalArgs,
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
      if (scriptArgs is List) {
        argv.addAll(scriptArgs.map((Object? value) => '$value'));
      } else {
        final Map<String, Object?> longOptions =
            scriptArgs as Map<String, Object?>? ?? <String, Object?>{};
        longOptions.forEach((String key, Object? value) {
          argv.add('--$key');
          argv.add('$value');
        });
        shortOptions.forEach((String key, Object? value) {
          argv.add('-$key');
          argv.add('$value');
        });
        if (positionalArgs.isNotEmpty) {
          argv.add('--');
          argv.addAll(positionalArgs.map((Object? value) => '$value'));
        }
      }
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
      if (scriptArgs is List) {
        command.addAll(scriptArgs.map((Object? value) => '$value'));
      } else {
        final Map<String, Object?> longOptions =
            scriptArgs as Map<String, Object?>? ?? <String, Object?>{};
        longOptions.forEach((String key, Object? value) {
          command.add('--$key');
          command.add('$value');
        });
        shortOptions.forEach((String key, Object? value) {
          command.add('-$key');
          command.add('$value');
        });
        if (positionalArgs.isNotEmpty) {
          command.add('--');
          command.addAll(positionalArgs.map((Object? value) => '$value'));
        }
      }
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
        "            'stderr': 'Timed out after ${_scriptTimeout}s',",
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

/// Tool to execute scripts from a skill bundle.
class RunSkillScriptTool extends BaseTool {
  /// Creates a run-skill-script tool backed by [toolset].
  RunSkillScriptTool(this._toolset)
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
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                "The relative path to the script (e.g., 'scripts/setup.py').",
          },
          'args': <String, Object?>{
            'anyOf': <Object?>[
              <String, Object?>{'type': 'object'},
              <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
            ],
            'description':
                "Optional arguments to pass to the script as key-value pairs (long options) or as a list of strings. If specified as a list, it is treated as the complete list of arguments, and 'short_options' and 'positional_args' must not be provided.",
          },
          'short_options': <String, Object?>{
            'type': 'object',
            'description':
                "Optional short options (single hyphen) to pass to the script as key-value pairs. Must not be provided if 'args' is a list.",
          },
          'positional_args': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                "Optional positional arguments to pass to the script. Must not be provided if 'args' is a list.",
          },
        },
        'required': <String>['skill_name', 'file_path'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Object? rawSkillName = args['skill_name'];
    final Object? rawScriptPath = args['file_path'] ?? args['script_path'];
    final Object? rawScriptArgs = args['args'];
    final Object? rawShortOptions = args['short_options'];
    final Object? rawPositionalArgs = args['positional_args'];

    final List<String> errors = <String>[];
    if (rawSkillName is! String || rawSkillName.trim().isEmpty) {
      errors.add("Argument 'skill_name' is required.");
    }
    if (rawScriptPath is! String || rawScriptPath.trim().isEmpty) {
      errors.add("Argument 'file_path' is required.");
    }
    if (rawScriptArgs != null &&
        rawScriptArgs is! Map &&
        rawScriptArgs is! List) {
      errors.add(
        "'args' must be a JSON object (dict) or a list of strings, got ${rawScriptArgs.runtimeType}.",
      );
    }
    if (rawShortOptions != null && rawShortOptions is! Map) {
      errors.add(
        "'short_options' must be a JSON object (dict), got ${rawShortOptions.runtimeType}.",
      );
    }
    if (rawPositionalArgs != null && rawPositionalArgs is! List) {
      errors.add(
        "'positional_args' must be a list of strings, got ${rawPositionalArgs.runtimeType}.",
      );
    }
    if (rawScriptArgs is List &&
        ((rawShortOptions is Map && rawShortOptions.isNotEmpty) ||
            (rawPositionalArgs is List && rawPositionalArgs.isNotEmpty))) {
      errors.add(
        "Cannot specify 'short_options' or 'positional_args' when 'args' is a list.",
      );
    }
    if (errors.isNotEmpty) {
      return <String, Object?>{
        'error': errors.join('\n'),
        'error_code': 'INVALID_ARGUMENTS',
      };
    }

    final String skillName = (rawSkillName as String).trim();
    final String scriptPath = (rawScriptPath as String).trim();
    Skill? skill;
    try {
      skill = await _toolset._getOrFetchSkill(
        skillName,
        invocationId: toolContext.invocationId,
      );
    } catch (error) {
      return <String, Object?>{
        'error': "Failed to fetch skill '$skillName' from registry: $error",
        'error_code': 'REGISTRY_ERROR',
      };
    }
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

    final BaseCodeExecutor? codeExecutor = _resolveCodeExecutor(
      _toolset._codeExecutor,
      toolContext,
    );
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
      scriptArgs: rawScriptArgs is Map
          ? rawScriptArgs.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            )
          : rawScriptArgs is List
          ? List<Object?>.from(rawScriptArgs)
          : null,
      shortOptions: rawShortOptions is Map
          ? rawShortOptions.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            )
          : <String, Object?>{},
      positionalArgs: rawPositionalArgs is List
          ? List<Object?>.from(rawPositionalArgs)
          : <Object?>[],
    );
  }

  @override
  String? detectErrorInResponse(Object? response) {
    return _detectSkillToolError(response);
  }
}

/// Toolset exposing skill-discovery, loading, and script-execution tools.
class SkillToolset extends BaseToolset {
  /// Creates a toolset that exposes skill discovery/loading/script tools.
  SkillToolset({
    List<Skill>? skills,
    SkillRegistry? registry,
    List<Object>? additionalTools,
    BaseCodeExecutor? codeExecutor,
    int scriptTimeout = _defaultScriptTimeout,
    super.toolNamePrefix,
    super.toolFilter,
  }) : _registry = registry,
       _codeExecutor = codeExecutor,
       _scriptTimeout = scriptTimeout {
    final Set<String> seen = <String>{};
    final List<Skill> localSkills = skills ?? const <Skill>[];
    for (final Skill skill in localSkills) {
      if (seen.contains(skill.name)) {
        throw ArgumentError("Duplicate skill name '${skill.name}'.");
      }
      seen.add(skill.name);
    }
    _skills = <String, Skill>{
      for (final Skill skill in localSkills) skill.name: skill,
    };
    _tools = <BaseTool>[
      ListSkillsTool(this),
      LoadSkillTool(this),
      LoadSkillResourceTool(this),
      RunSkillScriptTool(this),
      if (registry != null) SearchSkillsTool(this),
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
  final SkillRegistry? _registry;
  final Map<String, Map<String, Future<Skill?>>> _fetchedSkillCache =
      <String, Map<String, Future<Skill?>>>{};
  final BaseCodeExecutor? _codeExecutor;
  final int _scriptTimeout;
  static const int _maxCacheTurns = 16;

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

  Future<Skill?> _getOrFetchSkill(String name, {String? invocationId}) async {
    final Skill? local = _getSkill(name);
    if (local != null) {
      return local;
    }

    final SkillRegistry? registry = _registry;
    if (registry == null) {
      return null;
    }

    if (invocationId == null || invocationId.isEmpty) {
      return registry.getSkill(name: name);
    }

    if (!_fetchedSkillCache.containsKey(invocationId)) {
      if (_fetchedSkillCache.length >= _maxCacheTurns) {
        _fetchedSkillCache.remove(_fetchedSkillCache.keys.first);
      }
      _fetchedSkillCache[invocationId] = <String, Future<Skill?>>{};
    }
    final Map<String, Future<Skill?>> turnCache =
        _fetchedSkillCache[invocationId]!;

    return turnCache.putIfAbsent(name, () async {
      try {
        return await registry.getSkill(name: name);
      } catch (_) {
        turnCache.remove(name);
        rethrow;
      }
    });
  }

  List<Skill> _listSkills() => _skills.values.toList(growable: false);

  Future<List<BaseTool>> _resolveAdditionalToolsFromState(
    ReadonlyContext? readonlyContext,
  ) async {
    if (readonlyContext == null) {
      return const <BaseTool>[];
    }

    final String stateKey = '_adk_activated_skill_${readonlyContext.agentName}';
    final Object? rawActivated = readonlyContext.state[stateKey];
    final List<Object?> activated = rawActivated is List
        ? List<Object?>.from(rawActivated)
        : <Object?>[];
    if (activated.isEmpty) {
      return const <BaseTool>[];
    }

    final Set<String> additionalToolNames = <String>{};
    for (final Object? skillName in activated) {
      if (skillName is! String) {
        continue;
      }
      final Skill? skill = await _getOrFetchSkill(
        skillName,
        invocationId: readonlyContext.invocationId,
      );
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
  /// Appends skill guidance to [llmRequest].
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final List<String> instructions = <String>[
      _buildSkillSystemInstruction(toolNamePrefix),
    ];
    final bool hasListSkills = _tools.any(
      (BaseTool tool) => tool is ListSkillsTool,
    );
    if (!hasListSkills) {
      instructions.add(formatSkillsAsXml(_listSkills()));
    }
    if (_registry != null) {
      final String p = toolNamePrefix == null || toolNamePrefix!.isEmpty
          ? ''
          : '${toolNamePrefix}_';
      instructions.add(
        '\nIf the locally available skills are not sufficient to complete your task, '
        'you can use the `${p}search_skills` tool to discover additional skills from the registry.',
      );
    }
    llmRequest.appendInstructions(instructions);
  }

  @override
  Future<void> close() async {
    _fetchedSkillCache.clear();
    for (final BaseToolset toolset in _providedToolsets) {
      await toolset.close();
    }
    await super.close();
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

BaseCodeExecutor? _resolveCodeExecutor(
  BaseCodeExecutor? configured,
  ToolContext toolContext,
) {
  if (configured != null) {
    return configured;
  }
  final dynamic agent = toolContext.invocationContext.agent;
  try {
    final Object? agentCodeExecutor = agent.codeExecutor;
    if (agentCodeExecutor is BaseCodeExecutor) {
      return agentCodeExecutor;
    }
  } catch (_) {
    // Ignore missing property and keep searching fallback.
  }
  return null;
}
