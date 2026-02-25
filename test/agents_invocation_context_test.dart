import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopAgent extends BaseAgent {
  _NoopAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

InvocationContext _newContext({
  required String invocationId,
  bool resumable = false,
  List<Event>? events,
  PluginManager? pluginManager,
}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: _NoopAgent(name: 'root'),
    session: Session(
      id: 's1',
      appName: 'app',
      userId: 'u1',
      events: events ?? <Event>[],
    ),
    resumabilityConfig: ResumabilityConfig(isResumable: resumable),
    pluginManager: pluginManager,
  );
}

void main() {
  group('InvocationContext', () {
    test(
      'populateInvocationAgentStates only uses current invocation events',
      () {
        final Event inv1State = Event(
          invocationId: 'inv_1',
          author: 'worker',
          actions: EventActions(agentState: <String, Object?>{'step': 1}),
        );
        final Event inv2State = Event(
          invocationId: 'inv_2',
          author: 'worker',
          actions: EventActions(agentState: <String, Object?>{'step': 2}),
        );
        final InvocationContext context = _newContext(
          invocationId: 'inv_1',
          resumable: true,
          events: <Event>[inv1State, inv2State],
        );

        context.populateInvocationAgentStates();

        expect(context.agentStates['worker']?['step'], 1);
        expect(context.endOfAgents['worker'], isFalse);
      },
    );

    test(
      'shouldPauseInvocation requires resumable + long-running call match',
      () {
        final Event pausingEvent = Event(
          invocationId: 'inv_1',
          author: 'root',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'long_running_tool',
                id: 'call_pause',
                args: <String, Object?>{'key': 'value'},
              ),
            ],
          ),
          longRunningToolIds: <String>{'call_pause'},
        );

        final InvocationContext resumableContext = _newContext(
          invocationId: 'inv_1',
          resumable: true,
        );
        final InvocationContext nonResumableContext = _newContext(
          invocationId: 'inv_1',
          resumable: false,
        );

        expect(resumableContext.shouldPauseInvocation(pausingEvent), isTrue);
        expect(
          nonResumableContext.shouldPauseInvocation(pausingEvent),
          isFalse,
        );

        final Event noMatchEvent = Event(
          invocationId: 'inv_1',
          author: 'root',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(name: 'tool', id: 'call_other', args: {}),
            ],
          ),
          longRunningToolIds: <String>{'call_pause'},
        );
        expect(resumableContext.shouldPauseInvocation(noMatchEvent), isFalse);
      },
    );

    test(
      'findMatchingFunctionCall searches only current invocation and prior events',
      () {
        final Event callInInvocation = Event(
          id: 'evt_call_inv1',
          invocationId: 'inv_1',
          author: 'agent_a',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(name: 'tool_a', id: 'fc_1', args: {}),
            ],
          ),
        );
        final Event otherInvocationCall = Event(
          id: 'evt_call_inv2',
          invocationId: 'inv_2',
          author: 'agent_b',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(name: 'tool_b', id: 'fc_1', args: {}),
            ],
          ),
        );
        final Event responseEvent = Event(
          id: 'evt_response',
          invocationId: 'inv_1',
          author: 'agent_a',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'tool_a',
                id: 'fc_1',
                response: <String, Object?>{'ok': true},
              ),
            ],
          ),
        );
        final Event laterSameIdCall = Event(
          id: 'evt_later_same_id',
          invocationId: 'inv_1',
          author: 'agent_c',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(name: 'tool_c', id: 'fc_1', args: {}),
            ],
          ),
        );

        final InvocationContext context = _newContext(
          invocationId: 'inv_1',
          resumable: true,
          events: <Event>[
            callInInvocation,
            otherInvocationCall,
            responseEvent,
            laterSameIdCall,
          ],
        );

        final Event? matched = context.findMatchingFunctionCall(responseEvent);

        expect(matched, isNotNull);
        expect(matched!.id, 'evt_call_inv1');
        expect(matched.author, 'agent_a');
      },
    );

    test('copyWith preserves pluginManager instance by default', () {
      final PluginManager manager = PluginManager();
      final InvocationContext context = _newContext(
        invocationId: 'inv_1',
        pluginManager: manager,
      );

      final InvocationContext copied = context.copyWith();

      expect(identical(copied.pluginManager, manager), isTrue);
    });
  });
}
