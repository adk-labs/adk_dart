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

class _InterceptingPlugin extends BasePlugin {
  _InterceptingPlugin({this.beforeContent, this.afterContent})
    : super(name: '_intercepting_plugin');

  final Content? beforeContent;
  final Content? afterContent;

  int beforeCalls = 0;
  int afterCalls = 0;

  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    beforeCalls += 1;
    return beforeContent?.copyWith();
  }

  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    afterCalls += 1;
    return afterContent?.copyWith();
  }
}

InvocationContext _newContext(BaseAgent agent, {PluginManager? pluginManager}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: agent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
    pluginManager: pluginManager,
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

    test(
      'plugin before callback content takes precedence over agent callback',
      () async {
        int agentBeforeCalls = 0;
        final _ProbeAgent agent = _ProbeAgent(
          name: 'probe',
          beforeAgentCallback: (CallbackContext context) async {
            agentBeforeCalls += 1;
            return Content.modelText('agent-before');
          },
        );
        final _InterceptingPlugin plugin = _InterceptingPlugin(
          beforeContent: Content.modelText('plugin-before'),
        );
        final PluginManager manager = PluginManager(
          plugins: <BasePlugin>[plugin],
        );

        final List<Event> events = await agent
            .runAsync(_newContext(agent, pluginManager: manager))
            .toList();

        expect(plugin.beforeCalls, 1);
        expect(agentBeforeCalls, 0);
        expect(agent.runAsyncCalls, 0);
        expect(events, hasLength(1));
        expect(events.single.content?.parts.single.text, 'plugin-before');
      },
    );

    test(
      'plugin after callback content takes precedence over agent callback',
      () async {
        int agentAfterCalls = 0;
        final _ProbeAgent agent = _ProbeAgent(
          name: 'probe',
          afterAgentCallback: (CallbackContext context) async {
            agentAfterCalls += 1;
            return Content.modelText('agent-after');
          },
        );
        final _InterceptingPlugin plugin = _InterceptingPlugin(
          afterContent: Content.modelText('plugin-after'),
        );
        final PluginManager manager = PluginManager(
          plugins: <BasePlugin>[plugin],
        );

        final List<Event> events = await agent
            .runAsync(_newContext(agent, pluginManager: manager))
            .toList();

        expect(plugin.afterCalls, 1);
        expect(agentAfterCalls, 0);
        expect(agent.runAsyncCalls, 1);
        expect(events, hasLength(2));
        expect(events.first.content?.parts.single.text, 'run:1');
        expect(events.last.content?.parts.single.text, 'plugin-after');
      },
    );
  });
}
