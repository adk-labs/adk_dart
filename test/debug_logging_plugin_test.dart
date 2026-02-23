import 'dart:convert';
import 'dart:io';

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
    return <String, Object?>{'ok': true};
  }
}

InvocationContext _newContext() {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_debug',
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

Map<String, Object?> _parseSingleDoc(File file) {
  final String raw = file.readAsStringSync();
  final String jsonText = raw.replaceFirst('---\n', '').trim();
  final Object? decoded = jsonDecode(jsonText);
  expect(decoded, isA<Map>());
  return (decoded as Map).map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
}

void main() {
  test('writes invocation debug document with lifecycle entries', () async {
    final Directory temp = await Directory.systemTemp.createTemp(
      'adk-debug-plugin-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final File output = File('${temp.path}/adk_debug.yaml');

    final DebugLoggingPlugin plugin = DebugLoggingPlugin(
      outputPath: output.path,
      includeSessionState: true,
    );
    final InvocationContext invocationContext = _newContext();
    final Context callbackContext = Context(
      invocationContext,
      functionCallId: 'call_1',
    );

    await plugin.beforeRunCallback(invocationContext: invocationContext);
    await plugin.onUserMessageCallback(
      invocationContext: invocationContext,
      userMessage: Content.userText('hello'),
    );
    await plugin.beforeModelCallback(
      callbackContext: callbackContext,
      llmRequest: LlmRequest(
        model: 'model-a',
        config: GenerateContentConfig(systemInstruction: 'SYS'),
      ),
    );
    await plugin.afterModelCallback(
      callbackContext: callbackContext,
      llmResponse: LlmResponse(content: Content.modelText('world')),
    );
    await plugin.beforeToolCallback(
      tool: _FakeTool(),
      toolArgs: <String, dynamic>{'x': 1},
      toolContext: callbackContext,
    );
    await plugin.afterToolCallback(
      tool: _FakeTool(),
      toolArgs: <String, dynamic>{'x': 1},
      toolContext: callbackContext,
      result: <String, dynamic>{'ok': true},
    );
    await plugin.afterRunCallback(invocationContext: invocationContext);

    expect(output.existsSync(), isTrue);
    final Map<String, Object?> doc = _parseSingleDoc(output);
    expect(doc['invocation_id'], 'inv_debug');
    expect(doc['session_id'], 's1');
    final List<Object?> entries =
        (doc['entries'] as List<Object?>?) ?? <Object?>[];
    expect(entries, isNotEmpty);
    final String rendered = jsonEncode(entries);
    expect(rendered, contains('invocation_start'));
    expect(rendered, contains('user_message'));
    expect(rendered, contains('llm_request'));
    expect(rendered, contains('llm_response'));
    expect(rendered, contains('tool_call'));
    expect(rendered, contains('tool_response'));
    expect(rendered, contains('session_state_snapshot'));
    expect(rendered, contains('invocation_end'));
  });

  test(
    'omits raw system instruction text when includeSystemInstruction is false',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'adk-debug-plugin-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final File output = File('${temp.path}/adk_debug.yaml');

      final DebugLoggingPlugin plugin = DebugLoggingPlugin(
        outputPath: output.path,
        includeSystemInstruction: false,
      );
      final InvocationContext invocationContext = _newContext();
      final Context callbackContext = Context(invocationContext);

      await plugin.beforeRunCallback(invocationContext: invocationContext);
      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: LlmRequest(
          config: GenerateContentConfig(
            systemInstruction: 'SECRET_INSTRUCTION',
          ),
        ),
      );
      await plugin.afterRunCallback(invocationContext: invocationContext);

      final String raw = output.readAsStringSync();
      expect(raw, isNot(contains('SECRET_INSTRUCTION')));
      expect(raw, contains('system_instruction_length'));
    },
  );
}
