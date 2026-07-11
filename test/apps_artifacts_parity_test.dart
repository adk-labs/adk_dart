import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('apps summarizer parity', () {
    test('llm event summarizer compacts events into summary event', () async {
      final _FakeLlm llm = _FakeLlm(
        response: LlmResponse(content: Content.userText('short summary')),
      );
      final LlmEventSummarizer summarizer = LlmEventSummarizer(llm: llm);

      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'user',
          timestamp: 10,
          content: Content.userText('Hello there'),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'agent',
          timestamp: 20,
          content: Content.modelText('How can I help?'),
        ),
      ];

      final Event? summarized = await summarizer.maybeSummarizeEvents(
        events: events,
      );

      expect(summarized, isNotNull);
      expect(summarized!.actions.compaction, isNotNull);
      expect(summarized.actions.compaction!.startTimestamp, 10);
      expect(summarized.actions.compaction!.endTimestamp, 20);
      expect(summarized.actions.compaction!.compactedContent.role, 'model');
      expect(
        summarized.actions.compaction!.compactedContent.parts.first.text,
        'short summary',
      );
    });

    test('llm event summarizer returns null on empty events', () async {
      final _FakeLlm llm = _FakeLlm(response: LlmResponse());
      final LlmEventSummarizer summarizer = LlmEventSummarizer(llm: llm);

      final Event? summarized = await summarizer.maybeSummarizeEvents(
        events: const <Event>[],
      );
      expect(summarized, isNull);
    });
  });

  group('artifact util parity', () {
    test('parse/get artifact uri for session and user scopes', () {
      final String sessionUri = getArtifactUri(
        'app',
        'user',
        'file.txt',
        3,
        sessionId: 's1',
      );
      final ParsedArtifactUri? parsedSession = parseArtifactUri(sessionUri);
      expect(parsedSession, isNotNull);
      expect(parsedSession!.sessionId, 's1');
      expect(parsedSession.version, 3);

      final String userUri = getArtifactUri('app', 'user', 'user:file.txt', 2);
      final ParsedArtifactUri? parsedUser = parseArtifactUri(userUri);
      expect(parsedUser, isNotNull);
      expect(parsedUser!.sessionId, isNull);
      expect(parsedUser.version, 2);

      expect(
        isArtifactRef(
          Part.fromFileData(fileUri: sessionUri, mimeType: 'text/plain'),
        ),
        isTrue,
      );
    });
  });

  group('file artifact service parity', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adk_file_artifacts_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves/loads text artifacts with versioning', () async {
      final FileArtifactService service = FileArtifactService(tempDir.path);

      final int v0 = await service.saveArtifact(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/today.txt',
        artifact: Part.text('v0'),
      );
      final int v1 = await service.saveArtifact(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/today.txt',
        artifact: Part.text('v1'),
      );

      expect(v0, 0);
      expect(v1, 1);

      final Part? latest = await service.loadArtifact(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/today.txt',
      );
      expect(latest!.text, 'v1');

      final List<int> versions = await service.listVersions(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/today.txt',
      );
      expect(versions, <int>[0, 1]);

      final List<ArtifactVersion> metadata = await service.listArtifactVersions(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/today.txt',
      );
      expect(metadata, hasLength(2));
      expect(metadata.last.canonicalUri, startsWith('file://'));

      final ArtifactVersion? lastVersion = await service.getArtifactVersion(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/today.txt',
      );
      expect(lastVersion!.version, 1);
    });

    test('supports user scoped artifacts and key listing', () async {
      final FileArtifactService service = FileArtifactService(tempDir.path);

      await service.saveArtifact(
        appName: 'app',
        userId: 'user1',
        filename: 'user:shared/profile.json',
        artifact: Part.text('{"name":"adk"}'),
      );
      await service.saveArtifact(
        appName: 'app',
        userId: 'user1',
        sessionId: 'session-a',
        filename: 'session-only.txt',
        artifact: Part.text('session data'),
      );

      final List<String> all = await service.listArtifactKeys(
        appName: 'app',
        userId: 'user1',
        sessionId: 'session-a',
      );

      expect(all, contains('user:shared/profile.json'));
      expect(all, contains('session-only.txt'));
    });

    test('rejects path traversal filename', () async {
      final FileArtifactService service = FileArtifactService(tempDir.path);

      expect(
        () => service.saveArtifact(
          appName: 'app',
          userId: 'user1',
          sessionId: 's1',
          filename: '../escape.txt',
          artifact: Part.text('nope'),
        ),
        throwsA(isA<InputValidationError>()),
      );
    });

    test('rejects metadata canonical uri fallback outside root dir', () async {
      final FileArtifactService service = FileArtifactService(tempDir.path);
      await service.saveArtifact(
        appName: 'app',
        userId: 'user1',
        sessionId: 's1',
        filename: 'notes/outside.txt',
        artifact: Part.text('safe'),
      );

      final File payload = File(
        '${tempDir.path}/users/user1/sessions/s1/artifacts/notes/outside.txt/versions/0/outside.txt',
      );
      expect(payload.existsSync(), isTrue);
      payload.deleteSync();

      final Directory outside = Directory.systemTemp.createTempSync(
        'adk_artifact_outside_',
      );
      addTearDown(() {
        if (outside.existsSync()) {
          outside.deleteSync(recursive: true);
        }
      });
      final File outsideFile = File('${outside.path}/outside.txt')
        ..writeAsStringSync('outside');

      final File metadataFile = File(
        '${tempDir.path}/users/user1/sessions/s1/artifacts/notes/outside.txt/versions/0/metadata.json',
      );
      final Map<String, Object?> metadata =
          (jsonDecode(metadataFile.readAsStringSync()) as Map).map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
      metadata['canonical_uri'] = outsideFile.absolute.uri.toString();
      metadataFile.writeAsStringSync(jsonEncode(metadata));

      expect(
        () => service.loadArtifact(
          appName: 'app',
          userId: 'user1',
          sessionId: 's1',
          filename: 'notes/outside.txt',
        ),
        throwsA(isA<InputValidationError>()),
      );
    });
  });

  group('gcs artifact service parity', () {
    test('saves/loads/lists versions and metadata using gcs naming', () async {
      final GcsArtifactService service = GcsArtifactService.inMemory(
        'bucket-a',
      );

      final int v0 = await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'file.bin',
        artifact: Part.fromInlineData(
          mimeType: 'application/octet-stream',
          data: <int>[1, 2, 3],
        ),
        customMetadata: <String, Object?>{'k': 'v'},
      );
      expect(v0, 0);

      final Part? loaded = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'file.bin',
      );
      expect(loaded, isNotNull);
      expect(loaded!.inlineData!.data, <int>[1, 2, 3]);

      final List<int> versions = await service.listVersions(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'file.bin',
      );
      expect(versions, <int>[0]);

      final ArtifactVersion? metadata = await service.getArtifactVersion(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'file.bin',
      );
      expect(metadata, isNotNull);
      expect(metadata!.canonicalUri, startsWith('gs://bucket-a/'));
      expect(metadata.customMetadata['k'], 'v');

      final List<String> keys = await service.listArtifactKeys(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );
      expect(keys, contains('file.bin'));

      await service.deleteArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'file.bin',
      );
      expect(
        await service.listVersions(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'file.bin',
        ),
        isEmpty,
      );
    });

    test('user namespace does not require session id', () async {
      final GcsArtifactService service = GcsArtifactService.inMemory(
        'bucket-a',
      );

      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        filename: 'user:shared.txt',
        artifact: Part.text('shared'),
      );

      final List<String> keys = await service.listArtifactKeys(
        appName: 'app',
        userId: 'u1',
      );
      expect(keys, contains('user:shared.txt'));
    });

    test('supports fileData artifacts and preserves canonical uri', () async {
      final GcsArtifactService service = GcsArtifactService.inMemory(
        'bucket-a',
      );

      final int version = await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'docs/report.pdf',
        artifact: Part.fromFileData(
          fileUri: 'gs://external-bucket/docs/report.pdf',
          mimeType: 'application/pdf',
        ),
      );
      expect(version, 0);

      final Part? loaded = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'docs/report.pdf',
      );
      expect(loaded, isNotNull);
      expect(loaded!.fileData, isNotNull);
      expect(loaded.fileData!.fileUri, 'gs://external-bucket/docs/report.pdf');
      expect(loaded.fileData!.mimeType, 'application/pdf');

      final ArtifactVersion? metadata = await service.getArtifactVersion(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'docs/report.pdf',
      );
      expect(metadata, isNotNull);
      expect(metadata!.canonicalUri, 'gs://external-bucket/docs/report.pdf');
      expect(metadata.mimeType, 'application/pdf');
    });

    test('rejects fileData artifacts with empty uri', () async {
      final GcsArtifactService service = GcsArtifactService.inMemory(
        'bucket-a',
      );

      expect(
        () => service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'bad.dat',
          artifact: Part.fromFileData(fileUri: '   '),
        ),
        throwsA(isA<InputValidationError>()),
      );
    });

    test('live mode provides default backend bridge wiring', () {
      expect(() => GcsArtifactService('bucket-a'), returnsNormally);
      expect(
        () => GcsArtifactService(
          'bucket-a',
          mode: GcsArtifactMode.live,
          httpRequestProvider: (_) async => GcsArtifactHttpResponse(
            statusCode: 200,
            bodyBytes: utf8.encode('{}'),
          ),
        ),
        returnsNormally,
      );
    });

    test(
      'live mode fails fast when auth provider returns no headers',
      () async {
        final GcsArtifactService service = GcsArtifactService(
          'bucket-a',
          mode: GcsArtifactMode.live,
          authHeadersProvider: () async => <String, String>{},
          httpRequestProvider: (_) async => GcsArtifactHttpResponse(
            statusCode: 200,
            bodyBytes: utf8.encode('{}'),
          ),
        );

        await expectLater(
          service.listArtifactKeys(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('live mode wires bucket/object paths and auth headers', () async {
      final List<GcsArtifactHttpRequest> captured = <GcsArtifactHttpRequest>[];
      final GcsArtifactService service = GcsArtifactService(
        'bucket-a',
        mode: GcsArtifactMode.live,
        authHeadersProvider: () async => <String, String>{
          'authorization': 'Bearer token-1',
        },
        httpRequestProvider: (GcsArtifactHttpRequest request) async {
          captured.add(request);
          if (request.method == 'GET' &&
              request.uri.path == '/storage/v1/b/bucket-a/o' &&
              request.uri.queryParameters['prefix'] == 'app/u1/s1/file.bin/') {
            return GcsArtifactHttpResponse(
              statusCode: 200,
              bodyBytes: utf8.encode('{}'),
            );
          }
          if (request.method == 'POST' &&
              request.uri.path == '/upload/storage/v1/b/bucket-a/o' &&
              request.uri.queryParameters['uploadType'] == 'media' &&
              request.uri.queryParameters['name'] == 'app/u1/s1/file.bin/0') {
            return GcsArtifactHttpResponse(
              statusCode: 200,
              bodyBytes: utf8.encode(
                '{"name":"app/u1/s1/file.bin/0","contentType":"text/plain"}',
              ),
            );
          }
          if (request.method == 'GET' &&
              request.uri.path == '/storage/v1/b/bucket-a/o' &&
              request.uri.queryParameters['prefix'] == 'app/u1/s1/') {
            return GcsArtifactHttpResponse(
              statusCode: 200,
              bodyBytes: utf8.encode(
                '{"items":[{"name":"app/u1/s1/file.bin/0"}]}',
              ),
            );
          }
          if (request.method == 'GET' &&
              request.uri.path == '/storage/v1/b/bucket-a/o' &&
              request.uri.queryParameters['prefix'] == 'app/u1/user/') {
            return GcsArtifactHttpResponse(
              statusCode: 200,
              bodyBytes: utf8.encode('{}'),
            );
          }
          throw StateError(
            'Unexpected request: ${request.method} ${request.uri}',
          );
        },
      );

      final int savedVersion = await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'file.bin',
        artifact: Part.text('hello'),
      );
      expect(savedVersion, 0);

      final List<String> keys = await service.listArtifactKeys(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );
      expect(keys, <String>['file.bin']);
      expect(captured, isNotEmpty);
      expect(
        captured.every(
          (GcsArtifactHttpRequest request) =>
              request.headers['authorization'] == 'Bearer token-1',
        ),
        isTrue,
      );
    });

    test('canonicalizes gs uris for bucket and fileData artifacts', () async {
      final GcsArtifactService service = GcsArtifactService.inMemory(
        '  gs://bucket-a/  ',
      );

      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'text.txt',
        artifact: Part.text('v0'),
      );
      final ArtifactVersion? sessionVersion = await service.getArtifactVersion(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'text.txt',
      );
      expect(sessionVersion, isNotNull);
      expect(sessionVersion!.canonicalUri, startsWith('gs://bucket-a/'));

      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'docs/report.pdf',
        artifact: Part.fromFileData(
          fileUri: '  gs://external-bucket//docs///report.pdf  ',
          mimeType: 'application/pdf',
        ),
      );
      final Part? loaded = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'docs/report.pdf',
      );
      expect(loaded, isNotNull);
      expect(loaded!.fileData, isNotNull);
      expect(loaded.fileData!.fileUri, 'gs://external-bucket/docs/report.pdf');

      final ArtifactVersion? metadata = await service.getArtifactVersion(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'docs/report.pdf',
      );
      expect(metadata, isNotNull);
      expect(metadata!.canonicalUri, 'gs://external-bucket/docs/report.pdf');
    });
  });

  group('file artifact service path segment validation parity', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adk_file_segment_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final String userId in <String>[
      '../escape',
      '../../etc',
      'foo/../../bar',
      'valid/../..',
      '..',
      '.',
      'has/slash',
      'back\\slash',
      'null\x00byte',
      '',
    ]) {
      test('rejects traversal in user_id (${jsonEncode(userId)})', () async {
        final FileArtifactService service = FileArtifactService(tempDir.path);

        expect(
          () => service.saveArtifact(
            appName: 'myapp',
            userId: userId,
            sessionId: 'sess123',
            filename: 'safe.txt',
            artifact: Part.text('content'),
          ),
          throwsA(isA<InputValidationError>()),
        );
      });
    }

    for (final String sessionId in <String>[
      '../escape',
      '../../tmp',
      'foo/../../bar',
      '..',
      '.',
      'has/slash',
      'back\\slash',
      'null\x00byte',
    ]) {
      test(
        'rejects traversal in session_id (${jsonEncode(sessionId)})',
        () async {
          final FileArtifactService service = FileArtifactService(tempDir.path);

          expect(
            () => service.saveArtifact(
              appName: 'myapp',
              userId: 'user123',
              sessionId: sessionId,
              filename: 'safe.txt',
              artifact: Part.text('content'),
            ),
            throwsA(isA<InputValidationError>()),
          );
        },
      );
    }
  });

  group('file uri path normalization parity', () {
    test('windows-style file uri maps to native path via File.fromUri', () {
      // Mirrors Python's _file_uri_to_path Windows normalization. Dart's
      // File.fromUri is platform-aware, so a canonical file URI resolves to the
      // correct native path (equivalent to Python url2pathname on Windows).
      final Uri parsed = Uri.parse('file:///C:/tmp/adk%20artifacts');
      expect(parsed.scheme, 'file');
      expect(parsed.toFilePath(windows: true), r'C:\tmp\adk artifacts');
      expect(parsed.toFilePath(windows: false), '/C:/tmp/adk artifacts');
    });

    test('non-file uri is not treated as a filesystem path', () {
      final Uri parsed = Uri.parse('gs://bucket/adk_artifacts');
      expect(parsed.scheme, isNot('file'));
    });
  });

  group('artifact reference scope validation parity', () {
    BaseArtifactService inMemoryService() => InMemoryArtifactService();
    BaseArtifactService gcsService() => GcsArtifactService.inMemory('bucket-a');

    for (final MapEntry<String, BaseArtifactService Function()> entry
        in <String, BaseArtifactService Function()>{
          'in_memory': inMemoryService,
          'gcs': gcsService,
        }.entries) {
      final String label = entry.key;
      final BaseArtifactService Function() factory = entry.value;

      test('allows references inside the same session scope ($label)', () async {
        final BaseArtifactService service = factory();

        await service.saveArtifact(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess0',
          filename: 'source.txt',
          artifact: Part.text('hello'),
        );

        final Part ref = Part.fromFileData(
          fileUri:
              'artifact://apps/app0/users/user0/sessions/sess0/'
              'artifacts/source.txt/versions/0',
          mimeType: 'text/plain',
        );
        await service.saveArtifact(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess0',
          filename: 'ref.txt',
          artifact: ref,
        );

        final Part? loaded = await service.loadArtifact(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess0',
          filename: 'ref.txt',
        );
        expect(loaded, isNotNull);
        expect(_dereferencedText(loaded!), 'hello');
      });

      test(
        'allows references to user-scoped files from same user ($label)',
        () async {
          final BaseArtifactService service = factory();

          await service.saveArtifact(
            appName: 'app0',
            userId: 'user0',
            sessionId: 'sess0',
            filename: 'user:profile.txt',
            artifact: Part.text('profile'),
          );

          final Part ref = Part.fromFileData(
            fileUri:
                'artifact://apps/app0/users/user0/artifacts/'
                'user:profile.txt/versions/0',
            mimeType: 'text/plain',
          );
          await service.saveArtifact(
            appName: 'app0',
            userId: 'user0',
            sessionId: 'sess1',
            filename: 'ref.txt',
            artifact: ref,
          );

          final Part? loaded = await service.loadArtifact(
            appName: 'app0',
            userId: 'user0',
            sessionId: 'sess1',
            filename: 'ref.txt',
          );
          expect(loaded, isNotNull);
          expect(_dereferencedText(loaded!), 'profile');
        },
      );

      test('rejects references to different users on save ($label)', () async {
        final BaseArtifactService service = factory();

        await service.saveArtifact(
          appName: 'app0',
          userId: 'victim',
          sessionId: 'victim-sess',
          filename: 'user:secret.txt',
          artifact: Part.text('secret'),
        );

        final Part ref = Part.fromFileData(
          fileUri:
              'artifact://apps/app0/users/victim/artifacts/'
              'user:secret.txt/versions/0',
          mimeType: 'text/plain',
        );
        expect(
          () => service.saveArtifact(
            appName: 'app0',
            userId: 'attacker',
            sessionId: 'attacker-sess',
            filename: 'ref.txt',
            artifact: ref,
          ),
          throwsA(
            isA<InputValidationError>().having(
              (InputValidationError error) => error.message,
              'message',
              contains('same app and user scope'),
            ),
          ),
        );
      });

      test('rejects references to different apps on save ($label)', () async {
        final BaseArtifactService service = factory();

        await service.saveArtifact(
          appName: 'victim-app',
          userId: 'user0',
          sessionId: 'sess0',
          filename: 'user:secret.txt',
          artifact: Part.text('secret'),
        );

        final Part ref = Part.fromFileData(
          fileUri:
              'artifact://apps/victim-app/users/user0/artifacts/'
              'user:secret.txt/versions/0',
          mimeType: 'text/plain',
        );
        expect(
          () => service.saveArtifact(
            appName: 'attacker-app',
            userId: 'user0',
            sessionId: 'sess0',
            filename: 'ref.txt',
            artifact: ref,
          ),
          throwsA(
            isA<InputValidationError>().having(
              (InputValidationError error) => error.message,
              'message',
              contains('same app and user scope'),
            ),
          ),
        );
      });
    }

    test('validateArtifactReferenceScope allows same-scope references', () {
      expect(
        () => validateArtifactReferenceScope(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess0',
          parsedUri: parseArtifactUri(
            'artifact://apps/app0/users/user0/sessions/sess0/'
            'artifacts/source.txt/versions/0',
          )!,
        ),
        returnsNormally,
      );
      // User-scoped references (no session) are allowed across sessions.
      expect(
        () => validateArtifactReferenceScope(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess1',
          parsedUri: parseArtifactUri(
            'artifact://apps/app0/users/user0/artifacts/'
            'user:profile.txt/versions/0',
          )!,
        ),
        returnsNormally,
      );
    });

    test('validateArtifactReferenceScope rejects cross-app/user/session', () {
      expect(
        () => validateArtifactReferenceScope(
          appName: 'attacker-app',
          userId: 'user0',
          sessionId: 'sess0',
          parsedUri: parseArtifactUri(
            'artifact://apps/victim-app/users/user0/artifacts/'
            'user:secret.txt/versions/0',
          )!,
        ),
        throwsA(
          isA<InputValidationError>().having(
            (InputValidationError error) => error.message,
            'message',
            contains('same app and user scope'),
          ),
        ),
      );
      expect(
        () => validateArtifactReferenceScope(
          appName: 'app0',
          userId: 'attacker',
          sessionId: 'sess0',
          parsedUri: parseArtifactUri(
            'artifact://apps/app0/users/victim/artifacts/'
            'user:secret.txt/versions/0',
          )!,
        ),
        throwsA(
          isA<InputValidationError>().having(
            (InputValidationError error) => error.message,
            'message',
            contains('same app and user scope'),
          ),
        ),
      );
      // A session-scoped reference targeting a different session is rejected,
      // mirroring the cross-session-on-load rejection in the Python suite.
      expect(
        () => validateArtifactReferenceScope(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess0',
          parsedUri: parseArtifactUri(
            'artifact://apps/app0/users/user0/sessions/sess1/'
            'artifacts/source.txt/versions/0',
          )!,
        ),
        throwsA(
          isA<InputValidationError>().having(
            (InputValidationError error) => error.message,
            'message',
            contains('same session scope'),
          ),
        ),
      );
    });
  });
}

/// Returns the textual payload of a dereferenced artifact regardless of whether
/// the backend reconstructs it as a text part (in-memory) or as inline bytes
/// (GCS, which stores text as `text/plain` bytes).
String? _dereferencedText(Part part) {
  if (part.text != null) {
    return part.text;
  }
  if (part.inlineData != null) {
    return utf8.decode(part.inlineData!.data);
  }
  return null;
}

class _FakeLlm extends BaseLlm {
  _FakeLlm({required this.response}) : super(model: 'gemini-test');

  final LlmResponse response;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield response;
  }
}
