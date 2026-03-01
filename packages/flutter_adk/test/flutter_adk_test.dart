import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_adk/flutter_adk_platform_interface.dart';
import 'package:flutter_adk/flutter_adk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _EchoModel extends BaseLlm {
  _EchoModel() : super(model: 'echo-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('echo'));
  }
}

class MockFlutterAdkPlatform
    with MockPlatformInterfaceMixin
    implements FlutterAdkPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterAdkPlatform initialPlatform = FlutterAdkPlatform.instance;

  test('$MethodChannelFlutterAdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAdk>());
  });

  test('getPlatformVersion', () async {
    FlutterAdk flutterAdkPlugin = FlutterAdk();
    MockFlutterAdkPlatform fakePlatform = MockFlutterAdkPlatform();
    FlutterAdkPlatform.instance = fakePlatform;

    expect(await flutterAdkPlugin.getPlatformVersion(), '42');
  });

  test('exports adk_core symbols', () {
    final Session session = Session(
      id: 'session_1',
      appName: 'app',
      userId: 'u',
    );
    final InMemorySessionService sessions = InMemorySessionService();
    expect(session.id, 'session_1');
    expect(sessions.runtimeType, InMemorySessionService);
  });

  test('exports Agent and Runner symbols', () async {
    final Agent agent = Agent(
      name: 'capital_agent',
      model: _EchoModel(),
      instruction: 'Answer capital questions.',
      tools: <Object>[
        FunctionTool(
          name: 'get_capital_city',
          description: 'Returns a capital city.',
          func: ({required String country}) => <String, Object?>{
            'capital': country.toUpperCase(),
          },
        ),
      ],
    );

    final InMemoryRunner runner = InMemoryRunner(
      agent: agent,
      appName: 'flutter_app',
    );
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'u1',
      sessionId: 's1',
    );
    final List<Event> events = await runner
        .runAsync(
          userId: 'u1',
          sessionId: session.id,
          newMessage: Content.userText('hello'),
        )
        .toList();

    expect(events.last.content?.parts.first.text, 'echo');
    await runner.close();
  });

  test('exports Gemini model symbol', () {
    final Gemini gemini = Gemini(
      model: 'gemini-2.5-flash',
      environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
    );
    expect(gemini.model, 'gemini-2.5-flash');
  });
}
