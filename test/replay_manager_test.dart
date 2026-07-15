import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  group('ReplayManager tests', () {
    test('Event indexing and transitive propagation', () {
      final ReplayManager manager = ReplayManager();

      final Event e1 = Event(
        invocationId: 'inv_1',
        author: 'agent',
        nodeInfo: NodeInfo(path: 'workflow@1/nodeA@1'),
      );
      final Event e2 = Event(
        invocationId: 'inv_1',
        author: 'agent',
        nodeInfo: NodeInfo(path: 'workflow@1/nodeA@1/subNode@1'),
      );
      final Event e3 = Event(
        invocationId: 'inv_1',
        author: 'user',
        content: Content.userText('hello'),
      );

      final List<Event> events = <Event>[e1, e2, e3];
      final Session session = Session(
        id: 'sess_1',
        appName: 'app',
        userId: 'u1',
        events: events,
      );
      final LlmAgent agent = LlmAgent(
        name: 'root_agent',
        model: _NoopModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InvocationContext ic = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_1',
        agent: agent,
        session: session,
      );
      final Context ctx = Context(ic);

      final List<Event> nodeAEvents =
          manager.getEventsForRehydration(ctx, 'workflow@1/nodeA@1');

      expect(nodeAEvents, contains(e1));
      expect(nodeAEvents, contains(e2));
      expect(nodeAEvents, contains(e3));
    });
  });
}
