import 'dart:collection';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _RecordedHttpRequest {
  _RecordedHttpRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _QueuedHttpClient extends http.BaseClient {
  _QueuedHttpClient({required List<http.Response> responses})
    : _responses = Queue<http.Response>.from(responses);

  final Queue<http.Response> _responses;
  final List<_RecordedHttpRequest> recordedRequests = <_RecordedHttpRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_responses.isEmpty) {
      throw StateError('No queued response available for ${request.url}.');
    }
    final http.Response nextResponse = _responses.removeFirst();
    final List<int> bodyBytes = await request.finalize().toBytes();
    recordedRequests.add(
      _RecordedHttpRequest(
        uri: request.url,
        headers: Map<String, String>.from(request.headers),
        body: utf8.decode(bodyBytes),
      ),
    );
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode(nextResponse.body),
      ]),
      nextResponse.statusCode,
      headers: <String, String>{
        'content-type': 'application/json',
        ...nextResponse.headers,
      },
    );
  }
}

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

    test('http api client shapes requests and parses retrieval rows', () async {
      final _QueuedHttpClient httpClient = _QueuedHttpClient(
        responses: <http.Response>[
          http.Response('{}', 200),
          http.Response('{}', 200),
          http.Response('{}', 200),
          http.Response(
            jsonEncode(<String, Object?>{
              'memories': <Object?>[
                <String, Object?>{
                  'fact': 'remember this',
                  'update_time': '2026-02-01T00:00:00Z',
                },
              ],
            }),
            200,
          ),
        ],
      );
      final VertexAiMemoryBankHttpApiClient client =
          VertexAiMemoryBankHttpApiClient(
            project: 'proj',
            location: 'us-central1',
            apiKey: 'api-key',
            httpClient: httpClient,
            accessTokenProvider: () async => 'access-token',
          );

      await client.generateFromEventTexts(
        agentEngineId: '123',
        appName: 'app',
        userId: 'u1',
        eventTexts: <String>['hello memory'],
        config: <String, Object?>{'wait_for_completion': false},
      );
      await client.generateFromDirectMemories(
        agentEngineId: '123',
        appName: 'app',
        userId: 'u1',
        directMemories: <String>['fact one'],
        config: <String, Object?>{'wait_for_completion': false},
      );
      await client.createMemory(
        agentEngineId: '123',
        appName: 'app',
        userId: 'u1',
        fact: 'manual fact',
        config: <String, Object?>{'wait_for_completion': false},
      );
      final List<VertexAiRetrievedMemory> retrieved = await client
          .retrieve(
            agentEngineId: '123',
            appName: 'app',
            userId: 'u1',
            query: 'remember',
          )
          .toList();

      expect(httpClient.recordedRequests, hasLength(4));
      expect(
        httpClient.recordedRequests.first.uri.toString(),
        contains(':generateMemories'),
      );
      expect(
        httpClient.recordedRequests.first.uri.queryParameters['key'],
        'api-key',
      );
      expect(
        httpClient.recordedRequests.first.headers['authorization'],
        'Bearer access-token',
      );
      final Map<String, Object?> firstPayload =
          (jsonDecode(httpClient.recordedRequests.first.body) as Map).map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
      expect(firstPayload['scope'], <String, Object?>{
        'app_name': 'app',
        'user_id': 'u1',
      });
      expect(
        (firstPayload['direct_contents_source'] as Map)['events'],
        isA<List<Object?>>(),
      );

      expect(retrieved, hasLength(1));
      expect(retrieved.first.fact, 'remember this');
      expect(
        retrieved.first.updateTime.toUtc().toIso8601String(),
        startsWith('2026-02-01T00:00:00'),
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
