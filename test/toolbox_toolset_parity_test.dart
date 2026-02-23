import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeTool extends BaseTool {
  _FakeTool(String name) : super(name: name, description: 'fake');

  @override
  FunctionDeclaration? getDeclaration() => FunctionDeclaration(name: name);

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

class _FakeToolboxDelegate implements ToolboxToolsetDelegate {
  _FakeToolboxDelegate({required this.tools});

  final List<BaseTool> tools;
  bool closeCalled = false;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return tools;
  }

  @override
  Future<void> close() async {
    closeCalled = true;
  }
}

void main() {
  group('ToolboxToolset parity', () {
    test('throws clear error when toolbox delegate is missing', () async {
      final ToolboxToolset toolset = ToolboxToolset(
        serverUrl: 'http://127.0.0.1',
      );
      await expectLater(
        () => toolset.getTools(),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('requires a toolbox delegate'),
          ),
        ),
      );
    });

    test('delegates getTools and close to injected toolbox delegate', () async {
      final _FakeToolboxDelegate delegate = _FakeToolboxDelegate(
        tools: <BaseTool>[_FakeTool('tool_a'), _FakeTool('tool_b')],
      );
      final ToolboxToolset toolset = ToolboxToolset(
        serverUrl: 'http://127.0.0.1',
        toolsetName: 'my_toolset',
        toolNames: <String>['tool_a', 'tool_b'],
        delegate: delegate,
      );

      final List<BaseTool> tools = await toolset.getTools();
      expect(tools.map((BaseTool tool) => tool.name), <String>[
        'tool_a',
        'tool_b',
      ]);

      await toolset.close();
      expect(delegate.closeCalled, isTrue);
    });
  });
}
