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
  });

  group('gcs artifact service parity', () {
    test('saves/loads/lists versions and metadata using gcs naming', () async {
      final GcsArtifactService service = GcsArtifactService('bucket-a');

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
      final GcsArtifactService service = GcsArtifactService('bucket-a');

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
  });
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
