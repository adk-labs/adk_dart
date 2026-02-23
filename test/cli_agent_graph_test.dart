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
  });
}
