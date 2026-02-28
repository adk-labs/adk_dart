import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class MockModel extends BaseLlm {
  MockModel({required this.responses}) : super(model: 'mock-model');

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    if (_index >= responses.length) {
      return;
    }
    yield responses[_index++].copyWith();
  }
}

class _MetadataRewritePlugin extends BasePlugin {
  _MetadataRewritePlugin() : super(name: 'metadata_rewrite');

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    return event.copyWith(
      customMetadata: <String, dynamic>{'plugin': 'yes', 'run': 'override'},
    );
  }
}

Future<List<Event>> _collect(Stream<Event> stream) async {
  return stream.toList();
}

void main() {
  group('Runner + LlmAgent flow', () {
    test('runs a simple single-turn model response', () async {
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('hello from model')),
        ],
      );

      final Agent agent = Agent(name: 'root_agent', model: model);
      final InMemoryRunner runner = InMemoryRunner(agent: agent);

      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_1',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hi'),
        ),
      );

      expect(events, hasLength(1));
      expect(events.first.author, 'root_agent');
      expect(events.first.content?.parts.first.text, 'hello from model');
    });

    test(
      'handles function call -> function response -> final answer',
      () async {
        int functionCalled = 0;

        int increaseByOne(int x) {
          functionCalled += 1;
          return x + 1;
        }

        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'increase_by_one',
                    args: <String, dynamic>{'x': 1},
                  ),
                ],
              ),
            ),
            LlmResponse(content: Content.modelText('done')),
          ],
        );

        final Agent agent = Agent(
          name: 'root_agent',
          model: model,
          tools: <Object>[
            FunctionTool(
              func: increaseByOne,
              name: 'increase_by_one',
              description: 'Increase input integer by one',
            ),
          ],
        );

        final InMemoryRunner runner = InMemoryRunner(agent: agent);

        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: 'session_2',
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('test'),
          ),
        );

        expect(events.length, 3);
        expect(events[0].getFunctionCalls(), hasLength(1));
        expect(events[1].getFunctionResponses(), hasLength(1));
        expect(events[1].getFunctionResponses().first.name, 'increase_by_one');
        expect(events[1].getFunctionResponses().first.response['result'], 2);
        expect(events[2].content?.parts.first.text, 'done');
        expect(functionCalled, 1);

        expect(model.requests, hasLength(2));
        expect(model.requests.first.contents.last.parts.first.text, 'test');
      },
    );

    test('handles transfer_to_agent tool and continues in sub-agent', () async {
      final MockModel rootModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'transfer_to_agent',
                  args: <String, dynamic>{'agent_name': 'sub_agent'},
                ),
              ],
            ),
          ),
        ],
      );
      final MockModel subModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('from sub agent')),
        ],
      );

      final Agent subAgent = Agent(name: 'sub_agent', model: subModel);
      final Agent root = Agent(
        name: 'root_agent',
        model: rootModel,
        subAgents: <BaseAgent>[subAgent],
      );
      final InMemoryRunner runner = InMemoryRunner(agent: root);

      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_3',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('route this'),
        ),
      );

      expect(events, hasLength(3));
      expect(events[0].author, 'root_agent');
      expect(events[0].getFunctionCalls().first.name, 'transfer_to_agent');
      expect(events[1].getFunctionResponses().first.name, 'transfer_to_agent');
      expect(events[2].author, 'sub_agent');
      expect(events[2].content?.parts.first.text, 'from sub agent');
    });

    test(
      'non-resumable app ignores invocationId when newMessage is provided',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('fresh turn')),
          ],
        );

        final Agent agent = Agent(name: 'root_agent', model: model);
        final InMemoryRunner runner = InMemoryRunner(agent: agent);

        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: 'session_non_resumable',
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            invocationId: 'previous_invocation',
            newMessage: Content.userText('new message'),
          ),
        );

        expect(events, hasLength(1));
        expect(events.first.content?.parts.first.text, 'fresh turn');
        expect(events.first.invocationId, isNot('previous_invocation'));
      },
    );

    test(
      'resumable app resolves invocationId from function response call id',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('resumed')),
          ],
        );
        final Agent agent = Agent(name: 'root_agent', model: model);
        final App app = App(
          name: 'resumable_app',
          rootAgent: agent,
          resumabilityConfig: ResumabilityConfig(isResumable: true),
        );
        final Runner runner = Runner(
          app: app,
          sessionService: InMemorySessionService(),
        );

        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: 'session_resume_resolution',
        );
        await runner.sessionService.appendEvent(
          session: session,
          event: Event(
            invocationId: 'invocation_from_call',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'lookup_weather',
                  args: <String, dynamic>{'city': 'Seoul'},
                  id: 'call_123',
                ),
              ],
            ),
          ),
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'lookup_weather',
                  response: <String, dynamic>{'result': 'sunny'},
                  id: 'call_123',
                ),
              ],
            ),
          ),
        );

        expect(events, isNotEmpty);
        final Event resumedEvent = events.firstWhere(
          (Event event) =>
              event.content?.parts.any((Part part) => part.text == 'resumed') ==
              true,
          orElse: () => throw StateError('Missing resumed model response'),
        );
        expect(resumedEvent.invocationId, 'invocation_from_call');
      },
    );

    test(
      'run-level custom metadata is re-applied to plugin modified events',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('metadata test')),
          ],
        );
        final Agent agent = Agent(name: 'root_agent', model: model);
        final InMemoryRunner runner = InMemoryRunner(
          agent: agent,
          plugins: <BasePlugin>[_MetadataRewritePlugin()],
        );

        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: 'session_metadata_merge',
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('hi'),
            runConfig: RunConfig(
              customMetadata: <String, dynamic>{'run': 'from_run'},
            ),
          ),
        );

        expect(events, hasLength(1));
        expect(events.first.customMetadata, isNotNull);
        expect(events.first.customMetadata!['plugin'], 'yes');
        expect(events.first.customMetadata!['run'], 'override');
      },
    );

    test('throws SessionNotFoundError when session is missing', () async {
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('unused')),
        ],
      );
      final Agent agent = Agent(name: 'root_agent', model: model);
      final Runner runner = Runner(
        appName: 'test_app',
        agent: agent,
        sessionService: InMemorySessionService(),
      );

      expect(
        runner
            .runAsync(
              userId: 'user_1',
              sessionId: 'missing_session',
              newMessage: Content.userText('hi'),
            )
            .toList(),
        throwsA(isA<SessionNotFoundError>()),
      );
    });
  });
}
