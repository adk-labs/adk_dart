import 'package:adk_dart/adk_core.dart';

void main() {
  final Session session = Session(id: 's', appName: 'app', userId: 'u');
  final InMemorySessionService sessions = InMemorySessionService();
  final InMemoryTelemetryService telemetry = InMemoryTelemetryService();
  final Event event = Event(
    invocationId: 'inv',
    author: 'user',
    content: Content.userText('hello'),
  );

  // Keep references to avoid tree-shake-only false positives in smoke compile.
  print(
    '${session.id}:${sessions.runtimeType}:${telemetry.runtimeType}:${event.id}',
  );
}
