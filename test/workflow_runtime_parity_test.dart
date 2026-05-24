import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/workflow/workflow.dart' as wf;
import 'package:test/test.dart';

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
      expect(result.nodeStates['join']?.status, NodeStatus.succeeded);
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
  });
}
