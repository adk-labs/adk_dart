import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _MockToolset extends BaseToolset {
  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return <BaseTool>[];
  }
}

class _MockPlugin extends BasePlugin {
  _MockPlugin() : super(name: 'mock_plugin');
}

void main() {
  group('graph serialization parity', () {
    test('serializes workflow nodes and routed edges as json-safe maps', () {
      final FunctionNode nodeA = node(
        (WorkflowContext _, Object? input) => input,
        name: 'NodeA',
      );
      final FunctionNode nodeB = node(
        (WorkflowContext _, Object? input) => input,
        name: 'NodeB',
      );
      final JoinNode join = JoinNode(name: 'Join');
      final Workflow workflow = Workflow(
        name: 'test_workflow',
        nodes: <BaseNode>[nodeA, nodeB, join],
        edges: <Edge>[
          Edge(fromNode: START, toNode: nodeA),
          Edge(fromNode: nodeA, toNode: nodeB, route: 1),
          Edge(fromNode: nodeB, toNode: join),
        ],
      );

      final Map<String, Object?> result = serializeAgent(workflow);

      expect(result['name'], 'test_workflow');
      expect(result['type'], 'workflow');
      expect(result['nodes'], isA<List<Object?>>());
      expect(result['edges'], <Object?>[
        <String, Object?>{'from_node': START, 'to_node': 'NodeA'},
        <String, Object?>{'from_node': 'NodeA', 'to_node': 'NodeB', 'route': 1},
        <String, Object?>{'from_node': 'NodeB', 'to_node': 'Join'},
      ]);
      final Map<String, Object?> graph =
          result['graph']! as Map<String, Object?>;
      expect(graph['nodes'], result['nodes']);
      expect(graph['edges'], result['edges']);
      expect(jsonEncode(result), isA<String>());
    });

    test('serializes toolsets using their class name', () {
      final Agent agent = Agent(
        name: 'toolset_agent',
        tools: <Object>[_MockToolset()],
      );

      final Map<String, Object?> result = serializeAgent(agent);
      final List<Object?> tools = result['tools']! as List<Object?>;

      expect(tools.single, <String, Object?>{
        'name': '_MockToolset',
        'type': 'tool',
      });
    });

    test('serializes LiteLlm model as a json-safe model id', () {
      final Agent agent = Agent(
        name: 'lite_agent',
        model: LiteLlm(model: 'ollama_chat/llama3'),
      );

      final Map<String, Object?> result = serializeAgent(agent);

      expect(result['model'], 'ollama_chat/llama3');
      expect(jsonEncode(result), isA<String>());
    });

    test('serializes app info with plugins, cache config, and readme', () {
      final App app = App(
        name: 'graph_app',
        rootAgent: Agent(name: 'root_agent'),
        plugins: <BasePlugin>[_MockPlugin()],
        contextCacheConfig: <String, Object?>{'enabled': true},
      );

      final Map<String, Object?> result = serializeAppInfo(
        app,
        readme: '# Graph App',
      );

      expect(result['name'], 'graph_app');
      expect(result['root_agent'], isA<Map<String, Object?>>());
      expect(result['plugins'], <Object?>[
        <String, Object?>{'name': 'mock_plugin'},
      ]);
      expect(result['context_cache_config'], <String, Object?>{
        'enabled': true,
      });
      expect(result['readme'], '# Graph App');
      expect(jsonEncode(result), isA<String>());
    });
  });
}
