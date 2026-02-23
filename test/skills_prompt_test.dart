import 'package:adk_dart/adk_dart.dart';
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
  });
}
