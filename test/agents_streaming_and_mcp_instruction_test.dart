import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

InvocationContext _newInvocationContext({Map<String, Object?>? state}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_mcp',
    agent: LlmAgent(name: 'root', instruction: 'hi'),
    session: Session(
      id: 's1',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
}

void main() {
  group('agent streaming + mcp instruction parity', () {
    test('ActiveStreamingTool stores task and stream handles', () async {
      final LiveRequestQueue queue = LiveRequestQueue();
      final Future<Object?> task = Future<Object?>.value('done');
      final ActiveStreamingTool active = ActiveStreamingTool(
        task: task,
        stream: queue,
      );

      expect(active.stream, same(queue));
      expect(await active.task, 'done');
    });

    test(
      'McpInstructionProvider reads prompt and applies state values',
      () async {
        McpSessionManager.instance.clear();
        final StreamableHTTPConnectionParams connectionParams =
            StreamableHTTPConnectionParams(url: 'mock://mcp');
        McpSessionManager.instance.registerResources(
          connectionParams: connectionParams,
          resources: <String, List<McpResourceContent>>{
            'agent_prompt': <McpResourceContent>[
              McpResourceContent(text: 'Hello {city}! Welcome {{user}}.'),
            ],
          },
        );

        final InvocationContext invocationContext = _newInvocationContext(
          state: <String, Object?>{'city': 'Seoul', 'user': 'Jaichang'},
        );
        final McpInstructionProvider provider = McpInstructionProvider(
          connectionParams: connectionParams,
          promptName: 'agent_prompt',
        );

        final String instruction = await provider(
          ReadonlyContext(invocationContext),
        );
        expect(instruction, 'Hello {city}! Welcome {{user}}.');
      },
    );

    test('McpInstructionProvider throws when prompt is missing', () async {
      McpSessionManager.instance.clear();
      final StreamableHTTPConnectionParams connectionParams =
          StreamableHTTPConnectionParams(url: 'mock://mcp');

      final InvocationContext invocationContext = _newInvocationContext();
      final McpInstructionProvider provider = McpInstructionProvider(
        connectionParams: connectionParams,
        promptName: 'missing_prompt',
      );

      expect(
        () => provider(ReadonlyContext(invocationContext)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
