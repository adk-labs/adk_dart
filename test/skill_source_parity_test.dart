import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('SkillSource parity', () {
    test(
      'LocalSkillSource loads frontmatter instructions and resources',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk_skill_source_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final Directory skillDir = Directory(
          _join(tempDir.path, 'weather-skill'),
        )..createSync(recursive: true);
        _writeFile(_join(skillDir.path, 'SKILL.md'), '''
---
name: weather-skill
description: Reads weather data
---
Use weather references.
''');
        _writeFile(_join(skillDir.path, 'references/guide.md'), 'guide');
        _writeFile(_join(skillDir.path, 'assets/data.bin'), <int>[1, 2, 3]);
        _writeFile(_join(tempDir.path, 'secret.txt'), 'outside');

        final LocalSkillSource source = LocalSkillSource(tempDir.path);

        final Map<String, Frontmatter> frontmatters = await source
            .listFrontmatters();
        expect(frontmatters.keys, <String>['weather-skill']);
        expect(
          await source.loadInstructions('weather-skill'),
          'Use weather references.',
        );
        expect(
          await source.listResources('weather-skill', 'references'),
          <String>['references/guide.md'],
        );
        expect(
          utf8.decode(
            await source.loadResource('weather-skill', 'references/guide.md'),
          ),
          'guide',
        );
        expect(
          await source.loadResource('weather-skill', 'assets/data.bin'),
          <int>[1, 2, 3],
        );
        await expectLater(
          source.loadResource('weather-skill', '../secret.txt'),
          throwsA(
            isA<SkillSourceException>().having(
              (SkillSourceException error) => error.toString(),
              'message',
              contains('outside the skill source'),
            ),
          ),
        );
        await expectLater(
          source.listResources('weather-skill', '../'),
          throwsA(
            isA<SkillSourceException>().having(
              (SkillSourceException error) => error.toString(),
              'message',
              contains('outside the skill source'),
            ),
          ),
        );
        await expectLater(
          source.loadInstructions('../weather-skill'),
          throwsA(
            isA<SkillSourceException>().having(
              (SkillSourceException error) => error.toString(),
              'message',
              contains('outside the skill source'),
            ),
          ),
        );
      },
    );

    test('InMemorySkillSource builder matches Java-style access', () async {
      final InMemorySkillSource source = InMemorySkillSource.builder()
          .skill('weather-skill')
          .frontmatter(
            Frontmatter(
              name: 'weather-skill',
              description: 'Reads weather data',
            ),
          )
          .instructions('Use weather references.')
          .addResource('references/guide.md', 'guide')
          .addResource('assets/data.bin', <int>[1, 2, 3])
          .build();

      expect(
        (await source.listFrontmatters())['weather-skill']?.description,
        'Reads weather data',
      );
      expect(await source.listResources('weather-skill', 'assets'), <String>[
        'assets/data.bin',
      ]);
      expect(
        await source.loadInstructions('weather-skill'),
        'Use weather references.',
      );
      expect(
        utf8.decode(
          await source.loadResource('weather-skill', 'references/guide.md'),
        ),
        'guide',
      );
    });
  });
}

void _writeFile(String path, Object content) {
  final File file = File(path)..parent.createSync(recursive: true);
  if (content is List<int>) {
    file.writeAsBytesSync(content);
  } else {
    file.writeAsStringSync('$content');
  }
}

String _join(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}
