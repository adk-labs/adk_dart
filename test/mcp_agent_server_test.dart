import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _EchoTestAgent extends BaseAgent {
  _EchoTestAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String prompt = context.session.events.last.content?.parts.first.text ?? '';
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('echo: $prompt'),
    );
  }
}

void main() {
  group('AdkAgentMcpServer', () {
    test('exposes agent as MCP tool and runs request', () async {
      final _EchoTestAgent agent = _EchoTestAgent(name: 'echo_agent');
      final AdkAgentMcpServer server = AdkAgentMcpServer(
        agent: agent,
        description: 'Echo agent for MCP testing',
      );

      final Map<String, dynamic> descriptor = server.getToolDescriptor();
      expect(descriptor['name'], equals('echo_agent'));
      expect(descriptor['description'], equals('Echo agent for MCP testing'));
      expect(descriptor['inputSchema']['required'], contains('request'));

      final List<McpContentBlock> response = await server.runAgent(
        request: 'Hello MCP!',
        connectionId: 'conn_1',
      );

      expect(response.length, equals(1));
      expect(response.first.type, equals('text'));
      expect(response.first.text, equals('echo: Hello MCP!'));
    });

    test('reuses session across multiple calls on same connectionId', () async {
      final _EchoTestAgent agent = _EchoTestAgent(name: 'session_agent');
      final AdkAgentMcpServer server = AdkAgentMcpServer(agent: agent);

      final List<McpContentBlock> res1 = await server.runAgent(
        request: 'Turn 1',
        connectionId: 'conn_same',
      );
      final List<McpContentBlock> res2 = await server.runAgent(
        request: 'Turn 2',
        connectionId: 'conn_same',
      );

      expect(res1.first.text, equals('echo: Turn 1'));
      expect(res2.first.text, equals('echo: Turn 2'));

      final List<Session> sessions = (await server.runner.sessionService.listSessions(
        appName: 'session_agent',
        userId: mcpUserId,
      )).sessions;

      expect(sessions.length, equals(1));
    });
  });
}
