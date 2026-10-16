import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:adk_dart/adk_dart.dart';

void main() {
  group('EdgesBuilder Unit Tests', () {
    test('linear chain fromStart', () {
      final nodeA = node((ctx, input) => 'A', name: 'nodeA');
      final nodeB = node((ctx, input) => 'B', name: 'nodeB');

      final edges = EdgesBuilder.buildEdges((g) {
        g.fromStart().then(nodeA).then(nodeB);
      });

      expect(edges.length, equals(2));
      expect(edges[0].fromNode, equals(START));
      expect(edges[0].toNode, equals('nodeA'));
      expect(edges[1].fromNode, equals('nodeA'));
      expect(edges[1].toNode, equals('nodeB'));
    });

    test('chain with multiple nodes', () {
      final nodeA = node((ctx, input) => 'A', name: 'nodeA');
      final nodeB = node((ctx, input) => 'B', name: 'nodeB');
      final nodeC = node((ctx, input) => 'C', name: 'nodeC');

      final edges = EdgesBuilder.buildEdges((g) {
        g.fromStart().chain([nodeA, nodeB, nodeC]);
      });

      expect(edges.length, equals(3));
      expect(edges[0].fromNode, equals(START));
      expect(edges[0].toNode, equals('nodeA'));
      expect(edges[1].fromNode, equals('nodeA'));
      expect(edges[1].toNode, equals('nodeB'));
      expect(edges[2].fromNode, equals('nodeB'));
      expect(edges[2].toNode, equals('nodeC'));
    });

    test('fan-out and joinTo', () {
      final startNode = node((ctx, input) => 'start', name: 'starter');
      final worker1 = node((ctx, input) => 'w1', name: 'worker1');
      final worker2 = node((ctx, input) => 'w2', name: 'worker2');
      final join = JoinNode(name: 'joiner');

      final edges = EdgesBuilder.buildEdges((g) {
        g.from(startNode).thenGroup([worker1, worker2]).joinTo(join);
      });

      expect(edges.length, equals(4));
      // fan-out: starter -> worker1, starter -> worker2
      expect(edges[0].fromNode, equals('starter'));
      expect(edges[0].toNode, equals('worker1'));
      expect(edges[1].fromNode, equals('starter'));
      expect(edges[1].toNode, equals('worker2'));
      // join: worker1 -> joiner, worker2 -> joiner
      expect(edges[2].fromNode, equals('worker1'));
      expect(edges[2].toNode, equals('joiner'));
      expect(edges[3].fromNode, equals('worker2'));
      expect(edges[3].toNode, equals('joiner'));
    });

    test('fromGroup and fromNodes joinTo', () {
      final worker1 = node((ctx, input) => 'w1', name: 'worker1');
      final worker2 = node((ctx, input) => 'w2', name: 'worker2');
      final join = JoinNode(name: 'joiner');

      final edges = EdgesBuilder.buildEdges((g) {
        g.fromNodes(worker1, worker2).joinTo(join);
      });

      expect(edges.length, equals(2));
      expect(edges[0].fromNode, equals('worker1'));
      expect(edges[0].toNode, equals('joiner'));
      expect(edges[1].fromNode, equals('worker2'));
      expect(edges[1].toNode, equals('joiner'));
    });

    test('routing map with on, onAny, and otherwise', () {
      final classifier = node((ctx, input) => 'billing', name: 'classifier');
      final billing = node((ctx, input) => 'Billing handled', name: 'billing');
      final support = node((ctx, input) => 'Support handled', name: 'support');
      final fallback = node((ctx, input) => 'Fallback', name: 'fallback');

      final edges = EdgesBuilder.buildEdges((g) {
        g.from(classifier).route((r) {
          r.on('billing').then(billing);
          r.onAny(['tech', 'general']).then(support);
          r.otherwise(fallback);
        });
      });

      expect(edges.length, equals(3));
      expect(edges[0].fromNode, equals('classifier'));
      expect(edges[0].toNode, equals('billing'));
      expect(edges[0].route, equals('billing'));

      expect(edges[1].fromNode, equals('classifier'));
      expect(edges[1].toNode, equals('support'));
      expect(edges[1].route, equals(['tech', 'general']));

      expect(edges[2].fromNode, equals('classifier'));
      expect(edges[2].toNode, equals('fallback'));
      expect(edges[2].route, equals(DEFAULT_ROUTE));
    });

    test('route map validation errors', () {
      final n = node((ctx, input) => 'N', name: 'n');

      expect(
        () => EdgesBuilder.buildEdges((g) {
          g.from(n).route((r) {
            // empty route map
          });
        }),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => EdgesBuilder.buildEdges((g) {
          g.from(n).route((r) {
            r.on('uncompleted'); // not completed with then()
          });
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('Workflow.build end-to-end execution', () async {
      final step1 = node((ctx, input) => '${input}_step1', name: 'step1');
      final step2 = node((ctx, input) => '${input}_step2', name: 'step2');

      final workflow = Workflow.build(
        name: 'test_workflow',
        nodes: [step1, step2],
        buildEdges: (g) {
          g.fromStart().then(step1).then(step2);
        },
      );

      final result = await workflow.runWorkflow(input: 'start');
      expect(result.outputs['step1'], equals('start_step1'));
      expect(result.outputs['step2'], equals('start_step1_step2'));
    });
  });

  group('AgentEngineClient Unit Tests', () {
    test('createSession and query success', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith(':queryReasoningEngine')) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (body['class_method'] == 'create_session') {
            return http.Response(
              jsonEncode({
                'output': {'session_id': 'sess-12345'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (body['class_method'] == 'query') {
            return http.Response(
              jsonEncode({
                'output': {'text': 'Hello from reasoning engine!'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final client = AgentEngineClient(
        config: const AgentEngineConfig(
          project: 'test-project',
          location: 'us-central1',
          reasoningEngineId: 'engine-1',
        ),
        httpClient: mockClient,
      );

      final sessionOutput = await client.createSession(
        const SessionConfig(userId: 'user1'),
      );
      expect(sessionOutput, equals({'session_id': 'sess-12345'}));

      final queryOutput = await client.query(
        const QueryConfig(message: 'Hi'),
      );
      expect(queryOutput, equals({'text': 'Hello from reasoning engine!'}));
    });

    test('streamQuery parses SSE chunks and [DONE]', () async {
      final sseBody =
          'data: {"chunk": 1}\n\n'
          'data: {"chunk": 2}\n\n'
          'data: [DONE]\n\n';

      final mockClient = MockClient((request) async {
        return http.Response(
          sseBody,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final client = AgentEngineClient(
        config: const AgentEngineConfig(
          project: 'test-project',
          location: 'us-central1',
          reasoningEngineId: 'engine-1',
        ),
        httpClient: mockClient,
      );

      final fragments = await client
          .streamQuery(const QueryConfig(message: 'Stream test'))
          .toList();

      expect(fragments.length, equals(2));
      expect(fragments[0], equals({'chunk': 1}));
      expect(fragments[1], equals({'chunk': 2}));
    });
  });
}
