import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:archive/archive.dart' as archive;
import 'package:test/test.dart';

List<int> _createSkillZip(String skillMdContent) {
  final archive.Archive skillArchive = archive.Archive()
    ..addFile(archive.ArchiveFile.string('SKILL.md', skillMdContent));
  return archive.ZipEncoder().encode(skillArchive);
}

String _encodedSkillZip(String skillMdContent) {
  return base64Encode(_createSkillZip(skillMdContent));
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
  group('GcpSkillRegistry parity', () {
    test('throws when projectId or location is missing', () {
      expect(
        () => GcpSkillRegistry(projectId: '', location: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'getSkill fetches base64 zipped filesystem by full resource name',
      () async {
        final List<Uri> requestedUris = <Uri>[];
        final GcpSkillRegistry registry = GcpSkillRegistry(
          projectId: 'test-project',
          location: 'us-central1',
          apiBaseUri: Uri.parse('https://example.com/v1beta1'),
          authHeadersProvider: _staticAuthHeadersProvider,
          httpPostProvider: _unexpectedPost,
          httpGetProvider:
              (Uri uri, {required Map<String, String> headers}) async {
                requestedUris.add(uri);
                expect(headers, containsPair('Authorization', 'Bearer token'));
                return GcpSkillRegistryHttpResponse(
                  statusCode: 200,
                  body: <String, Object?>{
                    'zippedFilesystem': _encodedSkillZip('''
---
name: my-skill
description: test
---
# My Skill
'''),
                  },
                );
              },
        );

        final Skill skill = await registry.getSkill(name: 'my-skill');

        expect(skill.name, 'my-skill');
        expect(skill.description, 'test');
        expect(skill.instructions, '# My Skill');
        expect(
          requestedUris.single.toString(),
          'https://example.com/v1beta1/projects/test-project/locations/us-central1/skills/my-skill',
        );
      },
    );

    test('searchSkills maps retrieved skill names to frontmatter', () async {
      final List<Uri> requestedUris = <Uri>[];
      final List<Map<String, Object?>> requestedBodies =
          <Map<String, Object?>>[];
      final GcpSkillRegistry registry = GcpSkillRegistry(
        projectId: 'test-project',
        location: 'us-central1',
        apiBaseUri: Uri.parse('https://example.com/v1beta1'),
        authHeadersProvider: _staticAuthHeadersProvider,
        httpGetProvider: _unexpectedGet,
        httpPostProvider:
            (
              Uri uri, {
              required Map<String, String> headers,
              required Map<String, Object?> body,
            }) async {
              requestedUris.add(uri);
              requestedBodies.add(body);
              expect(headers, containsPair('Authorization', 'Bearer token'));
              return GcpSkillRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{
                  'retrievedSkills': <Map<String, Object?>>[
                    <String, Object?>{
                      'skillName':
                          'projects/test-project/locations/us-central1/skills/skill1',
                      'description': 'Description 1',
                    },
                    <String, Object?>{
                      'skill_name':
                          'projects/test-project/locations/us-central1/skills/skill2',
                      'description': 'Description 2',
                    },
                  ],
                },
              );
            },
      );

      final List<Frontmatter> results = await registry.searchSkills(
        query: 'query',
      );

      expect(results.map((Frontmatter item) => item.name), <String>[
        'skill1',
        'skill2',
      ]);
      expect(results.map((Frontmatter item) => item.description), <String>[
        'Description 1',
        'Description 2',
      ]);
      expect(
        requestedUris.single.toString(),
        'https://example.com/v1beta1/projects/test-project/locations/us-central1/skills:retrieve',
      );
      expect(requestedBodies.single, <String, Object?>{'query': 'query'});
    });

    test('getSkill raises when zipped filesystem is missing', () async {
      final GcpSkillRegistry registry = GcpSkillRegistry(
        projectId: 'test-project',
        location: 'us-central1',
        authHeadersProvider: _staticAuthHeadersProvider,
        httpPostProvider: _unexpectedPost,
        httpGetProvider:
            (Uri uri, {required Map<String, String> headers}) async {
              return GcpSkillRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{'zippedFilesystem': ''},
              );
            },
      );

      await expectLater(
        registry.getSkill(name: 'my-skill'),
        _throwsArgumentMessage('does not contain zipped filesystem'),
      );
    });

    test('getSkill rejects zip slip entries', () async {
      final archive.Archive skillArchive = archive.Archive()
        ..addFile(archive.ArchiveFile.string('../evil.txt', 'malicious'))
        ..addFile(
          archive.ArchiveFile.string('SKILL.md', '''
---
name: my-skill
description: test
---
# My Skill
'''),
        );
      final GcpSkillRegistry registry = GcpSkillRegistry(
        projectId: 'test-project',
        location: 'us-central1',
        authHeadersProvider: _staticAuthHeadersProvider,
        httpPostProvider: _unexpectedPost,
        httpGetProvider:
            (Uri uri, {required Map<String, String> headers}) async {
              return GcpSkillRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{
                  'zippedFilesystem': base64Encode(
                    archive.ZipEncoder().encode(skillArchive),
                  ),
                },
              );
            },
      );

      await expectLater(
        registry.getSkill(name: 'my-skill'),
        _throwsArgumentMessage('Dangerous zip entry ignored'),
      );
    });

    test('getSkill rejects invalid manifest skill name', () async {
      final GcpSkillRegistry registry = GcpSkillRegistry(
        projectId: 'test-project',
        location: 'us-central1',
        authHeadersProvider: _staticAuthHeadersProvider,
        httpPostProvider: _unexpectedPost,
        httpGetProvider:
            (Uri uri, {required Map<String, String> headers}) async {
              return GcpSkillRegistryHttpResponse(
                statusCode: 200,
                body: <String, Object?>{
                  'zippedFilesystem': _encodedSkillZip('''
---
name: ../evil
description: test
---
# My Skill
'''),
                },
              );
            },
      );

      await expectLater(
        registry.getSkill(name: 'my-skill'),
        _throwsArgumentMessage('Invalid skill name in SKILL.md'),
      );
    });
  });
}

Future<GcpSkillRegistryHttpResponse> _unexpectedGet(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  fail('Unexpected HTTP GET: $uri');
}

Future<GcpSkillRegistryHttpResponse> _unexpectedPost(
  Uri uri, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
}) async {
  fail('Unexpected HTTP POST: $uri');
}

Future<Map<String, String>> _staticAuthHeadersProvider() async {
  return <String, String>{'Authorization': 'Bearer token'};
}
