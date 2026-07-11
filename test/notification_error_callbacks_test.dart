// Tests for onAgentErrorCallback and onRunErrorCallback.
//
// Validates RFC #5044: agent-level and runner-level error callbacks. Ported
// from google/adk-python
// tests/unittests/plugins/test_notification_error_callbacks.py.

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _CrashingAgent extends BaseAgent {
  _CrashingAgent({required super.name, Object? crashError})
    : crashError = crashError ?? StateError('agent crashed');

  final Object crashError;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    throw crashError;
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    throw crashError;
  }
}

class _SuccessAgent extends BaseAgent {
  _SuccessAgent({
    required super.name,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  });

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('ok'),
    );
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('ok live'),
    );
  }
}

class _ErrorTrackingPlugin extends BasePlugin {
  _ErrorTrackingPlugin({String name = 'error_tracker'}) : super(name: name);

  final List<({String agentName, Object error})> agentErrors =
      <({String agentName, Object error})>[];
  final List<Object> runErrors = <Object>[];
  bool afterAgentCalled = false;
  bool afterRunCalled = false;

  @override
  Future<void> onAgentErrorCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
    required Object error,
  }) async {
    agentErrors.add((agentName: agent.name, error: error));
  }

  @override
  Future<void> onRunErrorCallback({
    required InvocationContext invocationContext,
    required Object error,
  }) async {
    runErrors.add(error);
  }

  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    afterAgentCalled = true;
    return null;
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    afterRunCalled = true;
  }
}

InvocationContext _newContext(BaseAgent agent, {PluginManager? pluginManager}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'test_invocation',
    agent: agent,
    session: Session(id: 's1', appName: 'test_app', userId: 'test_user'),
    pluginManager: pluginManager,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Agent-level error callback tests
  // -------------------------------------------------------------------------
  group('onAgentErrorCallback', () {
    test('fires when runAsyncImpl throws', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      await expectLater(
        agent.runAsync(ctx).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'agent crashed',
          ),
        ),
      );

      expect(plugin.agentErrors, hasLength(1));
      expect(plugin.agentErrors.first.agentName, 'crash_agent');
    });

    test('fires when runLiveImpl throws', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      await expectLater(agent.runLive(ctx).toList(), throwsA(isA<StateError>()));

      expect(plugin.agentErrors, hasLength(1));
      expect(plugin.agentErrors.first.agentName, 'crash_agent');
    });

    test('afterAgentCallback is NOT called on crash', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      await expectLater(agent.runAsync(ctx).toList(), throwsA(isA<Object>()));

      expect(plugin.afterAgentCalled, isFalse);
    });

    test('fires when beforeAgentCallback raises', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _SuccessAgent agent = _SuccessAgent(
        name: 'good_agent',
        beforeAgentCallback: (CallbackContext _) {
          throw StateError('before boom');
        },
      );
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      await expectLater(
        agent.runAsync(ctx).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'before boom',
          ),
        ),
      );

      expect(plugin.agentErrors, hasLength(1));
      expect(plugin.agentErrors.first.agentName, 'good_agent');
      expect(plugin.afterAgentCalled, isFalse);
    });

    test('fires when afterAgentCallback raises', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _SuccessAgent agent = _SuccessAgent(
        name: 'good_agent',
        afterAgentCallback: (CallbackContext _) {
          throw StateError('after boom');
        },
      );
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      await expectLater(
        agent.runAsync(ctx).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'after boom',
          ),
        ),
      );

      expect(plugin.agentErrors, hasLength(1));
      expect(plugin.agentErrors.first.agentName, 'good_agent');
    });

    test('original exception propagates after error callback', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final Object err = ArgumentError('specific error');
      final _CrashingAgent agent = _CrashingAgent(
        name: 'crash_agent',
        crashError: err,
      );
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      await expectLater(
        agent.runAsync(ctx).toList(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does NOT fire on success', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _SuccessAgent agent = _SuccessAgent(name: 'good_agent');
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      final List<Event> events = await agent.runAsync(ctx).toList();

      expect(events, isNotEmpty);
      expect(plugin.agentErrors, isEmpty);
      // afterAgentCallback should still fire on success.
      expect(plugin.afterAgentCalled, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Runner-level error callback tests
  // -------------------------------------------------------------------------
  group('onRunErrorCallback', () {
    test('fires when the agent crashes', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'test_user',
      );

      await expectLater(
        runner
            .runAsync(
              userId: 'test_user',
              sessionId: session.id,
              newMessage: Content.userText('hello'),
            )
            .toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'agent crashed',
          ),
        ),
      );

      expect(plugin.runErrors, hasLength(1));
    });

    test('afterRunCallback NOT called on crash', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'test_user',
      );

      await expectLater(
        runner
            .runAsync(
              userId: 'test_user',
              sessionId: session.id,
              newMessage: Content.userText('hello'),
            )
            .toList(),
        throwsA(isA<Object>()),
      );

      expect(plugin.afterRunCalled, isFalse);
    });

    test('does NOT fire on success', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _SuccessAgent agent = _SuccessAgent(name: 'good_agent');
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'test_user',
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'test_user',
            sessionId: session.id,
            newMessage: Content.userText('hello'),
          )
          .toList();

      expect(events, isNotEmpty);
      expect(plugin.runErrors, isEmpty);
      expect(plugin.afterRunCalled, isTrue);
    });

    test('an afterRunCallback failure notifies onRunError and re-raises', () async {
      final _ErrorTrackingPlugin tracker = _ErrorTrackingPlugin();
      final _SuccessAgent agent = _SuccessAgent(name: 'good_agent');
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[
          _FailingAfterRunPlugin(name: 'failing_after_run'),
          tracker,
        ],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'test_user',
      );

      await expectLater(
        runner
            .runAsync(
              userId: 'test_user',
              sessionId: session.id,
              newMessage: Content.userText('hello'),
            )
            .toList(),
        throwsA(
          isA<PluginManagerException>().having(
            (PluginManagerException e) => e.message,
            'message',
            contains('after_run failed'),
          ),
        ),
      );

      // Exactly one run-error notification for the after_run failure.
      expect(tracker.runErrors, hasLength(1));
      expect(tracker.runErrors.first.toString(), contains('after_run failed'));
    });
  });

  // -------------------------------------------------------------------------
  // Exactly-once-per-layer tests
  // -------------------------------------------------------------------------
  group('exactly once per layer', () {
    test('a crashing agent fires both callbacks once each', () async {
      final _ErrorTrackingPlugin plugin = _ErrorTrackingPlugin();
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'test_user',
      );

      await expectLater(
        runner
            .runAsync(
              userId: 'test_user',
              sessionId: session.id,
              newMessage: Content.userText('hello'),
            )
            .toList(),
        throwsA(isA<StateError>()),
      );

      // Agent error callback: exactly 1 call.
      expect(plugin.agentErrors, hasLength(1));
      expect(plugin.agentErrors.first.agentName, 'crash_agent');

      // Run error callback: exactly 1 call (same exception bubbled up).
      expect(plugin.runErrors, hasLength(1));
      expect(plugin.runErrors.first, same(plugin.agentErrors.first.error));

      // Neither after callback should fire.
      expect(plugin.afterAgentCalled, isFalse);
      expect(plugin.afterRunCalled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // PluginManager dispatch tests
  // -------------------------------------------------------------------------
  group('PluginManager error callback dispatch', () {
    test('runOnAgentErrorCallback calls all plugins', () async {
      final _ErrorTrackingPlugin p1 = _ErrorTrackingPlugin(name: 'p1');
      final _ErrorTrackingPlugin p2 = _ErrorTrackingPlugin(name: 'p2');
      final PluginManager pm = PluginManager(plugins: <BasePlugin>[p1, p2]);
      final BaseAgent agent = _SuccessAgent(name: 'test_agent');
      final InvocationContext ctx = _newContext(agent);

      await pm.runOnAgentErrorCallback(
        agent: agent,
        callbackContext: Context(ctx),
        error: StateError('boom'),
      );

      expect(p1.agentErrors, hasLength(1));
      expect(p2.agentErrors, hasLength(1));
    });

    test('runOnRunErrorCallback calls all plugins', () async {
      final _ErrorTrackingPlugin p1 = _ErrorTrackingPlugin(name: 'p1');
      final _ErrorTrackingPlugin p2 = _ErrorTrackingPlugin(name: 'p2');
      final PluginManager pm = PluginManager(plugins: <BasePlugin>[p1, p2]);
      final InvocationContext ctx = _newContext(_SuccessAgent(name: 'a'));

      await pm.runOnRunErrorCallback(
        invocationContext: ctx,
        error: StateError('boom'),
      );

      expect(p1.runErrors, hasLength(1));
      expect(p2.runErrors, hasLength(1));
    });

    test('a plugin callback failure does not mask the app error', () async {
      final _FailingPlugin p1 = _FailingPlugin(name: 'p1');
      final _ErrorTrackingPlugin p2 = _ErrorTrackingPlugin(name: 'p2');
      final PluginManager pm = PluginManager(plugins: <BasePlugin>[p1, p2]);
      final BaseAgent agent = _SuccessAgent(name: 'test_agent');
      final InvocationContext ctx = _newContext(agent);

      // Agent error callback: p1 raises, p2 must still be notified.
      await pm.runOnAgentErrorCallback(
        agent: agent,
        callbackContext: Context(ctx),
        error: StateError('app crash'),
      );
      expect(p1.agentErrorCalled, isTrue);
      expect(p2.agentErrors, hasLength(1));

      // Run error callback: same behavior.
      await pm.runOnRunErrorCallback(
        invocationContext: ctx,
        error: StateError('app crash'),
      );
      expect(p1.runErrorCalled, isTrue);
      expect(p2.runErrors, hasLength(1));
    });

    test('end-to-end: a crashing agent plugin does not mask the error', () async {
      final _FailingPlugin plugin = _FailingPlugin(name: 'bad_plugin');
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InvocationContext ctx = _newContext(
        agent,
        pluginManager: PluginManager(plugins: <BasePlugin>[plugin]),
      );

      // The caller must see the original StateError('agent crashed'), NOT the
      // plugin's ArgumentError.
      await expectLater(
        agent.runAsync(ctx).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'agent crashed',
          ),
        ),
      );
    });

    test('end-to-end: a crashing run plugin does not mask the error', () async {
      final _FailingPlugin plugin = _FailingPlugin(name: 'bad_plugin');
      final _CrashingAgent agent = _CrashingAgent(name: 'crash_agent');
      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'test_user',
      );

      await expectLater(
        runner
            .runAsync(
              userId: 'test_user',
              sessionId: session.id,
              newMessage: Content.userText('hello'),
            )
            .toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'agent crashed',
          ),
        ),
      );
    });
  });
}

class _FailingAfterRunPlugin extends BasePlugin {
  _FailingAfterRunPlugin({required super.name});

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    throw StateError('after_run failed');
  }
}

class _FailingPlugin extends BasePlugin {
  _FailingPlugin({required super.name});

  bool agentErrorCalled = false;
  bool runErrorCalled = false;

  @override
  Future<void> onAgentErrorCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
    required Object error,
  }) async {
    agentErrorCalled = true;
    throw ArgumentError('plugin boom');
  }

  @override
  Future<void> onRunErrorCallback({
    required InvocationContext invocationContext,
    required Object error,
  }) async {
    runErrorCalled = true;
    throw ArgumentError('plugin boom');
  }
}
