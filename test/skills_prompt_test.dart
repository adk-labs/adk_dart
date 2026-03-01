import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/skills/prompt.dart' as skills_prompt;
import 'package:test/test.dart';

void main() {
  group('formatSkillsAsXml', () {
    test('formats skill metadata into xml block', () {
      final List<SkillDescriptor> skills = <SkillDescriptor>[
        Frontmatter(name: 'skill1', description: 'desc1'),
        Frontmatter(name: 'skill2', description: 'desc2'),
      ];

      final String xml = formatSkillsAsXml(skills);
      expect(xml, contains('<name>\nskill1\n</name>'));
      expect(xml, contains('<description>\ndesc1\n</description>'));
      expect(xml, isNot(contains('<location>')));
      expect(xml, contains('<name>\nskill2\n</name>'));
      expect(xml, contains('<description>\ndesc2\n</description>'));
      expect(xml.startsWith('<available_skills>'), isTrue);
      expect(xml.endsWith('</available_skills>'), isTrue);
    });

    test('returns empty available_skills for empty input', () {
      final String xml = formatSkillsAsXml(<SkillDescriptor>[]);
      expect(xml, '<available_skills>\n</available_skills>');
    });

    test('escapes special xml chars', () {
      final List<SkillDescriptor> skills = <SkillDescriptor>[
        Frontmatter(name: 'my-skill', description: 'desc<ription>'),
      ];

      final String xml = formatSkillsAsXml(skills);
      expect(xml, contains('my-skill'));
      expect(xml, contains('desc&lt;ription&gt;'));
    });

    test('escapes apostrophes with python-compatible entity', () {
      final List<SkillDescriptor> skills = <SkillDescriptor>[
        Frontmatter(name: 'my-skill', description: "it's fine"),
      ];

      final String xml = formatSkillsAsXml(skills);
      expect(xml, contains('it&#x27;s fine'));
    });

    test('exposes deprecated skill system instruction alias', () {
      expect(
        skills_prompt.DEFAULT_SKILL_SYSTEM_INSTRUCTION,
        defaultSkillSystemInstruction,
      );
    });
  });
}
