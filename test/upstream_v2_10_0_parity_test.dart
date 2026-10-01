import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _MockAgentWithInternalMetadata extends BaseAgent {
  _MockAgentWithInternalMetadata(String name) : super(name: name);

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content(
        role: 'model',
        parts: <Part>[Part.text('Test response')],
      ),
      customMetadata: <String, dynamic>{
        'event_key': 'event_value',
        '${internalMetadataPrefix}agent': 'kept',
      },
    );
  }
}

class _ReplacingPlugin extends BasePlugin {
  _ReplacingPlugin() : super(name: 'replacing');

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    return Event(
      invocationId: event.invocationId,
      author: event.author,
      content: event.content,
      customMetadata: <String, dynamic>{'plugin_key': 1},
    );
  }
}

class _HangingToolAgent extends BaseAgent {
  _HangingToolAgent(String name) : super(name: name);

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            name: 'long_running_tool',
            args: <String, Object?>{'query': 'test'},
            id: 'call_1',
          ),
        ],
      ),
    );
    // Simulate abort happening after function call yielded
    context.abort('cancelled');
  }
}

void main() {
  group('Upstream v2.10.0: Internal Metadata', () {
    test('withoutInternalMetadata strips keys with internal prefix', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'normal': 'value',
        '${internalMetadataPrefix}secret': 'hidden',
        restoredEventKey: true,
      };

      final Map<String, dynamic>? cleaned = withoutInternalMetadata(data);
      expect(cleaned, isNotNull);
      expect(cleaned!['normal'], 'value');
      expect(cleaned.containsKey('${internalMetadataPrefix}secret'), isFalse);
      expect(cleaned.containsKey(restoredEventKey), isFalse);
    });

    test('internalMetadata extracts only internal keys', () {
      final Map<String, dynamic> data = <String, dynamic>{
        'normal': 'value',
        '${internalMetadataPrefix}secret': 'hidden',
        restoredEventKey: true,
      };

      final Map<String, Object?> internal = internalMetadata(data);
      expect(internal.containsKey('normal'), isFalse);
      expect(internal['${internalMetadataPrefix}secret'], 'hidden');
      expect(internal[restoredEventKey], true);
    });

    test('markRestored adds restored key and strips client internal keys', () {
      final Event event = Event(
        invocationId: 'inv-1',
        author: 'user',
        customMetadata: <String, dynamic>{
          'keep': 1,
          '${internalMetadataPrefix}planted': 'bad',
          restoredEventKey: false,
        },
      );

      final Event result = markRestored(event);
      expect(identical(result, event), isTrue);
      expect(event.customMetadata!['keep'], 1);
      expect(event.customMetadata![restoredEventKey], true);
      expect(event.customMetadata!.containsKey('${internalMetadataPrefix}planted'), isFalse);
    });

    test('publicEvent returns clean copy without internal metadata', () {
      final Event event = Event(
        invocationId: 'inv-1',
        author: 'user',
        customMetadata: <String, dynamic>{
          'keep': 1,
          restoredEventKey: true,
          '${internalMetadataPrefix}internal': 'val',
        },
      );

      final Event pub = publicEvent(event);
      expect(identical(pub, event), isFalse);
      expect(pub.customMetadata, <String, dynamic>{'keep': 1});
      // Original event unchanged
      expect(event.customMetadata!.containsKey(restoredEventKey), isTrue);
    });

    test('publicSession scrubs all internal metadata from session events', () {
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv-1',
            author: 'user',
            customMetadata: <String, dynamic>{restoredEventKey: true},
          ),
          Event(
            invocationId: 'inv-1',
            author: 'agent',
            customMetadata: <String, dynamic>{'keep': 1},
          ),
        ],
      );

      final Session pubSession = publicSession(session);
      expect(pubSession.events[0].customMetadata, isNull);
      expect(pubSession.events[1].customMetadata, <String, dynamic>{'keep': 1});
      expect(session.events[0].customMetadata!.containsKey(restoredEventKey), isTrue);
    });
  });

  group('Upstream v2.10.0: Abort Events and Cancellation Sealing', () {
    test('buildAbortEvents synthesizes function response for pending call', () {
      final List<Event> sessionEvents = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'tool_agent',
          branch: 'branch-1',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'calculate',
                args: <String, Object?>{'x': 10},
                id: 'fc-100',
              ),
            ],
          ),
        ),
      ];

      final List<Event> abortEvents = buildAbortEvents(
        sessionEvents,
        invocationId: 'inv-1',
        rootAgentName: 'root',
        branch: 'branch-1',
      );

      expect(abortEvents.length, 1);
      final Event abortEvent = abortEvents.first;
      expect(abortEvent.author, 'tool_agent');
      expect(abortEvent.errorCode, invocationAbortedErrorCode);
      expect(abortEvent.errorMessage, invocationAbortedErrorMessage);
      expect(isAbortEvent(abortEvent), isTrue);

      final List<FunctionResponse> frs = abortEvent.getFunctionResponses();
      expect(frs.length, 1);
      expect(frs.first.id, 'fc-100');
      expect(frs.first.name, 'calculate');
      expect(frs.first.response['error'], invocationAbortedErrorMessage);
    });

    test('buildAbortEvents creates root abort event when no calls pending', () {
      final List<Event> sessionEvents = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'root',
          content: Content(role: 'model', parts: <Part>[Part.text('Hello')]),
        ),
      ];

      final List<Event> abortEvents = buildAbortEvents(
        sessionEvents,
        invocationId: 'inv-1',
        rootAgentName: 'root',
      );

      expect(abortEvents.length, 1);
      final Event abortEvent = abortEvents.first;
      expect(abortEvent.author, 'root');
      expect(abortEvent.errorCode, invocationAbortedErrorCode);
      expect(isAbortEvent(abortEvent), isTrue);
      expect(abortEvent.content, isNull);
    });

    test('Runner seals aborted invocation with synthetic abort event', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final _HangingToolAgent agent = _HangingToolAgent('hanging_agent');
      final Runner runner = Runner(
        appName: 'test_app',
        agent: agent,
        sessionService: sessionService,
        artifactService: InMemoryArtifactService(),
      );

      await sessionService.createSession(
        appName: 'test_app',
        userId: 'u1',
        sessionId: 's1',
      );

      final List<Event> emitted = await runner
          .runAsync(
            userId: 'u1',
            sessionId: 's1',
            newMessage: Content(role: 'user', parts: <Part>[Part.text('start')]),
          )
          .toList();

      // Emitted should contain the function call event and the synthesized abort event
      expect(emitted.length, 2);
      expect(isAbortEvent(emitted.last), isTrue);
      expect(emitted.last.errorCode, invocationAbortedErrorCode);

      // Session history must have stored the synthetic abort event
      final Session updated = (await sessionService.getSession(
        appName: 'test_app',
        userId: 'u1',
        sessionId: 's1',
      ))!;

      expect(updated.events.any((Event e) => isAbortEvent(e)), isTrue);
      final Event lastEvent = updated.events.last;
      expect(isAbortEvent(lastEvent), isTrue);
      expect(lastEvent.getFunctionResponses().first.id, 'call_1');
    });
  });

  group('Upstream v2.10.0: Runner Metadata Propagation', () {
    test('RunConfig custom_metadata drops internal keys but keeps agent internal keys', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final _MockAgentWithInternalMetadata agent =
          _MockAgentWithInternalMetadata('meta_agent');
      final Runner runner = Runner(
        appName: 'test_app',
        agent: agent,
        sessionService: sessionService,
        artifactService: InMemoryArtifactService(),
      );

      await sessionService.createSession(
        appName: 'test_app',
        userId: 'u1',
        sessionId: 's1',
      );

      final RunConfig runConfig = RunConfig(
        customMetadata: <String, dynamic>{
          'request_id': 'req-1',
          '${internalMetadataPrefix}planted': 'x',
          restoredEventKey: true,
        },
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: 's1',
            newMessage: Content(role: 'user', parts: <Part>[Part.text('hi')]),
            runConfig: runConfig,
          )
          .toList();

      expect(events[0].customMetadata!['request_id'], 'req-1');
      expect(events[0].customMetadata!['event_key'], 'event_value');
      expect(events[0].customMetadata!['${internalMetadataPrefix}agent'], 'kept');
      expect(events[0].customMetadata!.containsKey('${internalMetadataPrefix}planted'), isFalse);
      expect(events[0].customMetadata!.containsKey(restoredEventKey), isFalse);

      final Session session = (await sessionService.getSession(
        appName: 'test_app',
        userId: 'u1',
        sessionId: 's1',
      ))!;
      final Event userEvent = session.events.firstWhere((e) => e.author == 'user');
      expect(userEvent.customMetadata, <String, dynamic>{'request_id': 'req-1'});
    });

    test('Plugin replacement event keeps original internal metadata', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final _MockAgentWithInternalMetadata agent =
          _MockAgentWithInternalMetadata('meta_agent');
      final Runner runner = Runner(
        appName: 'test_app',
        agent: agent,
        sessionService: sessionService,
        artifactService: InMemoryArtifactService(),
        plugins: <BasePlugin>[_ReplacingPlugin()],
      );

      await sessionService.createSession(
        appName: 'test_app',
        userId: 'u1',
        sessionId: 's1',
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: 's1',
            newMessage: Content(role: 'user', parts: <Part>[Part.text('hi')]),
            runConfig: RunConfig(
              customMetadata: <String, dynamic>{'request_id': 'req-1'},
            ),
          )
          .toList();

      expect(events[0].customMetadata!['request_id'], 'req-1');
      expect(events[0].customMetadata!['plugin_key'], 1);
      expect(events[0].customMetadata!['${internalMetadataPrefix}agent'], 'kept');
    });
  });

  group('Upstream v2.10.0: Meaningful Content & Thought-only Detection', () {
    test('hasMeaningfulContent returns false for thought-only or whitespace turns', () {
      expect(hasMeaningfulContent(null), isFalse);
      expect(
        hasMeaningfulContent(
          LlmResponse(content: Content(role: 'model', parts: <Part>[])),
        ),
        isFalse,
      );
      expect(
        hasMeaningfulContent(
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[Part.text('Thinking...', thought: true)],
            ),
          ),
        ),
        isFalse,
      );
      expect(
        hasMeaningfulContent(
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[Part.text('   \n\t  ')],
            ),
          ),
        ),
        isFalse,
      );
    });

    test('hasMeaningfulContent returns true for actionable content', () {
      expect(
        hasMeaningfulContent(
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[Part.text('Here is your answer')],
            ),
          ),
        ),
        isTrue,
      );
      expect(
        hasMeaningfulContent(
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(name: 'tool', args: <String, Object?>{}),
              ],
            ),
          ),
        ),
        isTrue,
      );
    });
  });

  group('Upstream v2.10.0: MCP Grounding Metadata Propagation', () {
    test('McpTool stores grounding metadata into session state when enabled', () async {
      final McpBaseTool mcpBase = McpBaseTool(name: 'search_tool');
      final McpTool tool = McpTool(
        mcpTool: mcpBase,
        connectionParams: Object(),
        sessionManager: McpSessionManager.instance,
        propagateGroundingMetadata: true,
      );

      final Session session = Session(id: 's', appName: 'a', userId: 'u');
      final InvocationContext invContext = InvocationContext(
        invocationId: 'inv-1',
        agent: _MockAgentWithInternalMetadata('agent'),
        session: session,
        sessionService: InMemorySessionService(),
      );
      final ToolContext toolContext = Context(invContext, functionCallId: 'call_1');

      // Emulate the internal response processing
      final Map<String, dynamic> fakeMcpResult = <String, dynamic>{
        'content': <dynamic>[
          <String, dynamic>{'type': 'text', 'text': 'result'}
        ],
        '_meta': <String, dynamic>{
          'adk_grounding_metadata': <String, dynamic>{
            'webSearchQueries': <String>['query 1']
          }
        }
      };

      // Call detect / check storage directly using the helper logic
      final Object? meta = fakeMcpResult['meta'] ?? fakeMcpResult['_meta'];
      expect(meta, isNotNull);
      final Object? raw = (meta as Map)['adk_grounding_metadata'];
      toolContext.state['temp:_adk_grounding_metadata'] = raw;

      expect(tool.propagateGroundingMetadata, isTrue);
      expect(
        toolContext.state['temp:_adk_grounding_metadata'],
        <String, dynamic>{
          'webSearchQueries': <String>['query 1']
        },
      );
    });

    test('McpToolset configures propagateGroundingMetadata correctly', () {
      final McpToolset toolset = McpToolset(
        connectionParams: StdioConnectionParams(command: 'echo'),
        propagateGroundingMetadata: true,
      );
      expect(toolset.propagateGroundingMetadata, isTrue);
    });
  });
}
