import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _ProbeAgent extends BaseAgent {
  _ProbeAgent({
    required super.name,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  });

  int runAsyncCalls = 0;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    runAsyncCalls += 1;
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('run:$runAsyncCalls'),
    );
  }
}

InvocationContext _newContext(BaseAgent agent) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: agent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  group('BaseAgent lifecycle callbacks', () {
    test(
      'before callback returning content short-circuits agent run',
      () async {
        final _ProbeAgent agent = _ProbeAgent(
          name: 'probe',
          beforeAgentCallback: (CallbackContext context) async {
            return Content.modelText('blocked-by-before');
          },
        );

        final List<Event> events = await agent
            .runAsync(_newContext(agent))
            .toList();

        expect(agent.runAsyncCalls, 0);
        expect(events, hasLength(1));
        expect(events.single.author, 'probe');
        expect(events.single.content?.parts.single.text, 'blocked-by-before');
      },
    );

    test(
      'before callback state delta emits actions event before run',
      () async {
        final _ProbeAgent agent = _ProbeAgent(
          name: 'probe',
          beforeAgentCallback: (CallbackContext context) async {
            context.state['before_flag'] = true;
            return null;
          },
        );

        final List<Event> events = await agent
            .runAsync(_newContext(agent))
            .toList();

        expect(agent.runAsyncCalls, 1);
        expect(events, hasLength(2));
        expect(events.first.actions.stateDelta['before_flag'], isTrue);
        expect(events.last.content?.parts.single.text, 'run:1');
      },
    );

    test('after callback state delta emits actions event after run', () async {
      final _ProbeAgent agent = _ProbeAgent(
        name: 'probe',
        afterAgentCallback: (CallbackContext context) async {
          context.state['after_flag'] = 123;
          return null;
        },
      );

      final List<Event> events = await agent
          .runAsync(_newContext(agent))
          .toList();

      expect(agent.runAsyncCalls, 1);
      expect(events, hasLength(2));
      expect(events.first.content?.parts.single.text, 'run:1');
      expect(events.last.actions.stateDelta['after_flag'], 123);
    });
  });
}
