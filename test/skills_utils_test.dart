import 'dart:convert';
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

class _FakeSkillGcsStore implements SkillGcsStore {
  _FakeSkillGcsStore(this._buckets);

  final Map<String, Map<String, List<int>>> _buckets;

  @override
  Future<List<int>?> downloadBlob(String bucketName, String blobName) async {
    final Map<String, List<int>> bucket =
        _buckets[bucketName] ?? const <String, List<int>>{};
    final List<int>? bytes = bucket[blobName];
    return bytes == null ? null : List<int>.from(bytes);
  }

  @override
  Future<List<String>> listBlobNames(
    String bucketName, {
    String? prefix,
  }) async {
    final Map<String, List<int>> bucket =
        _buckets[bucketName] ?? const <String, List<int>>{};
    final String effectivePrefix = prefix ?? '';
    final List<String> names =
        bucket.keys
            .where((String name) => name.startsWith(effectivePrefix))
            .toList()
          ..sort();
    return names;
  }
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

    test(
      'loadSkillFromDir preserves metadata lists and binary assets',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk-skill-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final Directory skillDir = Directory(
          _join(tempDir.path, 'binary-skill'),
        );
        skillDir.createSync(recursive: true);

        _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: binary-skill
description: Binary test
metadata:
  adk_additional_tools:
    - extra_tool
---
Binary instructions
''');
        final File binaryAsset = File(_join(skillDir.path, 'assets/file.pdf'));
        binaryAsset.parent.createSync(recursive: true);
        binaryAsset.writeAsBytesSync(<int>[37, 80, 68, 70]);

        final Skill skill = loadSkillFromDir(skillDir.path);
        expect(skill.frontmatter.metadata['adk_additional_tools'], <String>[
          'extra_tool',
        ]);
        expect(skill.resources.getAsset('file.pdf'), isNull);
        expect(skill.resources.getAssetBytes('file.pdf'), <int>[
          37,
          80,
          68,
          70,
        ]);
      },
    );

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

    test('loadSkillFromDir requires frontmatter delimiter at byte 0', () async {
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

      expect(
        () => loadSkillFromDir(skillDir.path),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('must start with YAML frontmatter'),
          ),
        ),
      );
    });

    test(
      'loadSkillFromDir closes frontmatter on first subsequent --- substring',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk-skill-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
        skillDir.createSync(recursive: true);

        _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: "A---B"
---
Body
''');

        expect(
          () => loadSkillFromDir(skillDir.path),
          throwsA(isA<FormatException>()),
        );
      },
    );

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

    test('listSkillsInDir returns only valid skills', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-skill-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final Directory validDir = Directory(
        _join(tempDir.path, 'weather-skill'),
      );
      validDir.createSync(recursive: true);
      _writeFile(_join(validDir.path, 'SKILL.md'), '''
---
name: weather-skill
description: Reads weather data
---
Weather instructions
''');

      final Directory invalidDir = Directory(_join(tempDir.path, 'bad-skill'));
      invalidDir.createSync(recursive: true);
      _writeFile(_join(invalidDir.path, 'SKILL.md'), '''
---
name: renamed-skill
description: Invalid skill
---
Bad instructions
''');

      final Directory missingManifest = Directory(
        _join(tempDir.path, 'no-manifest'),
      );
      missingManifest.createSync(recursive: true);

      final Map<String, Frontmatter> skills = listSkillsInDir(tempDir.path);
      expect(skills.keys, <String>['weather-skill']);
      expect(skills['weather-skill']?.description, 'Reads weather data');
    });

    test('listSkillsInGcsDir returns only valid skills', () async {
      final _FakeSkillGcsStore store = _FakeSkillGcsStore(
        <String, Map<String, List<int>>>{
          'skills-bucket': <String, List<int>>{
            'skills/weather-skill/SKILL.md': utf8.encode('''
---
name: weather-skill
description: Reads weather data
---
Weather instructions
'''),
            'skills/bad-skill/SKILL.md': utf8.encode('''
---
name: renamed-skill
description: Invalid skill
---
Bad instructions
'''),
          },
        },
      );

      final Map<String, Frontmatter> skills = await listSkillsInGcsDir(
        'skills-bucket',
        skillsBasePath: 'skills',
        storageStore: store,
      );
      expect(skills.keys, <String>['weather-skill']);
      expect(skills['weather-skill']?.description, 'Reads weather data');
    });

    test('loadSkillFromGcsDir loads text and binary resources', () async {
      final _FakeSkillGcsStore store = _FakeSkillGcsStore(
        <String, Map<String, List<int>>>{
          'skills-bucket': <String, List<int>>{
            'skills/weather-skill/SKILL.md': utf8.encode('''
---
name: weather-skill
description: Reads weather data
metadata:
  adk_additional_tools:
    - extra_tool
---
Weather instructions
'''),
            'skills/weather-skill/references/guide.md': utf8.encode('guide'),
            'skills/weather-skill/assets/template.txt': utf8.encode('template'),
            'skills/weather-skill/assets/file.pdf': <int>[37, 80, 68, 70],
            'skills/weather-skill/scripts/setup.sh': utf8.encode('echo setup'),
            'skills/weather-skill/scripts/binary.bin': <int>[0, 159, 146, 150],
          },
        },
      );

      final Skill skill = await loadSkillFromGcsDir(
        'skills-bucket',
        'weather-skill',
        skillsBasePath: 'skills',
        storageStore: store,
      );

      expect(skill.name, 'weather-skill');
      expect(skill.instructions, 'Weather instructions');
      expect(skill.frontmatter.metadata['adk_additional_tools'], <String>[
        'extra_tool',
      ]);
      expect(skill.resources.getReference('guide.md'), 'guide');
      expect(skill.resources.getAsset('template.txt'), 'template');
      expect(skill.resources.getAssetBytes('file.pdf'), <int>[37, 80, 68, 70]);
      expect(skill.resources.getScript('setup.sh')?.src, 'echo setup');
      expect(skill.resources.getScript('binary.bin'), isNull);
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

    test(
      'loadSkillFromDir surfaces filesystem read errors from resources',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('permission test is Unix-specific');
          return;
        }

        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk-skill-test-',
        );
        addTearDown(() async {
          final File blocked = File(
            _join(_join(tempDir.path, 'my-skill'), 'references/blocked.md'),
          );
          if (await blocked.exists()) {
            await Process.run('chmod', <String>['644', blocked.path]);
          }
          await tempDir.delete(recursive: true);
        });

        final Directory skillDir = Directory(_join(tempDir.path, 'my-skill'));
        skillDir.createSync(recursive: true);
        _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: my-skill
description: A skill
---
Body
''');

        final String blockedPath = _join(
          skillDir.path,
          'references/blocked.md',
        );
        _writeFile(blockedPath, 'secret');
        final ProcessResult chmodResult = await Process.run('chmod', <String>[
          '000',
          blockedPath,
        ]);
        if (chmodResult.exitCode != 0) {
          markTestSkipped('chmod is unavailable in current environment');
          return;
        }

        expect(
          () => loadSkillFromDir(skillDir.path),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });
}
