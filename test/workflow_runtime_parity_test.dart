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
      expect(result.nodeStates['second_tool']?.status, NodeStatus.succeeded);
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
  });
}
