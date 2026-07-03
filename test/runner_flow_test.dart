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

class _EarlyExitPlugin extends BasePlugin {
  _EarlyExitPlugin() : super(name: 'early_exit');

  int afterRunCalls = 0;

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    return Content.modelText('early exit');
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    afterRunCalls += 1;
  }
}

class _AbortUserMessagePlugin extends BasePlugin {
  _AbortUserMessagePlugin(this.controller) : super(name: 'abort_user_message');

  final AdkAbortController controller;

  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    controller.abort('stop before user append');
    return null;
  }
}

class _AbortOnEventPlugin extends BasePlugin {
  _AbortOnEventPlugin(this.controller) : super(name: 'abort_on_event');

  final AdkAbortController controller;

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    controller.abort('stop before event append');
    return null;
  }
}

class _UserMessageStateSnapshotPlugin extends BasePlugin {
  _UserMessageStateSnapshotPlugin() : super(name: 'state_snapshot');

  Map<String, Object?>? stateInCallback;

  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    stateInCallback = Map<String, Object?>.from(
      invocationContext.session.state,
    );
    return null;
  }
}

class _BeforeModelUserContentPlugin extends BasePlugin {
  _BeforeModelUserContentPlugin() : super(name: 'before_model_user_content');

  String? userText;

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    userText = callbackContext.userContent?.parts
        .where((Part part) => part.text != null && !part.thought)
        .map((Part part) => part.text!)
        .join();
    return null;
  }
}

class _CloseCountingToolset extends BaseToolset {
  int closeCalls = 0;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return const <BaseTool>[];
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

class _MockWorkflowAgent extends BaseAgent {
  _MockWorkflowAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content(
        role: 'user',
        parts: <Part>[
          Part(
            functionResponse: FunctionResponse(
              name: 'escalate',
              id: 'esc-1',
              response: <String, dynamic>{},
            ),
          )
        ],
      ),
      actions: EventActions(escalate: true),
    );
  }

  @override
  _MockWorkflowAgent clone({Map<String, Object?>? update}) {
    return _MockWorkflowAgent(name: name);
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

    test('closes configured toolsets after runAsync completes', () async {
      final _CloseCountingToolset toolset = _CloseCountingToolset();
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('done')),
        ],
      );
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        tools: <Object>[toolset],
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_toolset_close',
      );

      await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hi'),
        ),
      );

      expect(toolset.closeCalls, 1);
    });

    test('onUserMessage callback sees runAsync stateDelta', () async {
      final _UserMessageStateSnapshotPlugin plugin =
          _UserMessageStateSnapshotPlugin();
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('state observed')),
        ],
      );
      final Agent agent = Agent(name: 'root_agent', model: model);
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_state_delta_callback',
      );

      await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hi'),
          stateDelta: <String, Object?>{
            'callback_key': 'callback_value',
            'number': 123,
          },
        ),
      );

      expect(plugin.stateInCallback, isNotNull);
      expect(
        plugin.stateInCallback,
        containsPair('callback_key', 'callback_value'),
      );
      expect(plugin.stateInCallback, containsPair('number', 123));

      final Session? loaded = await runner.sessionService.getSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: session.id,
      );
      expect(loaded?.state, containsPair('callback_key', 'callback_value'));
      expect(loaded?.state, containsPair('number', 123));
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
        final _BeforeModelUserContentPlugin plugin =
            _BeforeModelUserContentPlugin();
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('resumed')),
          ],
        );
        final Agent agent = Agent(name: 'root_agent', model: model);
        final App app = App(
          name: 'resumable_app',
          rootAgent: agent,
          plugins: <BasePlugin>[plugin],
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
            author: 'user',
            content: Content.userText('what is the weather?'),
          ),
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
        expect(plugin.userText, 'what is the weather?');
      },
    );

    test(
      'resumable app falls back to root for stale function-call author',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('resumed by root')),
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
          sessionId: 'session_stale_resume_author',
        );
        await runner.sessionService.appendEvent(
          session: session,
          event: Event(
            invocationId: 'invocation_from_stale_call',
            author: 'agent_from_previous_session',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'lookup_weather',
                  args: <String, dynamic>{'city': 'Seoul'},
                  id: 'call_stale',
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
                  id: 'call_stale',
                ),
              ],
            ),
          ),
        );

        expect(events, isNotEmpty);
        final Event resumedEvent = events.firstWhere(
          (Event event) =>
              event.content?.parts.any(
                (Part part) => part.text == 'resumed by root',
              ) ==
              true,
          orElse: () => throw StateError('Missing resumed model response'),
        );
        expect(resumedEvent.author, 'root_agent');
        expect(resumedEvent.invocationId, 'invocation_from_stale_call');
      },
    );

    test(
      'resumable app stays paused when a long-running call is followed by a function response',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('unexpected continuation')),
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
          sessionId: 'session_pause_after_response',
        );
        await runner.sessionService.appendEvent(
          session: session,
          event: Event(
            invocationId: 'invocation_pause',
            author: 'user',
            content: Content.userText('start'),
          ),
        );
        await runner.sessionService.appendEvent(
          session: session,
          event: Event(
            invocationId: 'invocation_pause',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'lookup_weather',
                  id: 'call_pause',
                  args: <String, dynamic>{'city': 'Seoul'},
                ),
              ],
            ),
            longRunningToolIds: <String>{'call_pause'},
          ),
        );
        await runner.sessionService.appendEvent(
          session: session,
          event: Event(
            invocationId: 'invocation_pause',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'lookup_weather',
                  id: 'call_pause',
                  response: <String, dynamic>{'pending': true},
                ),
              ],
            ),
          ),
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            invocationId: 'invocation_pause',
          ),
        );

        expect(events, isEmpty);
        expect(model.requests, isEmpty);
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

        final Session? reloaded = await runner.sessionService.getSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: session.id,
        );
        expect(reloaded, isNotNull);
        expect(reloaded!.events, hasLength(2));
        expect(reloaded.events.last.customMetadata, isNotNull);
        expect(reloaded.events.last.customMetadata!['plugin'], 'yes');
        expect(reloaded.events.last.customMetadata!['run'], 'override');
      },
    );

    test(
      'after_run callback runs even when before_run short-circuits',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('unused')),
          ],
        );
        final Agent agent = Agent(name: 'root_agent', model: model);
        final _EarlyExitPlugin plugin = _EarlyExitPlugin();
        final InMemoryRunner runner = InMemoryRunner(
          agent: agent,
          plugins: <BasePlugin>[plugin],
        );

        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: 'session_early_exit_after_run',
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('hi'),
          ),
        );

        expect(events, hasLength(1));
        expect(events.first.content?.parts.first.text, 'early exit');
        expect(plugin.afterRunCalls, 1);
        expect(model.requests, isEmpty);
      },
    );

    test('runAsync stops before session mutation when pre-aborted', () async {
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('unused')),
        ],
      );
      final Agent agent = Agent(name: 'root_agent', model: model);
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_pre_aborted',
      );
      final AdkAbortController controller = AdkAbortController()
        ..abort('already stopped');

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hi'),
          abortSignal: controller.signal,
        ),
      );

      expect(events, isEmpty);
      expect(model.requests, isEmpty);
      final Session? reloaded = await runner.sessionService.getSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: session.id,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.events, isEmpty);
    });

    test('runAsync stops after user-message plugin aborts', () async {
      final MockModel model = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('unused')),
        ],
      );
      final Agent agent = Agent(name: 'root_agent', model: model);
      final AdkAbortController controller = AdkAbortController();
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[_AbortUserMessagePlugin(controller)],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_abort_user_message',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hi'),
          abortSignal: controller.signal,
        ),
      );

      expect(events, isEmpty);
      expect(model.requests, isEmpty);
      final Session? reloaded = await runner.sessionService.getSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: session.id,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.events, isEmpty);
    });

    test(
      'runAsync stops after event plugin aborts before append/yield',
      () async {
        final MockModel model = MockModel(
          responses: <LlmResponse>[
            LlmResponse(content: Content.modelText('should not persist')),
          ],
        );
        final Agent agent = Agent(name: 'root_agent', model: model);
        final AdkAbortController controller = AdkAbortController();
        final InMemoryRunner runner = InMemoryRunner(
          agent: agent,
          plugins: <BasePlugin>[_AbortOnEventPlugin(controller)],
        );
        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: 'session_abort_on_event',
        );

        final List<Event> events = await _collect(
          runner.runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: Content.userText('hi'),
            abortSignal: controller.signal,
          ),
        );

        expect(events, isEmpty);
        expect(model.requests, hasLength(1));
        final Session? reloaded = await runner.sessionService.getSession(
          appName: runner.appName,
          userId: 'user_1',
          sessionId: session.id,
        );
        expect(reloaded, isNotNull);
        expect(reloaded!.events, hasLength(1));
        expect(reloaded.events.single.author, 'user');
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

    test('findAgentToRun: candidate under workflow agent falls back to root', () async {
      final MockModel leafModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Hello from leaf')),
        ],
      );
      final Agent leaf = Agent(name: 'leaf', model: leafModel);
      final SequentialAgent seq = SequentialAgent(
        name: 'seq',
        subAgents: <BaseAgent>[leaf],
      );
      final MockModel rootModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Hello from root')),
        ],
      );
      final Agent root = Agent(
        name: 'root',
        model: rootModel,
        subAgents: <BaseAgent>[seq],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: root);

      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_workflow_fallback',
      );

      // leaf produced the last model event, then the user replied.
      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv-1',
          author: 'leaf',
          content: Content.modelText('Hello from leaf'),
        ),
      );

      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv-1',
          author: 'user',
          content: Content.userText('Hi'),
        ),
      );

      // On next run, since leaf is under seq (SequentialAgent, not LlmAgent),
      // it should fallback to root.
      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('Hi again'),
        ),
      );

      expect(events, isNotEmpty);
      expect(events.last.author, 'root');
      expect(events.last.content?.parts.single.text, 'Hello from root');
    });

    test('findAgentToRun: leaf not transferable returns nearest transferable ancestor', () async {
      final MockModel leafModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Hello from leaf')),
        ],
      );
      final Agent leaf = Agent(
        name: 'leaf',
        model: leafModel,
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final MockModel midModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Hello from mid')),
        ],
      );
      final Agent mid = Agent(
        name: 'mid',
        model: midModel,
        subAgents: <BaseAgent>[leaf],
      );
      final MockModel rootModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('Hello from root')),
        ],
      );
      final Agent root = Agent(
        name: 'root',
        model: rootModel,
        subAgents: <BaseAgent>[mid],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: root);

      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_leaf_not_transferable',
      );

      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv-1',
          author: 'mid',
          content: Content.modelText('mid'),
        ),
      );
      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv-1',
          author: 'leaf',
          content: Content.modelText('leaf'),
        ),
      );
      await runner.sessionService.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv-1',
          author: 'user',
          content: Content.userText('Hi'),
        ),
      );

      // On next run, since leaf disallows transfer to parent, walk up to mid (transferable LlmAgent).
      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('Hi again'),
        ),
      );

      expect(events, isNotEmpty);
      expect(events.last.author, 'mid');
      expect(events.last.content?.parts.single.text, 'Hello from mid');
    });

    test('agent transfer returns control to parent after sub-agent completes', () async {
      final _MockWorkflowAgent workflow = _MockWorkflowAgent(name: 'workflow');
      final MockModel rootModel = MockModel(
        responses: <LlmResponse>[
          LlmResponse(
            content: Content(
              parts: <Part>[
                Part(
                  functionCall: FunctionCall(
                    name: 'transfer_to_agent',
                    args: <String, dynamic>{'agent_name': 'workflow'},
                    id: 'fc-trans',
                  ),
                ),
              ],
            ),
          ),
          LlmResponse(content: Content.modelText('root-after-workflow')),
        ],
      );
      final Agent root = Agent(
        name: 'root',
        model: rootModel,
        subAgents: <BaseAgent>[workflow],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: root);

      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_transfer_control',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hi'),
        ),
      );

      final List<Event> agentEvents = events.where((Event e) => e.author != 'user').toList();
      expect(agentEvents, isNotEmpty);
      expect(agentEvents.last.author, 'root');
      expect(agentEvents.last.content?.parts.single.text, 'root-after-workflow');
    });

    test('empty STOP after tool call surfaces error event', () async {
      final LlmResponse turn1 = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'increase_by_one',
              args: <String, dynamic>{'x': 1},
            ),
          ],
        ),
        finishReason: 'STOP',
      );
      // An empty Gemini turn: STOP with no content parts and no error from the model.
      final LlmResponse turn2 = LlmResponse(
        content: Content(role: 'model', parts: <Part>[]),
        finishReason: 'STOP',
      );

      int functionCalled = 0;
      final int Function(int) increaseByOne = (int x) {
        functionCalled++;
        return x + 1;
      };

      final MockModel model = MockModel(responses: <LlmResponse>[turn1, turn2]);
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
        sessionId: 'session_empty_stop',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('test'),
        ),
      );

      expect(functionCalled, 1);

      final List<Event> functionCallEvents =
          events.where((Event e) => e.getFunctionCalls().isNotEmpty).toList();
      final List<Event> functionResponseEvents =
          events.where((Event e) => e.getFunctionResponses().isNotEmpty).toList();
      expect(functionCallEvents, hasLength(1));
      expect(functionResponseEvents, hasLength(1));

      // The empty turn 2 must surface as an error event, not an empty final.
      final List<Event> errorEvents =
          events.where((Event e) => e.errorCode != null).toList();
      expect(errorEvents, hasLength(1));
      final Event err = errorEvents.first;
      expect(err.errorCode, 'MODEL_RETURNED_NO_CONTENT');
      expect(err.errorMessage, isNotNull);
      // And it must be the run's final event.
      expect(events.last, same(err));
    });

    test('tool skipSummarization string output is appended as text', () async {
      final LlmResponse turn1 = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'skip_sum_tool',
              args: <String, dynamic>{},
            ),
          ],
        ),
        finishReason: 'STOP',
      );
      final LlmResponse turn2 = LlmResponse(content: Content.modelText('done'));

      final MockModel model = MockModel(responses: <LlmResponse>[turn1, turn2]);
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        tools: <Object>[
          _SkipSummarizationTool(result: 'tool_response_text'),
        ],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_skip_sum_1',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('test'),
        ),
      );

      // Verify that the tool response event has both function response and text part.
      final List<Event> responseEvents =
          events.where((Event e) => e.getFunctionResponses().isNotEmpty).toList();
      expect(responseEvents, hasLength(1));
      final Event responseEvent = responseEvents.first;

      final List<Part> textParts =
          responseEvent.content?.parts.where((Part p) => p.text != null).toList() ?? <Part>[];
      expect(textParts, hasLength(1));
      expect(textParts.first.text, 'tool_response_text');
    });

    test('tool skipSummarization structured output is JSON-encoded as text', () async {
      final LlmResponse turn1 = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'skip_sum_tool',
              args: <String, dynamic>{},
            ),
          ],
        ),
        finishReason: 'STOP',
      );
      final LlmResponse turn2 = LlmResponse(content: Content.modelText('done'));

      final MockModel model = MockModel(responses: <LlmResponse>[turn1, turn2]);
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        tools: <Object>[
          _SkipSummarizationTool(result: <String, dynamic>{'value': 123}),
        ],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_skip_sum_2',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('test'),
        ),
      );

      final List<Event> responseEvents =
          events.where((Event e) => e.getFunctionResponses().isNotEmpty).toList();
      expect(responseEvents, hasLength(1));
      final Event responseEvent = responseEvents.first;

      final List<Part> textParts =
          responseEvent.content?.parts.where((Part p) => p.text != null).toList() ?? <Part>[];
      expect(textParts, hasLength(1));
      expect(textParts.first.text, '{"value":123}');
    });

    test('tool skipSummarization null output is not appended as text', () async {
      final LlmResponse turn1 = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'skip_sum_tool',
              args: <String, dynamic>{},
            ),
          ],
        ),
        finishReason: 'STOP',
      );
      final LlmResponse turn2 = LlmResponse(content: Content.modelText('done'));

      final MockModel model = MockModel(responses: <LlmResponse>[turn1, turn2]);
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        tools: <Object>[
          _SkipSummarizationTool(result: null),
        ],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 'session_skip_sum_3',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('test'),
        ),
      );

      final List<Event> responseEvents =
          events.where((Event e) => e.getFunctionResponses().isNotEmpty).toList();
      expect(responseEvents, hasLength(1));
      final Event responseEvent = responseEvents.first;

      final List<Part> textParts =
          responseEvent.content?.parts.where((Part p) => p.text != null).toList() ?? <Part>[];
      // null result maps to {"result": null} which is skipped from adding text.
      expect(textParts, isEmpty);
    });
  });
}

class _SkipSummarizationTool extends BaseTool {
  _SkipSummarizationTool({required this.result})
      : super(name: 'skip_sum_tool', description: 'description');

  final Object? result;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(name: name, description: description);
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    toolContext.actions.skipSummarization = true;
    return result;
  }
}



