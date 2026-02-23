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
  _FakeTool() : super(name: 'search', description: 'fake');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, dynamic>{'ok': true};
  }
}

class _ResultErrorPlugin extends ReflectAndRetryToolPlugin {
  _ResultErrorPlugin({super.maxRetries, super.throwExceptionIfRetryExceeded});

  @override
  Future<Object?> extractErrorFromResult({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return result['error'];
  }
}

Context _newContext(String invocationId) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's_$invocationId', appName: 'app', userId: 'u1'),
  );
  return Context(invocationContext, functionCallId: 'call_1');
}

void main() {
  test(
    'returns reflection guidance until max retries, then exceed guidance',
    () async {
      final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
        maxRetries: 2,
        throwExceptionIfRetryExceeded: false,
      );
      final Context context = _newContext('inv_1');
      final _FakeTool tool = _FakeTool();

      final Map<String, dynamic>? first = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'q': 'a'},
        toolContext: context,
        error: Exception('boom'),
      );
      final Map<String, dynamic>? second = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'q': 'a'},
        toolContext: context,
        error: Exception('boom'),
      );
      final Map<String, dynamic>? third = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'q': 'a'},
        toolContext: context,
        error: Exception('boom'),
      );

      expect(first, isNotNull);
      expect(first!['response_type'], reflectAndRetryResponseType);
      expect(first['retry_count'], 1);
      expect(second?['retry_count'], 2);
      expect(third?['retry_count'], 2);
      expect(
        third?['reflection_guidance'],
        contains('retry limit has been exceeded'),
      );
    },
  );

  test(
    'throws when retries exceeded and throwException flag is true',
    () async {
      final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
        maxRetries: 0,
        throwExceptionIfRetryExceeded: true,
      );

      await expectLater(
        plugin.onToolErrorCallback(
          tool: _FakeTool(),
          toolArgs: <String, dynamic>{},
          toolContext: _newContext('inv_throw'),
          error: Exception('fatal'),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('resets failure counter after successful tool callback', () async {
    final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
      maxRetries: 2,
      throwExceptionIfRetryExceeded: false,
    );
    final Context context = _newContext('inv_reset');
    final _FakeTool tool = _FakeTool();

    final Map<String, dynamic>? first = await plugin.onToolErrorCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: context,
      error: Exception('boom'),
    );
    expect(first?['retry_count'], 1);

    await plugin.afterToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: context,
      result: <String, dynamic>{'status': 'ok'},
    );

    final Map<String, dynamic>? afterReset = await plugin.onToolErrorCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: context,
      error: Exception('boom'),
    );
    expect(afterReset?['retry_count'], 1);
  });

  test('global scope shares counters across invocations', () async {
    final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
      maxRetries: 2,
      throwExceptionIfRetryExceeded: false,
      trackingScope: TrackingScope.global,
    );
    final _FakeTool tool = _FakeTool();

    final Map<String, dynamic>? first = await plugin.onToolErrorCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: _newContext('inv_a'),
      error: Exception('boom'),
    );
    final Map<String, dynamic>? second = await plugin.onToolErrorCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: _newContext('inv_b'),
      error: Exception('boom'),
    );
    final Map<String, dynamic>? third = await plugin.onToolErrorCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: _newContext('inv_a'),
      error: Exception('boom'),
    );

    expect(first?['retry_count'], 1);
    expect(second?['retry_count'], 2);
    expect(third?['retry_count'], 2);
    expect(
      third?['reflection_guidance'],
      contains('retry limit has been exceeded'),
    );
  });

  test(
    'afterToolCallback can route errors extracted from successful result',
    () async {
      final _ResultErrorPlugin plugin = _ResultErrorPlugin(
        maxRetries: 2,
        throwExceptionIfRetryExceeded: false,
      );
      final Map<String, dynamic>? response = await plugin.afterToolCallback(
        tool: _FakeTool(),
        toolArgs: <String, dynamic>{},
        toolContext: _newContext('inv_extract'),
        result: <String, dynamic>{'error': 'permission denied'},
      );

      expect(response, isNotNull);
      expect(response?['response_type'], reflectAndRetryResponseType);
      expect(response?['retry_count'], 1);
    },
  );
}
