import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeRetriever implements BaseRetriever {
  _FakeRetriever(this._results);

  final List<RetrievalResult> _results;

  @override
  List<RetrievalResult> retrieve(String query) => _results;
}

Context _newToolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_retrieval',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_retrieval',
      appName: 'app',
      userId: 'u1',
      state: <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

void main() {
  group('retrieval tools parity', () {
    test('BaseRetrievalTool declaration exposes query schema', () {
      final LlamaIndexRetrieval tool = LlamaIndexRetrieval(
        name: 'retrieval',
        description: 'retrieval tool',
        retriever: _FakeRetriever(<RetrievalResult>[
          RetrievalResult(text: 'x'),
        ]),
      );
      final FunctionDeclaration? declaration = tool.getDeclaration();
      expect(declaration, isNotNull);
      final Map<String, dynamic> props = Map<String, dynamic>.from(
        declaration!.parameters['properties']! as Map,
      );
      expect(props.containsKey('query'), isTrue);
    });

    test('LlamaIndexRetrieval returns first retrieval text', () async {
      final LlamaIndexRetrieval tool = LlamaIndexRetrieval(
        name: 'retrieval',
        description: 'retrieval tool',
        retriever: _FakeRetriever(<RetrievalResult>[
          RetrievalResult(text: 'first hit'),
          RetrievalResult(text: 'second hit'),
        ]),
      );
      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'anything'},
        toolContext: _newToolContext(),
      );
      expect(result, 'first hit');
    });

    test(
      'LlamaIndexRetrieval throws when no retrieval results exist',
      () async {
        final LlamaIndexRetrieval tool = LlamaIndexRetrieval(
          name: 'retrieval',
          description: 'retrieval tool',
          retriever: _FakeRetriever(const <RetrievalResult>[]),
        );
        await expectLater(
          () => tool.run(
            args: <String, dynamic>{'query': 'missing'},
            toolContext: _newToolContext(),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'FilesRetrieval indexes local files and serves best match text',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk_retrieval_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });
        final File fileA = File('${tempDir.path}/a.txt');
        final File fileB = File('${tempDir.path}/b.txt');
        await fileA.writeAsString('dart parity retrieval text');
        await fileB.writeAsString('unrelated content');

        final FilesRetrieval tool = FilesRetrieval(
          name: 'files_retrieval',
          description: 'files retrieval',
          inputDir: tempDir.path,
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{'query': 'parity'},
          toolContext: _newToolContext(),
        );
        expect('$result', contains('dart parity retrieval text'));
      },
    );

    test(
      'VertexAiRagRetrieval injects built-in retrieval tool for Gemini 2+',
      () async {
        final VertexAiRagRetrieval tool = VertexAiRagRetrieval(
          name: 'vertex_rag',
          description: 'vertex rag retrieval',
          ragCorpora: <String>['corpus-a'],
          similarityTopK: 3,
        );
        final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

        await tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(request.config.tools, hasLength(1));
        final Map<String, Object?> retrieval = Map<String, Object?>.from(
          request.config.tools!.single.retrieval! as Map,
        );
        final Map<String, Object?> vertexRagStore = Map<String, Object?>.from(
          retrieval['vertexRagStore']! as Map,
        );
        expect(vertexRagStore['ragCorpora'], <String>['corpus-a']);
        expect(vertexRagStore['similarityTopK'], 3);
      },
    );

    test(
      'VertexAiRagRetrieval injects built-in retrieval for Gemini EAP models',
      () async {
        final VertexAiRagRetrieval tool = VertexAiRagRetrieval(
          name: 'vertex_rag',
          description: 'vertex rag retrieval',
          ragCorpora: <String>['corpus-eap'],
        );
        final LlmRequest request = LlmRequest(model: 'gemini-flash-early-exp');

        await tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(request.toolsDict.containsKey('vertex_rag'), isFalse);
        expect(request.config.tools, hasLength(1));
        final Map<String, Object?> retrieval = Map<String, Object?>.from(
          request.config.tools!.single.retrieval! as Map,
        );
        expect(retrieval['vertexRagStore'], isA<Map>());
      },
    );

    test('VertexRagRetrievalTool injects server-side RAG config', () async {
      final VertexRagRetrievalTool tool = VertexRagRetrievalTool(
        ragResources: <VertexAiRagResource>[
          VertexAiRagResource(path: 'projects/p/locations/us/ragCorpora/c1'),
        ],
        vectorDistanceThreshold: 0.4,
      );
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      expect(
        await tool.run(
          args: const <String, dynamic>{},
          toolContext: _newToolContext(),
        ),
        isNull,
      );
      final Map<String, Object?> retrieval = Map<String, Object?>.from(
        request.config.tools!.single.retrieval! as Map,
      );
      final Map<String, Object?> vertexRagStore = Map<String, Object?>.from(
        retrieval['vertexRagStore']! as Map,
      );
      final List<Object?> resources = vertexRagStore['ragResources']! as List;
      expect(
        (resources.single as Map)['ragCorpus'],
        'projects/p/locations/us/ragCorpora/c1',
      );
      expect(vertexRagStore['vectorDistanceThreshold'], 0.4);
    });

    test(
      'VertexAiRagRetrieval falls back to function declaration on non-Gemini2 models',
      () async {
        final VertexAiRagRetrieval tool = VertexAiRagRetrieval(
          name: 'vertex_rag',
          description: 'vertex rag retrieval',
        );
        final LlmRequest request = LlmRequest(model: 'gpt-4.1');

        await tool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(request.toolsDict.containsKey('vertex_rag'), isTrue);
        expect(request.config.tools, isNotNull);
      },
    );

    test(
      'VertexAiRagRetrieval returns fallback message when no handler or empty results',
      () async {
        final VertexAiRagRetrieval noHandler = VertexAiRagRetrieval(
          name: 'vertex_rag',
          description: 'vertex rag retrieval',
        );
        final Object? noHandlerResult = await noHandler.run(
          args: <String, dynamic>{'query': 'hello'},
          toolContext: _newToolContext(),
        );
        expect('$noHandlerResult', contains('No matching result found'));

        final VertexAiRagRetrieval empty = VertexAiRagRetrieval(
          name: 'vertex_rag',
          description: 'vertex rag retrieval',
          queryHandler:
              ({
                required String text,
                List<VertexAiRagResource>? ragResources,
                List<String>? ragCorpora,
                int? similarityTopK,
                double? vectorDistanceThreshold,
              }) async {
                return <String>[];
              },
        );
        final Object? emptyResult = await empty.run(
          args: <String, dynamic>{'query': 'hello'},
          toolContext: _newToolContext(),
        );
        expect('$emptyResult', contains('No matching result found'));
      },
    );

    test(
      'VertexAiRagRetrieval returns list when handler returns contexts',
      () async {
        final VertexAiRagRetrieval tool = VertexAiRagRetrieval(
          name: 'vertex_rag',
          description: 'vertex rag retrieval',
          queryHandler:
              ({
                required String text,
                List<VertexAiRagResource>? ragResources,
                List<String>? ragCorpora,
                int? similarityTopK,
                double? vectorDistanceThreshold,
              }) async {
                expect(text, 'hello');
                return <String>['context-1', 'context-2'];
              },
        );
        final Object? result = await tool.run(
          args: <String, dynamic>{'query': 'hello'},
          toolContext: _newToolContext(),
        );
        expect(result, <String>['context-1', 'context-2']);
      },
    );
  });
}
