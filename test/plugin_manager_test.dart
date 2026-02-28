import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _FakeTool extends BaseTool {
  _FakeTool() : super(name: 'fake_tool', description: 'fake');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, dynamic>{'result': 'ok'};
  }
}

class _RecordingPlugin extends BasePlugin {
  _RecordingPlugin({required super.name, this.returnBeforeModel});

  final LlmResponse? returnBeforeModel;
  int beforeModelCalls = 0;

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    beforeModelCalls += 1;
    return returnBeforeModel;
  }
}

class _ThrowingPlugin extends BasePlugin {
  _ThrowingPlugin({required super.name});

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    throw StateError('plugin failure');
  }
}

class _CloseThrowingPlugin extends BasePlugin {
  _CloseThrowingPlugin({required super.name});

  @override
  Future<void> close() async {
    throw StateError('close failed');
  }
}

class _AfterRunThrowingPlugin extends BasePlugin {
  _AfterRunThrowingPlugin({required super.name});

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    throw StateError('after run failure');
  }
}

class _CloseSlowPlugin extends BasePlugin {
  _CloseSlowPlugin({required super.name});

  @override
  Future<void> close() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

InvocationContext _newInvocationContext() {
  final LlmAgent agent = LlmAgent(
    name: 'root_agent',
    model: _NoopModel(),
    disallowTransferToParent: true,
    disallowTransferToPeers: true,
  );
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_plugin_manager',
    agent: agent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  test('registerPlugin rejects duplicate names', () {
    final PluginManager manager = PluginManager();
    manager.registerPlugin(_RecordingPlugin(name: 'dup'));

    expect(
      () => manager.registerPlugin(_RecordingPlugin(name: 'dup')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'runBeforeModelCallback returns first non-null and short-circuits',
    () async {
      final _RecordingPlugin first = _RecordingPlugin(
        name: 'first',
        returnBeforeModel: LlmResponse(content: Content.modelText('cached')),
      );
      final _RecordingPlugin second = _RecordingPlugin(name: 'second');
      final PluginManager manager = PluginManager(
        plugins: <BasePlugin>[first, second],
      );

      final LlmResponse? response = await manager.runBeforeModelCallback(
        callbackContext: Context(_newInvocationContext()),
        llmRequest: LlmRequest(),
      );

      expect(response, isNotNull);
      expect(response!.content?.parts.first.text, 'cached');
      expect(first.beforeModelCalls, 1);
      expect(second.beforeModelCalls, 0);
    },
  );

  test('run callback wraps plugin errors with callback name', () async {
    final PluginManager manager = PluginManager(
      plugins: <BasePlugin>[_ThrowingPlugin(name: 'bad')],
    );

    await expectLater(
      manager.runBeforeModelCallback(
        callbackContext: Context(_newInvocationContext()),
        llmRequest: LlmRequest(),
      ),
      throwsA(
        isA<PluginManagerException>().having(
          (PluginManagerException error) => error.message,
          'message',
          contains("Error in plugin 'bad' during 'before_model_callback'"),
        ),
      ),
    );
  });

  test('close aggregates plugin timeout/errors', () async {
    final PluginManager manager = PluginManager(
      closeTimeout: const Duration(milliseconds: 20),
      plugins: <BasePlugin>[
        _CloseThrowingPlugin(name: 'throwing'),
        _CloseSlowPlugin(name: 'slow'),
      ],
    );

    await expectLater(
      manager.close(),
      throwsA(
        isA<PluginManagerException>().having(
          (PluginManagerException error) => error.message,
          'message',
          contains('Failed to close plugins'),
        ),
      ),
    );
  });

  test('runAfterRunCallback wraps plugin errors with callback name', () async {
    final PluginManager manager = PluginManager(
      plugins: <BasePlugin>[_AfterRunThrowingPlugin(name: 'bad_after')],
    );

    await expectLater(
      manager.runAfterRunCallback(invocationContext: _newInvocationContext()),
      throwsA(
        isA<PluginManagerException>().having(
          (PluginManagerException error) => error.message,
          'message',
          contains("Error in plugin 'bad_after' during 'after_run_callback'"),
        ),
      ),
    );
  });

  test('runBeforeToolCallback forwards first plugin result', () async {
    final PluginManager manager = PluginManager(
      plugins: <BasePlugin>[
        _BeforeToolReturningPlugin(name: 'p1'),
        _BeforeToolReturningPlugin(name: 'p2'),
      ],
    );

    final Map<String, dynamic>? result = await manager.runBeforeToolCallback(
      tool: _FakeTool(),
      toolArgs: <String, dynamic>{'a': 1},
      toolContext: Context(_newInvocationContext(), functionCallId: 'fc_1'),
    );

    expect(result, isNotNull);
    expect(result!['status'], 'handled');
    expect(result['plugin'], 'p1');
  });
}

class _BeforeToolReturningPlugin extends BasePlugin {
  _BeforeToolReturningPlugin({required super.name});

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    return <String, dynamic>{'status': 'handled', 'plugin': name};
  }
}
