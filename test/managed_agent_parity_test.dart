import 'dart:async';
import 'package:test/test.dart';
import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/models/gemini_rest_api_client.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';

class MockGeminiRestTransport implements GeminiRestTransport {
  MockGeminiRestTransport(this.streamResponse);

  final Stream<Map<String, Object?>> streamResponse;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  final List<Map<String, String>> headersList = <Map<String, String>>[];

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> createInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<Map<String, Object?>> streamCreateInteraction({
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    String apiVersion = 'v1beta',
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) {
    payloads.add(payload);
    if (headers != null) {
      headersList.add(headers);
    }
    return streamResponse;
  }
}

void main() {
  group('ManagedAgent parity', () {
    test('construction sets fields correctly', () {
      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        environment: <String, String>{'type': 'remote'},
        agentConfig: <String, Object?>{'temperature': 0.7},
        mode: 'single_turn',
      );

      expect(agent.name, equals('mgr'));
      expect(agent.agentId, equals('projects/123/locations/global/agents/456'));
      expect(agent.environment, equals(<String, String>{'type': 'remote'}));
      expect(agent.agentConfig, equals(<String, Object?>{'temperature': 0.7}));
      expect(agent.mode, equals('single_turn'));
      expect(agent.tools, isEmpty);
    });

    test('resolveTools maps ToolDeclaration and RemoteMcpServer', () async {
      final RemoteMcpServer mcpServer = RemoteMcpServer(
        url: 'https://mcp-server/api',
        name: 'my-mcp',
        headers: <String, String>{'x-static': 'foo'},
        allowedTools: <String>['tool-a', 'tool-b'],
        headerProvider: (ReadonlyContext ctx) async {
          return <String, String>{'x-dynamic': 'bar'};
        },
      );

      final ToolDeclaration urlContextTool = ToolDeclaration(
        urlContext: const <String, Object?>{},
      );

      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        tools: <Object>[mcpServer, urlContextTool],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );
      final InvocationContext context = InvocationContext(
        invocationId: 'inv1',
        sessionService: sessionService,
        session: session,
        agent: agent,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'hello')],
        ),
      );

      final List<Map<String, Object?>> resolvedTools =
          await agent.resolveBackendTools(context);

      expect(resolvedTools, hasLength(2));

      final Map<String, Object?> resolvedMcp = resolvedTools.firstWhere(
        (Map<String, Object?> t) => t['type'] == 'mcp_server',
      );
      expect(resolvedMcp['url'], equals('https://mcp-server/api'));
      expect(resolvedMcp['name'], equals('my-mcp'));
      expect(
        resolvedMcp['headers'],
        equals(<String, String>{
          'x-static': 'foo',
          'x-dynamic': 'bar',
        }),
      );
      expect(
        resolvedMcp['allowed_tools'],
        equals(<Map<String, Object?>>[
          <String, Object?>{
            'tools': <String>['tool-a', 'tool-b']
          }
        ]),
      );

      final Map<String, Object?> resolvedUrl = resolvedTools.firstWhere(
        (Map<String, Object?> t) => t['type'] == 'url_context',
      );
      expect(resolvedUrl, isNotNull);
    });

    test('resolveTools rejects client-executed tools', () async {
      final FunctionTool clientTool = FunctionTool(
        name: 'client_fn',
        description: 'run on client',
        func: (Map<String, Object?> args) async => <String, Object?>{},
      );

      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        tools: <Object>[clientTool],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );
      final InvocationContext context = InvocationContext(
        invocationId: 'inv1',
        sessionService: sessionService,
        session: session,
        agent: agent,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'hello')],
        ),
      );

      expect(
        () => agent.resolveBackendTools(context),
        throwsUnsupportedError,
      );
    });

    test('runAsyncImpl creates connection payload and recovers environment/interaction states', () async {
      final StreamController<Map<String, Object?>> controller =
          StreamController<Map<String, Object?>>();
      final MockGeminiRestTransport transport = MockGeminiRestTransport(controller.stream);

      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        environment: 'my-env',
        restClient: transport,
        apiKey: 'fake-key',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );

      // First run - starts new environment and interaction
      final InvocationContext context1 = InvocationContext(
        invocationId: 'inv1',
        sessionService: sessionService,
        session: session,
        agent: agent,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'hello')],
        ),
      );

      final List<Event> events1 = <Event>[];
      final Stream<Event> run1 = agent.runAsync(context1);
      final Future<void> drain1 = run1.forEach(events1.add);

      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'environment_id': 'env_456',
        'status': 'completed',
        'outputs': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'Hello user!',
          }
        ],
      });
      await controller.close();
      await drain1;

      expect(events1, hasLength(1));
      expect(events1.first.content!.parts.first.text, equals('Hello user!'));
      expect(events1.first.interactionId, equals('interaction_123'));
      expect(events1.first.environmentId, equals('env_456'));

      expect(transport.payloads, hasLength(1));
      expect(transport.payloads.first['agent'], equals('projects/123/locations/global/agents/456'));
      expect(transport.payloads.first['environment'], equals('my-env'));
      expect(transport.payloads.first['previous_interaction_id'], isNull);

      // Save the event to session
      session.events.addAll(events1);

      // Second run - recovers environment and previous interaction ID
      final StreamController<Map<String, Object?>> controller2 =
          StreamController<Map<String, Object?>>();
      final MockGeminiRestTransport transport2 = MockGeminiRestTransport(controller2.stream);
      final ManagedAgent agent2 = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        restClient: transport2,
        apiKey: 'fake-key',
      );

      final InvocationContext context2 = InvocationContext(
        invocationId: 'inv2',
        sessionService: sessionService,
        session: session,
        agent: agent2,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'continue')],
        ),
      );

      final List<Event> events2 = <Event>[];
      final Stream<Event> run2 = agent2.runAsync(context2);
      final Future<void> drain2 = run2.forEach(events2.add);

      controller2.add(<String, Object?>{
        'id': 'interaction_789',
        'environment_id': 'env_456',
        'status': 'completed',
        'outputs': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'Continuing response...',
          }
        ],
      });
      await controller2.close();
      await drain2;

      expect(transport2.payloads, hasLength(1));
      expect(transport2.payloads.first['environment'], equals('env_456'));
      expect(transport2.payloads.first['previous_interaction_id'], equals('interaction_123'));
    });

    test('runAsyncImpl handles sse streaming mode', () async {
      final StreamController<Map<String, Object?>> controller =
          StreamController<Map<String, Object?>>();
      final MockGeminiRestTransport transport = MockGeminiRestTransport(controller.stream);

      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        restClient: transport,
        apiKey: 'fake-key',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );
      final InvocationContext context = InvocationContext(
        invocationId: 'inv1',
        sessionService: sessionService,
        session: session,
        agent: agent,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'hello')],
        ),
        runConfig: RunConfig(streamingMode: StreamingMode.sse),
      );

      final List<Event> events = <Event>[];
      final Stream<Event> run = agent.runAsync(context);
      final Future<void> drain = run.forEach(events.add);

      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'content.delta',
        'delta': <String, Object?>{
          'type': 'text',
          'text': 'Hel',
        },
      });
      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'content.delta',
        'delta': <String, Object?>{
          'type': 'text',
          'text': 'lo!',
        },
      });
      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'content.stop',
      });
      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'interaction.complete',
        'interaction': <String, Object?>{
          'id': 'interaction_123',
          'status': 'completed',
        },
      });
      await controller.close();
      await drain;

      expect(events, hasLength(4));
      expect(events[0].content!.parts.first.text, equals('Hel'));
      expect(events[0].partial, isTrue);
      expect(events[1].content!.parts.first.text, equals('lo!'));
      expect(events[1].partial, isTrue);

      final String textEvent2 = events[2].content!.parts.map((p) => p.text ?? '').join();
      expect(textEvent2, equals('Hello!'));
      expect(events[2].partial, isFalse);
      expect(events[2].turnComplete, isFalse);

      expect(events[3].content, isNull);
      expect(events[3].partial, isNull);
      expect(events[3].turnComplete, isTrue);
    });

    test('runAsyncImpl handles non-streaming mode (NONE)', () async {
      final StreamController<Map<String, Object?>> controller =
          StreamController<Map<String, Object?>>();
      final MockGeminiRestTransport transport = MockGeminiRestTransport(controller.stream);

      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        restClient: transport,
        apiKey: 'fake-key',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );
      final InvocationContext context = InvocationContext(
        invocationId: 'inv1',
        sessionService: sessionService,
        session: session,
        agent: agent,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'hello')],
        ),
        runConfig: RunConfig(streamingMode: StreamingMode.none),
      );

      final List<Event> events = <Event>[];
      final Stream<Event> run = agent.runAsync(context);
      final Future<void> drain = run.forEach(events.add);

      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'content.delta',
        'delta': <String, Object?>{
          'type': 'text',
          'text': 'Hel',
        },
      });
      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'content.delta',
        'delta': <String, Object?>{
          'type': 'text',
          'text': 'lo!',
        },
      });
      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'content.stop',
      });
      controller.add(<String, Object?>{
        'id': 'interaction_123',
        'event_type': 'interaction.complete',
        'interaction': <String, Object?>{
          'id': 'interaction_123',
          'status': 'completed',
        },
      });
      await controller.close();
      await drain;

      expect(events, hasLength(2));
      final String textEvent0 = events[0].content!.parts.map((p) => p.text ?? '').join();
      expect(textEvent0, equals('Hello!'));
      expect(events[0].partial, isFalse);
      expect(events[0].turnComplete, isFalse);

      expect(events[1].content, isNull);
      expect(events[1].partial, isNull);
      expect(events[1].turnComplete, isTrue);
    });

    test('runAsyncImpl handles API errors gracefully', () async {
      final StreamController<Map<String, Object?>> controller =
          StreamController<Map<String, Object?>>();
      final MockGeminiRestTransport transport = MockGeminiRestTransport(controller.stream);

      final ManagedAgent agent = ManagedAgent(
        name: 'mgr',
        agentId: 'projects/123/locations/global/agents/456',
        restClient: transport,
        apiKey: 'fake-key',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );
      final InvocationContext context = InvocationContext(
        invocationId: 'inv1',
        sessionService: sessionService,
        session: session,
        agent: agent,
        userContent: Content(
          role: 'user',
          parts: <Part>[Part(text: 'hello')],
        ),
      );

      final List<Event> events = <Event>[];
      final Stream<Event> run = agent.runAsync(context);
      final Future<void> drain = run.forEach(events.add);

      controller.addError(Exception('API failure'));
      await controller.close();
      await drain;

      expect(events, hasLength(1));
      expect(events.first.errorCode, equals('UNKNOWN_ERROR'));
      expect(events.first.errorMessage, contains('API failure'));
      expect(events.first.turnComplete, isTrue);
    });
  });
}
