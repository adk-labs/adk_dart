import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

class StubEchoModel extends BaseLlm {
  StubEchoModel() : super(model: 'stub_echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String prompt = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
            .where((Part p) => p.text != null)
            .map((Part p) => p.text!)
            .join(' ');
    yield LlmResponse(content: Content.modelText('Remembered: $prompt'));
  }
}

Future<void> main() async {
  final String dbPath = '${Directory.current.path}/sessions_demo.db';
  print('Using SQLite session database at: $dbPath');

  // 1. Create a SQLite-backed session service
  final SqliteSessionService sessionService = SqliteSessionService(dbPath);

  final Agent agent = Agent(
    name: 'persistent_assistant',
    model: StubEchoModel(),
    instruction: 'You remember user conversation history across restarts.',
  );

  // 2. Initialize Runner with SQLite session service
  final Runner runner = Runner(
    agent: agent,
    sessionService: sessionService,
    appName: 'persistence_demo',
  );

  // 3. Create or resume a session
  final String userId = 'user_alice';
  final String sessionId = 'session_persistent_001';

  Session? session = await sessionService.getSession(
    appName: runner.appName,
    userId: userId,
    sessionId: sessionId,
  );

  if (session == null) {
    print('Creating new persistent session...');
    session = await sessionService.createSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
    );
  } else {
    print('Resuming existing session with ${session.events.length} previous events.');
  }

  // 4. Run a turn
  await for (final Event event in runner.runAsync(
    userId: userId,
    sessionId: session.id,
    newMessage: Content.userText('My favorite color is Blue.'),
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

  // 5. Verify saved events in DB
  final Session reloadedSession = (await sessionService.getSession(
    appName: runner.appName,
    userId: userId,
    sessionId: sessionId,
  ))!;

  print('\nSuccessfully saved ${reloadedSession.events.length} events to SQLite database.');

  // Clean up temporary demo database file
  final File file = File(dbPath);
  if (await file.exists()) {
    await file.delete();
    print('Cleaned up demo database file.');
  }
}
