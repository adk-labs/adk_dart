import 'dart:async';

import 'package:adk_dart/src/a2a/protocol.dart';
import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/agents/managed_agent.dart';
import 'package:adk_dart/src/agents/mcp_instruction_provider.dart';
import 'package:adk_dart/src/agents/parallel_agent.dart';
import 'package:adk_dart/src/agents/readonly_context.dart';
import 'package:adk_dart/src/agents/remote_a2a_agent.dart';
import 'package:adk_dart/src/agents/sequential_agent.dart';
import 'package:adk_dart/src/apps/app.dart' show ResumabilityConfig;
import 'package:adk_dart/src/errors/session_persistence_error.dart';
import 'package:adk_dart/src/errors/stale_session_error.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/event_actions.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/flows/llm_flows/functions.dart'
    show requestInputFunctionCallName;
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/gemini_rest_api_client.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/plugins/multimodal_tool_results_plugin.dart';
import 'package:adk_dart/src/sessions/base_session_service.dart';
import 'package:adk_dart/src/sessions/buffered_session_service.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_session_manager.dart';
import 'package:adk_dart/src/tools/tool_context.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/utils/agent_info.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _CapturingRestTransport extends GeminiRestTransport {
  String? lastApiVersion;
  String? lastBaseUrl;

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
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
  }) async* {
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
  }) async* {
    lastApiVersion = apiVersion;
    lastBaseUrl = baseUrl;
    yield <String, Object?>{
      'id': 'inter_1',
      'event_type': 'content.delta',
      'delta': <String, Object?>{'type': 'text', 'text': 'hello managed'},
    };
    yield <String, Object?>{
      'id': 'inter_1',
      'event_type': 'interaction.complete',
    };
  }
}

class _SpyMcpSessionManager implements McpSessionManager {
  bool listPromptArgumentNamesCalled = false;
  Map<String, Object?>? lastPromptArguments;
  bool promptArgumentsWasPassedAsNull = false;

  @override
  Future<Set<String>> listPromptArgumentNames({
    required McpConnectionParams connectionParams,
    required String promptName,
    Map<String, String>? headers,
  }) async {
    listPromptArgumentNamesCalled = true;
    return <String>{'secret_token', 'city'};
  }

  @override
  Future<List<McpResourceContent>> readResourceAsync({
    required McpConnectionParams connectionParams,
    required String resourceName,
    Map<String, Object?>? promptArguments,
    Map<String, String>? headers,
  }) async {
    lastPromptArguments = promptArguments;
    promptArgumentsWasPassedAsNull = promptArguments == null;
    final String suffix = promptArguments == null
        ? 'none'
        : promptArguments.entries
              .map((MapEntry<String, Object?> e) => '${e.key}=${e.value}')
              .join(',');
    return <McpResourceContent>[McpResourceContent(text: 'prompt:$suffix')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeA2aClient extends A2aClient {
  _FakeA2aClient(this.responses);

  final List<Object> responses;

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) async* {
    for (final Object response in responses) {
      yield response;
    }
  }
}

class _FakeA2aClientFactory extends A2aClientFactory {
  _FakeA2aClientFactory(this.client);

  final A2aClient client;

  @override
  A2aClient create(AgentCard agentCard) => client;
}

class _BatchingInMemorySessionService extends InMemorySessionService {
  final List<int> batchSizes = <int>[];
  Object? Function(Session session, List<Event> events)? onBeforeAppend;
  int appendAttempts = 0;

  @override
  bool get supportsBatchAppendEvents => true;

  @override
  Future<List<Event>> appendEvents({
    required Session session,
    required List<Event> events,
  }) async {
    appendAttempts += 1;
    final Object? error = onBeforeAppend?.call(session, events);
    if (error != null) {
      throw error;
    }
    batchSizes.add(events.length);
    return super.appendEvents(session: session, events: events);
  }
}

class _FakeTool extends BaseTool {
  _FakeTool() : super(name: 'media_tool', description: 'returns media');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, dynamic>{'result': 'ok'};
  }
}

InvocationContext _newCtx(
  BaseAgent agent, {
  Map<String, Object?>? state,
  Content? userContent,
  bool resumable = false,
  Session? session,
  BaseSessionService? sessionService,
}) {
  return InvocationContext(
    sessionService: sessionService ?? InMemorySessionService(),
    invocationId: 'inv_nov19',
    agent: agent,
    session:
        session ??
        Session(
          id: 's_nov19',
          appName: 'app',
          userId: 'u1',
          state: state ?? <String, Object?>{},
        ),
    userContent: userContent,
    resumabilityConfig: ResumabilityConfig(isResumable: resumable),
  );
}

void main() {
  group('1. BaseAgent.toString() excludes parentAgent (8ec642c12)', () {
    test('printing child does not include parent or recurse infinitely', () {
      final LlmAgent leaf = LlmAgent(
        name: 'leaf_agent',
        description: 'leaf',
        model: _NoopModel(),
      );
      final LlmAgent mid = LlmAgent(
        name: 'mid_agent',
        description: 'mid',
        model: _NoopModel(),
        subAgents: <BaseAgent>[leaf],
      );
      final LlmAgent root = LlmAgent(
        name: 'root_agent',
        description: 'root',
        model: _NoopModel(),
        subAgents: <BaseAgent>[mid],
      );

      expect(leaf.parentAgent, same(mid));
      expect(mid.parentAgent, same(root));

      final String leafStr = leaf.toString();
      final String rootStr = root.toString();

      expect(leafStr, contains('leaf_agent'));
      expect(leafStr, isNot(contains('mid_agent')));
      expect(leafStr, isNot(contains('root_agent')));
      expect(rootStr, contains('root_agent'));
      expect(rootStr, contains('mid_agent'));
      expect(rootStr, contains('leaf_agent'));
    });
  });

  group('2. ManagedAgent Developer API v1beta (30cb66ec1)', () {
    test('defaults to v1beta on Developer API transport', () async {
      final _CapturingRestTransport transport = _CapturingRestTransport();
      final ManagedAgent agent = ManagedAgent(
        name: 'managed_v1beta',
        agentId: 'antigravity-preview',
        apiKey: 'test-key',
        restClient: transport,
      );
      final InvocationContext ctx = _newCtx(
        agent,
        userContent: Content.userText('hi'),
      );

      final List<Event> events = await agent.runAsync(ctx).toList();

      expect(events, isNotEmpty);
      expect(transport.lastApiVersion, 'v1beta');
    });

    test('caller-supplied apiVersion overrides default v1beta', () async {
      final _CapturingRestTransport transport = _CapturingRestTransport();
      final ManagedAgent agent = ManagedAgent(
        name: 'managed_explicit_version',
        agentId: 'antigravity-preview',
        apiKey: 'test-key',
        apiVersion: 'v1',
        restClient: transport,
      );
      final InvocationContext ctx = _newCtx(
        agent,
        userContent: Content.userText('hi'),
      );

      await agent.runAsync(ctx).toList();

      expect(transport.lastApiVersion, 'v1');
    });
  });

  group('3. LlmAgent cachedContent seed (3256db08c)', () {
    test('accepts and preserves cachedContent in generateContentConfig', () {
      final LlmAgent agent = LlmAgent(
        name: 'cached_agent',
        model: _NoopModel(),
        generateContentConfig: GenerateContentConfig(
          cachedContent: 'cachedContents/seed_123',
        ),
      );
      expect(
        agent.generateContentConfig?.cachedContent,
        'cachedContents/seed_123',
      );
      final LlmAgent cloned = agent.clone();
      expect(
        cloned.generateContentConfig?.cachedContent,
        'cachedContents/seed_123',
      );
    });
  });

  group('4. McpInstructionProvider session state isolation (889ddd313)', () {
    test(
      'does not consult listPromptArgumentNames or read session state when arguments is null',
      () async {
        final _SpyMcpSessionManager spy = _SpyMcpSessionManager();
        final McpInstructionProvider provider = McpInstructionProvider(
          connectionParams: StreamableHTTPConnectionParams(url: 'mock://mcp'),
          promptName: 'sys_prompt',
          sessionManager: spy,
        );
        final InvocationContext ctx = _newCtx(
          LlmAgent(name: 'root', model: _NoopModel()),
          state: <String, Object?>{
            'secret_token': 'top_secret_value',
            'city': 'Seoul',
          },
        );

        final String result = await provider(ReadonlyContext(ctx));

        expect(spy.listPromptArgumentNamesCalled, isFalse);
        expect(spy.promptArgumentsWasPassedAsNull, isTrue);
        expect(spy.lastPromptArguments, isNull);
        expect(result, 'prompt:none');
      },
    );

    test('passes explicit static arguments map', () async {
      final _SpyMcpSessionManager spy = _SpyMcpSessionManager();
      final McpInstructionProvider provider = McpInstructionProvider(
        connectionParams: StreamableHTTPConnectionParams(url: 'mock://mcp'),
        promptName: 'sys_prompt',
        arguments: <String, String>{'locale': 'ko-KR'},
        sessionManager: spy,
      );
      final InvocationContext ctx = _newCtx(
        LlmAgent(name: 'root', model: _NoopModel()),
        state: <String, Object?>{'secret_token': 'do_not_leak'},
      );

      final String result = await provider(ReadonlyContext(ctx));

      expect(spy.listPromptArgumentNamesCalled, isFalse);
      expect(spy.lastPromptArguments, <String, Object?>{'locale': 'ko-KR'});
      expect(result, 'prompt:locale=ko-KR');
    });

    test('passes callable arguments built from ReadonlyContext', () async {
      final _SpyMcpSessionManager spy = _SpyMcpSessionManager();
      final McpInstructionProvider provider = McpInstructionProvider(
        connectionParams: StreamableHTTPConnectionParams(url: 'mock://mcp'),
        promptName: 'sys_prompt',
        arguments: (ReadonlyContext ctx) => <String, String>{
          'city': '${ctx.state['city']}',
        },
        sessionManager: spy,
      );
      final InvocationContext ctx = _newCtx(
        LlmAgent(name: 'root', model: _NoopModel()),
        state: <String, Object?>{
          'secret_token': 'do_not_leak',
          'city': 'Busan',
        },
      );

      final String result = await provider(ReadonlyContext(ctx));

      expect(spy.listPromptArgumentNamesCalled, isFalse);
      expect(spy.lastPromptArguments, <String, Object?>{'city': 'Busan'});
      expect(result, 'prompt:city=Busan');
    });
  });

  group('5. RemoteA2aAgent streamed output without lastChunk (dbae28d3c)', () {
    AgentCard makeCard() => AgentCard(
      name: 'remote_agent',
      description: 'remote',
      url: 'https://example.invalid/a2a',
      version: '1.0.0',
      capabilities: AgentCapabilities(streaming: true),
      defaultInputModes: <String>['text/plain'],
      defaultOutputModes: <String>['text/plain'],
      skills: <AgentSkill>[],
    );

    test(
      'persists streamed partial artifact chunks on TaskStatusUpdateEvent boundary',
      () async {
        final A2aTask workingTask = A2aTask(
          id: 'task_1',
          contextId: 'ctx_1',
          status: A2aTaskStatus(state: A2aTaskState.working),
        );
        final A2aTask completedTask = A2aTask(
          id: 'task_1',
          contextId: 'ctx_1',
          status: A2aTaskStatus(state: A2aTaskState.completed),
        );

        final _FakeA2aClient client = _FakeA2aClient(<Object>[
          (
            workingTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_1',
              artifact: A2aArtifact(
                artifactId: 'art_1',
                parts: <A2aPart>[A2aPart.text('Hello ')],
              ),
              append: false,
              lastChunk: false,
            ),
          ),
          (
            workingTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_1',
              artifact: A2aArtifact(
                artifactId: 'art_1',
                parts: <A2aPart>[A2aPart.text('world!')],
              ),
              append: true,
              lastChunk: false,
            ),
          ),
          (
            completedTask,
            A2aTaskStatusUpdateEvent(
              taskId: 'task_1',
              status: A2aTaskStatus(state: A2aTaskState.completed),
              finalEvent: true,
            ),
          ),
        ]);

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: makeCard(),
          a2aClientFactory: _FakeA2aClientFactory(client),
        );
        final InvocationContext ctx = _newCtx(
          agent,
          userContent: Content.userText('say hi'),
        );

        final List<Event> events = await agent.runAsync(ctx).toList();
        final List<Event> partials = events
            .where((Event e) => e.partial == true)
            .toList();
        final List<Event> finals = events
            .where((Event e) => e.partial != true)
            .toList();

        expect(partials, hasLength(2));
        expect(partials[0].content?.parts.single.text, 'Hello ');
        expect(partials[1].content?.parts.single.text, 'world!');
        expect(finals, hasLength(1));
        expect(finals.single.partial, isFalse);
        expect(finals.single.content?.parts.single.text, 'Hello world!');
      },
    );

    test(
      'flushes open streamed buffer when stream closes on completed task without boundary event',
      () async {
        final A2aTask completedTask = A2aTask(
          id: 'task_2',
          contextId: 'ctx_2',
          status: A2aTaskStatus(state: A2aTaskState.completed),
        );

        final _FakeA2aClient client = _FakeA2aClient(<Object>[
          (
            completedTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_2',
              artifact: A2aArtifact(
                artifactId: 'art_2',
                parts: <A2aPart>[A2aPart.text('Part A ')],
              ),
              append: false,
              lastChunk: false,
            ),
          ),
          (
            completedTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_2',
              artifact: A2aArtifact(
                artifactId: 'art_2',
                parts: <A2aPart>[A2aPart.text('Part B')],
              ),
              append: true,
              lastChunk: false,
            ),
          ),
        ]);

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: makeCard(),
          a2aClientFactory: _FakeA2aClientFactory(client),
        );
        final InvocationContext ctx = _newCtx(
          agent,
          userContent: Content.userText('go'),
        );

        final List<Event> events = await agent.runAsync(ctx).toList();
        final List<Event> finals = events
            .where((Event e) => e.partial != true)
            .toList();

        expect(finals, hasLength(1));
        expect(finals.single.content?.parts.single.text, 'Part A Part B');
      },
    );

    test(
      'handles delta closing chunk (append=true, lastChunk=true) and empty closing marker',
      () async {
        final A2aTask workingTask = A2aTask(
          id: 'task_3',
          contextId: 'ctx_3',
          status: A2aTaskStatus(state: A2aTaskState.working),
        );

        final _FakeA2aClient client = _FakeA2aClient(<Object>[
          (
            workingTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_3',
              artifact: A2aArtifact(
                artifactId: 'delta_art',
                parts: <A2aPart>[A2aPart.text('One ')],
              ),
              append: false,
              lastChunk: false,
            ),
          ),
          (
            workingTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_3',
              artifact: A2aArtifact(
                artifactId: 'delta_art',
                parts: <A2aPart>[A2aPart.text('Two')],
              ),
              append: true,
              lastChunk: true,
            ),
          ),
          (
            workingTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_3',
              artifact: A2aArtifact(
                artifactId: 'marker_art',
                parts: <A2aPart>[A2aPart.text('Marker body')],
              ),
              append: false,
              lastChunk: false,
            ),
          ),
          (
            workingTask,
            A2aTaskArtifactUpdateEvent(
              taskId: 'task_3',
              artifact: A2aArtifact(
                artifactId: 'marker_art',
                parts: <A2aPart>[],
              ),
              append: true,
              lastChunk: true,
            ),
          ),
          (
            A2aTask(
              id: 'task_3',
              contextId: 'ctx_3',
              status: A2aTaskStatus(state: A2aTaskState.completed),
            ),
            A2aTaskStatusUpdateEvent(
              taskId: 'task_3',
              status: A2aTaskStatus(state: A2aTaskState.completed),
              finalEvent: true,
            ),
          ),
        ]);

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: makeCard(),
          a2aClientFactory: _FakeA2aClientFactory(client),
        );
        final InvocationContext ctx = _newCtx(
          agent,
          userContent: Content.userText('stream'),
        );

        final List<Event> events = await agent.runAsync(ctx).toList();
        final List<Event> nonPartialWithText = events
            .where(
              (Event e) =>
                  e.partial != true && (e.content?.parts.isNotEmpty ?? false),
            )
            .toList();

        expect(nonPartialWithText, hasLength(2));
        expect(nonPartialWithText[0].content?.parts.single.text, 'One Two');
        expect(nonPartialWithText[1].content?.parts.single.text, 'Marker body');
      },
    );
  });

  group(
    '6. Sessions: appendEvents, BufferedSessionService, out-of-order getSession',
    () {
      test(
        'InMemorySessionService.getSession keeps out-of-order timestamp events when filtering (b7c9c40f8)',
        () async {
          final InMemorySessionService service = InMemorySessionService();
          final Session session = await service.createSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_ooo',
          );

          // Appended out of timestamp order: 200, 100, 300, 150
          await service.appendEvents(
            session: session,
            events: <Event>[
              Event(invocationId: 'i', author: 'a', id: 'e1', timestamp: 200.0),
              Event(invocationId: 'i', author: 'a', id: 'e2', timestamp: 100.0),
              Event(invocationId: 'i', author: 'a', id: 'e3', timestamp: 300.0),
              Event(invocationId: 'i', author: 'a', id: 'e4', timestamp: 150.0),
            ],
          );

          final Session? filtered = await service.getSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_ooo',
            config: GetSessionConfig(afterTimestamp: 150.0),
          );
          expect(filtered!.events.map((Event e) => e.id).toList(), <String>[
            'e1',
            'e3',
            'e4',
          ]);

          final Session? recentFiltered = await service.getSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_ooo',
            config: GetSessionConfig(afterTimestamp: 150.0, numRecentEvents: 2),
          );
          expect(
            recentFiltered!.events.map((Event e) => e.id).toList(),
            <String>['e3', 'e4'],
          );
        },
      );

      test(
        'BufferedSessionService batches writes via appendEvents and flushes on read',
        () async {
          final _BatchingInMemorySessionService delegate =
              _BatchingInMemorySessionService();
          final BufferedSessionService buffered = BufferedSessionService(
            delegate,
            config: BufferedSessionServiceConfig(
              maxWriteDelay: const Duration(milliseconds: 5),
              maxBatchEvents: 10,
            ),
          );

          final Session session = await buffered.createSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_batch',
          );

          await buffered.appendEvent(
            session: session,
            event: Event(
              invocationId: 'inv1',
              author: 'agent',
              id: 'ev1',
              actions: EventActions(stateDelta: <String, Object?>{'k': 1}),
            ),
          );
          await buffered.appendEvent(
            session: session,
            event: Event(
              invocationId: 'inv1',
              author: 'agent',
              id: 'ev2',
              actions: EventActions(stateDelta: <String, Object?>{'k': 2}),
            ),
          );
          await buffered.appendEvent(
            session: session,
            event: Event(
              invocationId: 'inv1',
              author: 'agent',
              id: 'ev3',
              actions: EventActions(
                stateDelta: <String, Object?>{'user:u': 'v'},
              ),
            ),
          );

          // Live session updated immediately
          expect(session.events.map((Event e) => e.id), <String>[
            'ev1',
            'ev2',
            'ev3',
          ]);
          expect(session.state['k'], 2);

          // Reading waits for buffered writes and flushes them in a single batch
          final Session? stored = await buffered.getSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_batch',
          );
          expect(stored!.events.map((Event e) => e.id), <String>[
            'ev1',
            'ev2',
            'ev3',
          ]);
          expect(stored.state['k'], 2);
          expect(stored.state['user:u'], 'v');
          expect(delegate.batchSizes, <int>[3]);

          await buffered.close();
          expect(
            () => buffered.appendEvent(
              session: session,
              event: Event(invocationId: 'inv1', author: 'agent', id: 'ev4'),
            ),
            throwsStateError,
          );
        },
      );

      test(
        'BufferedSessionService surfaces SessionPersistenceError and retries transient errors',
        () async {
          final _BatchingInMemorySessionService delegate =
              _BatchingInMemorySessionService();
          int remainingFailures = 2;
          delegate.onBeforeAppend = (Session s, List<Event> events) {
            if (remainingFailures > 0) {
              remainingFailures -= 1;
              return StateError('transient boom');
            }
            return null;
          };

          final BufferedSessionService retrying = BufferedSessionService(
            delegate,
            config: BufferedSessionServiceConfig(
              retryConfig: const RetryConfig(
                maxAttempts: 3,
                initialDelay: Duration(milliseconds: 1),
                jitter: 0.0,
              ),
            ),
          );
          final Session s1 = await retrying.createSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_retry',
          );
          await retrying.appendEvent(
            session: s1,
            event: Event(invocationId: 'i', author: 'a', id: 'e_ok'),
          );
          await retrying.flushSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_retry',
          );
          expect(delegate.appendAttempts, 3);
          await retrying.close();

          // Non-retried StaleSessionError surfaces SessionPersistenceError
          final _BatchingInMemorySessionService staleDelegate =
              _BatchingInMemorySessionService();
          bool failStale = true;
          staleDelegate.onBeforeAppend = (Session s, List<Event> events) {
            if (failStale) {
              return StaleSessionError('stale version');
            }
            return null;
          };
          final BufferedSessionService bufferedStale = BufferedSessionService(
            staleDelegate,
            config: BufferedSessionServiceConfig(
              retryConfig: const RetryConfig(
                maxAttempts: 5,
                initialDelay: Duration(milliseconds: 1),
                jitter: 0.0,
              ),
            ),
          );
          final Session s2 = await bufferedStale.createSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_stale',
          );
          await bufferedStale.appendEvent(
            session: s2,
            event: Event(invocationId: 'i', author: 'a', id: 'e_stale'),
          );
          await expectLater(
            bufferedStale.flushSession(
              appName: 'app',
              userId: 'u1',
              sessionId: 's_stale',
            ),
            throwsA(
              isA<SessionPersistenceError>().having(
                (SessionPersistenceError e) => e.cause,
                'cause',
                isA<StaleSessionError>(),
              ),
            ),
          );
          // StaleSessionError must never be retried
          expect(staleDelegate.appendAttempts, 1);

          // Freshly read session can append once conflict resolves
          failStale = false;
          final Session fresh = (await bufferedStale.getSession(
            appName: 'app',
            userId: 'u1',
            sessionId: 's_stale',
          ))!;
          await bufferedStale.appendEvent(
            session: fresh,
            event: Event(invocationId: 'i', author: 'a', id: 'e_fresh'),
          );
          await bufferedStale.flush();
          await bufferedStale.close();
        },
      );
    },
  );

  group('7. Workflow checkpoint coalescing & unsupported resume schema', () {
    test(
      'coalesces parallel node status checkpoints per scheduler tick (6dbe5bb6d)',
      () async {
        final FunctionNode n1 = FunctionNode(
          name: 'n1',
          function: (WorkflowContext ctx, Object? input) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return 'r1';
          },
        );
        final FunctionNode n2 = FunctionNode(
          name: 'n2',
          function: (WorkflowContext ctx, Object? input) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return 'r2';
          },
        );
        final FunctionNode n3 = FunctionNode(
          name: 'n3',
          function: (WorkflowContext ctx, Object? input) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return 'r3';
          },
        );
        final JoinNode join = JoinNode(
          name: 'join',
          dependsOn: <String>['n1', 'n2', 'n3'],
        );

        final Workflow workflow = Workflow(
          name: 'coalesce_wf',
          nodes: <BaseNode>[n1, n2, n3, join],
          edges: <Edge>[
            Edge(fromNode: START, toNode: 'n1'),
            Edge(fromNode: START, toNode: 'n2'),
            Edge(fromNode: START, toNode: 'n3'),
            Edge(fromNode: 'n1', toNode: 'join'),
            Edge(fromNode: 'n2', toNode: 'join'),
            Edge(fromNode: 'n3', toNode: 'join'),
          ],
        );

        final InvocationContext ctx = _newCtx(
          workflow,
          userContent: Content.userText('go'),
          resumable: true,
        );

        final List<Event> events = await workflow.runAsync(ctx).toList();
        final List<Event> checkpoints = events
            .where((Event e) => e.actions.agentState != null)
            .toList();

        // Initial checkpoint + tick 1 (n1,n2,n3 running) + tick 2 (n1,n2,n3 completed & join running) + final (join completed)
        // Without coalescing this would have been 1 + 3 + 3 + 1 + 1 = 9 checkpoints.
        expect(checkpoints.length, lessThanOrEqualTo(4));
        // The first running checkpoint should capture all 3 parallel nodes together.
        final Map<String, Object?> tick1Nodes = Map<String, Object?>.from(
          checkpoints[1].actions.agentState!['nodes']! as Map,
        );
        expect((tick1Nodes['n1'] as Map)['status'], 'running');
        expect((tick1Nodes['n2'] as Map)['status'], 'running');
        expect((tick1Nodes['n3'] as Map)['status'], 'running');
      },
    );

    test(
      'ignores a resume response schema of an unsupported shape (01b4b5a76)',
      () {
        final FunctionNode askNode = FunctionNode(
          name: 'ask',
          function: (WorkflowContext ctx, Object? input) => input,
        );
        final Workflow workflow = Workflow(
          name: 'resume_wf',
          nodes: <BaseNode>[askNode],
          edges: <Edge>[Edge(fromNode: START, toNode: 'ask')],
        );

        final List<Event> history = <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'ask',
            nodeInfo: NodeInfo(path: 'resume_wf@1/ask@1'),
            longRunningToolIds: <String>{'call_int_1'},
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  id: 'call_int_1',
                  name: requestInputFunctionCallName,
                  args: <String, dynamic>{
                    'message': 'provide value',
                    // Unsupported non-JSON-Schema shape (e.g. a bare string)
                    'response_schema': 'not_a_json_schema_object',
                  },
                ),
              ],
            ),
          ),
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  id: 'call_int_1',
                  name: requestInputFunctionCallName,
                  response: <String, dynamic>{'result': 42},
                ),
              ],
            ),
          ),
        ];

        final WorkflowResult rehydrated = workflow.rehydrateResultFromEvents(
          history,
          invocationId: 'inv_1',
        );
        expect(rehydrated.outputs['ask'], 42);
        expect(rehydrated.nodeStates['ask']?.status, NodeStatus.completed);
      },
    );
  });

  group(
    '8. MultimodalToolResultsPlugin session mode inline media (2b7e32098)',
    () {
      test(
        'does not resend inline media carried by framework in session mode, keeps file_data and text',
        () async {
          final MultimodalToolResultsPlugin plugin =
              MultimodalToolResultsPlugin(retention: 'session');
          final InvocationContext invocationContext = _newCtx(
            LlmAgent(name: 'root_agent', model: _NoopModel()),
          );
          final Context context = Context(
            invocationContext,
            functionCallId: 'call_1',
          );
          final _FakeTool tool = _FakeTool();

          final Part inlineImage = Part.fromInlineData(
            mimeType: 'image/png',
            data: <int>[1, 2, 3, 4],
          );
          final Part fileRef = Part.fromFileData(
            fileUri: 'gs://bucket/doc.pdf',
            mimeType: 'application/pdf',
          );
          final Part textPart = Part.text('caption');

          await plugin.afterToolCallback(
            tool: tool,
            toolArgs: <String, dynamic>{},
            toolContext: context,
            result: <String, dynamic>{
              'result': <Part>[inlineImage, fileRef, textPart],
            },
          );

          final LlmRequest req1 = LlmRequest(
            contents: <Content>[
              Content(role: 'user', parts: <Part>[Part.text('turn 1')]),
            ],
          );
          await plugin.beforeModelCallback(
            callbackContext: context,
            llmRequest: req1,
          );

          // Inline image carried by framework must NOT be attached to req1!
          expect(
            req1.contents.last.parts.where((Part p) => p.inlineData != null),
            isEmpty,
          );
          expect(
            req1.contents.last.parts.where((Part p) => p.fileData != null),
            hasLength(1),
          );
          expect(
            req1.contents.last.parts.where((Part p) => p.text == 'caption'),
            hasLength(1),
          );

          // Turn 2 still re-attaches fileRef and textPart, never inlineImage
          final LlmRequest req2 = LlmRequest(
            contents: <Content>[
              Content(role: 'user', parts: <Part>[Part.text('turn 2')]),
            ],
          );
          await plugin.beforeModelCallback(
            callbackContext: context,
            llmRequest: req2,
          );
          expect(
            req2.contents.last.parts.where((Part p) => p.inlineData != null),
            isEmpty,
          );
          expect(
            req2.contents.last.parts.where((Part p) => p.fileData != null),
            hasLength(1),
          );
          expect(
            req2.contents.last.parts.where((Part p) => p.text == 'caption'),
            hasLength(1),
          );
        },
      );

      test(
        'next_model_call mode omits framework-carried inline/file media and keeps text',
        () async {
          final MultimodalToolResultsPlugin plugin =
              MultimodalToolResultsPlugin(retention: 'next_model_call');
          final InvocationContext invocationContext = _newCtx(
            LlmAgent(name: 'root_agent', model: _NoopModel()),
          );
          final Context context = Context(
            invocationContext,
            functionCallId: 'call_1',
          );

          await plugin.afterToolCallback(
            tool: _FakeTool(),
            toolArgs: <String, dynamic>{},
            toolContext: context,
            result: <String, dynamic>{
              'result': <Part>[
                Part.fromInlineData(mimeType: 'image/png', data: <int>[9, 8]),
                Part.text('only text'),
              ],
            },
          );

          final LlmRequest req = LlmRequest(
            contents: <Content>[
              Content(role: 'user', parts: <Part>[Part.text('q')]),
            ],
          );
          await plugin.beforeModelCallback(
            callbackContext: context,
            llmRequest: req,
          );
          expect(
            req.contents.last.parts.where((Part p) => p.inlineData != null),
            isEmpty,
          );
          expect(
            req.contents.last.parts.where((Part p) => p.text == 'only text'),
            hasLength(1),
          );
        },
      );
    },
  );

  group('9. getAgentsDict supports non-LLM root nodes (ec2ac7c5e)', () {
    test(
      'traverses SequentialAgent root and flattens non-LLM containers for nearest LLM sub-agents',
      () async {
        final LlmAgent workerA = LlmAgent(
          name: 'worker_a',
          description: 'A',
          instruction: 'do A',
          model: _NoopModel(),
        );
        final LlmAgent workerB = LlmAgent(
          name: 'worker_b',
          description: 'B',
          instruction: 'do B',
          model: _NoopModel(),
        );
        final ParallelAgent nestedParallel = ParallelAgent(
          name: 'nested_parallel',
          subAgents: <BaseAgent>[workerB],
        );
        final LlmAgent coordinator = LlmAgent(
          name: 'coordinator',
          description: 'coord',
          instruction: 'delegate',
          model: _NoopModel(),
          subAgents: <BaseAgent>[nestedParallel],
        );
        final SequentialAgent rootSeq = SequentialAgent(
          name: 'root_seq',
          subAgents: <BaseAgent>[workerA, coordinator],
        );

        final Map<String, AgentInfo> info = await getAgentsDict(rootSeq);
        expect(
          info.keys,
          unorderedEquals(<String>['worker_a', 'coordinator', 'worker_b']),
        );
        expect(info['coordinator']!.subAgents, <String>['worker_b']);
        expect(info.containsKey('root_seq'), isFalse);
        expect(info.containsKey('nested_parallel'), isFalse);
      },
    );

    test('traverses Workflow root with AgentNode children', () async {
      final LlmAgent wfLlm = LlmAgent(
        name: 'wf_llm',
        description: 'inside workflow',
        instruction: 'be helpful',
        model: _NoopModel(),
      );
      final Workflow wf = Workflow(
        name: 'my_wf',
        nodes: <BaseNode>[AgentNode(agent: wfLlm)],
        edges: <Edge>[Edge(fromNode: START, toNode: 'wf_llm')],
      );

      final Map<String, AgentInfo> info = await getAgentsDict(wf);
      expect(info.keys, <String>['wf_llm']);
      expect(info['wf_llm']!.instruction, 'be helpful');
    });

    test('keeps first LlmAgent when duplicate names are encountered', () async {
      final LlmAgent first = LlmAgent(
        name: 'dup',
        description: 'first desc',
        instruction: 'first inst',
        model: _NoopModel(),
      );
      final LlmAgent second = LlmAgent(
        name: 'dup',
        description: 'second desc',
        instruction: 'second inst',
        model: _NoopModel(),
      );
      final Workflow wf = Workflow(
        name: 'dup_wf',
        nodes: <BaseNode>[
          AgentNode(name: 'node_1', agent: first),
          AgentNode(name: 'node_2', agent: second),
        ],
      );

      final Map<String, AgentInfo> info = await getAgentsDict(wf);
      expect(info.keys, <String>['dup']);
      expect(info['dup']!.description, 'first desc');
    });
  });

  group('10. Audit regression fixes (Nov 20)', () {
    test(
      'MultimodalToolResultsPlugin session mode accumulates multiple tool calls in the same turn without fixed-length list error',
      () async {
        final MultimodalToolResultsPlugin plugin = MultimodalToolResultsPlugin(
          retention: 'session',
        );
        final InvocationContext invocationContext = _newCtx(
          LlmAgent(name: 'root_agent', model: _NoopModel()),
        );
        final Context context1 = Context(
          invocationContext,
          functionCallId: 'call_1',
        );
        final Context context2 = Context(
          invocationContext,
          functionCallId: 'call_2',
        );

        await plugin.afterToolCallback(
          tool: _FakeTool(),
          toolArgs: <String, dynamic>{},
          toolContext: context1,
          result: <String, dynamic>{
            'result': <Part>[Part.text('first tool text')],
          },
        );
        await plugin.afterToolCallback(
          tool: _FakeTool(),
          toolArgs: <String, dynamic>{},
          toolContext: context2,
          result: <String, dynamic>{
            'result': <Part>[Part.text('second tool text')],
          },
        );

        final LlmRequest req = LlmRequest(
          contents: <Content>[
            Content(role: 'user', parts: <Part>[Part.text('turn 1')]),
          ],
        );
        await plugin.beforeModelCallback(
          callbackContext: context2,
          llmRequest: req,
        );
        final List<String?> texts = req.contents.last.parts
            .map((Part p) => p.text)
            .toList();
        expect(texts, containsAll(<String>['first tool text', 'second tool text']));
      },
    );

    test(
      'BufferedSessionService and BufferedSessionServiceConfig enforce FeatureName.bufferedSessionService gate',
      () {
        overrideFeatureEnabled(FeatureName.bufferedSessionService, false);
        addTearDown(resetFeatureRegistryForTest);

        expect(() => BufferedSessionServiceConfig(), throwsStateError);
        expect(
          () => BufferedSessionService(InMemorySessionService()),
          throwsStateError,
        );
      },
    );
  });
}
