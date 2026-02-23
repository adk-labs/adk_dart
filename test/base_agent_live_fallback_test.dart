import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _AsyncOnlyAgent extends BaseAgent {
  _AsyncOnlyAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('async-path'),
    );
  }
}

void main() {
  test('BaseAgent.runLiveImpl falls back to runAsyncImpl', () async {
    final _AsyncOnlyAgent agent = _AsyncOnlyAgent(name: 'async_only');
    final InvocationContext context = InvocationContext(
      sessionService: InMemorySessionService(),
      invocationId: 'inv_live_fallback',
      agent: agent,
      session: Session(id: 's1', appName: 'app', userId: 'u1'),
    );

    final List<Event> events = await agent.runLive(context).toList();
    expect(events, hasLength(1));
    expect(events.first.content?.parts.first.text, 'async-path');
  });
}
