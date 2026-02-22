import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _EmitAgent extends BaseAgent {
  _EmitAgent({
    required super.name,
    this.delay = Duration.zero,
    this.escalate = false,
  });

  final Duration delay;
  final bool escalate;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('hello $name'),
      actions: escalate ? EventActions(escalate: true) : EventActions(),
    );

    if (escalate) {
      yield Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        content: Content.modelText('done $name'),
      );
    }
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('live $name'),
    );
  }
}

Future<InvocationContext> _newContext({
  required BaseAgent agent,
  required bool resumable,
}) async {
  final InMemorySessionService service = InMemorySessionService();
  final Session session = await service.createSession(
    appName: 'test_app',
    userId: 'test_user',
  );
  return InvocationContext(
    invocationId: 'inv_1',
    agent: agent,
    session: session,
    sessionService: service,
    resumabilityConfig: ResumabilityConfig(isResumable: resumable),
  );
}

void main() {
  group('SequentialAgent', () {
    test(
      'runs sub-agents in order and emits checkpoints when resumable',
      () async {
        final _EmitAgent agent1 = _EmitAgent(name: 'a1');
        final _EmitAgent agent2 = _EmitAgent(name: 'a2');
        final SequentialAgent root = SequentialAgent(
          name: 'root',
          subAgents: <BaseAgent>[agent1, agent2],
        );

        final InvocationContext context = await _newContext(
          agent: root,
          resumable: true,
        );

        final List<Event> events = await root.runAsync(context).toList();
        expect(events, hasLength(5));
        expect(events[0].author, 'root');
        expect(events[0].actions.agentState?['current_sub_agent'], 'a1');
        expect(events[1].author, 'a1');
        expect(events[2].actions.agentState?['current_sub_agent'], 'a2');
        expect(events[3].author, 'a2');
        expect(events[4].actions.endOfAgent, isTrue);
      },
    );

    test('resumes from saved current_sub_agent', () async {
      final _EmitAgent agent1 = _EmitAgent(name: 'a1');
      final _EmitAgent agent2 = _EmitAgent(name: 'a2');
      final SequentialAgent root = SequentialAgent(
        name: 'root',
        subAgents: <BaseAgent>[agent1, agent2],
      );

      final InvocationContext context = await _newContext(
        agent: root,
        resumable: true,
      );
      context.agentStates[root.name] = <String, Object?>{
        'current_sub_agent': 'a2',
      };

      final List<Event> events = await root.runAsync(context).toList();
      expect(events, hasLength(2));
      expect(events[0].author, 'a2');
      expect(events[1].actions.endOfAgent, isTrue);
    });
  });

  group('ParallelAgent', () {
    test('runs sub-agents in parallel with isolated branches', () async {
      final _EmitAgent slow = _EmitAgent(
        name: 'slow',
        delay: const Duration(milliseconds: 200),
      );
      final _EmitAgent fast = _EmitAgent(name: 'fast');

      final ParallelAgent root = ParallelAgent(
        name: 'root',
        subAgents: <BaseAgent>[slow, fast],
      );

      final InvocationContext context = await _newContext(
        agent: root,
        resumable: true,
      );

      final List<Event> events = await root.runAsync(context).toList();
      expect(events, hasLength(4));
      expect(events[0].author, 'root');
      expect(events[1].author, 'fast');
      expect(events[2].author, 'slow');
      expect(events[1].branch, 'root.fast');
      expect(events[2].branch, 'root.slow');
      expect(events[3].actions.endOfAgent, isTrue);
    });
  });

  group('LoopAgent', () {
    test('iterates sub-agents up to maxIterations', () async {
      final _EmitAgent worker = _EmitAgent(name: 'worker');
      final LoopAgent loop = LoopAgent(
        name: 'loop',
        subAgents: <BaseAgent>[worker],
        maxIterations: 2,
      );

      final InvocationContext context = await _newContext(
        agent: loop,
        resumable: true,
      );

      final List<Event> events = await loop.runAsync(context).toList();
      expect(events, hasLength(5));
      expect(events[0].actions.agentState?['times_looped'], 0);
      expect(events[2].actions.agentState?['times_looped'], 1);
      expect(events[4].actions.endOfAgent, isTrue);
    });

    test('stops when a sub-agent escalates', () async {
      final _EmitAgent normal = _EmitAgent(name: 'normal');
      final _EmitAgent escalator = _EmitAgent(
        name: 'escalator',
        escalate: true,
      );
      final _EmitAgent ignored = _EmitAgent(name: 'ignored');

      final LoopAgent loop = LoopAgent(
        name: 'loop',
        subAgents: <BaseAgent>[normal, escalator, ignored],
      );

      final InvocationContext context = await _newContext(
        agent: loop,
        resumable: false,
      );

      final List<Event> events = await loop.runAsync(context).toList();
      expect(events.map((Event e) => e.author), <String>[
        'normal',
        'escalator',
        'escalator',
      ]);
    });
  });
}
