import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

/// Builds a tool context backed by a standalone in-memory invocation context.
Context _toolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_node_tool',
    agent: LlmAgent(name: 'root_agent'),
    session: Session(id: 's_node_tool', appName: 'app', userId: 'u1'),
  );
  return Context(invocationContext, functionCallId: 'fc_node_tool');
}

void main() {
  group('NodeTool parity', () {
    test('accepts a plain BaseNode', () {
      // In this port, agents (Workflow, LlmAgent) are BaseAgent, not BaseNode,
      // so they cannot be passed to NodeTool at compile time. An AgentNode,
      // however, is a legitimate BaseNode wrapper and is accepted. The BaseAgent
      // guard exists only as a runtime safety net for BaseNodes that also
      // implement BaseAgent.
      final AgentNode agentNode = AgentNode(agent: LlmAgent(name: 'inner'));
      expect(NodeTool(node: agentNode).node, same(agentNode));
    });

    test('wraps a function node and returns its output', () async {
      final FunctionNode greet = node(
        (WorkflowContext _, Object? input) => 'Hello, $input!',
        name: 'greet_node',
      );
      final NodeTool tool = NodeTool(node: greet, name: 'greet_tool');

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'world'},
        toolContext: _toolContext(),
      );

      expect(result, 'Hello, world!');
    });

    test('passes the full argument map when there is no request key', () async {
      final FunctionNode echo = node(
        (WorkflowContext _, Object? input) => input,
        name: 'echo_node',
      );
      final NodeTool tool = NodeTool(node: echo);

      final Object? result = await tool.run(
        args: <String, dynamic>{'a': 1, 'b': 2},
        toolContext: _toolContext(),
      );

      expect(result, <String, dynamic>{'a': 1, 'b': 2});
    });

    test('executes a multi-node workflow via a tool node', () async {
      // A NodeTool can wrap a ToolNode whose tool runs a sub-workflow-like
      // computation. Here the wrapped function node aggregates its input.
      final FunctionNode aggregate = node(
        (WorkflowContext _, Object? input) {
          final Map<String, Object?> map = input is Map
              ? <String, Object?>{
                  for (final MapEntry<Object?, Object?> e in input.entries)
                    '${e.key}': e.value,
                }
              : <String, Object?>{};
          return 'A is ${map['a']} and B is ${map['b']}.';
        },
        name: 'aggregate_node',
      );
      final NodeTool tool = NodeTool(node: aggregate, name: 'agg_tool');

      final Object? result = await tool.run(
        args: <String, dynamic>{'a': 1, 'b': 2},
        toolContext: _toolContext(),
      );

      expect(result, 'A is 1 and B is 2.');
    });

    test('exposes a function declaration with name and description', () {
      final FunctionNode greet = node(
        (WorkflowContext _, Object? input) => 'hi',
        name: 'greet_node',
        description: 'Greets the user.',
      );
      final NodeTool tool = NodeTool(node: greet, name: 'greet_tool');

      final FunctionDeclaration? decl = tool.getDeclaration();
      expect(decl, isNotNull);
      expect(decl!.name, 'greet_tool');
      expect(decl.description, 'Greets the user.');
      expect(decl.parameters['type'], 'object');
    });

    test('defaults name and description from the wrapped node', () {
      final FunctionNode greet = node(
        (WorkflowContext _, Object? input) => 'hi',
        name: 'greet_node',
      );
      final NodeTool tool = NodeTool(node: greet);

      expect(tool.name, 'greet_node');
      expect(tool.description, 'Executes the node: greet_node');
      expect(tool.isLongRunning, isTrue);
    });

    test('returns an error string when the node throws', () async {
      final FunctionNode boom = node(
        (WorkflowContext _, Object? _) => throw StateError('boom'),
        name: 'boom_node',
      );
      final NodeTool tool = NodeTool(node: boom);

      final Object? result = await tool.run(
        args: <String, dynamic>{'request': 'x'},
        toolContext: _toolContext(),
      );

      expect('$result', contains('Error running node boom_node'));
    });
  });
}
