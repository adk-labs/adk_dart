import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingMemoryBankClient implements VertexAiMemoryBankApiClient {
  final List<int> directBatchSizes = <int>[];
  final List<String> createdFacts = <String>[];
  final List<String> generatedEventTexts = <String>[];
  final List<Map<String, Object?>> directConfigs = <Map<String, Object?>>[];
  final List<VertexAiRetrievedMemory> retrieved = <VertexAiRetrievedMemory>[];

  @override
  Future<void> createMemory({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String fact,
    required Map<String, Object?> config,
  }) async {
    createdFacts.add(fact);
  }

  @override
  Future<void> generateFromDirectMemories({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<String> directMemories,
    required Map<String, Object?> config,
  }) async {
    directBatchSizes.add(directMemories.length);
    directConfigs.add(Map<String, Object?>.from(config));
  }

  @override
  Future<void> generateFromEventTexts({
    required String agentEngineId,
    required String appName,
    required String userId,
    required List<String> eventTexts,
    required Map<String, Object?> config,
  }) async {
    generatedEventTexts.addAll(eventTexts);
  }

  @override
  Stream<VertexAiRetrievedMemory> retrieve({
    required String agentEngineId,
    required String appName,
    required String userId,
    required String query,
  }) async* {
    for (final VertexAiRetrievedMemory item in retrieved) {
      yield item;
    }
  }
}

class _RecordingRagClient implements VertexAiRagClient {
  final List<Map<String, String>> uploads = <Map<String, String>>[];
  VertexAiRagRetrievalResponse response = VertexAiRagRetrievalResponse();

  @override
  Future<VertexAiRagRetrievalResponse> retrievalQuery({
    required String text,
    List<VertexRagStoreRagResource>? ragResources,
    List<String>? ragCorpora,
    int? similarityTopK,
    double? vectorDistanceThreshold,
  }) async {
    return response;
  }

  @override
  Future<void> uploadFile({
    required String corpusName,
    required String text,
    required String displayName,
  }) async {
    uploads.add(<String, String>{
      'corpus': corpusName,
      'text': text,
      'display_name': displayName,
    });
  }
}

void main() {
  group('vertex memory bank parity', () {
    test('supports in-memory event ingest and search', () async {
      final VertexAiMemoryBankService service = VertexAiMemoryBankService(
        agentEngineId: '123',
      );
      await service.addEventsToMemory(
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content.userText('alpha beta memory'),
          ),
          Event(invocationId: 'inv_2', author: 'user'),
        ],
      );

      final SearchMemoryResponse result = await service.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'alpha',
      );

      expect(result.memories, hasLength(1));
      expect(result.memories.first.content.parts.first.text, contains('alpha'));
    });

    test('uses direct memory batches when consolidation is enabled', () async {
      final _RecordingMemoryBankClient recording = _RecordingMemoryBankClient();
      final VertexAiMemoryBankService service = VertexAiMemoryBankService(
        agentEngineId: 'ae_1',
        clientFactory: ({String? project, String? location, String? apiKey}) {
          return recording;
        },
      );

      final List<MemoryEntry> memories = List<MemoryEntry>.generate(11, (
        int i,
      ) {
        return MemoryEntry(content: Content.userText('fact $i'));
      });

      await service.addMemory(
        appName: 'app',
        userId: 'u1',
        memories: memories,
        customMetadata: <String, Object?>{'enable_consolidation': true},
      );

      expect(recording.directBatchSizes, <int>[5, 5, 1]);
      expect(recording.createdFacts, isEmpty);
    });

    test('validates consolidation flag and memory content', () async {
      final VertexAiMemoryBankService service = VertexAiMemoryBankService(
        agentEngineId: 'ae_2',
      );

      await expectLater(
        service.addMemory(
          appName: 'app',
          userId: 'u1',
          memories: <MemoryEntry>[MemoryEntry(content: Content.userText('ok'))],
          customMetadata: <String, Object?>{'enable_consolidation': 'yes'},
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        service.addMemory(
          appName: 'app',
          userId: 'u1',
          memories: <MemoryEntry>[
            MemoryEntry(
              content: Content(
                role: 'user',
                parts: <Part>[
                  Part.fromInlineData(
                    mimeType: 'image/png',
                    data: <int>[1, 2, 3],
                  ),
                ],
              ),
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('vertex rag memory parity', () {
    test(
      'uploads session transcript payload by app/user/session key',
      () async {
        final _RecordingRagClient ragClient = _RecordingRagClient();
        final VertexAiRagMemoryService service = VertexAiRagMemoryService(
          ragCorpus: 'corpus_1',
          ragClient: ragClient,
        );

        final Session session = Session(
          id: 's1',
          appName: 'app',
          userId: 'u1',
          events: <Event>[
            Event(
              invocationId: 'inv_1',
              author: 'user',
              timestamp: 100,
              content: Content.userText('hello\nworld'),
            ),
          ],
        );

        await service.addSessionToMemory(session);

        expect(ragClient.uploads, hasLength(1));
        expect(ragClient.uploads.first['display_name'], 'app.u1.s1');
        expect(ragClient.uploads.first['text'], contains('hello world'));
      },
    );

    test(
      'search merges overlapping session chunks and filters user scope',
      () async {
        final _RecordingRagClient ragClient = _RecordingRagClient();
        ragClient.response = VertexAiRagRetrievalResponse(
          contexts: <VertexAiRagContext>[
            VertexAiRagContext(
              sourceDisplayName: 'app.u1.s1',
              text:
                  '{"author":"u","timestamp":1,"text":"one"}\n'
                  '{"author":"u","timestamp":2,"text":"two"}',
            ),
            VertexAiRagContext(
              sourceDisplayName: 'app.u1.s1',
              text:
                  '{"author":"u","timestamp":2,"text":"two"}\n'
                  '{"author":"u","timestamp":3,"text":"three"}',
            ),
            VertexAiRagContext(
              sourceDisplayName: 'app.other.s9',
              text: '{"author":"x","timestamp":9,"text":"skip"}',
            ),
          ],
        );

        final VertexAiRagMemoryService service = VertexAiRagMemoryService(
          ragCorpus: 'corpus_1',
          ragClient: ragClient,
        );

        final SearchMemoryResponse result = await service.searchMemory(
          appName: 'app',
          userId: 'u1',
          query: 'two',
        );

        expect(
          result.memories.map((MemoryEntry e) => e.content.parts.first.text),
          <String?>['one', 'two', 'three'],
        );
      },
    );

    test('requires rag resources to be configured', () async {
      final VertexAiRagMemoryService service = VertexAiRagMemoryService(
        ragClient: _RecordingRagClient(),
      );

      await expectLater(
        service.addSessionToMemory(
          Session(
            id: 's1',
            appName: 'app',
            userId: 'u1',
            events: <Event>[
              Event(
                invocationId: 'inv_1',
                author: 'user',
                content: Content.userText('hello'),
              ),
            ],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
