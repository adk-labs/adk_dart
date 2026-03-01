import '../tools/skill_toolset.dart' show defaultSkillSystemInstruction;

export 'skill.dart' show formatSkillsAsXml;

@Deprecated(
  'Importing DEFAULT_SKILL_SYSTEM_INSTRUCTION from skills.prompt is deprecated. '
  'Import it from tools.skill_toolset instead.',
)
// ignore: constant_identifier_names
const String DEFAULT_SKILL_SYSTEM_INSTRUCTION = defaultSkillSystemInstruction;
