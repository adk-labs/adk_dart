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
    tearDown(() {
      ToolboxToolset.clearDefaultDelegateFactory();
    });

    test('throws clear error when toolbox integration is missing', () {
      expect(
        () => ToolboxToolset(serverUrl: 'http://127.0.0.1'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('requires toolbox integration'),
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

    test('uses registered default delegate factory and forwards arguments', () async {
      final _FakeToolboxDelegate delegate = _FakeToolboxDelegate(
        tools: <BaseTool>[_FakeTool('tool_a')],
      );
      Map<String, Object?>? captured;
      ToolboxToolset.registerDefaultDelegateFactory(({
        required String serverUrl,
        String? toolsetName,
        List<String>? toolNames,
        Map<String, AuthTokenGetter>? authTokenGetters,
        Map<String, Object?>? boundParams,
        Object? credentials,
        Map<String, String>? additionalHeaders,
        Map<String, Object?>? additionalOptions,
      }) {
        captured = <String, Object?>{
          'serverUrl': serverUrl,
          'toolsetName': toolsetName,
          'toolNames': toolNames,
          'authTokenGetters': authTokenGetters,
          'boundParams': boundParams,
          'credentials': credentials,
          'additionalHeaders': additionalHeaders,
          'additionalOptions': additionalOptions,
        };
        return delegate;
      });

      final ToolboxToolset toolset = ToolboxToolset(
        serverUrl: 'http://127.0.0.1',
        toolsetName: 'my_toolset',
        toolNames: <String>['tool_a'],
        authTokenGetters: <String, AuthTokenGetter>{
          'service': () => 'token',
        },
        boundParams: <String, Object?>{'region': 'us-central1'},
        credentials: 'cred',
        additionalHeaders: <String, String>{'x-adk': '1'},
        additionalOptions: <String, Object?>{'timeout': 1},
      );

      final List<BaseTool> tools = await toolset.getTools();
      expect(tools.map((BaseTool tool) => tool.name), <String>['tool_a']);

      expect(captured?['serverUrl'], 'http://127.0.0.1');
      expect(captured?['toolsetName'], 'my_toolset');
      expect(captured?['toolNames'], <String>['tool_a']);
      expect(
        (captured?['authTokenGetters'] as Map?)?.containsKey('service'),
        isTrue,
      );
      expect(
        captured?['boundParams'],
        <String, Object?>{'region': 'us-central1'},
      );
      expect(captured?['credentials'], 'cred');
      expect(captured?['additionalHeaders'], <String, String>{'x-adk': '1'});
      expect(captured?['additionalOptions'], <String, Object?>{'timeout': 1});
    });
  });
}
