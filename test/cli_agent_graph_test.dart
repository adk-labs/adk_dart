import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('agent graph', () {
    test('renders mermaid graph including tools and sub agents', () async {
      final FunctionTool getTime = FunctionTool(
        name: 'get_current_time',
        description: 'Returns time.',
        func: ({required String city}) {
          return <String, Object>{'city': city, 'time': '10:30 AM'};
        },
      );
      final Agent child = Agent(name: 'child_agent', model: 'gemini-2.5-flash');
      final Agent root = Agent(
        name: 'root_agent',
        model: 'gemini-2.5-flash',
        subAgents: <BaseAgent>[child],
        tools: <Object>[getTime],
      );

      final String mermaid = await getAgentGraph(root);
      expect(mermaid, contains('flowchart LR'));
      expect(mermaid, contains('root_agent'));
      expect(mermaid, contains('child_agent'));
      expect(mermaid, contains('get_current_time'));
    });

    test(
      'renders workflow graph nodes, routed edges, and dependencies',
      () async {
        final FunctionNode classify = node((
          WorkflowContext context,
          Object? input,
        ) {
          context.route = 'approved';
          return 'classified';
        }, name: 'classify');
        final FunctionNode approved = node(
          (WorkflowContext context, Object? input) => 'approved',
          name: 'approved',
        );
        final FunctionNode rejected = node(
          (WorkflowContext context, Object? input) => 'rejected',
          name: 'rejected',
        );
        final FunctionNode summarize = node(
          (WorkflowContext context, Object? input) => 'summary',
          name: 'summarize',
          dependsOn: <String>['approved'],
        );
        final Workflow workflow = Workflow(
          name: 'workflow_root',
          nodes: <BaseNode>[classify, approved, rejected, summarize],
          edges: <Edge>[
            Edge(fromNode: START, toNode: classify),
            Edge(fromNode: classify, toNode: approved, route: 'approved'),
            Edge(fromNode: classify, toNode: rejected, route: DEFAULT_ROUTE),
          ],
        );

        final AgentGraph graph = await buildGraph(workflow);
        expect(
          graph.nodes.map((AgentGraphNode n) => n.kind),
          contains('workflow'),
        );
        expect(
          graph.edgeLabels[(
            'workflow_root:classify',
            'workflow_root:approved',
          )],
          'approved',
        );
        expect(
          graph.edgeLabels[(
            'workflow_root:classify',
            'workflow_root:rejected',
          )],
          DEFAULT_ROUTE,
        );

        final String mermaid = await getAgentGraph(workflow);
        expect(mermaid, contains('workflow_root'));
        expect(mermaid, contains('classify'));
        expect(mermaid, contains('workflow_root --> workflow_root_classify'));
        expect(
          mermaid,
          contains(
            'workflow_root_classify -- "approved" --> workflow_root_approved',
          ),
        );
        expect(
          mermaid,
          contains(
            'workflow_root_classify -- "__DEFAULT__" --> workflow_root_rejected',
          ),
        );
        expect(
          mermaid,
          contains('workflow_root_approved --> workflow_root_summarize'),
        );
      },
    );
  });
}
