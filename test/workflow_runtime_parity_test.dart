import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/workflow/workflow.dart' as wf;
import 'package:test/test.dart';

class _RetryableWorkflowError implements Exception {
  const _RetryableWorkflowError(this.message);

  final String message;

  @override
  String toString() => '_RetryableWorkflowError: $message';
}

class _NonRetryableWorkflowError implements Exception {
  const _NonRetryableWorkflowError(this.message);

  final String message;

  @override
  String toString() => '_NonRetryableWorkflowError: $message';
}

class _EchoAgent extends BaseAgent {
  _EchoAgent({required super.name, this.stateKey});

  final String? stateKey;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String input =
        context.userContent?.parts
            .where((Part part) => part.text != null)
            .map((Part part) => part.text!)
            .join() ??
        '';
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('agent:$input'),
      actions: stateKey == null
          ? EventActions()
          : EventActions(
              stateDelta: <String, Object?>{stateKey!: 'agent:$input'},
            ),
    );
  }
}

void main() {
  group('workflow runtime parity', () {
    test('runs dependency graph and join nodes', () async {
      final Workflow workflow = Workflow(
        name: 'graph',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? input) => '$input-a', name: 'a'),
          node((WorkflowContext _, Object? input) => '$input-b', name: 'b'),
          JoinNode(name: 'join', dependsOn: const <String>['a', 'b']),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'start');

      expect(result.outputs['a'], 'start-a');
      expect(result.outputs['b'], 'start-b');
      expect(result.outputs['join'], <String, Object?>{
        'a': 'start-a',
        'b': 'start-b',
      });
      expect(result.nodeStates['join']?.status, NodeStatus.completed);
      expect(result.nodeStates['join']?.input, <String, Object?>{
        'a': 'start-a',
        'b': 'start-b',
      });
      expect(result.nodeStates['join']?.runCounter, 1);
      expect(result.nodeStates['join']?.runId, '1');
    });

    test('uses edges as dependencies', () async {
      final FunctionNode first = node(
        (WorkflowContext _, Object? input) => '$input-first',
        name: 'first',
      );
      final FunctionNode second = node(
        (WorkflowContext _, Object? input) => '$input-second',
        name: 'second',
      );
      final Workflow workflow = Workflow(
        name: 'edge_graph',
        nodes: <BaseNode>[first, second],
        edges: <Edge>[Edge(fromNode: first, toNode: second)],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'go');

      expect(result.outputs['second'], 'go-first-second');
    });

    test('stamps workflow output events with nodeInfo metadata', () async {
      final Workflow workflow = Workflow(
        name: 'workflow_agent',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? _) => 'hello', name: 'writer'),
        ],
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_workflow_node_info',
        agent: workflow,
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );

      final List<Event> events = await workflow.runAsync(context).toList();

      expect(events, hasLength(1));
      expect(events.single.nodeInfo.path, 'workflow_agent@1/writer@1');
      expect(events.single.nodeInfo.outputFor, <String>[
        'workflow_agent@1/writer@1',
      ]);
      expect(events.single.nodeInfo.messageAsOutput, isTrue);
      expect(events.single.content?.parts.single.text, 'hello');
    });

    test('converts RequestInput node output to long-running event', () async {
      final Workflow workflow = Workflow(
        name: 'hitl_workflow',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? _) =>
                RequestInput(interruptId: 'ask_1', message: 'Need a decision'),
            name: 'ask_user',
          ),
        ],
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_hitl',
        agent: workflow,
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );

      final List<Event> events = await workflow.runAsync(context).toList();

      expect(events, hasLength(1));
      expect(hasRequestInputFunctionCall(events.single), isTrue);
      expect(events.single.longRunningToolIds, <String>{'ask_1'});
      expect(events.single.nodeInfo.path, 'hitl_workflow@1/ask_user@1');
      final FunctionCall call = events.single.getFunctionCalls().single;
      expect(call.name, requestInputFunctionCallName);
      expect(call.id, 'ask_1');
      expect(call.args['message'], 'Need a decision');
    });

    test(
      'keeps RequestInput node waiting and skips downstream nodes',
      () async {
        final Workflow workflow = Workflow(
          name: 'hitl_waiting',
          nodes: <BaseNode>[
            node(
              (WorkflowContext _, Object? _) =>
                  RequestInput(interruptId: 'ask_2', message: 'Confirm'),
              name: 'ask_user',
            ),
            node(
              (WorkflowContext _, Object? _) => 'should not run',
              name: 'after_user',
            ),
          ],
          edges: <Edge>[Edge(fromNode: 'ask_user', toNode: 'after_user')],
        );

        final WorkflowResult result = await workflow.runWorkflow();
        final NodeState askState = result.nodeStates['ask_user']!;

        expect(askState.status, NodeStatus.waiting);
        expect(askState.interrupts, <String>['ask_2']);
        expect(result.outputs['ask_user'], isA<RequestInput>());
        expect(result.outputs.containsKey('after_user'), isFalse);
        expect(result.nodeStates['after_user'], isNull);
      },
    );

    test('routes edges from workflow event actions', () async {
      final FunctionNode router = node((WorkflowContext _, Object? _) {
        return Event(
          invocationId: 'inv_route',
          author: 'router',
          output: 'A',
          actions: EventActions(route: 'route_b'),
        );
      }, name: 'router');
      final FunctionNode routeB = node(
        (WorkflowContext _, Object? input) => 'b:$input',
        name: 'route_b_node',
      );
      final FunctionNode routeC = node(
        (WorkflowContext _, Object? _) => 'c',
        name: 'route_c_node',
      );
      final Workflow workflow = Workflow(
        name: 'routed_graph',
        nodes: <BaseNode>[router, routeB, routeC],
        edges: <Edge>[
          Edge(fromNode: router, toNode: routeB, route: 'route_b'),
          Edge(fromNode: router, toNode: routeC, route: 'route_c'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['router'], 'A');
      expect(result.outputs['route_b_node'], 'b:A');
      expect(result.outputs.containsKey('route_c_node'), isFalse);
      expect(result.nodeStates['route_c_node'], isNull);
    });

    test('routes default and untagged workflow edges', () async {
      final FunctionNode router = node((WorkflowContext _, Object? _) {
        return Event(
          invocationId: 'inv_default_route',
          author: 'router',
          actions: EventActions(route: 'unmatched'),
        );
      }, name: 'router');
      final FunctionNode specific = node(
        (WorkflowContext _, Object? _) => 'specific',
        name: 'specific',
      );
      final FunctionNode fallback = node(
        (WorkflowContext _, Object? _) => 'fallback',
        name: 'fallback',
      );
      final FunctionNode always = node(
        (WorkflowContext _, Object? _) => 'always',
        name: 'always',
      );
      final Workflow workflow = Workflow(
        name: 'default_routed_graph',
        nodes: <BaseNode>[router, specific, fallback, always],
        edges: <Edge>[
          Edge(fromNode: router, toNode: specific, route: 'route_b'),
          Edge(fromNode: router, toNode: fallback, route: DEFAULT_ROUTE),
          Edge(fromNode: router, toNode: always),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs.containsKey('specific'), isFalse);
      expect(result.outputs.containsKey('router'), isTrue);
      expect(result.outputs['router'], isNull);
      expect(result.outputs['fallback'], 'fallback');
      expect(result.outputs['always'], 'always');
    });

    test('runs dynamic child nodes via WorkflowContext.runNode', () async {
      int attempts = 0;
      final Workflow workflow = Workflow(
        name: 'dynamic_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? input) async {
            final Object? childOutput = await context.runNode(
              node(
                (WorkflowContext _, Object? childInput) {
                  attempts += 1;
                  if (attempts < 2) {
                    throw const _RetryableWorkflowError('retry dynamic');
                  }
                  return '$childInput-child';
                },
                name: 'dynamic_child',
                retryConfig: const wf.RetryConfig(maxAttempts: 2),
              ),
              input: '$input-parent',
            );
            return 'parent:$childOutput';
          }, name: 'parent'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'start');

      expect(result.outputs['dynamic_child'], 'start-parent-child');
      expect(result.outputs['parent'], 'parent:start-parent-child');
      expect(result.nodeStates['dynamic_child']?.status, NodeStatus.completed);
      expect(result.nodeStates['dynamic_child']?.attemptCount, 2);
      expect(result.nodeStates['dynamic_child']?.input, 'start-parent');
    });

    test('runs dynamic nodes from standalone WorkflowContext', () async {
      final WorkflowContext context = WorkflowContext(input: 'standalone');

      final Object? output = await context.runNode(
        node(
          (WorkflowContext _, Object? input) => '$input-child',
          name: 'standalone_child',
        ),
        input: context.input,
      );

      expect(output, 'standalone-child');
      expect(context.outputs['standalone_child'], 'standalone-child');
      expect(
        context.nodeStates['standalone_child']?.status,
        NodeStatus.completed,
      );
    });

    test('marks dynamic request-input nodes as waiting', () async {
      final Workflow workflow = Workflow(
        name: 'dynamic_hitl_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) {
            return context.runNode(
              node(
                (WorkflowContext _, Object? _) =>
                    RequestInput(interruptId: 'dynamic_ask'),
                name: 'dynamic_ask_user',
              ),
            );
          }, name: 'parent'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();
      final NodeState childState = result.nodeStates['dynamic_ask_user']!;

      expect(childState.status, NodeStatus.waiting);
      expect(childState.interrupts, <String>['dynamic_ask']);
      expect(result.outputs['dynamic_ask_user'], isA<RequestInput>());
    });

    test('retries failed nodes', () async {
      int attempts = 0;
      final Workflow workflow = Workflow(
        name: 'retry',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? _) {
              attempts += 1;
              if (attempts < 2) {
                throw StateError('try again');
              }
              return 'ok';
            },
            name: 'flaky',
            retryConfig: const wf.RetryConfig(maxAttempts: 2),
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['flaky'], 'ok');
      expect(result.nodeStates['flaky']?.attemptCount, 2);
    });

    test(
      'uses Python-style default attempts when retry config is present',
      () async {
        int attempts = 0;
        final Workflow workflow = Workflow(
          name: 'retry_default_attempts',
          nodes: <BaseNode>[
            node(
              (WorkflowContext _, Object? _) {
                attempts += 1;
                if (attempts < 5) {
                  throw const _RetryableWorkflowError('try again');
                }
                return 'ok';
              },
              name: 'flaky',
              retryConfig: const wf.RetryConfig(),
            ),
          ],
        );

        final WorkflowResult result = await workflow.runWorkflow();

        expect(result.outputs['flaky'], 'ok');
        expect(result.nodeStates['flaky']?.attemptCount, 5);
      },
    );

    test('retries only matching exception names', () async {
      int attempts = 0;
      final Workflow workflow = Workflow(
        name: 'retry_filtered',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? _) {
              attempts += 1;
              if (attempts < 3) {
                throw const _RetryableWorkflowError('try again');
              }
              return 'ok';
            },
            name: 'flaky',
            retryConfig: const wf.RetryConfig(
              exceptions: <Object>['_RetryableWorkflowError'],
            ),
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['flaky'], 'ok');
      expect(result.nodeStates['flaky']?.attemptCount, 3);
    });

    test('does not retry non-matching exception names', () async {
      int attempts = 0;
      final Workflow workflow = Workflow(
        name: 'retry_filtered_miss',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? _) {
              attempts += 1;
              throw const _NonRetryableWorkflowError('stop');
            },
            name: 'flaky',
            retryConfig: const wf.RetryConfig(
              exceptions: <Object>['_RetryableWorkflowError'],
            ),
          ),
        ],
      );

      await expectLater(
        workflow.runWorkflow(),
        throwsA(isA<_NonRetryableWorkflowError>()),
      );
      expect(attempts, 1);
    });

    test('times out slow nodes', () async {
      final Workflow workflow = Workflow(
        name: 'timeout',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? _) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return 'late';
            },
            name: 'slow',
            timeout: const Duration(milliseconds: 1),
          ),
        ],
      );

      await expectLater(
        workflow.runWorkflow(),
        throwsA(isA<NodeTimeoutError>()),
      );
    });

    test('runs function tools as workflow nodes', () async {
      final FunctionTool firstTool = FunctionTool(
        name: 'first_tool',
        description: 'Returns structured tool output.',
        func: () => <String, Object?>{'value': 'hello'},
      );
      final FunctionTool secondTool = FunctionTool(
        name: 'second_tool',
        description: 'Uses predecessor output as tool args.',
        func: ({required String value}) => '$value world',
      );
      final Workflow workflow = Workflow(
        name: 'tool_nodes',
        nodes: <BaseNode>[
          ToolNode(tool: firstTool),
          ToolNode(tool: secondTool, dependsOn: const <String>['first_tool']),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['first_tool'], <String, Object?>{'value': 'hello'});
      expect(result.outputs['second_tool'], 'hello world');
      expect(result.nodeStates['second_tool']?.status, NodeStatus.completed);
    });

    test('rejects non-map input for tool nodes', () async {
      final FunctionTool tool = FunctionTool(
        name: 'needs_args',
        description: 'Requires map args.',
        func: ({required String value}) => value,
      );
      final Workflow workflow = Workflow(
        name: 'tool_node_input',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? input) => 'not a map',
            name: 'source',
          ),
          ToolNode(tool: tool, dependsOn: const <String>['source']),
        ],
      );

      await expectLater(workflow.runWorkflow(), throwsA(isA<ArgumentError>()));
    });

    test('runs agents as workflow nodes', () async {
      final Workflow workflow = Workflow(
        name: 'agent_node_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext _, Object? input) => '$input from source',
            name: 'source',
          ),
          AgentNode(
            agent: _EchoAgent(name: 'echo_agent'),
            dependsOn: const <String>['source'],
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'hello');

      expect(result.outputs['echo_agent'], 'agent:hello from source');
    });

    test('agent nodes merge state deltas into the workflow session', () async {
      final Session session = Session(id: 's', appName: 'app', userId: 'u');
      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv',
        agent: LlmAgent(name: 'root'),
        session: session,
      );

      final Object? output = await AgentNode(
        agent: _EchoAgent(name: 'echo_agent', stateKey: 'echo_output'),
      ).run(WorkflowContext(invocationContext: invocationContext), 'stateful');

      expect(output, 'agent:stateful');
      expect(session.state['echo_output'], 'agent:stateful');
    });

    test('buildNode wraps workflow-compatible values', () {
      final FunctionTool tool = FunctionTool(
        name: 'wrapped_tool',
        description: 'tool',
        func: () => 'ok',
      );
      final _EchoAgent agent = _EchoAgent(name: 'wrapped_agent');
      final FunctionNode existing = node(
        (WorkflowContext _, Object? input) => input,
        name: 'existing',
      );

      final BaseNode toolNode = buildNode(tool, name: 'tool_node');
      final BaseNode agentNode = buildNode(agent, name: 'agent_node');
      final BaseNode functionNode = buildNode(
        (WorkflowContext _, Object? input) => '$input-built',
        name: 'function_node',
        dependsOn: const <String>['source'],
        rerunOnResume: true,
        waitForOutput: true,
        retryConfig: const wf.RetryConfig(maxAttempts: 2),
        timeout: const Duration(seconds: 1),
      );

      expect(buildNode(existing), same(existing));
      expect(toolNode, isA<ToolNode>());
      expect(toolNode.name, 'tool_node');
      expect(agentNode, isA<AgentNode>());
      expect(agentNode.name, 'agent_node');
      expect(functionNode, isA<FunctionNode>());
      expect(functionNode.dependsOn, const <String>['source']);
      expect(functionNode.rerunOnResume, isTrue);
      expect(functionNode.waitForOutput, isTrue);
      expect(functionNode.retryConfig?.maxAttempts, 2);
      expect(functionNode.timeout, const Duration(seconds: 1));
      expect(
        () => buildNode(existing, name: 'override'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(() => buildNode(Object()), throwsArgumentError);
    });
  });
}
