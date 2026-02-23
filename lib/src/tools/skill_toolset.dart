import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import '../skills/skill.dart';
import 'base_tool.dart';
import 'base_toolset.dart';
import 'tool_context.dart';

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

    String? content;
    if (resourcePath.startsWith('references/')) {
      final String referenceName = resourcePath.substring('references/'.length);
      content = skill.resources.getReference(referenceName);
    } else if (resourcePath.startsWith('assets/')) {
      final String assetName = resourcePath.substring('assets/'.length);
      content = skill.resources.getAsset(assetName);
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

    return <String, Object?>{
      'skill_name': skillName,
      'path': resourcePath,
      'content': content,
    };
  }
}

class SkillToolset extends BaseToolset {
  SkillToolset({required List<Skill> skills}) {
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
    ];
  }

  late final Map<String, Skill> _skills;
  late final List<BaseTool> _tools;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return _tools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  Skill? _getSkill(String name) => _skills[name];

  List<Skill> _listSkills() => _skills.values.toList(growable: false);

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final List<String> instructions = <String>[
      defaultSkillSystemInstruction,
      formatSkillsAsXml(_listSkills()),
    ];
    llmRequest.appendInstructions(instructions);
  }
}
