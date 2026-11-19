import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/src/agents/context_cache_config.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/live/cascade_live_connection.dart';
import 'package:adk_dart/src/live/cascade_live_events.dart';
import 'package:adk_dart/src/live/transforms.dart';
import 'package:adk_dart/src/models/apigee_llm.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/base_llm_connection.dart';
import 'package:adk_dart/src/models/cache_metadata.dart';
import 'package:adk_dart/src/models/gemini_context_cache_manager.dart';
import 'package:adk_dart/src/models/gemini_llm_connection.dart';
import 'package:adk_dart/src/models/gemini_rest_api_client.dart';
import 'package:adk_dart/src/models/google_llm.dart';
import 'package:adk_dart/src/models/interactions_utils.dart';
import 'package:adk_dart/src/models/lite_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:test/test.dart';

class _RecordingGeminiLiveSession extends GeminiLiveSession {
  final StreamController<GeminiLiveSessionMessage> controller =
      StreamController<GeminiLiveSessionMessage>.broadcast();

  Content? lastContextUpdateSystemInstruction;
  List<ToolDeclaration>? lastContextUpdateTools;
  int contextUpdateCalls = 0;

  @override
  Future<void> sendContent({
    required List<Content> turns,
    required bool turnComplete,
  }) async {}

  @override
  Future<void> sendToolResponses({
    required List<FunctionResponse> functionResponses,
  }) async {}

  @override
  Future<void> sendRealtimeInput({required RealtimeBlob blob}) async {}

  @override
  Future<void> sendContextUpdate({
    Content? systemInstruction,
    List<ToolDeclaration>? tools,
  }) async {
    contextUpdateCalls += 1;
    lastContextUpdateSystemInstruction = systemInstruction;
    lastContextUpdateTools = tools;
  }

  @override
  Stream<GeminiLiveSessionMessage> receive() => controller.stream;

  @override
  Future<void> close() async {
    await controller.close();
  }
}

class _StubBaseLlm extends BaseLlm {
  _StubBaseLlm({super.model = 'gemini-2.5-flash'});

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _RecordingRestTransport implements GeminiRestTransport {
  Map<String, String>? lastHeaders;
  String? lastApiVersion;
  String? lastBaseUrl;

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    lastHeaders = headers == null ? null : Map<String, String>.from(headers);
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    return <String, Object?>{
      'candidates': <Map<String, Object?>>[
        <String, Object?>{
          'content': <String, Object?>{
            'role': 'model',
            'parts': <Map<String, Object?>>[
              <String, Object?>{'text': 'ok'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    };
  }

  @override
  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    lastHeaders = headers == null ? null : Map<String, String>.from(headers);
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
  }

  @override
  Future<Map<String, Object?>> createInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    lastHeaders = headers == null ? null : Map<String, String>.from(headers);
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    return <String, Object?>{
      'id': 'int-1',
      'status': 'completed',
      'outputs': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': 'interaction ok'},
      ],
    };
  }

  @override
  Stream<Map<String, Object?>> streamCreateInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    lastHeaders = headers == null ? null : Map<String, String>.from(headers);
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
  }
}

class _RecordingApigeeCompletionsClient implements ApigeeCompletionsClient {
  Map<String, String>? lastHeaders;
  String? lastBaseUrl;

  @override
  Stream<LlmResponse> generateContent({
    required LlmRequest request,
    required bool stream,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {
    lastBaseUrl = baseUrl;
    lastHeaders = Map<String, String>.from(headers);
    yield LlmResponse(content: Content.modelText('ok'), turnComplete: true);
  }
}

class _ConfigurableGeminiCacheClient implements GeminiCacheClient {
  _ConfigurableGeminiCacheClient({this.createError});

  Object? createError;
  int createCalls = 0;
  int deleteCalls = 0;
  final List<String> deletedNames = <String>[];

  @override
  Future<GeminiCreatedCache> createCache({
    required String model,
    required List<Content> contents,
    required String ttl,
    required String displayName,
    String? systemInstruction,
    List<ToolDeclaration>? tools,
    LlmToolConfig? toolConfig,
  }) async {
    createCalls += 1;
    if (createError != null) {
      throw createError!;
    }
    return GeminiCreatedCache(name: 'caches/created-$createCalls');
  }

  @override
  Future<void> deleteCache({required String cacheName}) async {
    deleteCalls += 1;
    deletedNames.add(cacheName);
  }
}

class _EmptyIngress extends LiveIngress {
  const _EmptyIngress();

  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) =>
      const Stream<IngressEvent>.empty();
}

class _EmptyEgress extends LiveEgress {
  const _EmptyEgress();

  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) => const Stream<EgressEvent>.empty();
}

void main() {
  group('1. 6ccd07b79: BaseLlmConnection.sendContextUpdate', () {
    test(
      'GeminiLlmConnection forwards systemInstruction and tools on Gemini 3.x Live',
      () async {
        final _RecordingGeminiLiveSession session =
            _RecordingGeminiLiveSession();
        final GeminiLlmConnection connection = GeminiLlmConnection(
          model: _StubBaseLlm(model: 'gemini-3.5-live-preview'),
          liveSession: session,
          modelVersion: 'models/gemini-3.5-live-preview',
        );

        final List<ToolDeclaration> tools = <ToolDeclaration>[
          ToolDeclaration(
            functionDeclarations: <FunctionDeclaration>[
              FunctionDeclaration(name: 'get_weather'),
            ],
          ),
        ];

        await connection.sendContextUpdate(
          systemInstruction: 'Updated instruction',
          tools: tools,
        );

        expect(session.contextUpdateCalls, 1);
        expect(session.lastContextUpdateSystemInstruction?.role, 'system');
        expect(
          session.lastContextUpdateSystemInstruction?.parts.single.text,
          'Updated instruction',
        );
        expect(session.lastContextUpdateTools, same(tools));

        await connection.sendContextUpdate(systemInstruction: '', tools: null);
        expect(session.contextUpdateCalls, 2);
        expect(session.lastContextUpdateSystemInstruction, isNull);
        expect(session.lastContextUpdateTools, isNull);

        await connection.close();
      },
    );

    test(
      'GeminiLlmConnection throws StateError for non-Gemini-3.x-Live models',
      () async {
        for (final String? modelVersion in <String?>[
          'gemini-2.5-flash-live',
          'gemini-2.5-flash',
          'gemini-3.5-live-translate',
          null,
        ]) {
          final _RecordingGeminiLiveSession session =
              _RecordingGeminiLiveSession();
          final GeminiLlmConnection connection = GeminiLlmConnection(
            model: _StubBaseLlm(model: modelVersion ?? 'gemini-2.5-flash'),
            liveSession: session,
            modelVersion: modelVersion,
          );

          await expectLater(
            connection.sendContextUpdate(systemInstruction: 'Hello'),
            throwsA(
              isA<StateError>().having(
                (StateError e) => e.message,
                'message',
                contains('Context updates need a Gemini 3.x Live model'),
              ),
            ),
          );
          expect(session.contextUpdateCalls, 0);
          await connection.close();
        }
      },
    );

    test('CascadeLiveConnection.sendContextUpdate is a no-op', () async {
      final CascadeLiveConnection connection = CascadeLiveConnection(
        LlmRequest(model: 'gemini-2.5-flash'),
        _StubBaseLlm(),
        const _EmptyIngress(),
        const _EmptyEgress(),
      );

      await expectLater(
        connection.sendContextUpdate(
          systemInstruction: 'New instruction',
          tools: <ToolDeclaration>[],
        ),
        completes,
      );
      await connection.close();
    });
  });

  group('2. aa0f434a8: Keep Gemini Developer API on v1beta by default', () {
    test(
      'Gemini defaults Gemini API to v1beta and leaves Vertex AI unset',
      () {
        final Gemini geminiApi = Gemini(
          model: 'gemini-2.5-flash',
          environment: const <String, String>{},
        );
        expect(geminiApi.clientHttpOptions.apiVersion, 'v1beta');

        final Gemini vertexAi = Gemini(
          model: 'gemini-2.5-flash',
          environment: const <String, String>{
            'GOOGLE_GENAI_USE_VERTEXAI': 'true',
          },
        );
        expect(vertexAi.clientHttpOptions.apiVersion, isNull);
      },
    );

    test(
      'GOOGLE_GENAI_API_VERSION=beta counts as unset (v1beta on Gemini API, null on Vertex AI)',
      () {
        final Gemini geminiApi = Gemini(
          model: 'gemini-2.5-flash',
          environment: const <String, String>{
            'GOOGLE_GENAI_API_VERSION': 'beta',
          },
        );
        expect(geminiApi.configuredApiVersion(), isNull);
        expect(geminiApi.clientHttpOptions.apiVersion, 'v1beta');

        final Gemini vertexAi = Gemini(
          model: 'gemini-2.5-flash',
          environment: const <String, String>{
            'GOOGLE_GENAI_USE_VERTEXAI': 'true',
            'GOOGLE_GENAI_API_VERSION': 'beta',
          },
        );
        expect(vertexAi.configuredApiVersion(), isNull);
        expect(vertexAi.clientHttpOptions.apiVersion, isNull);
      },
    );

    test('explicit apiVersion, env var, and baseUrl version take precedence', () {
      final Gemini explicitField = Gemini(
        model: 'gemini-2.5-flash',
        apiVersion: 'v1',
        environment: const <String, String>{},
      );
      expect(explicitField.clientHttpOptions.apiVersion, 'v1');

      final Gemini explicitEnv = Gemini(
        model: 'gemini-2.5-flash',
        environment: const <String, String>{
          'GOOGLE_GENAI_API_VERSION': 'v1',
        },
      );
      expect(explicitEnv.clientHttpOptions.apiVersion, 'v1');

      final Gemini embeddedBaseUrl = Gemini(
        model: 'gemini-2.5-flash',
        apiVersion: 'v1alpha',
        baseUrl: 'https://generativelanguage.googleapis.com/v1',
        environment: const <String, String>{},
      );
      expect(embeddedBaseUrl.clientHttpOptions.apiVersion, 'v1');
    });

    test('ApigeeLlm defaults Gemini API to v1beta and Vertex AI to null', () {
      final ApigeeLlm apigeeGemini = ApigeeLlm(
        model: 'apigee/gemini/gemini-2.5-flash',
        proxyUrl: 'https://proxy.example.com',
        environment: const <String, String>{},
      );
      expect(apigeeGemini.clientHttpOptions.apiVersion, 'v1beta');

      final ApigeeLlm apigeeGeminiExplicit = ApigeeLlm(
        model: 'apigee/gemini/v1/gemini-2.5-flash',
        proxyUrl: 'https://proxy.example.com',
        environment: const <String, String>{},
      );
      expect(apigeeGeminiExplicit.clientHttpOptions.apiVersion, 'v1');

      final ApigeeLlm apigeeVertex = ApigeeLlm(
        model: 'apigee/vertex_ai/gemini-2.5-flash',
        proxyUrl: 'https://proxy.example.com',
        environment: const <String, String>{
          'GOOGLE_CLOUD_PROJECT': 'proj',
          'GOOGLE_CLOUD_LOCATION': 'us-central1',
        },
      );
      expect(apigeeVertex.clientHttpOptions.apiVersion, isNull);
    });
  });

  group(
    '3. 761538ab2: Live tracking headers with caller-supplied client or httpOptions',
    () {
      test(
        'connect merges tracking headers when caller-supplied client is set',
        () {
          LlmRequest? captured;
          final _RecordingGeminiLiveSession session =
              _RecordingGeminiLiveSession();
          final Gemini llm = Gemini(
            model: 'gemini-2.5-flash',
            client: Object(),
            liveSessionFactory: (LlmRequest req) {
              captured = req;
              return session;
            },
            environment: const <String, String>{},
          );

          llm.connect(LlmRequest(model: 'gemini-2.5-flash'));

          expect(captured, isNotNull);
          expect(captured!.liveConnectConfig.httpOptions, isNotNull);
          expect(
            captured!.liveConnectConfig.httpOptions!.headers['x-goog-api-client'],
            contains('google-adk/'),
          );
          expect(
            captured!.liveConnectConfig.httpOptions!.headers['user-agent'],
            contains('google-adk/'),
          );
        },
      );

      test(
        'connect preserves caller liveConnectConfig.httpOptions while merging tracking headers',
        () {
          LlmRequest? captured;
          final _RecordingGeminiLiveSession session =
              _RecordingGeminiLiveSession();
          final Gemini llm = Gemini(
            model: 'gemini-2.5-flash',
            liveSessionFactory: (LlmRequest req) {
              captured = req;
              return session;
            },
            environment: const <String, String>{},
          );

          final HttpOptions callerOptions = HttpOptions(
            apiVersion: 'v1alpha',
            headers: <String, String>{
              'x-custom': 'abc',
              'x-goog-api-client': 'caller-sdk/1.0',
            },
          )..baseUrl = 'https://generativelanguage.googleapis.com';

          llm.connect(
            LlmRequest(
              model: 'gemini-2.5-flash',
              liveConnectConfig: LiveConnectConfig(httpOptions: callerOptions),
            ),
          );

          expect(captured, isNotNull);
          final HttpOptions? resolved = captured!.liveConnectConfig.httpOptions;
          expect(resolved, isNotNull);
          expect(resolved!.apiVersion, 'v1alpha');
          expect(resolved.baseUrl, 'https://generativelanguage.googleapis.com');
          expect(resolved.headers['x-custom'], 'abc');
          expect(resolved.headers['x-goog-api-client'], contains('google-adk/'));
          expect(
            resolved.headers['x-goog-api-client'],
            contains('caller-sdk/1.0'),
          );
        },
      );

      test(
        'connect leaves liveConnectConfig.httpOptions null when client and httpOptions are unset',
        () {
          LlmRequest? captured;
          final _RecordingGeminiLiveSession session =
              _RecordingGeminiLiveSession();
          final Gemini llm = Gemini(
            model: 'gemini-2.5-flash',
            liveSessionFactory: (LlmRequest req) {
              captured = req;
              return session;
            },
            environment: const <String, String>{},
          );

          llm.connect(LlmRequest(model: 'gemini-2.5-flash'));

          expect(captured, isNotNull);
          expect(captured!.liveConnectConfig.httpOptions, isNull);
        },
      );
    },
  );

  group('4. c38ecdae6: Exclude runtime tag on non-Google endpoints', () {
    const Map<String, String> agentEngineEnv = <String, String>{
      'GOOGLE_CLOUD_AGENT_ENGINE_ID': 'engine-123',
      'GEMINI_API_KEY': 'test-key',
    };

    test(
      'Gemini includes +remote_reasoning_engine for Google endpoints and excludes it for non-Google baseUrl',
      () async {
        final Gemini googleDefault = Gemini(
          model: 'gemini-2.5-flash',
          environment: agentEngineEnv,
        );
        expect(googleDefault.excludeRuntimeTag(), isFalse);
        expect(
          googleDefault.clientHttpOptions.headers['x-goog-api-client'],
          contains('+remote_reasoning_engine'),
        );

        final Gemini googleExplicit = Gemini(
          model: 'gemini-2.5-flash',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          environment: agentEngineEnv,
        );
        expect(googleExplicit.excludeRuntimeTag(), isFalse);
        expect(
          googleExplicit.clientHttpOptions.headers['x-goog-api-client'],
          contains('+remote_reasoning_engine'),
        );

        final _RecordingRestTransport transport = _RecordingRestTransport();
        final Gemini nonGoogle = Gemini(
          model: 'gemini-2.5-flash',
          baseUrl: 'https://proxy.customer.example.com/v1',
          useInteractionsApi: true,
          restTransport: transport,
          environment: agentEngineEnv,
        );
        expect(nonGoogle.excludeRuntimeTag(), isTrue);
        expect(
          nonGoogle.clientHttpOptions.headers['x-goog-api-client'],
          isNot(contains('+remote_reasoning_engine')),
        );
        expect(
          nonGoogle.liveClientHttpOptions.headers['x-goog-api-client'],
          isNot(contains('+remote_reasoning_engine')),
        );

        await nonGoogle
            .generateContent(
              LlmRequest(
                model: 'gemini-2.5-flash',
                contents: <Content>[Content.userText('hi')],
              ),
            )
            .toList();
        expect(transport.lastHeaders, isNotNull);
        expect(
          transport.lastHeaders!['x-goog-api-client'],
          contains('google-adk/'),
        );
        expect(
          transport.lastHeaders!['x-goog-api-client'],
          isNot(contains('+remote_reasoning_engine')),
        );
      },
    );

    test(
      'ApigeeLlm excludes +remote_reasoning_engine on both GenAI and chat completions',
      () async {
        final _RecordingApigeeCompletionsClient completionsClient =
            _RecordingApigeeCompletionsClient();
        final ApigeeLlm apigeeOpenAi = ApigeeLlm(
          model: 'apigee/openai/gpt-4o-mini',
          proxyUrl: 'https://apigee.customer.example.com/v1/chat/completions',
          customHeaders: const <String, String>{'x-apigee-key': 'secret'},
          completionsClient: completionsClient,
          environment: agentEngineEnv,
        );
        expect(apigeeOpenAi.excludeRuntimeTag(), isTrue);
        expect(
          apigeeOpenAi.clientHttpOptions.headers['x-goog-api-client'],
          isNot(contains('+remote_reasoning_engine')),
        );

        await apigeeOpenAi
            .generateContent(
              LlmRequest(
                model: 'apigee/openai/gpt-4o-mini',
                contents: <Content>[Content.userText('hello')],
              ),
            )
            .toList();
        expect(completionsClient.lastHeaders, isNotNull);
        expect(completionsClient.lastHeaders!['x-apigee-key'], 'secret');
        expect(
          completionsClient.lastHeaders!['x-goog-api-client'],
          contains('google-adk/'),
        );
        expect(
          completionsClient.lastHeaders!['x-goog-api-client'],
          isNot(contains('+remote_reasoning_engine')),
        );
      },
    );
  });

  group(
    '5. 43e959ee4: Stop retrying context cache creation on models that refuse it',
    () {
      setUp(clearExplicitCachingRefusalCacheForTest);
      tearDown(clearExplicitCachingRefusalCacheForTest);

      test(
        'remembers refusal for (scope, model) and skips retries on subsequent turns',
        () async {
          final _ConfigurableGeminiCacheClient client =
              _ConfigurableGeminiCacheClient(
                createError: StateError(
                  '400 INVALID_ARGUMENT: Model gemini-4.0-pro does not support explicit context caching.',
                ),
              );
          final GeminiContextCacheManager manager = GeminiContextCacheManager(
            cacheClient: client,
            backend: 'gemini',
          );

          // Turn 1: fingerprint-only
          final LlmRequest turn1 = LlmRequest(
            model: 'gemini-4.0-pro',
            contents: <Content>[Content.userText('hello')],
            cacheConfig: ContextCacheConfig(minTokens: 10),
          );
          final CacheMetadata? meta1 = await manager.handleContextCaching(
            turn1,
          );
          expect(meta1, isNotNull);
          expect(meta1!.cacheName, isNull);
          expect(client.createCalls, 0);

          // Turn 2: attempts cache creation -> refused -> remembered
          final LlmRequest turn2 = LlmRequest(
            model: 'gemini-4.0-pro',
            contents: <Content>[
              Content.userText('hello'),
              Content.userText('world'),
            ],
            cacheConfig: ContextCacheConfig(minTokens: 10),
            cacheMetadata: meta1,
            cacheableContentsTokenCount: 5000,
          );
          final CacheMetadata? meta2 = await manager.handleContextCaching(
            turn2,
          );
          expect(meta2, isNotNull);
          expect(meta2!.cacheName, isNull);
          expect(client.createCalls, 1);

          // Turn 3: same model & scope -> does NOT call createCache again
          final LlmRequest turn3 = LlmRequest(
            model: 'gemini-4.0-pro',
            contents: <Content>[
              Content.userText('hello'),
              Content.userText('world'),
              Content.userText('again'),
            ],
            cacheConfig: ContextCacheConfig(minTokens: 10),
            cacheMetadata: meta2,
            cacheableContentsTokenCount: 6000,
          );
          final CacheMetadata? meta3 = await manager.handleContextCaching(
            turn3,
          );
          expect(meta3, isNotNull);
          expect(meta3!.cacheName, isNull);
          expect(client.createCalls, 1);

          // Different scope still attempts cache creation
          final GeminiContextCacheManager otherScopeManager =
              GeminiContextCacheManager(
                cacheClient: client,
                backend: 'vertex',
                project: 'p1',
                location: 'us-central1',
              );
          final LlmRequest otherTurn1 = LlmRequest(
            model: 'gemini-4.0-pro',
            contents: <Content>[Content.userText('hello')],
            cacheConfig: ContextCacheConfig(minTokens: 10),
          );
          final CacheMetadata? otherMeta1 = await otherScopeManager
              .handleContextCaching(otherTurn1);
          final LlmRequest otherTurn2 = LlmRequest(
            model: 'gemini-4.0-pro',
            contents: <Content>[
              Content.userText('hello'),
              Content.userText('world'),
            ],
            cacheConfig: ContextCacheConfig(minTokens: 10),
            cacheMetadata: otherMeta1,
            cacheableContentsTokenCount: 5000,
          );
          await otherScopeManager.handleContextCaching(otherTurn2);
          expect(client.createCalls, 2);
        },
      );

      test('does not permanently suppress retries on transient errors', () async {
        final _ConfigurableGeminiCacheClient client =
            _ConfigurableGeminiCacheClient(
              createError: StateError('503 UNAVAILABLE: transient error'),
            );
        final GeminiContextCacheManager manager = GeminiContextCacheManager(
          cacheClient: client,
        );

        final LlmRequest turn1 = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('hello')],
          cacheConfig: ContextCacheConfig(minTokens: 10),
        );
        final CacheMetadata? meta1 = await manager.handleContextCaching(turn1);

        final LlmRequest turn2 = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[
            Content.userText('hello'),
            Content.userText('world'),
          ],
          cacheConfig: ContextCacheConfig(minTokens: 10),
          cacheMetadata: meta1,
          cacheableContentsTokenCount: 5000,
        );
        final CacheMetadata? meta2 = await manager.handleContextCaching(turn2);
        expect(client.createCalls, 1);

        client.createError = null;
        final LlmRequest turn3 = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[
            Content.userText('hello'),
            Content.userText('world'),
            Content.userText('again'),
          ],
          cacheConfig: ContextCacheConfig(minTokens: 10),
          cacheMetadata: meta2,
          cacheableContentsTokenCount: 10000,
        );
        final CacheMetadata? meta3 = await manager.handleContextCaching(turn3);
        expect(client.createCalls, 2);
        expect(meta3?.cacheName, 'caches/created-2');
      });
    },
  );

  group('6. 3256db08c: Attach agent cachedContent seed on initial turn', () {
    test(
      'attaches pre-created seed cache on turn 1, reuses on turn 2, and never deletes it',
      () async {
        final _ConfigurableGeminiCacheClient client =
            _ConfigurableGeminiCacheClient();
        final GeminiContextCacheManager manager = GeminiContextCacheManager(
          cacheClient: client,
        );

        // Turn 1 with cachedContent seed
        final LlmRequest turn1 = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('first question')],
          config: GenerateContentConfig(
            systemInstruction: 'Static system instruction',
            cachedContent: 'caches/pre-created-seed',
          ),
          cacheConfig: ContextCacheConfig(ttlSeconds: 600, cacheIntervals: 5),
        );

        final CacheMetadata? meta1 = await manager.handleContextCaching(turn1);
        expect(meta1, isNotNull);
        expect(meta1!.cacheName, 'caches/pre-created-seed');
        expect(meta1.createdAt, isNull);
        expect(meta1.contentsCount, 0);
        expect(meta1.invocationsUsed, 1);
        expect(turn1.config.cachedContent, 'caches/pre-created-seed');
        expect(turn1.config.systemInstruction, isNull);
        expect(turn1.contents.length, 1);
        expect(client.createCalls, 0);

        // Turn 2 with same seed cache -> reuses seed cache
        final LlmRequest turn2 = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[
            Content.userText('first question'),
            Content.userText('second question'),
          ],
          config: GenerateContentConfig(
            systemInstruction: 'Static system instruction',
            cachedContent: 'caches/pre-created-seed',
          ),
          cacheConfig: ContextCacheConfig(ttlSeconds: 600, cacheIntervals: 5),
          cacheMetadata: meta1,
        );
        final CacheMetadata? meta2 = await manager.handleContextCaching(turn2);
        expect(meta2, isNotNull);
        expect(meta2!.cacheName, 'caches/pre-created-seed');
        expect(meta2.invocationsUsed, 2);
        expect(meta2.createdAt, isNull);
        expect(turn2.config.systemInstruction, isNull);
        expect(turn2.contents.length, 2);

        // Turn 3: seed cache unset -> invalidated, NOT deleted, cachedContent cleared
        final LlmRequest turn3 = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[
            Content.userText('first question'),
            Content.userText('second question'),
            Content.userText('third question'),
          ],
          config: GenerateContentConfig(
            systemInstruction: 'Static system instruction',
            cachedContent: null,
          ),
          cacheConfig: ContextCacheConfig(ttlSeconds: 600, cacheIntervals: 5),
          cacheMetadata: meta2,
        );
        final CacheMetadata? meta3 = await manager.handleContextCaching(turn3);
        expect(meta3, isNotNull);
        expect(meta3!.cacheName, isNull);
        expect(turn3.config.cachedContent, isNull);
        expect(client.deleteCalls, 0);
      },
    );
  });

  group(
    '7. 6959bac7b: Accept content lists in Interactions code execution results',
    () {
      test(
        'converts code_execution_result content list into CodeExecutionResult + media parts',
        () {
          final String pngBase64 = base64Encode(<int>[137, 80, 78, 71]);
          final LlmResponse response = convertInteractionToLlmResponse(
            <String, Object?>{
              'id': 'int-code-1',
              'status': 'completed',
              'outputs': <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'code_execution_result',
                  'is_error': false,
                  'result': <Map<String, Object?>>[
                    <String, Object?>{'type': 'text', 'text': 'line1\n'},
                    <String, Object?>{
                      'type': 'image',
                      'mime_type': 'image/png',
                      'data': pngBase64,
                    },
                    <String, Object?>{'type': 'text', 'text': 'line2'},
                    <String, Object?>{
                      'type': 'document',
                      'mime_type': 'application/pdf',
                      'uri': 'gs://bucket/report.pdf',
                    },
                    <String, Object?>{'type': 'unknown_type', 'foo': 'bar'},
                  ],
                },
              ],
            },
          );

          expect(response.content, isNotNull);
          final List<Part> parts = response.content!.parts;
          expect(parts.length, 3);

          final Map<String, Object?> codeResult =
              parts[0].codeExecutionResult as Map<String, Object?>;
          expect(codeResult['output'], 'line1\nline2');
          expect(codeResult['outcome'], 'OUTCOME_OK');

          expect(parts[1].inlineData, isNotNull);
          expect(parts[1].inlineData!.mimeType, 'image/png');
          expect(parts[1].inlineData!.data, <int>[137, 80, 78, 71]);

          expect(parts[2].fileData, isNotNull);
          expect(parts[2].fileData!.fileUri, 'gs://bucket/report.pdf');
          expect(parts[2].fileData!.mimeType, 'application/pdf');
        },
      );

      test('preserves legacy string result and error outcome', () {
        final List<Part> parts = convertInteractionOutputToParts(
          <String, Object?>{
            'type': 'code_execution_result',
            'is_error': true,
            'result': 'ZeroDivisionError',
          },
        );
        expect(parts.length, 1);
        final Map<String, Object?> codeResult =
            parts.single.codeExecutionResult as Map<String, Object?>;
        expect(codeResult['output'], 'ZeroDivisionError');
        expect(codeResult['outcome'], 'OUTCOME_FAILED');
      });
    },
  );

  group('8. de1d3079e: LiteLlm treats Gemini 4+ as Gemini 3 or newer', () {
    test('maps thinking_budget=0 to reasoning_effort=none on Gemini 4+', () {
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        LlmRequest(
          model: 'gemini/gemini-4.0-pro',
          contents: <Content>[Content.userText('hi')],
          config: GenerateContentConfig(
            thinkingConfig: const <String, Object?>{'thinking_budget': 0},
          ),
        ),
        stream: false,
      );
      expect(payload['reasoning_effort'], 'none');
      expect(payload.containsKey('thinking'), isFalse);
    });

    test('maps positive thinking_budget to reasoning_effort on Gemini 4+', () {
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        LlmRequest(
          model: 'vertex_ai/gemini-4-flash',
          contents: <Content>[Content.userText('hi')],
          config: GenerateContentConfig(
            thinkingConfig: const <String, Object?>{'thinking_budget': 2048},
          ),
        ),
        stream: false,
      );
      expect(payload['reasoning_effort'], 'medium');
      expect(payload.containsKey('thinking'), isFalse);
    });

    test(
      'does not inject thinking={type: enabled} for include_thoughts=true on Gemini 4+',
      () {
        final Map<String, Object?> payload = LiteLlm.buildPayload(
          LlmRequest(
            model: 'gemini/gemini-4.0-pro',
            contents: <Content>[Content.userText('hi')],
            config: GenerateContentConfig(
              thinkingConfig: const <String, Object?>{'include_thoughts': true},
            ),
          ),
          stream: false,
        );
        expect(payload.containsKey('thinking'), isFalse);
      },
    );

    test('keeps Gemini 2.5 on legacy thinking budget dict format', () {
      final Map<String, Object?> payload = LiteLlm.buildPayload(
        LlmRequest(
          model: 'gemini/gemini-2.5-flash',
          contents: <Content>[Content.userText('hi')],
          config: GenerateContentConfig(
            thinkingConfig: const <String, Object?>{'thinking_budget': 0},
          ),
        ),
        stream: false,
      );
      expect(payload['thinking'], <String, Object?>{
        'type': 'enabled',
        'budget_tokens': 0,
      });
      expect(payload.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('9. FeatureRegistry updates (c6586f19a..fb08c7842)', () {
    test(
      'registers BUFFERED_SESSION_SERVICE and CHECK_GROUNDING as experimental defaultOn=true',
      () {
        expect(
          FeatureName.bufferedSessionService.value,
          'BUFFERED_SESSION_SERVICE',
        );
        expect(FeatureName.checkGrounding.value, 'CHECK_GROUNDING');

        final FeatureConfig? bufferedConfig = getFeatureConfig(
          FeatureName.bufferedSessionService,
        );
        expect(bufferedConfig, isNotNull);
        expect(bufferedConfig!.stage, FeatureStage.experimental);
        expect(bufferedConfig.defaultOn, isTrue);

        final FeatureConfig? groundingConfig = getFeatureConfig(
          FeatureName.checkGrounding,
        );
        expect(groundingConfig, isNotNull);
        expect(groundingConfig!.stage, FeatureStage.experimental);
        expect(groundingConfig.defaultOn, isTrue);
      },
    );
  });
}
