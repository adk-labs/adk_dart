import 'dart:io';
import 'package:adk_dart/adk_dart.dart';

const String _defaultAgentId = 'antigravity-preview-05-2026';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY environment variable.');
    return;
  }

  final String agentId = Platform.environment['MANAGED_AGENT_ID'] ?? _defaultAgentId;

  // Initialize a ManagedAgent.
  // It connects to the Google GenAI Interactions API (interactions.create) directly.
  final ManagedAgent agent = ManagedAgent(
    name: 'managed_search_agent',
    agentId: agentId,
    // Provision a remote sandbox for the agent. The environment ID is recovered
    // from prior events, so follow-up turns reuse the same sandbox.
    environment: <String, Object?>{'type': 'remote'},
    // Only server-side tools are supported for ManagedAgent. googleSearch runs on the server.
    tools: <Object>[googleSearch],
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'managed_user',
    sessionId: 'managed_session',
  );

  print('Sending message to Managed Agent: What is the current stock price of Google?');

  try {
    await for (final Event event in runner.runAsync(
      userId: 'managed_user',
      sessionId: session.id,
      newMessage: .userText('What is the current stock price of Google?'),
    )) {
      final String text =
          event.content?.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ') ??
          '';
      
      if (text.isNotEmpty) {
        print('[${event.author}] $text');
      }
    }
  } catch (e) {
    print('Error executing Managed Agent: $e');
  }
}
