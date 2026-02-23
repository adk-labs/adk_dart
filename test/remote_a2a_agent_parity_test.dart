import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteA2aAgent parity', () {
    test(
      'resolves agent card from file and forwards metadata/context',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'remote_a2a_agent_',
        );
        addTearDown(() => dir.delete(recursive: true));

        final File cardFile = File('${dir.path}/agent_card.json');
        await cardFile.writeAsString(
          jsonEncode(<String, Object?>{
            'name': 'remote-agent',
            'description': 'Remote card description',
            'url': 'https://remote.example/rpc',
            'version': '1.0.0',
          }),
        );

        final _RecordingClient client = _RecordingClient(
          () => Stream<Object>.fromIterable(<Object>[
            A2aMessage(
              messageId: 'resp_1',
              role: A2aRole.agent,
              contextId: 'ctx-1',
              parts: <A2aPart>[A2aPart.text('pong')],
            ),
          ]),
        );
        final _RecordingClientFactory factory = _RecordingClientFactory(client);

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: cardFile.path,
          a2aClientFactory: factory,
          a2aRequestMetaProvider: (InvocationContext ctx, A2aMessage request) =>
              <String, Object?>{
                'state_step': ctx.session.state['step'] ?? 'none',
              },
        );

        final InvocationContext context = _context(
          agent: agent,
          state: <String, Object?>{'step': 'ready'},
          events: <Event>[
            Event(
              invocationId: 'inv-0',
              author: 'user',
              content: Content.userText('ping'),
            ),
          ],
        );

        final List<Event> events = await agent.runAsync(context).toList();

        expect(factory.createdFor, isNotNull);
        expect(factory.createdFor!.name, 'remote-agent');
        expect(agent.description, 'Remote card description');

        expect(client.requests, hasLength(1));
        expect(client.requests.single.role, A2aRole.user);
        expect(client.requests.single.contextId, isNull);
        expect(
          client.requestMetadatas.single,
          containsPair('state_step', 'ready'),
        );
        expect(client.contexts.single?.state['step'], 'ready');
        expect(
          (client.requests.single.parts.single.root as A2aTextPart).text,
          'ping',
        );

        expect(events, hasLength(1));
        expect(events.single.author, 'remote_agent');
        expect(events.single.content?.parts.single.text, 'pong');
        expect(events.single.customMetadata?['a2a:context_id'], 'ctx-1');
      },
    );

    test('resolves agent card from URL source', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));

      server.listen((HttpRequest request) async {
        if (request.uri.path != '/agent.json') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'name': 'remote-url-agent',
            'description': 'Resolved from URL',
            'url': 'https://remote.example/rpc',
            'version': '1.0.0',
          }),
        );
        await request.response.close();
      });

      final _RecordingClientFactory factory = _RecordingClientFactory(
        _RecordingClient(
          () => Stream<Object>.value(
            A2aMessage(
              messageId: 'resp_url',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('ok')],
            ),
          ),
        ),
      );

      final RemoteA2aAgent agent = RemoteA2aAgent(
        name: 'remote_agent',
        agentCard: 'http://127.0.0.1:${server.port}/agent.json',
        a2aClientFactory: factory,
      );

      final InvocationContext context = _context(
        agent: agent,
        events: <Event>[
          Event(
            invocationId: 'inv-url',
            author: 'user',
            content: Content.userText('hello'),
          ),
        ],
      );

      await agent.runAsync(context).toList();

      expect(factory.createdFor, isNotNull);
      expect(factory.createdFor!.name, 'remote-url-agent');
      expect(agent.description, 'Resolved from URL');
    });

    test(
      'reuses task/context ids for user function response request',
      () async {
        final _RecordingClient client = _RecordingClient(
          () => Stream<Object>.value(
            A2aMessage(
              messageId: 'resp_fc',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('done')],
            ),
          ),
        );

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: AgentCard(
            name: 'remote',
            description: 'desc',
            url: 'https://remote.example/rpc',
            version: '1.0.0',
          ),
          a2aClientFactory: _RecordingClientFactory(client),
        );

        final InvocationContext context = _context(
          agent: agent,
          events: <Event>[
            Event(
              invocationId: 'inv-fc',
              author: 'planner',
              customMetadata: <String, dynamic>{
                'a2a:task_id': 'task-1',
                'a2a:context_id': 'ctx-1',
              },
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'lookup',
                    id: 'call-1',
                    args: <String, Object?>{'city': 'seoul'},
                  ),
                ],
              ),
            ),
            Event(
              invocationId: 'inv-fc',
              author: 'user',
              content: Content(
                role: 'user',
                parts: <Part>[
                  Part.fromFunctionResponse(
                    name: 'lookup',
                    id: 'call-1',
                    response: <String, Object?>{'result': '10:30 AM'},
                  ),
                ],
              ),
            ),
          ],
        );

        await agent.runAsync(context).toList();

        expect(client.requests, hasLength(1));
        final A2aMessage request = client.requests.single;
        expect(request.taskId, 'task-1');
        expect(request.contextId, 'ctx-1');

        final A2aDataPart dataPart = request.parts.single.dataPart!;
        expect(
          dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)],
          a2aDataPartMetadataTypeFunctionResponse,
        );
      },
    );

    test(
      'fullHistoryWhenStateless keeps pre-response history when enabled',
      () async {
        final _RecordingClient defaultClient = _RecordingClient(
          () => Stream<Object>.value(
            A2aMessage(
              messageId: 'resp-default',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('ok')],
            ),
          ),
        );
        final RemoteA2aAgent defaultAgent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: AgentCard(
            name: 'remote',
            description: 'desc',
            url: 'https://remote.example/rpc',
            version: '1.0.0',
          ),
          a2aClientFactory: _RecordingClientFactory(defaultClient),
        );

        final List<Event> history = <Event>[
          Event(
            invocationId: 'inv-hist',
            author: 'user',
            content: Content.userText('old user'),
          ),
          Event(
            invocationId: 'inv-hist',
            author: 'remote_agent',
            customMetadata: <String, dynamic>{
              'a2a:response': <String, Object?>{'kind': 'message'},
            },
            content: Content.modelText('remote reply'),
          ),
          Event(
            invocationId: 'inv-hist',
            author: 'user',
            content: Content.userText('latest user'),
          ),
        ];

        await defaultAgent
            .runAsync(_context(agent: defaultAgent, events: history))
            .toList();

        expect(defaultClient.requests, hasLength(1));
        expect(
          defaultClient.requests.single.parts
              .map((A2aPart part) => part.textPart?.text)
              .whereType<String>()
              .toList(),
          <String>['latest user'],
        );

        final _RecordingClient fullHistoryClient = _RecordingClient(
          () => Stream<Object>.value(
            A2aMessage(
              messageId: 'resp-full',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('ok')],
            ),
          ),
        );
        final RemoteA2aAgent fullHistoryAgent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: AgentCard(
            name: 'remote',
            description: 'desc',
            url: 'https://remote.example/rpc',
            version: '1.0.0',
          ),
          fullHistoryWhenStateless: true,
          a2aClientFactory: _RecordingClientFactory(fullHistoryClient),
        );

        await fullHistoryAgent
            .runAsync(_context(agent: fullHistoryAgent, events: history))
            .toList();

        expect(fullHistoryClient.requests, hasLength(1));
        expect(
          fullHistoryClient.requests.single.parts
              .map((A2aPart part) => part.textPart?.text)
              .whereType<String>()
              .toList(),
          <String>['old user', 'remote reply', 'latest user'],
        );
      },
    );

    test(
      'converts streaming task updates and marks in-flight thoughts',
      () async {
        final A2aTask task = A2aTask(
          id: 'task-1',
          contextId: 'ctx-1',
          status: A2aTaskStatus(
            state: A2aTaskState.submitted,
            message: A2aMessage(
              messageId: 'm-submitted',
              role: A2aRole.agent,
              parts: <A2aPart>[A2aPart.text('processing')],
            ),
          ),
          artifacts: <A2aArtifact>[
            A2aArtifact(
              artifactId: 'artifact-1',
              parts: <A2aPart>[A2aPart.text('artifact content')],
            ),
          ],
        );

        final _RecordingClient client = _RecordingClient(
          () => Stream<Object>.fromIterable(<Object>[
            (task, null),
            (
              task,
              A2aTaskStatusUpdateEvent(
                taskId: 'task-1',
                contextId: 'ctx-1',
                status: A2aTaskStatus(
                  state: A2aTaskState.working,
                  message: A2aMessage(
                    messageId: 'm-working',
                    role: A2aRole.agent,
                    parts: <A2aPart>[A2aPart.text('still working')],
                  ),
                ),
              ),
            ),
            (
              task,
              A2aTaskArtifactUpdateEvent(
                taskId: 'task-1',
                contextId: 'ctx-1',
                append: true,
                lastChunk: false,
                artifact: A2aArtifact(
                  artifactId: 'artifact-1',
                  parts: <A2aPart>[A2aPart.text('partial')],
                ),
              ),
            ),
            (
              task,
              A2aTaskArtifactUpdateEvent(
                taskId: 'task-1',
                contextId: 'ctx-1',
                append: true,
                lastChunk: true,
                artifact: A2aArtifact(
                  artifactId: 'artifact-1',
                  parts: <A2aPart>[A2aPart.text('final artifact')],
                ),
              ),
            ),
            A2aMessage(
              messageId: 'm-final',
              role: A2aRole.agent,
              contextId: 'ctx-1',
              parts: <A2aPart>[A2aPart.text('final reply')],
            ),
          ]),
        );

        final RemoteA2aAgent agent = RemoteA2aAgent(
          name: 'remote_agent',
          agentCard: AgentCard(
            name: 'remote',
            description: 'desc',
            url: 'https://remote.example/rpc',
            version: '1.0.0',
          ),
          a2aClientFactory: _RecordingClientFactory(client),
        );

        final List<Event> events = await agent
            .runAsync(
              _context(
                agent: agent,
                events: <Event>[
                  Event(
                    invocationId: 'inv-stream',
                    author: 'user',
                    content: Content.userText('hi'),
                  ),
                ],
              ),
            )
            .toList();

        expect(events, hasLength(4));
        expect(events[0].content?.parts.first.thought, isTrue);
        expect(events[1].content?.parts.first.thought, isTrue);
        expect(events[3].content?.parts.first.thought, isFalse);

        for (final Event event in events) {
          expect(event.customMetadata?['a2a:request'], isA<Map>());
          expect(event.customMetadata?['a2a:response'], isA<Map>());
        }
        expect(events[0].customMetadata?['a2a:task_id'], 'task-1');
        expect(events[0].customMetadata?['a2a:context_id'], 'ctx-1');
      },
    );

    test('emits status-code metadata when A2A HTTP error is raised', () async {
      final _RecordingClient client = _RecordingClient(
        () => Stream<Object>.error(
          A2aClientHttpError('gateway timeout', statusCode: 504),
        ),
      );
      final RemoteA2aAgent agent = RemoteA2aAgent(
        name: 'remote_agent',
        agentCard: AgentCard(
          name: 'remote',
          description: 'desc',
          url: 'https://remote.example/rpc',
          version: '1.0.0',
        ),
        a2aClientFactory: _RecordingClientFactory(client),
      );

      final List<Event> events = await agent
          .runAsync(
            _context(
              agent: agent,
              events: <Event>[
                Event(
                  invocationId: 'inv-http',
                  author: 'user',
                  content: Content.userText('hello'),
                ),
              ],
            ),
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.single.errorMessage, contains('A2A request failed:'));
      expect(events.single.customMetadata?['a2a:status_code'], '504');
      expect(
        events.single.customMetadata?['a2a:error'],
        contains('A2A request failed:'),
      );
    });

    test('runLiveImpl remains explicitly unsupported', () async {
      final RemoteA2aAgent agent = RemoteA2aAgent(
        name: 'remote_agent',
        agentCard: AgentCard(
          name: 'remote',
          description: 'desc',
          url: 'https://remote.example/rpc',
          version: '1.0.0',
        ),
        a2aClientFactory: _RecordingClientFactory(
          _RecordingClient(
            () => Stream<Object>.value(
              A2aMessage(
                messageId: 'resp-live',
                role: A2aRole.agent,
                parts: <A2aPart>[A2aPart.text('ok')],
              ),
            ),
          ),
        ),
      );

      final InvocationContext context = _context(
        agent: agent,
        events: <Event>[
          Event(
            invocationId: 'inv-live',
            author: 'user',
            content: Content.userText('hi'),
          ),
        ],
      );

      await expectLater(
        agent.runLive(context).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('not implemented'),
          ),
        ),
      );
    });
  });
}

InvocationContext _context({
  required RemoteA2aAgent agent,
  required List<Event> events,
  Map<String, Object?>? state,
}) {
  return InvocationContext(
    sessionService: _FakeSessionService(),
    invocationId: 'invocation',
    agent: agent,
    session: Session(
      id: 'session-1',
      appName: 'app',
      userId: 'user',
      state: state ?? <String, Object?>{},
      events: events,
    ),
  );
}

class _RecordingClient implements A2aClient {
  _RecordingClient(this._responseFactory);

  final Stream<Object> Function() _responseFactory;
  final List<A2aMessage> requests = <A2aMessage>[];
  final List<Map<String, Object?>?> requestMetadatas =
      <Map<String, Object?>?>[];
  final List<A2aClientCallContext?> contexts = <A2aClientCallContext?>[];

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) {
    requests.add(request);
    requestMetadatas.add(
      requestMetadata == null
          ? null
          : Map<String, Object?>.from(requestMetadata),
    );
    contexts.add(context);
    return _responseFactory();
  }
}

class _RecordingClientFactory implements A2aClientFactory {
  _RecordingClientFactory(this._client);

  final A2aClient _client;
  AgentCard? createdFor;

  @override
  A2aClient create(AgentCard agentCard) {
    createdFor = agentCard;
    return _client;
  }
}

class _FakeSessionService extends BaseSessionService {
  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    return Session(
      id: sessionId ?? 'session',
      appName: appName,
      userId: userId,
      state: state,
    );
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {}

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    return null;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    return ListSessionsResponse();
  }
}
