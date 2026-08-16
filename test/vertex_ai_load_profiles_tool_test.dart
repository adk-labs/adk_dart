import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('VertexAiLoadProfilesTool retrieves structured profiles for user', () async {
    final InMemoryMemoryService memoryService = InMemoryMemoryService();
    await memoryService.addEventsToMemory(
      appName: 'test-app',
      userId: 'user-123',
      events: <Event>[
        Event(
          invocationId: 'inv-event',
          author: 'user',
          content: Content.userText('User prefers dark mode and Dart programming.'),
        ),
      ],
    );

    final VertexAiLoadProfilesTool tool = VertexAiLoadProfilesTool(
      memoryService: memoryService,
    );

    expect(tool.name, 'load_profiles');
    expect(tool.getDeclaration()?.name, 'load_profiles');

    final InvocationContext invocationContext = InvocationContext(
      invocationId: 'inv-1',
      session: Session(id: 's-1', appName: 'test-app', userId: 'user-123'),
      agent: LlmAgent(name: 'agent'),
      artifactService: InMemoryArtifactService(),
      sessionService: InMemorySessionService(),
    );

    final Context toolContext = Context(
      invocationContext,
      functionCallId: 'call-1',
    );

    final Map<String, Object?> result = await tool.run(
      args: const <String, dynamic>{},
      toolContext: toolContext,
    );

    expect(result, contains('profiles'));
    expect(result['profiles'], isA<List>());
    final List<String> profiles = (result['profiles'] as List).cast<String>();
    expect(profiles, isNotEmpty);
    expect(profiles.first, contains('User prefers dark mode'));
  });
}
