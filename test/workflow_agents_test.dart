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

class _LiveStubLlmAgent extends LlmAgent {
  _LiveStubLlmAgent({required super.name, super.instruction = 'stub'});

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('live-llm $name'),
    );
  }
}

class _PauseOnceAgent extends BaseAgent {
  _PauseOnceAgent({required super.name, this.delay = Duration.zero});

  final Duration delay;
  static const String _longRunningToolId = 'call_pause';
  bool hasPaused = false;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    if (!hasPaused) {
      hasPaused = true;
      yield Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'long_running',
              id: _longRunningToolId,
              args: <String, Object?>{'agent': name},
            ),
          ],
        ),
        longRunningToolIds: <String>{_longRunningToolId},
      );
      return;
    }

    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('resumed $name'),
    );

    if (context.isResumable) {
      context.setAgentState(name, endOfAgent: true);
      yield createAgentStateEvent(context);
    }
  }
}

class _DelayedMultiEventAgent extends BaseAgent {
  _DelayedMultiEventAgent({
    required super.name,
    this.firstDelay = Duration.zero,
    this.secondDelay = Duration.zero,
  });

  final Duration firstDelay;
  final Duration secondDelay;
  int emittedEvents = 0;
  bool streamClosed = false;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    try {
      if (firstDelay > Duration.zero) {
        await Future<void>.delayed(firstDelay);
      }

      emittedEvents += 1;
      yield Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        content: Content.modelText('first $name'),
      );

      if (secondDelay > Duration.zero) {
        await Future<void>.delayed(secondDelay);
      }

      emittedEvents += 1;
      yield Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        content: Content.modelText('second $name'),
      );
    } finally {
      streamClosed = true;
    }
  }
}

class _CompletingCheckpointAgent extends BaseAgent {
  _CompletingCheckpointAgent({required super.name});
  int runCount = 0;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    runCount += 1;

    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('done $name'),
    );

    if (context.isResumable) {
      context.setAgentState(name, endOfAgent: true);
      yield createAgentStateEvent(context);
    }
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

    test(
      'runLive injects task_completed handoff tool once for LLM sub-agent',
      () async {
        final _LiveStubLlmAgent llm = _LiveStubLlmAgent(
          name: 'llm_child',
          instruction: 'Base instruction.',
        );
        final SequentialAgent root = SequentialAgent(
          name: 'root',
          subAgents: <BaseAgent>[llm],
        );
        final InvocationContext context = await _newContext(
          agent: root,
          resumable: false,
        );

        await root.runLive(context).toList();
        await root.runLive(context).toList();

        final List<BaseTool> taskCompletedTools = llm.tools
            .whereType<BaseTool>()
            .where((BaseTool tool) => tool.name == 'task_completed')
            .toList(growable: false);
        expect(taskCompletedTools, hasLength(1));
        expect(llm.instruction, isA<String>());
        final String instruction = llm.instruction as String;
        expect(
          RegExp(r'\btask_completed\b').allMatches(instruction).length,
          equals(1),
        );
      },
    );
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
      expect(events, hasLength(3));
      expect(events[0].author, 'root');
      expect(events[1].author, 'fast');
      expect(events[2].author, 'slow');
      expect(events[1].branch, 'root.fast');
      expect(events[2].branch, 'root.slow');
      expect(
        events.where((Event event) => event.actions.endOfAgent == true),
        isEmpty,
      );
    });

    test('runLive falls back to async execution', () async {
      final ParallelAgent root = ParallelAgent(
        name: 'root',
        subAgents: <BaseAgent>[_EmitAgent(name: 'child')],
      );
      final InvocationContext context = await _newContext(
        agent: root,
        resumable: false,
      );

      final List<Event> events = await root.runLive(context).toList();
      expect(events, hasLength(1));
      expect(events.single.author, 'child');
      expect(events.single.branch, 'root.child');
    });

    test(
      'pauses immediately without draining remaining sub-agent streams',
      () async {
        final _PauseOnceAgent pauser = _PauseOnceAgent(
          name: 'pauser',
          delay: const Duration(milliseconds: 10),
        );
        final _DelayedMultiEventAgent trailing = _DelayedMultiEventAgent(
          name: 'trailing',
          firstDelay: const Duration(milliseconds: 200),
          secondDelay: const Duration(milliseconds: 200),
        );
        final ParallelAgent root = ParallelAgent(
          name: 'root',
          subAgents: <BaseAgent>[pauser, trailing],
        );

        final InvocationContext context = await _newContext(
          agent: root,
          resumable: true,
        );

        final List<Event> events = await root.runAsync(context).toList();

        expect(events.map((Event event) => event.author), <String>[
          'root',
          'pauser',
        ]);
        expect(
          events.where(
            (Event event) =>
                event.author == 'root' && event.actions.endOfAgent == true,
          ),
          isEmpty,
        );
        expect(trailing.emittedEvents, lessThan(2));
        expect(trailing.streamClosed, isTrue);
      },
    );

    test('keeps resumability when paused run is resumed', () async {
      final _CompletingCheckpointAgent completed = _CompletingCheckpointAgent(
        name: 'completed',
      );
      final _PauseOnceAgent pauser = _PauseOnceAgent(
        name: 'pauser',
        delay: const Duration(milliseconds: 50),
      );
      final ParallelAgent root = ParallelAgent(
        name: 'root',
        subAgents: <BaseAgent>[completed, pauser],
      );

      final InvocationContext context = await _newContext(
        agent: root,
        resumable: true,
      );

      final List<Event> firstRun = await root.runAsync(context).toList();
      expect(
        firstRun.where(
          (Event event) =>
              event.author == 'root' && event.actions.endOfAgent == true,
        ),
        isEmpty,
      );
      expect(completed.runCount, 1);

      context.session.events.addAll(firstRun);
      context.populateInvocationAgentStates();

      final List<Event> resumedRun = await root.runAsync(context).toList();
      expect(completed.runCount, 1);
      expect(
        resumedRun.where((Event event) => event.author == 'completed'),
        isEmpty,
      );
      expect(resumedRun.map((Event event) => event.author), <String>[
        'pauser',
        'pauser',
        'root',
      ]);
      expect(resumedRun[0].content?.parts.single.text, 'resumed pauser');
      expect(resumedRun[1].actions.endOfAgent, isTrue);
      expect(resumedRun[2].actions.endOfAgent, isTrue);
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

    test('treats maxIterations=0 as no iteration limit', () async {
      final _EmitAgent worker = _EmitAgent(name: 'worker');
      final _EmitAgent escalator = _EmitAgent(
        name: 'escalator',
        escalate: true,
      );
      final LoopAgent loop = LoopAgent(
        name: 'loop',
        subAgents: <BaseAgent>[worker, escalator],
        maxIterations: 0,
      );
      final InvocationContext context = await _newContext(
        agent: loop,
        resumable: false,
      );

      final List<Event> events = await loop.runAsync(context).toList();
      expect(events.map((Event event) => event.author), <String>[
        'worker',
        'escalator',
        'escalator',
      ]);
    });

    test('runLive falls back to async execution', () async {
      final LoopAgent loop = LoopAgent(
        name: 'loop',
        subAgents: <BaseAgent>[_EmitAgent(name: 'worker')],
        maxIterations: 1,
      );
      final InvocationContext context = await _newContext(
        agent: loop,
        resumable: false,
      );

      final List<Event> events = await loop.runLive(context).toList();
      expect(events, hasLength(1));
      expect(events.single.author, 'worker');
    });
  });
}
