import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/environment/environment.dart' as env_pkg;
import 'package:adk_dart/src/errors/already_exists_error.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/integrations/daytona/daytona.dart' as daytona_pkg;
import 'package:adk_dart/src/integrations/e2b/e2b_environment.dart';
import 'package:adk_dart/src/integrations/firestore/firestore.dart';
import 'package:adk_dart/src/integrations/fsspec/fsspec.dart';
import 'package:adk_dart/src/integrations/openai/openai.dart';
import 'package:adk_dart/src/integrations/redis/redis.dart';
import 'package:adk_dart/src/integrations/teams/teams.dart';
import 'package:adk_dart/src/labs/antigravity/antigravity.dart';
import 'package:adk_dart/src/labs/classifiers/classifiers.dart';
import 'package:adk_dart/src/memory/base_memory_service.dart';
import 'package:adk_dart/src/models/apigee_llm.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/base_llm_connection.dart';
import 'package:adk_dart/src/models/cache_metadata.dart';
import 'package:adk_dart/src/models/gemini_llm_connection.dart';
import 'package:adk_dart/src/models/gemma_llm.dart';
import 'package:adk_dart/src/models/google_llm.dart';
import 'package:adk_dart/src/models/interactions_utils.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/plugins/bigquery_agent_analytics_plugin.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/telemetry/metrics.dart';
import 'package:adk_dart/src/telemetry/tracing.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeDecisionsClient implements OpenAIDecisionsClient {
  Map<String, Object?>? lastRequest;
  double? lastTimeout;
  Map<String, Object?> nextResponse = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> createDecision(
    Map<String, Object?> body, {
    double? timeout,
  }) async {
    lastRequest = body;
    lastTimeout = timeout;
    return nextResponse;
  }
}

class _StaticReplyModel extends BaseLlm {
  _StaticReplyModel(this.replyText) : super(model: 'static-model');

  final String replyText;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part(text: 'internal reasoning', thought: true),
          Part.text(replyText),
        ],
      ),
      turnComplete: true,
    );
  }
}

class _ErrorModel extends BaseLlm {
  _ErrorModel() : super(model: 'error-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      errorCode: 'RATE_LIMIT',
      errorMessage: 'Quota exceeded',
      turnComplete: true,
    );
  }
}

class _RecordingLiveSession extends GeminiLiveSession {
  final List<List<Content>> sentTurns = <List<Content>>[];

  @override
  Future<void> sendContent({
    required List<Content> turns,
    required bool turnComplete,
  }) async {
    sentTurns.add(turns);
  }

  @override
  Future<void> sendToolResponses({
    required List<FunctionResponse> functionResponses,
  }) async {}

  @override
  Future<void> sendRealtimeInput({required RealtimeBlob blob}) async {}

  @override
  Stream<GeminiLiveSessionMessage> receive() =>
      const Stream<GeminiLiveSessionMessage>.empty();

  @override
  Future<void> close() async {}
}

class _DumpableModel {
  _DumpableModel({required this.id});

  final String id;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'optional_note': null,
  };
}

class _SseStreamingHttpClient extends http.BaseClient {
  _SseStreamingHttpClient(this.ssePayload);

  final String ssePayload;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(ssePayload)]),
      200,
      headers: const <String, String>{'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  group('1. Environment, DaytonaEnvironment, and E2BEnvironment', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adk_env_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('LocalEnvironment readFileStream yields chunks and writeFile validates content before truncating', () async {
      final env_pkg.LocalEnvironment env = env_pkg.LocalEnvironment(
        workingDirectory: tempDir,
      );
      await env.writeFile('hello.txt', 'initial content');

      // Invalid content (lone UTF-16 surrogate) must throw FormatException and
      // leave the existing file intact without truncating it.
      final String loneSurrogate = String.fromCharCodes(<int>[0x61, 0xD800]);
      await expectLater(
        () => env.writeFile('hello.txt', loneSurrogate),
        throwsFormatException,
      );
      expect(utf8.decode(await env.readFile('hello.txt')), 'initial content');

      // Invalid content must also not create parent directories.
      await expectLater(
        () => env.writeFile('nested/dir/bad.txt', loneSurrogate),
        throwsFormatException,
      );
      expect(Directory('${tempDir.path}/nested').existsSync(), isFalse);

      // readFileStream streams the file contents accurately.
      final List<int> streamedBytes = <int>[];
      await for (final List<int> chunk in env.readFileStream('hello.txt')) {
        streamedBytes.addAll(chunk);
      }
      expect(utf8.decode(streamedBytes), 'initial content');
    });

    test('DaytonaEnvironment and E2BEnvironment validate writeFile content and support readFileStream', () async {
      final daytona_pkg.DaytonaEnvironment daytona =
          daytona_pkg.DaytonaEnvironment(
            apiKey: 'test-key',
            httpClient: _SseStreamingHttpClient(''),
          );
      final String loneSurrogate = String.fromCharCodes(<int>[0xD800]);
      await expectLater(
        () => daytona.writeFile('/home/daytona/a.txt', loneSurrogate),
        throwsFormatException,
      );
      await expectLater(
        () => daytona.writeFile('/home/daytona/a.txt', 12345),
        throwsArgumentError,
      );

      final HttpE2BSandboxClient e2bClient = HttpE2BSandboxClient(
        apiKey: 'e2b_test_key',
      );
      final E2BEnvironment e2b = E2BEnvironment(
        apiKey: 'e2b_test_key',
        client: e2bClient,
      );
      await e2b.initialize();
      addTearDown(e2b.close);
      await e2b.writeFile('existing.txt', 'keep me');
      await expectLater(
        () => e2b.writeFile('existing.txt', loneSurrogate),
        throwsFormatException,
      );
      await expectLater(
        () => e2b.writeFile('existing.txt', Object()),
        throwsArgumentError,
      );
      expect(utf8.decode(await e2b.readFile('existing.txt')), 'keep me');

      final List<int> streamed = <int>[];
      await for (final List<int> chunk in e2b.readFileStream('existing.txt')) {
        streamed.addAll(chunk);
      }
      expect(utf8.decode(streamed), 'keep me');
    });
  });

  group('2. FsspecArtifactService', () {
    late InMemoryFsspecFilesystem fs;
    late FsspecArtifactService service;

    setUp(() {
      fs = InMemoryFsspecFilesystem(protocol: 'memory');
      service = FsspecArtifactService('memory://bucket/root', fs: fs);
    });

    test('loads, versions, lists, and inspects session and user-scoped artifacts', () async {
      fs.putFile(
        'bucket/root/my_app/user_1/sess_1/report.txt/0',
        utf8.encode('version 0'),
        info: <String, Object?>{
          'ContentType': 'text/plain',
          'metadata': <String, Object?>{
            'adkIsText': 'true',
            'tag': 'draft',
          },
        },
      );
      fs.putFile(
        'bucket/root/my_app/user_1/sess_1/report.txt/1',
        utf8.encode('version 1'),
        info: <String, Object?>{
          'ContentType': 'text/plain',
          'metadata': <String, Object?>{
            'adkIsText': 'true',
            'tag': 'final',
          },
        },
      );
      fs.putFile(
        'bucket/root/my_app/user_1/user/user:profile.json/0',
        utf8.encode('{"role":"admin"}'),
        info: <String, Object?>{
          'ContentType': 'application/json',
        },
      );

      final Part? latest = await service.loadArtifact(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 'sess_1',
        filename: 'report.txt',
      );
      expect(latest?.text, 'version 1');

      final Part? firstVersion = await service.loadArtifact(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 'sess_1',
        filename: 'report.txt',
        version: 0,
      );
      expect(firstVersion?.text, 'version 0');

      final List<String> keys = await service.listArtifactKeys(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 'sess_1',
      );
      expect(keys, <String>['report.txt', 'user:profile.json']);

      final List<int> versions = await service.listVersions(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 'sess_1',
        filename: 'report.txt',
      );
      expect(versions, <int>[0, 1]);

      await expectLater(
        () => service.getArtifactVersion(
          appName: 'my_app',
          userId: 'user_1',
          sessionId: 'sess_1',
          filename: 'report.txt',
        ),
        throwsUnimplementedError,
      );

      // Read-only service throws UnsupportedError on saveArtifact / deleteArtifact.
      await expectLater(
        () => service.saveArtifact(
          appName: 'my_app',
          userId: 'user_1',
          sessionId: 'sess_1',
          filename: 'report.txt',
          artifact: Part.text('v2'),
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        () => service.deleteArtifact(
          appName: 'my_app',
          userId: 'user_1',
          sessionId: 'sess_1',
          filename: 'report.txt',
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects path traversal and unsafe segment names', () async {
      await expectLater(
        () => service.loadArtifact(
          appName: 'app',
          userId: 'user_1',
          sessionId: 'sess_1',
          filename: '../secret.txt',
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => service.loadArtifact(
          appName: 'app',
          userId: 'user_1',
          sessionId: 'sess_1',
          filename: '/abs/secret.txt',
        ),
        throwsArgumentError,
      );
    });
  });

  group('3. OpenAIDecisionsClassifier and RefusalAnswer routing', () {
    test('translates Binary, Choice, Score, and Refusal decisions', () async {
      final _FakeDecisionsClient client = _FakeDecisionsClient()
        ..nextResponse = <String, Object?>{
          'model': 'gpt-6-luna-2026',
          'decisions': <String, Object?>{
            'is_safe': <String, Object?>{
              'type': 'predicate',
              'probability_true': 0.92,
            },
            'intent': <String, Object?>{
              'type': 'choice',
              'selected': 'billing',
              'probabilities': <String, Object?>{
                'billing': 0.8,
                'support': 0.2,
              },
            },
            'urgency': <String, Object?>{
              'type': 'score',
              'expected_score': 1.4,
              'probabilities': <String, Object?>{
                '0': 0.1,
                '1': 0.4,
                '2': 0.5,
              },
            },
            'sensitive': <String, Object?>{
              'type': 'refusal',
            },
          },
          'usage': <String, Object?>{
            'input_tokens': 40,
            'output_tokens': 12,
            'total_tokens': 52,
          },
        };

      final OpenAIDecisionsClassifier classifier = OpenAIDecisionsClassifier(
        apiKey: 'sk-test',
        client: client,
      );

      final ClassifierResponse response = await classifier.classify(
        input: 'My invoice was charged twice.',
        questions: <String, ClassifierQuestion>{
          'is_safe': const Binary(
            instructions: 'Is this message safe?',
            criteria: 'No policy violations',
          ),
          'intent': Choice(
            instructions: 'Classify intent',
            criteria: <String, Object?>{
              'billing': 'Payment and invoices',
              'support': 'Technical issues',
            },
          ),
          'urgency': Score(
            instructions: 'Rate urgency',
            criteria: <Object?>['Low', 'Medium', 'High'],
          ),
          'sensitive': const Binary(instructions: 'Sensitive check'),
        },
      );

      expect(response.modelVersion, 'gpt-6-luna-2026');
      expect((response.answers['is_safe'] as BinaryAnswer).probability, 0.92);
      expect((response.answers['intent'] as ChoiceAnswer).choice, 'billing');
      final ScoreAnswer urgency = response.answers['urgency'] as ScoreAnswer;
      expect(urgency.score, 1.4);
      expect(urgency.expected, 1.4);
      expect(urgency.probabilities[2], 0.5);
      expect(response.answers['sensitive'], isA<RefusalAnswer>());
    });

    test('ClassifierNode throws WorkflowDataError when classifier returns RefusalAnswer', () {
      overrideFeatureEnabled(FeatureName.classifier, true);
      addTearDown(resetFeatureRegistryForTest);

      final ClassifierNode guardNode = ClassifierNode(
        name: 'guard_node',
        classifier: OpenAIDecisionsClassifier(apiKey: 'sk-test'),
        question: const Binary(instructions: 'Check safety'),
      );
      expect(
        () => guardNode.routeFor(RefusalAnswer()),
        throwsA(isA<WorkflowDataError>()),
      );
    });
  });

  group('4. TeamsRunner', () {
    test('routes Teams message activity through Runner and sends typing + text reply', () async {
      final LlmAgent agent = LlmAgent(
        name: 'teams_helper',
        model: _StaticReplyModel('Hello from Teams!'),
      );
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        appName: 'teams_app',
      );
      final SimpleTeamsAgentApplication agentApp =
          SimpleTeamsAgentApplication();
      final TeamsRunner teamsRunner = TeamsRunner(runner, agentApp);
      final TeamsHttpApp httpApp = teamsRunner.createApp(null);

      final List<Object> sentActivities = await httpApp.handleMessagesPayload(
        <String, Object?>{
          'type': 'message',
          'text': '  hello there! ',
          'from': <String, Object?>{'id': '29:user-raw'},
          'conversation': <String, Object?>{'id': 'conv-abc'},
        },
      );
      await teamsRunner.waitForBackgroundTasks();

      expect(sentActivities, hasLength(2));
      expect((sentActivities.first as TeamsActivity).type, 'typing');
      expect(sentActivities.last, 'Hello from Teams!');

      // Error events produce a user-facing error fallback message.
      final InMemoryRunner errorAdkRunner = InMemoryRunner(
        agent: LlmAgent(name: 'err_agent', model: _ErrorModel()),
        appName: 'teams_err_app',
      );
      final SimpleTeamsAgentApplication errorAgentApp =
          SimpleTeamsAgentApplication();
      final TeamsRunner errorTeamsRunner = TeamsRunner(
        errorAdkRunner,
        errorAgentApp,
      );
      final TeamsHttpApp errorHttpApp = errorTeamsRunner.createApp(null);

      final List<Object> errorReplies = await errorHttpApp
          .handleMessagesPayload(<String, Object?>{
            'type': 'message',
            'text': 'trigger error',
            'from': <String, Object?>{'id': 'u1'},
            'conversation': <String, Object?>{'id': 'c1'},
          });
      await errorTeamsRunner.waitForBackgroundTasks();

      expect(errorReplies.last, contains('Sorry, something went wrong'));
    });
  });

  group('5. Firestore and Redis session/memory fixes', () {
    test('FirestoreMemoryService filters thought parts and FirestoreSessionService validates identity segments', () async {
      final FirestoreMemoryService memoryService = FirestoreMemoryService();
      final Session session = Session(
        id: 'sess_1',
        appName: 'app_1',
        userId: 'user_1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part(text: 'secret internal chain of thought', thought: true),
              ],
            ),
          ),
          Event(
            invocationId: 'inv_1',
            author: 'agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part(text: 'hidden thought', thought: true),
                Part.text('visible answer about cats'),
              ],
            ),
          ),
        ],
      );
      await memoryService.addSessionToMemory(session);

      final SearchMemoryResponse secretSearch = await memoryService.searchMemory(
        appName: 'app_1',
        userId: 'user_1',
        query: 'secret',
      );
      expect(secretSearch.memories, isEmpty);

      final SearchMemoryResponse catSearch = await memoryService.searchMemory(
        appName: 'app_1',
        userId: 'user_1',
        query: 'cats',
      );
      expect(catSearch.memories, hasLength(1));
      expect(catSearch.memories.single.content.parts, hasLength(1));
      expect(
        catSearch.memories.single.content.parts.single.text,
        'visible answer about cats',
      );

      final FirestoreSessionService sessionService = FirestoreSessionService();
      for (final String badId in <String>[
        '',
        '.',
        '..',
        'foo/bar',
        '__reserved__',
      ]) {
        await expectLater(
          () => sessionService.createSession(
            appName: 'app_1',
            userId: 'user_1',
            sessionId: badId,
          ),
          throwsArgumentError,
        );
      }
    });

    test('RedisSessionService.createSession does not overwrite shared app/user state on duplicate sessionId', () async {
      final RedisSessionService redisService = RedisSessionService();
      await redisService.createSession(
        appName: 'app_1',
        userId: 'user_1',
        sessionId: 'dup_sess',
        state: <String, Object?>{
          'app:theme': 'dark',
          'user:lang': 'ko',
          'counter': 1,
        },
      );

      await expectLater(
        () => redisService.createSession(
          appName: 'app_1',
          userId: 'user_1',
          sessionId: 'dup_sess',
          state: <String, Object?>{
            'app:theme': 'corrupted',
            'user:lang': 'corrupted',
            'counter': 999,
          },
        ),
        throwsA(isA<AlreadyExistsError>()),
      );

      final Session? existing = await redisService.getSession(
        appName: 'app_1',
        userId: 'user_1',
        sessionId: 'dup_sess',
      );
      expect(existing?.state['app:theme'], 'dark');
      expect(existing?.state['user:lang'], 'ko');
      expect(existing?.state['counter'], 1);
    });
  });

  group('6. Antigravity extractSubagentNames', () {
    test('extracts subagent names from invoke_subagent and start_subagent tool calls', () {
      expect(
        extractSubagentNames(
          const AntigravityToolCall(
            id: 'call_1',
            name: BuiltinTools.invokeSubagent,
            args: <String, Object?>{'TypeName': 'research'},
          ),
        ),
        <String>['research'],
      );
      expect(
        extractSubagentNames(
          const AntigravityToolCall(
            id: 'call_2',
            name: BuiltinTools.startSubagent,
            args: <String, Object?>{
              'Subagents': <Map<String, Object?>>[
                <String, Object?>{'subagent_name': 'planner'},
                <String, Object?>{'TypeName': 'coder'},
              ],
            },
          ),
        ),
        <String>['planner', 'coder'],
      );
      expect(
        extractSubagentNames(
          const AntigravityToolCall(
            id: 'call_3',
            name: 'other_tool',
            args: <String, Object?>{'TypeName': 'ignored'},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('7. Models: ApigeeLlm, GeminiLlmConnection, GemmaLlm, and interactions_utils', () {
    test('ApigeeLlm reports truncated tool calls on finish_reason=length as MAX_TOKENS', () async {
      final LlmResponse nonStreaming = ApigeeLlm.parseChatCompletionsResponse(
        <String, Object?>{
          'model': 'gpt-4o',
          'choices': <Map<String, Object?>>[
            <String, Object?>{
              'finish_reason': 'length',
              'message': <String, Object?>{
                'role': 'assistant',
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'call_trunc',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'get_weather',
                      'arguments': '{"city": "Seo',
                    },
                  },
                ],
              },
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 10,
            'completion_tokens': 16,
            'total_tokens': 26,
          },
        },
      );
      expect(nonStreaming.finishReason, 'MAX_TOKENS');
      expect(nonStreaming.errorCode, 'MAX_TOKENS');
      expect(nonStreaming.errorMessage, contains('truncated'));
      expect(nonStreaming.content, isNull);

      // Streaming with truncated tool call arguments emits MAX_TOKENS error response.
      final String sse = <String>[
        'data: ${jsonEncode(<String, Object?>{
          'model': 'gpt-4o',
          'choices': <Map<String, Object?>>[
            <String, Object?>{
              'delta': <String, Object?>{
                'role': 'assistant',
                'tool_calls': <Map<String, Object?>>[
                  <String, Object?>{
                    'index': 0,
                    'id': 'call_stream_1',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'search_docs',
                      'arguments': '{"query": "unclosed',
                    },
                  },
                ],
              },
            },
          ],
        })}\n\n',
        'data: ${jsonEncode(<String, Object?>{
          'model': 'gpt-4o',
          'choices': <Map<String, Object?>>[
            <String, Object?>{
              'delta': const <String, Object?>{},
              'finish_reason': 'length',
            },
          ],
          'usage': <String, Object?>{
            'prompt_tokens': 5,
            'completion_tokens': 10,
            'total_tokens': 15,
          },
        })}\n\n',
        'data: [DONE]\n\n',
      ].join();

      final ChatCompletionsHttpClient client = ChatCompletionsHttpClient(
        httpClient: _SseStreamingHttpClient(sse),
      );
      final List<LlmResponse> streamResponses = await client
          .generateContent(
            request: LlmRequest(
              model: 'gpt-4o',
              contents: <Content>[Content.userText('hi')],
            ),
            stream: true,
            baseUrl: 'https://proxy.example.com/v1/chat/completions',
            headers: const <String, String>{},
          )
          .toList();

      final LlmResponse terminal = streamResponses.last;
      expect(terminal.finishReason, 'MAX_TOKENS');
      expect(terminal.errorCode, 'MAX_TOKENS');
      expect(terminal.errorMessage, contains('truncated while streaming'));
      expect(terminal.content, isNull);
    });

    test('GeminiLlmConnection filterMediaHistory removes media parts and empty turns', () async {
      final _RecordingLiveSession liveSession = _RecordingLiveSession();
      final GeminiLlmConnection connection = GeminiLlmConnection(
        model: Gemini(model: 'gemini-2.5-flash'),
        liveSession: liveSession,
      );

      final List<Content> history = <Content>[
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromFileData(
              fileUri: 'artifact://app/u1/s1/_adk_live/audio_chunk.pcm#0',
              mimeType: 'audio/pcm',
            ),
          ],
        ),
        Content(
          role: 'user',
          parts: <Part>[
            Part.fromInlineData(mimeType: 'audio/pcm', data: <int>[4, 5]),
            Part.text('kept text'),
          ],
        ),
      ];

      expect(filterMediaHistory(history), hasLength(1));
      await connection.sendHistory(history);
      expect(liveSession.sentTurns, hasLength(1));
      expect(liveSession.sentTurns.single, hasLength(1));
      expect(liveSession.sentTurns.single.single.parts.single.text, 'kept text');
    });

    test('GemmaLlm serializes DateTime, bytes, toJson models (excluding nulls), and lone surrogates', () async {
      LlmRequest? capturedRequest;
      final GemmaLlm gemma = GemmaLlm(
        model: 'gemma-3-27b-it',
        generateHook: (LlmRequest request, bool stream) async* {
          capturedRequest = request;
          yield LlmResponse(content: Content.modelText('done'));
        },
      );

      final String loneSurrogate = String.fromCharCodes(<int>[0xD800]);
      await gemma
          .generateContent(
            LlmRequest(
              model: 'gemma-3-27b-it',
              contents: <Content>[
                Content(
                  role: 'user',
                  parts: <Part>[
                    Part.fromFunctionResponse(
                      name: 'complex_tool',
                      response: <String, Object?>{
                        'timestamp': DateTime.utc(2026, 11, 2, 12, 30),
                        'bytes': Uint8List.fromList(<int>[1, 2, 3]),
                        'model': _DumpableModel(id: 'm1'),
                        'surrogate': loneSurrogate,
                      },
                    ),
                  ],
                ),
              ],
            ),
          )
          .toList();

      final String serializedText =
          capturedRequest!.contents.single.parts.single.text!;
      expect(serializedText, contains('2026-11-02T12:30:00.000Z'));
      expect(serializedText, contains(base64Encode(<int>[1, 2, 3])));
      expect(serializedText, contains('"id":"m1"'));
      expect(serializedText, isNot(contains('optional_note')));
      expect(serializedText, contains(r'\ud800'));
    });

    test('interactions_utils marks failed MCP function_result with is_error and preserves streaming thought_signature', () {
      final Map<String, Object?>? okResult = convertPartToInteractionContent(
        Part.fromFunctionResponse(
          id: 'c1',
          name: 'mcp_tool',
          response: <String, dynamic>{'output': 'ok'},
        ),
      );
      expect(okResult?['is_error'], isFalse);

      final Map<String, Object?>? errResult = convertPartToInteractionContent(
        Part.fromFunctionResponse(
          id: 'c2',
          name: 'mcp_tool',
          response: <String, dynamic>{'isError': true, 'content': 'boom'},
        ),
      );
      expect(errResult?['is_error'], isTrue);

      final InteractionsStreamState streamState = InteractionsStreamState();
      final LlmResponse? summaryDelta = convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'content.delta',
          'delta': <String, Object?>{
            'type': 'thought_summary',
            'content': <String, Object?>{'text': 'Thinking step 1'},
          },
        },
        streamState.parts,
        streamState: streamState,
        interactionId: 'int_1',
      );
      expect(summaryDelta?.partial, isTrue);
      expect(summaryDelta?.content?.parts.single.thought, isTrue);
      expect(summaryDelta?.content?.parts.single.text, 'Thinking step 1');

      final String sigBase64 = base64Encode(<int>[9, 8, 7, 6]);
      final LlmResponse? sigDelta = convertInteractionEventToLlmResponse(
        <String, Object?>{
          'event_type': 'content.delta',
          'delta': <String, Object?>{
            'type': 'thought_signature',
            'signature': sigBase64,
          },
        },
        streamState.parts,
        streamState: streamState,
        interactionId: 'int_1',
      );
      expect(sigDelta, isNull);
      expect(streamState.parts, hasLength(2));
      expect(streamState.parts.last.thought, isTrue);
      expect(streamState.parts.last.thoughtSignature, <int>[9, 8, 7, 6]);
    });
  });

  group('8. BigQueryAgentAnalyticsPlugin logContentFormatterErrorDetails', () {
    test('fails closed by default and logs formatter error details only when opted in', () async {
      final InvocationContext ctx = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_bq',
        agent: LlmAgent(name: 'bq_agent', instruction: 'Helpful'),
        session: Session(id: 's1', appName: 'app', userId: 'u1'),
      );

      final BigQueryAgentAnalyticsPlugin defaultPlugin =
          BigQueryAgentAnalyticsPlugin(
            projectId: 'p',
            datasetId: 'd',
            useBigQueryInsertAllSink: false,
            config: BigQueryLoggerConfig(
              createViews: false,
              contentFormatter: (Object? content, String eventType) {
                throw StateError('sensitive payload fragment');
              },
            ),
          );
      await defaultPlugin.onUserMessageCallback(
        invocationContext: ctx,
        userMessage: Content.userText('hello'),
      );
      final Map<String, Object?> defaultRow = defaultPlugin.loggedRows.single;
      expect(defaultRow['content'], isNull);
      expect(defaultRow['error_message'], isNull);
      final Map<String, Object?> defaultAttrs =
          jsonDecode('${defaultRow['attributes']}') as Map<String, Object?>;
      expect(
        (defaultAttrs['adk'] as Map<String, Object?>)['content_formatter_error'],
        isNull,
      );

      final BigQueryAgentAnalyticsPlugin optInPlugin =
          BigQueryAgentAnalyticsPlugin(
            projectId: 'p',
            datasetId: 'd',
            useBigQueryInsertAllSink: false,
            config: BigQueryLoggerConfig(
              createViews: false,
              logContentFormatterErrorDetails: true,
              contentFormatter: (Object? content, String eventType) {
                throw StateError('formatter boom');
              },
            ),
          );
      await optInPlugin.onUserMessageCallback(
        invocationContext: ctx,
        userMessage: Content.userText('hello'),
      );
      final Map<String, Object?> optInRow = optInPlugin.loggedRows.single;
      expect(optInRow['content'], isNull);
      expect('${optInRow['error_message']}', contains('formatter boom'));
      final Map<String, Object?> optInAttrs =
          jsonDecode('${optInRow['attributes']}') as Map<String, Object?>;
      expect(
        '${(optInAttrs['adk'] as Map<String, Object?>)['content_formatter_error']}',
        contains('formatter boom'),
      );
    });
  });

  group('9. Telemetry schema v2 token usage and streaming chunk latency', () {
    test('records modality breakdowns, cache_write, error.type, and streaming chunk latency', () {
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      final LlmResponse response = LlmResponse(
        modelVersion: 'gemini-2.5-pro',
        finishReason: 'STOP',
        cacheMetadata: CacheMetadata(
          cacheName: 'caches/123',
          expireTime: 999999,
          fingerprint: 'fp',
          invocationsUsed: 0,
          contentsCount: 2,
        ),
        usageMetadata: <String, Object?>{
          'prompt_token_count': 100,
          'tool_use_prompt_token_count': 20,
          'cached_content_token_count': 30,
          'candidates_token_count': 40,
          'thoughts_token_count': 10,
          'prompt_tokens_details': <Map<String, Object?>>[
            <String, Object?>{'modality': 'TEXT', 'token_count': 80},
            <String, Object?>{'modality': 'IMAGE', 'token_count': 20},
          ],
          'tool_use_prompt_tokens_details': <Map<String, Object?>>[
            <String, Object?>{'modality': 'TEXT', 'token_count': 20},
          ],
          'cache_tokens_details': <Map<String, Object?>>[
            <String, Object?>{'modality': 'TEXT', 'token_count': 30},
          ],
          'candidates_tokens_details': <Map<String, Object?>>[
            <String, Object?>{'modality': 'TEXT', 'token_count': 40},
          ],
        },
      );

      final TokenUsage? usage = TokenUsage.fromLlmResponses(<LlmResponse>[
        response,
      ]);
      expect(usage, isNotNull);
      expect(usage!.inputTokens, 120);
      expect(usage.outputTokens, 50);
      expect(usage.cacheReadInputTokens, 30);
      expect(usage.cacheWriteInputTokens, 100);
      expect(usage.toolInputTokens, 20);
      expect(usage.reasoningOutputTokens, 10);
      expect(usage.inputTokensByModality, <ModalityTokenUsage>[
        const ModalityTokenUsage('text', 100),
        const ModalityTokenUsage('image', 20),
      ]);

      recordInferenceTokenUsage(
        tokenUsage: usage,
        agentName: 'telemetry_agent',
        requestModel: 'gemini-2.5-pro',
        responseModel: 'gemini-2.5-pro',
        system: 'gcp.gemini',
        finishReasons: const <String>['stop'],
        error: StateError('stream interrupted'),
        recorder: recorder,
      );

      expect(
        recorder.records.where(
          (AdkMetricRecord r) =>
              r.name == genAiClientTokenUsageMetric &&
              r.attributes['gen_ai.token.type.detail'] == 'cache_write',
        ),
        hasLength(1),
      );
      expect(
        recorder.records.every(
          (AdkMetricRecord r) => r.attributes['error.type'] == 'StateError',
        ),
        isTrue,
      );

      expect(
        shouldEmitInferenceTokenMetrics(
          system: 'gcp.gemini',
          hasGenAiInstrumentor: true,
          environment: const <String, String>{
            'ADK_GOOGLE_GENAI_INSTRUMENTOR_SCHEMA_VERSION': 'v1',
          },
        ),
        isFalse,
      );
      expect(
        shouldEmitInferenceTokenMetrics(
          system: 'gcp.gemini',
          hasGenAiInstrumentor: true,
          environment: const <String, String>{
            'ADK_GOOGLE_GENAI_INSTRUMENTOR_SCHEMA_VERSION': 'v2',
          },
        ),
        isTrue,
      );

      recorder.clear();
      final GenerateContentSpan gcSpan = GenerateContentSpan(
        TraceSpanRecord('generate_content gemini-2.5-pro'),
        requestModel: 'gemini-2.5-pro',
        systemName: 'gcp.gemini',
        startTimeMicros: 1000000,
      );
      recordInferenceChunk(
        gcSpan,
        LlmResponse(modelVersion: 'gemini-2.5-pro-001', partial: true),
        nowMicros: 1250000,
        recorder: recorder,
      );
      recordInferenceChunk(
        gcSpan,
        LlmResponse(modelVersion: 'gemini-2.5-pro-001', partial: true),
        nowMicros: 1650000,
        recorder: recorder,
      );

      final List<AdkMetricRecord> ttfc = recorder.records
          .where(
            (AdkMetricRecord r) =>
                r.name == genAiClientOperationTimeToFirstChunkMetric,
          )
          .toList();
      final List<AdkMetricRecord> chunkDurations = recorder.records
          .where(
            (AdkMetricRecord r) =>
                r.name == genAiClientInferenceChunkDurationMetric,
          )
          .toList();
      expect(ttfc, hasLength(1));
      expect(ttfc.single.value, closeTo(0.25, 1e-6));
      expect(chunkDurations, hasLength(2));
      expect(chunkDurations[0].value, closeTo(0.25, 1e-6));
      expect(chunkDurations[1].value, closeTo(0.40, 1e-6));
    });
  });
}
