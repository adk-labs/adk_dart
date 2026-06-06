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

    test('limits graph-scheduled nodes with maxConcurrency', () async {
      final List<String> started = <String>[];
      final Map<String, Completer<void>> finishers = <String, Completer<void>>{
        for (int i = 0; i < 4; i += 1) 'node_$i': Completer<void>(),
      };
      FunctionNode worker(String name) {
        return node((WorkflowContext _, Object? input) async {
          started.add(name);
          await finishers[name]!.future;
          expect(input, isNull);
          return '$name done';
        }, name: name);
      }

      final Workflow workflow = Workflow(
        name: 'limited_concurrency',
        maxConcurrency: 2,
        nodes: <BaseNode>[for (int i = 0; i < 4; i += 1) worker('node_$i')],
      );

      final Future<WorkflowResult> resultFuture = workflow.runWorkflow();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(started, hasLength(2));
      finishers[started.first]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started, hasLength(3));

      for (final Completer<void> finisher in finishers.values) {
        if (!finisher.isCompleted) {
          finisher.complete();
        }
      }
      final WorkflowResult result = await resultFuture;

      for (int i = 0; i < 4; i += 1) {
        expect(result.outputs['node_$i'], 'node_$i done');
      }
    });

    test('parallel worker processes list input in original order', () async {
      final BaseNode producer = node(
        (WorkflowContext _, Object? _) => <Map<String, Object?>>[
          <String, Object?>{'value': 'first', 'delay': 10},
          <String, Object?>{'value': 'second', 'delay': 1},
        ],
        name: 'producer',
      );
      final ParallelWorker worker = ParallelWorker(
        node: node((WorkflowContext _, Object? input) async {
          final Map<dynamic, dynamic> item = input! as Map<dynamic, dynamic>;
          await Future<void>.delayed(
            Duration(milliseconds: item['delay'] as int),
          );
          return '${item['value']}_processed';
        }, name: 'worker'),
      );
      final Workflow workflow = Workflow(
        name: 'parallel_worker_ordered',
        nodes: <BaseNode>[producer, worker],
        edges: <Edge>[Edge(fromNode: producer, toNode: worker)],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['worker'], <String>[
        'first_processed',
        'second_processed',
      ]);
      expect(result.outputs['worker@1'], 'first_processed');
      expect(result.outputs['worker@2'], 'second_processed');
      expect(result.nodeStates['worker']?.status, NodeStatus.completed);
      expect(result.nodeStates['worker@1']?.status, NodeStatus.completed);
      expect(result.nodeStates['worker@2']?.status, NodeStatus.completed);
    });

    test('parallel worker returns empty list for empty input', () async {
      final ParallelWorker worker = parallelWorker(
        node((WorkflowContext _, Object? input) => '$input', name: 'worker'),
      );
      final Workflow workflow = Workflow(
        name: 'parallel_worker_empty',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? _) => <Object?>[], name: 'producer'),
          worker,
        ],
        edges: <Edge>[Edge(fromNode: 'producer', toNode: worker)],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['worker'], <Object?>[]);
      expect(result.outputs.containsKey('worker@1'), isFalse);
    });

    test('parallel worker wraps non-list input', () async {
      final Workflow workflow = Workflow(
        name: 'parallel_worker_single',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? _) => 'single', name: 'producer'),
          parallelWorker(
            node(
              (WorkflowContext _, Object? input) => '$input processed',
              name: 'worker',
            ),
          ),
        ],
        edges: <Edge>[Edge(fromNode: 'producer', toNode: 'worker')],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['worker'], <String>['single processed']);
      expect(result.outputs['worker@1'], 'single processed');
    });

    test('parallel worker honors maxConcurrency', () async {
      final List<int> started = <int>[];
      final Map<int, Completer<void>> finishers = <int, Completer<void>>{
        for (int i = 0; i < 4; i += 1) i: Completer<void>(),
      };
      final ParallelWorker worker = ParallelWorker(
        node: node((WorkflowContext _, Object? input) async {
          final int item = input! as int;
          started.add(item);
          await finishers[item]!.future;
          return 'done:$item';
        }, name: 'worker'),
        maxConcurrency: 2,
      );
      final Workflow workflow = Workflow(
        name: 'parallel_worker_limited',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? _) => <int>[0, 1, 2, 3], name: 'p'),
          worker,
        ],
        edges: <Edge>[Edge(fromNode: 'p', toNode: worker)],
      );

      final Future<WorkflowResult> resultFuture = workflow.runWorkflow();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(started, <int>[0, 1]);
      finishers[0]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started, <int>[0, 1, 2]);

      for (final Completer<void> finisher in finishers.values) {
        if (!finisher.isCompleted) {
          finisher.complete();
        }
      }
      final WorkflowResult result = await resultFuture;

      expect(result.outputs['worker'], <String>[
        'done:0',
        'done:1',
        'done:2',
        'done:3',
      ]);
    });

    test('parallel worker stops queued work after worker failure', () async {
      final List<int> started = <int>[];
      final ParallelWorker worker = ParallelWorker(
        node: node((WorkflowContext _, Object? input) async {
          final int item = input! as int;
          started.add(item);
          if (item == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('worker failed');
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return 'done:$item';
        }, name: 'worker'),
        maxConcurrency: 2,
      );
      final Workflow workflow = Workflow(
        name: 'parallel_worker_failure_stops_queue',
        nodes: <BaseNode>[
          node((WorkflowContext _, Object? _) => <int>[0, 1, 2], name: 'p'),
          worker,
        ],
        edges: <Edge>[Edge(fromNode: 'p', toNode: worker)],
      );

      await expectLater(
        workflow.runWorkflow(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'worker failed',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(started, <int>[0, 1]);
    });

    test('sibling nodes observe workflow cancellation after failure', () async {
      final List<bool> observedCancellation = <bool>[];
      late WorkflowContext slowContext;
      final Workflow workflow = Workflow(
        name: 'workflow_sibling_cancellation_signal',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) async {
            slowContext = context;
            await Future<void>.delayed(const Duration(milliseconds: 40));
            observedCancellation.add(context.isCancelled);
            context.throwIfCancelled();
            return 'slow';
          }, name: 'slow'),
          node((WorkflowContext _, Object? _) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('fail');
          }, name: 'fail'),
        ],
        edges: <Edge>[
          Edge(fromNode: START, toNode: 'slow'),
          Edge(fromNode: START, toNode: 'fail'),
        ],
      );

      await expectLater(
        workflow.runWorkflow(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'fail',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(observedCancellation, <bool>[true]);
      expect(slowContext.nodeStates['slow']?.status, NodeStatus.cancelled);
      expect(slowContext.outputs.containsKey('slow'), isFalse);
    });

    test('rejects task-mode LlmAgent as static workflow graph node', () {
      final LlmAgent taskAgent = LlmAgent(name: 'task_agent', mode: 'task');

      expect(
        () => Workflow(
          name: 'task_static_graph',
          nodes: <BaseNode>[AgentNode(agent: taskAgent)],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains("mode='task'"),
          ),
        ),
      );
    });

    test('rejects chat-mode LlmAgent following a non-START node', () {
      final FunctionNode predecessor = node(
        (WorkflowContext _, Object? input) => '$input prepared',
        name: 'predecessor',
      );
      final LlmAgent chatAgent = LlmAgent(name: 'chat_agent', mode: 'chat');

      expect(
        () => Workflow(
          name: 'chat_after_node',
          nodes: <BaseNode>[
            predecessor,
            AgentNode(agent: chatAgent),
          ],
          edges: <Edge>[Edge(fromNode: predecessor, toNode: chatAgent.name)],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            allOf(
              contains("mode='chat'"),
              contains("following node 'predecessor'"),
            ),
          ),
        ),
      );
    });

    test('allows chat-mode LlmAgent directly from START', () {
      final LlmAgent chatAgent = LlmAgent(name: 'chat_agent', mode: 'chat');

      final Workflow workflow = Workflow(
        name: 'chat_from_start',
        nodes: <BaseNode>[AgentNode(agent: chatAgent)],
        edges: <Edge>[Edge(fromNode: START, toNode: chatAgent.name)],
      );

      expect(workflow.nodes.single.name, 'chat_agent');
    });

    test('buildNode wraps agents with rerunOnResume enabled by default', () {
      final BaseNode wrapped = buildNode(_EchoAgent(name: 'echo'));

      expect(wrapped, isA<AgentNode>());
      expect(wrapped.rerunOnResume, isTrue);
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
        'workflow_agent@1',
      ]);
      expect(events.single.nodeInfo.messageAsOutput, isTrue);
      expect(events.single.content?.parts.single.text, 'hello');
    });

    test('stamps terminal node outputFor with workflow path', () async {
      final FunctionNode first = node(
        (WorkflowContext _, Object? input) => '$input:first',
        name: 'first',
      );
      final FunctionNode second = node(
        (WorkflowContext _, Object? input) => '$input:second',
        name: 'second',
      );
      final Workflow workflow = Workflow(
        name: 'terminal_output_for_workflow',
        nodes: <BaseNode>[first, second],
        edges: <Edge>[
          Edge(fromNode: START, toNode: first),
          Edge(fromNode: first, toNode: second),
        ],
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_terminal_output_for',
        agent: workflow,
        session: Session(id: 's', appName: 'app', userId: 'u'),
        userContent: Content.userText('go'),
      );

      final List<Event> events = await workflow.runAsync(context).toList();

      final Map<String, Event> byAuthor = <String, Event>{
        for (final Event event in events) event.author: event,
      };
      expect(byAuthor['first']?.nodeInfo.outputFor, <String>[
        'terminal_output_for_workflow@1/first@1',
      ]);
      expect(byAuthor['second']?.nodeInfo.outputFor, <String>[
        'terminal_output_for_workflow@1/second@1',
        'terminal_output_for_workflow@1',
      ]);
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

    test(
      'reruns request-input nodes with resume inputs when enabled',
      () async {
        final Workflow workflow = Workflow(
          name: 'hitl_resume',
          nodes: <BaseNode>[
            node(
              (WorkflowContext context, Object? _) {
                final Object? resumeInput = context.resumeInputs['ask_resume'];
                if (resumeInput != null) {
                  return resumeInput;
                }
                return RequestInput(
                  interruptId: 'ask_resume',
                  message: 'Need input',
                );
              },
              name: 'ask_user',
              rerunOnResume: true,
            ),
            node((WorkflowContext _, Object? input) {
              final Map<dynamic, dynamic> response =
                  input! as Map<dynamic, dynamic>;
              return 'received:${response['text']}';
            }, name: 'after_user'),
          ],
          edges: <Edge>[Edge(fromNode: 'ask_user', toNode: 'after_user')],
        );

        final WorkflowResult first = await workflow.runWorkflow();
        final NodeState firstAskState = first.nodeStates['ask_user']!;
        final String? firstRunId = firstAskState.runId;

        final WorkflowResult second = await workflow.runWorkflow(
          previousResult: first,
          resumeInputs: <String, Object?>{
            'ask_resume': <String, Object?>{'text': 'Hello from user'},
          },
        );

        expect(firstAskState.status, NodeStatus.waiting);
        expect(firstAskState.interrupts, <String>['ask_resume']);
        expect(second.outputs['after_user'], 'received:Hello from user');
        final NodeState secondAskState = second.nodeStates['ask_user']!;
        expect(secondAskState.status, NodeStatus.completed);
        expect(secondAskState.runId, firstRunId);
        expect(secondAskState.runCounter, firstAskState.runCounter);
        expect(secondAskState.interrupts, isEmpty);
        expect(secondAskState.resumeInputs, isEmpty);
      },
    );

    test(
      'accumulates partial resume inputs until all interrupts resolve',
      () async {
        int runs = 0;
        final Workflow workflow = Workflow(
          name: 'hitl_partial_resume',
          nodes: <BaseNode>[
            node(
              (WorkflowContext context, Object? _) {
                runs += 1;
                final Object? first = context.resumeInputs['req1'];
                final Object? second = context.resumeInputs['req2'];
                if (first != null && second != null) {
                  return '$first/$second';
                }
                context.interruptIds.addAll(<String>{'req1', 'req2'});
                return null;
              },
              name: 'ask_twice',
              rerunOnResume: true,
            ),
          ],
        );

        final WorkflowResult first = await workflow.runWorkflow();
        final WorkflowResult partial = await workflow.runWorkflow(
          previousResult: first,
          resumeInputs: <String, Object?>{'req1': 'one'},
        );

        expect(runs, 1);
        expect(partial.outputs.containsKey('ask_twice'), isFalse);
        final NodeState partialState = partial.nodeStates['ask_twice']!;
        expect(partialState.status, NodeStatus.waiting);
        expect(partialState.interrupts, <String>['req2']);
        expect(partialState.resumeInputs, <String, Object?>{'req1': 'one'});

        final WorkflowResult completed = await workflow.runWorkflow(
          previousResult: partial,
          resumeInputs: <String, Object?>{'req2': 'two'},
        );

        expect(runs, 2);
        expect(completed.outputs['ask_twice'], 'one/two');
        expect(completed.nodeStates['ask_twice']?.status, NodeStatus.completed);
        expect(completed.nodeStates['ask_twice']?.interrupts, isEmpty);
        expect(completed.nodeStates['ask_twice']?.resumeInputs, isEmpty);
      },
    );

    test(
      'uses resume response output without rerunning completed predecessors',
      () async {
        int setupRuns = 0;
        int askRuns = 0;
        int afterRuns = 0;
        final Workflow workflow = Workflow(
          name: 'hitl_no_rerun',
          nodes: <BaseNode>[
            node((WorkflowContext _, Object? _) {
              setupRuns += 1;
              return 'ready';
            }, name: 'setup'),
            node((WorkflowContext _, Object? input) {
              askRuns += 1;
              return RequestInput(
                interruptId: 'approval',
                message: 'Approve $input?',
              );
            }, name: 'ask_user'),
            node((WorkflowContext _, Object? input) {
              afterRuns += 1;
              final Map<dynamic, dynamic> response =
                  input! as Map<dynamic, dynamic>;
              return 'approved:${response['approved']}';
            }, name: 'after_user'),
          ],
          edges: <Edge>[
            Edge(fromNode: 'setup', toNode: 'ask_user'),
            Edge(fromNode: 'ask_user', toNode: 'after_user'),
          ],
        );

        final WorkflowResult first = await workflow.runWorkflow();

        expect(first.nodeStates['ask_user']?.status, NodeStatus.waiting);
        expect(first.outputs.containsKey('after_user'), isFalse);
        expect(setupRuns, 1);
        expect(askRuns, 1);
        expect(afterRuns, 0);

        final WorkflowResult second = await workflow.runWorkflow(
          previousResult: first,
          resumeInputs: <String, Object?>{
            'approval': <String, Object?>{'approved': true},
          },
        );

        expect(setupRuns, 1);
        expect(askRuns, 1);
        expect(afterRuns, 1);
        expect(second.outputs['ask_user'], <String, Object?>{'approved': true});
        expect(second.outputs['after_user'], 'approved:true');
        expect(second.nodeStates['ask_user']?.status, NodeStatus.completed);
        expect(second.nodeStates['ask_user']?.interrupts, isEmpty);
      },
    );

    test(
      'preserves interrupted node route when completing from resume',
      () async {
        int routeRuns = 0;
        final Workflow workflow = Workflow(
          name: 'hitl_route_resume',
          nodes: <BaseNode>[
            node((WorkflowContext context, Object? _) {
              routeRuns += 1;
              context.route = 'go';
              return RequestInput(
                interruptId: 'route_confirm',
                message: 'Continue?',
              );
            }, name: 'route_node'),
            node((WorkflowContext _, Object? input) {
              final Map<dynamic, dynamic> response =
                  input! as Map<dynamic, dynamic>;
              return 'reached:${response['ok']}';
            }, name: 'target_node'),
          ],
          edges: <Edge>[
            Edge(fromNode: 'route_node', toNode: 'target_node', route: 'go'),
          ],
        );

        final WorkflowResult first = await workflow.runWorkflow();
        expect(first.nodeStates['route_node']?.status, NodeStatus.waiting);
        expect(first.nodeStates['route_node']?.route, 'go');
        expect(first.outputs.containsKey('target_node'), isFalse);

        final WorkflowResult second = await workflow.runWorkflow(
          previousResult: first,
          resumeInputs: <String, Object?>{
            'route_confirm': <String, Object?>{'ok': true},
          },
        );

        expect(routeRuns, 1);
        expect(second.outputs['target_node'], 'reached:true');
        expect(second.nodeStates['route_node']?.status, NodeStatus.completed);
        expect(second.nodeStates['route_node']?.route, 'go');
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

    test('rejects duplicate workflow edges regardless of route', () {
      final FunctionNode target = node(
        (WorkflowContext _, Object? _) => 'target',
        name: 'target',
      );

      expect(
        () => Workflow(
          name: 'duplicate_edges',
          nodes: <BaseNode>[target],
          edges: <Edge>[
            Edge(fromNode: START, toNode: target),
            Edge(fromNode: START, toNode: target, route: 'fallback'),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            allOf(
              contains('Duplicate edge found'),
              contains('from=START, to=target'),
            ),
          ),
        ),
      );
    });

    test('rejects multiple DEFAULT_ROUTE edges from one source', () {
      final FunctionNode router = node(
        (WorkflowContext _, Object? _) => null,
        name: 'router',
      );
      final FunctionNode firstFallback = node(
        (WorkflowContext _, Object? _) => 'first',
        name: 'first_fallback',
      );
      final FunctionNode secondFallback = node(
        (WorkflowContext _, Object? _) => 'second',
        name: 'second_fallback',
      );

      expect(
        () => Workflow(
          name: 'multiple_default_routes',
          nodes: <BaseNode>[router, firstFallback, secondFallback],
          edges: <Edge>[
            Edge(fromNode: START, toNode: router),
            Edge(fromNode: router, toNode: firstFallback, route: DEFAULT_ROUTE),
            Edge(
              fromNode: router,
              toNode: secondFallback,
              route: DEFAULT_ROUTE,
            ),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            allOf(
              contains('Multiple DEFAULT_ROUTE edges'),
              contains('node router to first_fallback and second_fallback'),
            ),
          ),
        ),
      );
    });

    test('uses direct ctx.output as node output', () async {
      final Workflow workflow = Workflow(
        name: 'direct_output_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? input) {
            context.output = '$input-direct';
            return null;
          }, name: 'writer'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'start');

      expect(result.outputs['writer'], 'start-direct');
      expect(result.nodeStates['writer']?.status, NodeStatus.completed);
    });

    test('routes direct ctx.route values', () async {
      final Workflow workflow = Workflow(
        name: 'direct_route_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) {
            context.route = 'approved';
            return null;
          }, name: 'router'),
          node(
            (WorkflowContext _, Object? input) => 'next:$input',
            name: 'approved_node',
          ),
          node(
            (WorkflowContext _, Object? _) => 'blocked',
            name: 'blocked_node',
          ),
        ],
        edges: <Edge>[
          Edge(fromNode: 'router', toNode: 'approved_node', route: 'approved'),
          Edge(fromNode: 'router', toNode: 'blocked_node', route: 'blocked'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['router'], isNull);
      expect(result.outputs['approved_node'], 'next:null');
      expect(result.outputs.containsKey('blocked_node'), isFalse);
    });

    test('combines direct ctx.output with returned route event', () async {
      final Workflow workflow = Workflow(
        name: 'direct_output_route_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) {
            context.output = 'payload';
            return Event(
              invocationId: 'invocation',
              author: 'router',
              actions: EventActions(route: 'approved'),
            );
          }, name: 'router'),
          node(
            (WorkflowContext _, Object? input) => 'next:$input',
            name: 'approved_node',
          ),
          node(
            (WorkflowContext _, Object? _) => 'blocked',
            name: 'blocked_node',
          ),
        ],
        edges: <Edge>[
          Edge(fromNode: 'router', toNode: 'approved_node', route: 'approved'),
          Edge(fromNode: 'router', toNode: 'blocked_node', route: 'blocked'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['router'], 'payload');
      expect(result.outputs['approved_node'], 'next:payload');
      expect(result.outputs.containsKey('blocked_node'), isFalse);
    });

    test('treats direct ctx.output null as no output', () async {
      final Workflow workflow = Workflow(
        name: 'direct_null_output_graph',
        nodes: <BaseNode>[
          FunctionNode(
            name: 'needs_output',
            waitForOutput: true,
            function: (WorkflowContext context, Object? _) {
              context.output = null;
              return null;
            },
          ),
          node(
            (WorkflowContext _, Object? _) => 'should not run',
            name: 'after_needs_output',
          ),
        ],
        edges: <Edge>[
          Edge(fromNode: 'needs_output', toNode: 'after_needs_output'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.nodeStates['needs_output']?.status, NodeStatus.waiting);
      expect(result.outputs.containsKey('needs_output'), isFalse);
      expect(result.outputs.containsKey('after_needs_output'), isFalse);
    });

    test('keeps direct interrupt nodes waiting', () async {
      final Workflow workflow = Workflow(
        name: 'direct_interrupt_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) {
            context.interruptIds.add('manual_interrupt');
            return null;
          }, name: 'manual_hitl'),
          node(
            (WorkflowContext _, Object? _) => 'should not run',
            name: 'after_manual_hitl',
          ),
        ],
        edges: <Edge>[
          Edge(fromNode: 'manual_hitl', toNode: 'after_manual_hitl'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();
      final NodeState state = result.nodeStates['manual_hitl']!;

      expect(state.status, NodeStatus.waiting);
      expect(state.interrupts, <String>['manual_interrupt']);
      expect(result.outputs.containsKey('after_manual_hitl'), isFalse);
    });

    test('isolates direct ctx.output for parallel nodes', () async {
      final Workflow workflow = Workflow(
        name: 'parallel_direct_output_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) {
            context.output = 'a';
            return null;
          }, name: 'a'),
          node((WorkflowContext context, Object? _) {
            context.output = 'b';
            return null;
          }, name: 'b'),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(result.outputs['a'], 'a');
      expect(result.outputs['b'], 'b');
    });

    test('runs dynamic child nodes via WorkflowContext.runNode', () async {
      int attempts = 0;
      final Workflow workflow = Workflow(
        name: 'dynamic_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? input) async {
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
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'start');

      expect(result.outputs['dynamic_child@1'], 'start-parent-child');
      expect(result.outputs['parent'], 'parent:start-parent-child');
      expect(
        result.nodeStates['dynamic_child@1']?.status,
        NodeStatus.completed,
      );
      expect(result.nodeStates['dynamic_child@1']?.attemptCount, 2);
      expect(result.nodeStates['dynamic_child@1']?.input, 'start-parent');
      expect(result.nodeStates['dynamic_child@1']?.runId, '1');
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
      expect(context.outputs['standalone_child@1'], 'standalone-child');
      expect(
        context.nodeStates['standalone_child@1']?.status,
        NodeStatus.completed,
      );
    });

    test('requires rerunOnResume parent for dynamic workflow nodes', () async {
      final Workflow workflow = Workflow(
        name: 'dynamic_parent_guard_graph',
        nodes: <BaseNode>[
          node((WorkflowContext context, Object? _) {
            return context.runNode(
              node(
                (WorkflowContext _, Object? _) => 'child',
                name: 'guard_child',
              ),
            );
          }, name: 'parent'),
        ],
      );

      await expectLater(
        workflow.runWorkflow(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('rerunOnResume: true'),
          ),
        ),
      );
    });

    test('assigns automatic dynamic runIds per node name', () async {
      int childRuns = 0;
      final FunctionNode child = node((WorkflowContext _, Object? input) {
        childRuns += 1;
        return 'auto:$input';
      }, name: 'auto_child');
      final Workflow workflow = Workflow(
        name: 'dynamic_auto_run_id_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) async {
              final List<Object?> outputs = await Future.wait(<Future<Object?>>[
                context.runNode(child, input: 'a'),
                context.runNode(child, input: 'b'),
                context.runNode(child, input: 'c'),
              ]);
              return outputs.join(',');
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(childRuns, 3);
      expect(result.outputs['auto_child@1'], 'auto:a');
      expect(result.outputs['auto_child@2'], 'auto:b');
      expect(result.outputs['auto_child@3'], 'auto:c');
      expect(result.outputs['parent'], 'auto:a,auto:b,auto:c');
      expect(result.nodeStates['auto_child@1']?.runId, '1');
      expect(result.nodeStates['auto_child@2']?.runId, '2');
      expect(result.nodeStates['auto_child@3']?.runId, '3');
    });

    test('separates dynamic node instances by explicit runId', () async {
      int childRuns = 0;
      final FunctionNode child = node((WorkflowContext _, Object? input) {
        childRuns += 1;
        return 'child:$input';
      }, name: 'dynamic_child');
      final Workflow workflow = Workflow(
        name: 'dynamic_run_id_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) async {
              final Object? first = await context.runNode(
                child,
                input: 'first',
                runId: 'first-id',
              );
              final Object? second = await context.runNode(
                child,
                input: 'second',
                runId: 'second-id',
              );
              return '$first/$second';
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();

      expect(childRuns, 2);
      expect(result.outputs['dynamic_child@first-id'], 'child:first');
      expect(result.outputs['dynamic_child@second-id'], 'child:second');
      expect(result.outputs['parent'], 'child:first/child:second');
      expect(result.nodeStates['dynamic_child@first-id']?.runId, 'first-id');
      expect(result.nodeStates['dynamic_child@second-id']?.runId, 'second-id');
    });

    test('rejects numeric explicit dynamic runIds', () async {
      final WorkflowContext context = WorkflowContext();

      await expectLater(
        context.runNode(
          node((WorkflowContext _, Object? input) => input, name: 'child'),
          runId: '123',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('marks dynamic request-input nodes as waiting', () async {
      final Workflow workflow = Workflow(
        name: 'dynamic_hitl_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) {
              return context.runNode(
                node(
                  (WorkflowContext _, Object? _) =>
                      RequestInput(interruptId: 'dynamic_ask'),
                  name: 'dynamic_ask_user',
                ),
              );
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );

      final WorkflowResult result = await workflow.runWorkflow();
      final NodeState childState = result.nodeStates['dynamic_ask_user@1']!;

      expect(childState.status, NodeStatus.waiting);
      expect(childState.interrupts, <String>['dynamic_ask']);
      expect(result.outputs['dynamic_ask_user@1'], isA<RequestInput>());
    });

    test(
      'deduplicates explicit dynamic runIds independently on resume',
      () async {
        final Map<String, int> childRuns = <String, int>{
          'cached': 0,
          'waiting': 0,
        };
        final FunctionNode child = node(
          (WorkflowContext context, Object? input) {
            final String label = input! as String;
            childRuns[label] = childRuns[label]! + 1;
            if (label == 'waiting') {
              final Object? resumeInput = context.resumeInputs['explicit_wait'];
              if (resumeInput != null) {
                final Map<dynamic, dynamic> response =
                    resumeInput as Map<dynamic, dynamic>;
                return 'resumed:${response['value']}';
              }
              return RequestInput(
                interruptId: 'explicit_wait',
                message: 'Continue?',
              );
            }
            return 'cached-result';
          },
          name: 'explicit_child',
          rerunOnResume: true,
        );
        final Workflow workflow = Workflow(
          name: 'dynamic_explicit_resume_graph',
          nodes: <BaseNode>[
            node(
              (WorkflowContext context, Object? _) async {
                final Object? cached = await context.runNode(
                  child,
                  input: 'cached',
                  runId: 'cached-id',
                );
                final Object? waiting = await context.runNode(
                  child,
                  input: 'waiting',
                  runId: 'waiting-id',
                );
                if (waiting is RequestInput) {
                  return waiting;
                }
                return '$cached + $waiting';
              },
              name: 'parent',
              rerunOnResume: true,
            ),
          ],
        );

        final WorkflowResult first = await workflow.runWorkflow();
        expect(
          first.nodeStates['explicit_child@cached-id']?.status,
          NodeStatus.completed,
        );
        expect(
          first.nodeStates['explicit_child@waiting-id']?.status,
          NodeStatus.waiting,
        );

        final WorkflowResult second = await workflow.runWorkflow(
          previousResult: first,
          resumeInputs: <String, Object?>{
            'explicit_wait': <String, Object?>{'value': 'done'},
          },
        );

        expect(childRuns['cached'], 1);
        expect(childRuns['waiting'], 2);
        expect(second.outputs['parent'], 'cached-result + resumed:done');
        expect(second.outputs['explicit_child@cached-id'], 'cached-result');
        expect(second.outputs['explicit_child@waiting-id'], 'resumed:done');
      },
    );

    test('deduplicates completed dynamic nodes when parent resumes', () async {
      int parentRuns = 0;
      int completerRuns = 0;
      int interrupterRuns = 0;
      final FunctionNode completer = node((WorkflowContext _, Object? _) {
        completerRuns += 1;
        return 'completed_result';
      }, name: 'dynamic_completer');
      final FunctionNode interrupter = node(
        (WorkflowContext context, Object? _) {
          interrupterRuns += 1;
          final Object? resumeInput = context.resumeInputs['dyn_fc'];
          if (resumeInput != null) {
            final Map<dynamic, dynamic> response =
                resumeInput as Map<dynamic, dynamic>;
            return 'resumed:${response['value']}';
          }
          return RequestInput(interruptId: 'dyn_fc', message: 'Approve?');
        },
        name: 'dynamic_interrupter',
        rerunOnResume: true,
      );
      final Workflow workflow = Workflow(
        name: 'dynamic_resume_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) async {
              parentRuns += 1;
              final Object? completed = await context.runNode(completer);
              final Object? interrupted = await context.runNode(interrupter);
              if (interrupted is RequestInput) {
                return interrupted;
              }
              return '$completed + $interrupted';
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );

      final WorkflowResult first = await workflow.runWorkflow();
      expect(first.nodeStates['parent']?.status, NodeStatus.waiting);
      expect(
        first.nodeStates['dynamic_completer@1']?.status,
        NodeStatus.completed,
      );
      expect(
        first.nodeStates['dynamic_interrupter@1']?.status,
        NodeStatus.waiting,
      );

      final WorkflowResult second = await workflow.runWorkflow(
        previousResult: first,
        resumeInputs: <String, Object?>{
          'dyn_fc': <String, Object?>{'value': 'done'},
        },
      );

      expect(parentRuns, 2);
      expect(completerRuns, 1);
      expect(interrupterRuns, 2);
      expect(second.outputs['parent'], 'completed_result + resumed:done');
      expect(
        second.nodeStates['dynamic_interrupter@1']?.status,
        NodeStatus.completed,
      );
    });

    test(
      'uses dynamic resume response output when child does not rerun',
      () async {
        int parentRuns = 0;
        int childRuns = 0;
        final FunctionNode child = node((WorkflowContext _, Object? _) {
          childRuns += 1;
          return RequestInput(interruptId: 'dyn_default', message: 'Continue?');
        }, name: 'dynamic_default_child');
        final Workflow workflow = Workflow(
          name: 'dynamic_no_rerun_graph',
          nodes: <BaseNode>[
            node(
              (WorkflowContext context, Object? _) async {
                parentRuns += 1;
                final Object? childOutput = await context.runNode(child);
                if (childOutput is RequestInput) {
                  return childOutput;
                }
                final Map<dynamic, dynamic> response =
                    childOutput! as Map<dynamic, dynamic>;
                return 'continued:${response['ok']}';
              },
              name: 'parent',
              rerunOnResume: true,
            ),
          ],
        );

        final WorkflowResult first = await workflow.runWorkflow();
        expect(
          first.nodeStates['dynamic_default_child@1']?.status,
          NodeStatus.waiting,
        );

        final WorkflowResult second = await workflow.runWorkflow(
          previousResult: first,
          resumeInputs: <String, Object?>{
            'dyn_default': <String, Object?>{'ok': true},
          },
        );

        expect(parentRuns, 2);
        expect(childRuns, 1);
        expect(second.outputs['dynamic_default_child@1'], <String, Object?>{
          'ok': true,
        });
        expect(second.outputs['parent'], 'continued:true');
        expect(
          second.nodeStates['dynamic_default_child@1']?.status,
          NodeStatus.completed,
        );
      },
    );

    test('suppresses parent output for dynamic useAsOutput children', () async {
      int childRuns = 0;
      final FunctionNode child = node(
        (WorkflowContext context, Object? _) {
          childRuns += 1;
          final Object? resumeInput = context.resumeInputs['delegated_fc'];
          if (resumeInput != null) {
            return 'child:${resumeInput as String}';
          }
          return RequestInput(interruptId: 'delegated_fc', message: 'Approve?');
        },
        name: 'delegated_child',
        rerunOnResume: true,
      );
      final Workflow workflow = Workflow(
        name: 'dynamic_use_as_output_graph',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) async {
              final Object? result = await context.runNode(
                child,
                useAsOutput: true,
              );
              if (result is RequestInput) {
                return result;
              }
              context.output = result;
              return null;
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );

      final WorkflowResult first = await workflow.runWorkflow();
      expect(first.nodeStates['parent']?.status, NodeStatus.waiting);
      expect(first.nodeStates['delegated_child@1']?.status, NodeStatus.waiting);

      final WorkflowResult second = await workflow.runWorkflow(
        previousResult: first,
        resumeInputs: <String, Object?>{'delegated_fc': 'approved'},
      );

      expect(childRuns, 2);
      expect(second.outputs['delegated_child@1'], 'child:approved');
      expect(second.outputs['parent'], isNull);
      expect(second.nodeStates['parent']?.status, NodeStatus.completed);
    });

    test('stamps delegated dynamic outputFor ancestors on events', () async {
      final FunctionNode child = node(
        (WorkflowContext _, Object? _) => 'delegated child output',
        name: 'delegated_event_child',
      );
      final Workflow workflow = Workflow(
        name: 'delegated_event_workflow',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) async {
              final Object? output = await context.runNode(
                child,
                useAsOutput: true,
              );
              context.output = output;
              return null;
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_delegated_output_for',
        agent: workflow,
        session: Session(id: 's', appName: 'app', userId: 'u'),
      );

      final List<Event> events = await workflow.runAsync(context).toList();

      expect(events, hasLength(1));
      expect(
        events.single.nodeInfo.path,
        'delegated_event_workflow@1/delegated_event_child@1',
      );
      expect(events.single.nodeInfo.outputFor, <String>[
        'delegated_event_workflow@1/delegated_event_child@1',
        'delegated_event_workflow@1/parent@1',
        'delegated_event_workflow@1',
      ]);
      expect(
        events.single.content?.parts.single.text,
        'delegated child output',
      );
    });

    test('uses overrideBranch for dynamic node output events', () async {
      final FunctionNode child = node(
        (WorkflowContext _, Object? _) => 'branch child output',
        name: 'override_branch_child',
      );
      final Workflow workflow = Workflow(
        name: 'override_branch_workflow',
        nodes: <BaseNode>[
          node(
            (WorkflowContext context, Object? _) async {
              await context.runNode(child, overrideBranch: 'custom_branch');
              return null;
            },
            name: 'parent',
            rerunOnResume: true,
          ),
        ],
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_dynamic_override_branch',
        agent: workflow,
        session: Session(id: 's', appName: 'app', userId: 'u'),
        branch: 'parent_branch',
      );

      final List<Event> events = await workflow.runAsync(context).toList();

      expect(events, hasLength(1));
      expect(events.single.branch, 'custom_branch');
      expect(events.single.content?.parts.single.text, 'branch child output');
    });

    test(
      'appends useSubBranch segment for dynamic node output events',
      () async {
        final FunctionNode child = node(
          (WorkflowContext _, Object? _) => 'sub branch child output',
          name: 'sub_branch_child',
        );
        final Workflow workflow = Workflow(
          name: 'sub_branch_workflow',
          nodes: <BaseNode>[
            node(
              (WorkflowContext context, Object? _) async {
                await context.runNode(child, useSubBranch: true);
                return null;
              },
              name: 'parent',
              rerunOnResume: true,
            ),
          ],
        );
        final InvocationContext context = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv_dynamic_sub_branch',
          agent: workflow,
          session: Session(id: 's', appName: 'app', userId: 'u'),
          branch: 'parent_branch',
        );

        final List<Event> events = await workflow.runAsync(context).toList();

        expect(events, hasLength(1));
        expect(events.single.branch, 'parent_branch.sub_branch_child@1');
        expect(
          events.single.content?.parts.single.text,
          'sub branch child output',
        );
      },
    );

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
