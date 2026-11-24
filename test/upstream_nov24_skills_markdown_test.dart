import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/skills/skill_web.dart' as skill_web;
import 'package:test/test.dart';

void main() {
  group('loadSkillFromMarkdown (6686413c2)', () {
    test('builds a Skill from SKILL.md text carrying the given resources', () {
      final Resources resources = Resources(
        references: <String, SkillResourceData>{'policy.md': 'Open 9 to 5.'},
      );

      final Skill skill = loadSkillFromMarkdown(
        '---\nname: support-hours\ndescription: Check support hours\n---\n'
        'Read references/policy.md.\n',
        resources: resources,
      );

      expect(skill.name, 'support-hours');
      expect(skill.description, 'Check support hours');
      expect(skill.instructions, 'Read references/policy.md.');
      expect(skill.resources.references, <String, SkillResourceData>{
        'policy.md': 'Open 9 to 5.',
      });
      expect(skill.resources.assets, isEmpty);
      expect(skill.resources.scripts, isEmpty);
    });

    test('without resources defaults to empty Resources', () {
      final Skill skill = loadSkillFromMarkdown(
        '---\nname: support-hours\ndescription: Check support hours\n---\nBody',
      );

      expect(skill.name, 'support-hours');
      expect(skill.description, 'Check support hours');
      expect(skill.instructions, 'Body');
      expect(skill.resources.references, isEmpty);
      expect(skill.resources.assets, isEmpty);
      expect(skill.resources.scripts, isEmpty);
    });

    test('rejects invalid SKILL.md frontmatter', () {
      final List<({String id, String markdown, Matcher match})> cases =
          <({String id, String markdown, Matcher match})>[
            (
              id: 'no_frontmatter',
              markdown: 'name: my-skill\ndescription: A skill\nBody',
              match: contains('must start with YAML'),
            ),
            (
              id: 'unclosed',
              markdown: '---\nname: my-skill\ndescription: A skill\nBody',
              match: contains('not properly'),
            ),
            (
              id: 'invalid_yaml',
              markdown: '---\nname: [my-skill\n---\nBody',
              match: contains('Invalid YAML'),
            ),
            (
              id: 'not_a_mapping',
              markdown: '---\n- my-skill\n---\nBody',
              match: contains('must be a YAML mapping'),
            ),
            (
              id: 'invalid_name',
              markdown: '---\nname: My Skill\ndescription: A skill\n---\nBody',
              match: contains('name must'),
            ),
          ];

      for (final ({String id, String markdown, Matcher match}) c in cases) {
        expect(
          () => loadSkillFromMarkdown(c.markdown),
          throwsA(
            isA<Object>().having((Object e) => e.toString(), 'message', c.match),
          ),
          reason: 'case: ${c.id}',
        );
      }
    });

    test('skill_web.loadSkillFromMarkdown matches VM behavior', () {
      final skill_web.Resources resources = skill_web.Resources(
        references: <String, skill_web.SkillResourceData>{
          'policy.md': 'Open 9 to 5.',
        },
      );

      final skill_web.Skill skill = skill_web.loadSkillFromMarkdown(
        '---\nname: support-hours\ndescription: Check support hours\n---\n'
        'Read references/policy.md.\n',
        resources: resources,
      );

      expect(skill.name, 'support-hours');
      expect(skill.description, 'Check support hours');
      expect(skill.instructions, 'Read references/policy.md.');
      expect(skill.resources.references['policy.md'], 'Open 9 to 5.');
    });
  });
}
