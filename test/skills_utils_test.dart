import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

String _join(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

void _writeFile(String path, String content) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Matcher _throwsArgumentMessage(String messageFragment) {
  return throwsA(
    isA<ArgumentError>().having(
      (ArgumentError error) => error.message.toString(),
      'message',
      contains(messageFragment),
    ),
  );
}

void main() {
  group('skills utils', () {
    test('loadSkillFromDir loads instructions and resources', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'test-skill'));
      skillDir.createSync(recursive: true);

      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: test-skill
description: Test description
---
Test instructions
''');
      _writeFile(_join(skillDir.path, 'references/ref1.md'), 'ref1 content');
      _writeFile(_join(skillDir.path, 'assets/asset1.txt'), 'asset1 content');
      _writeFile(_join(skillDir.path, 'scripts/script1.sh'), 'echo hello');

      final Skill skill = loadSkillFromDir(skillDir.path);
      expect(skill.name, 'test-skill');
      expect(skill.description, 'Test description');
      expect(skill.instructions, 'Test instructions');
      expect(skill.resources.getReference('ref1.md'), 'ref1 content');
      expect(skill.resources.getAsset('asset1.txt'), 'asset1 content');
      expect(skill.resources.getScript('script1.sh')?.src, 'echo hello');
    });

    test('loadSkillFromDir supports allowed-tools yaml key', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
      skillDir.createSync(recursive: true);

      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
allowed-tools: "some-tool-*"
---
Instructions here
''');

      final Skill skill = loadSkillFromDir(skillDir.path);
      expect(skill.frontmatter.allowedTools, 'some-tool-*');
    });

    test('loadSkillFromDir parses YAML block scalars in frontmatter', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
      skillDir.createSync(recursive: true);

      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: |
  Multi-line
  description
compatibility: >
  python-parity
---
Instructions here
''');

      final Skill skill = loadSkillFromDir(skillDir.path);
      expect(skill.name, 'my-skill');
      expect(skill.description, contains('Multi-line'));
      expect(skill.frontmatter.compatibility, contains('python-parity'));
    });

    test('loadSkillFromDir rejects directory-name mismatch', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'wrong-dir'));
      skillDir.createSync(recursive: true);
      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
---
Body
''');

      expect(
        () => loadSkillFromDir(skillDir.path),
        _throwsArgumentMessage('does not match directory'),
      );
    });

    test('loadSkillFromDir accepts resolved symlink directory name', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory realSkillDir = Directory(_join(tempDir.path, 'my-skill'));
      realSkillDir.createSync(recursive: true);
      _writeFile(_join(realSkillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
---
Body
''');

      final Link skillLink = Link(_join(tempDir.path, 'linked-skill'));
      skillLink.createSync(realSkillDir.path);

      final Skill skill = loadSkillFromDir(skillLink.path);
      expect(skill.name, 'my-skill');
    });

    test('validateSkillDir returns empty list for valid skill', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
      skillDir.createSync(recursive: true);
      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
---
Body
''');

      expect(validateSkillDir(skillDir.path), isEmpty);
    });

    test('validateSkillDir reports missing directory', () {
      final List<String> problems = validateSkillDir(
        _join(
          Directory.systemTemp.path,
          'adk-nonexistent-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      expect(problems, hasLength(1));
      expect(problems.first, contains('does not exist'));
    });

    test('validateSkillDir reports missing SKILL.md', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
      skillDir.createSync(recursive: true);

      final List<String> problems = validateSkillDir(skillDir.path);
      expect(problems, hasLength(1));
      expect(problems.first, contains('SKILL.md not found'));
    });

    test('validateSkillDir reports name mismatch', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'wrong-dir'));
      skillDir.createSync(recursive: true);
      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
---
Body
''');

      final List<String> problems = validateSkillDir(skillDir.path);
      expect(
        problems.any((String problem) => problem.contains('does not match')),
        isTrue,
      );
    });

    test('validateSkillDir reports unknown frontmatter field', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
      skillDir.createSync(recursive: true);
      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
unknown-field: something
---
Body
''');

      final List<String> problems = validateSkillDir(skillDir.path);
      expect(
        problems.any(
          (String problem) => problem.contains('Unknown frontmatter'),
        ),
        isTrue,
      );
    });

    test('readSkillProperties reads frontmatter only', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
      skillDir.createSync(recursive: true);
      _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A cool skill
license: MIT
---
Body content
''');

      final Frontmatter properties = readSkillProperties(skillDir.path);
      expect(properties.name, 'my-skill');
      expect(properties.description, 'A cool skill');
      expect(properties.license, 'MIT');
    });
  });
}
