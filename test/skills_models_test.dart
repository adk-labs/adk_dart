import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

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
  group('Frontmatter model', () {
    test('stores valid fields', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'test-skill',
        description: 'Test description',
        license: 'Apache 2.0',
        compatibility: 'test',
        allowedTools: 'test',
        metadata: <String, String>{'key': 'value'},
      );

      expect(frontmatter.name, 'test-skill');
      expect(frontmatter.description, 'Test description');
      expect(frontmatter.license, 'Apache 2.0');
      expect(frontmatter.compatibility, 'test');
      expect(frontmatter.allowedTools, 'test');
      expect(frontmatter.metadata, <String, String>{'key': 'value'});
    });

    test('allows extra fields through fromMap', () {
      final Frontmatter frontmatter = Frontmatter.fromMap(<String, Object?>{
        'name': 'my-skill',
        'description': 'desc',
        'unknown_field': 'value',
      });
      expect(frontmatter.name, 'my-skill');
      expect(frontmatter.extraFields['unknown_field'], 'value');
      expect(frontmatter.toMap()['unknown_field'], 'value');
    });

    test('applies NFKC-like normalization for full-width letters', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'ｍｙ-skill',
        description: 'desc',
      );
      expect(frontmatter.name, 'my-skill');
    });

    test('applies full NFKC normalization for compatibility characters', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'my﹣ﬀoo',
        description: 'desc',
      );
      expect(frontmatter.name, 'my-ffoo');
    });

    test('reads allowed-tools alias in fromMap', () {
      final Frontmatter frontmatter = Frontmatter.fromMap(<String, Object?>{
        'name': 'my-skill',
        'description': 'desc',
        'allowed-tools': 'tool-pattern',
      });
      expect(frontmatter.allowedTools, 'tool-pattern');
    });

    test('writes allowed-tools with byAlias map output', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'my-skill',
        description: 'desc',
        allowedTools: 'tool-pattern',
      );
      final Map<String, Object?> dumped = frontmatter.toMap(byAlias: true);
      expect(dumped['allowed-tools'], 'tool-pattern');
    });

    test('rejects name longer than 64 chars', () {
      expect(
        () => Frontmatter(name: 'a' * 65, description: 'desc'),
        _throwsArgumentMessage('at most 64 characters'),
      );
    });

    test('rejects uppercase name', () {
      expect(
        () => Frontmatter(name: 'My-Skill', description: 'desc'),
        _throwsArgumentMessage('lowercase kebab-case'),
      );
    });

    test('rejects leading hyphen', () {
      expect(
        () => Frontmatter(name: '-my-skill', description: 'desc'),
        _throwsArgumentMessage('lowercase kebab-case'),
      );
    });

    test('rejects trailing hyphen', () {
      expect(
        () => Frontmatter(name: 'my-skill-', description: 'desc'),
        _throwsArgumentMessage('lowercase kebab-case'),
      );
    });

    test('rejects consecutive hyphens', () {
      expect(
        () => Frontmatter(name: 'my--skill', description: 'desc'),
        _throwsArgumentMessage('lowercase kebab-case'),
      );
    });

    test('rejects underscore in name', () {
      expect(
        () => Frontmatter(name: 'my_skill', description: 'desc'),
        _throwsArgumentMessage('lowercase kebab-case'),
      );
    });

    test('rejects ampersand in name', () {
      expect(
        () => Frontmatter(name: 'skill&name', description: 'desc'),
        _throwsArgumentMessage('lowercase kebab-case'),
      );
    });

    test('accepts valid kebab-case name', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'my-skill-2',
        description: 'desc',
      );
      expect(frontmatter.name, 'my-skill-2');
    });

    test('accepts single word name', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'skill',
        description: 'desc',
      );
      expect(frontmatter.name, 'skill');
    });

    test('rejects empty description', () {
      expect(
        () => Frontmatter(name: 'my-skill', description: ''),
        _throwsArgumentMessage('must not be empty'),
      );
    });

    test('rejects too long description', () {
      expect(
        () => Frontmatter(name: 'my-skill', description: 'x' * 1025),
        _throwsArgumentMessage('at most 1024 characters'),
      );
    });

    test('rejects too long compatibility', () {
      expect(
        () => Frontmatter(
          name: 'my-skill',
          description: 'desc',
          compatibility: 'c' * 501,
        ),
        _throwsArgumentMessage('at most 500 characters'),
      );
    });
  });

  group('Resource models', () {
    test('resources getters and listing', () {
      final Resources resources = Resources(
        references: <String, String>{'ref1': 'ref content'},
        assets: <String, String>{'asset1': 'asset content'},
        scripts: <String, Script>{'script1': Script(src: "print('hello')")},
      );

      expect(resources.getReference('ref1'), 'ref content');
      expect(resources.getAsset('asset1'), 'asset content');
      expect(resources.getScript('script1')?.src, "print('hello')");
      expect(resources.getReference('ref2'), isNull);
      expect(resources.getAsset('asset2'), isNull);
      expect(resources.getScript('script2'), isNull);
      expect(resources.listReferences(), <String>['ref1']);
      expect(resources.listAssets(), <String>['asset1']);
      expect(resources.listScripts(), <String>['script1']);
    });

    test('skill exposes frontmatter properties', () {
      final Frontmatter frontmatter = Frontmatter(
        name: 'my-skill',
        description: 'my description',
      );
      final Skill skill = Skill(
        frontmatter: frontmatter,
        instructions: 'do this',
      );
      expect(skill.name, 'my-skill');
      expect(skill.description, 'my description');
    });

    test('script string conversion returns source', () {
      final Script script = Script(src: "print('hello')");
      expect('$script', "print('hello')");
    });
  });
}
