import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  // 1. Configure Streamable HTTP connection parameters for the MCP server
  final StreamableHTTPConnectionParams mcpParams =
      StreamableHTTPConnectionParams(
    url: 'http://127.0.0.1:8080/mcp',
  );

  // 2. Create the McpToolset
  final McpToolset mcpToolset = McpToolset(
    connectionParams: mcpParams,
  );

  // 3. Define the ADK Agent equipped with the MCP Toolset
  final Agent agent = Agent(
    name: 'mcp_assistant',
    model: Gemini(
      model: 'gemini-3.7-flash',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    ),
    instruction: '''
You are a helpful assistant with access to external MCP tools.
Use the provided MCP tools to inspect resources, execute commands, or query data as requested by the user.
''',
    tools: <Object>[mcpToolset],
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_mcp',
  );

  print('Sending query to MCP-enabled Agent...');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: .userText('List available tools and execute a test query.'),
  )) {
    final String text = event.content?.parts
            .where((Part p) => p.text != null)
            .map((Part p) => p.text!)
            .join(' ') ??
        '';
    if (text.isNotEmpty) {
      print('[${event.author}] $text');
    }
  }
}
