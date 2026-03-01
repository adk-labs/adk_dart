import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    test('provides builtin toolbox delegate when none is registered', () {
      expect(
        () => ToolboxToolset(serverUrl: 'http://127.0.0.1'),
        returnsNormally,
      );
    });

    test('builtin delegate loads tools and invokes toolbox endpoint', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final List<Map<String, Object?>> capturedInvocations =
          <Map<String, Object?>>[];
      unawaited(() async {
        await for (final HttpRequest request in server) {
          if (request.method == 'GET' &&
              request.uri.path == '/api/toolset/default') {
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(<String, Object?>{
                  'serverVersion': '1',
                  'tools': <String, Object?>{
                    'echo_tool': <String, Object?>{
                      'description': 'Echo from toolbox',
                      'parameters': <Object?>[
                        <String, Object?>{
                          'name': 'text',
                          'type': 'string',
                          'required': true,
                          'description': 'input text',
                        },
                      ],
                      'authRequired': <Object?>[],
                    },
                  },
                }),
              );
            await request.response.close();
            continue;
          }
          if (request.method == 'POST' &&
              request.uri.path == '/api/tool/echo_tool/invoke') {
            final String body = await utf8.decoder.bind(request).join();
            capturedInvocations.add(
              (jsonDecode(body) as Map).map(
                (Object? key, Object? value) => MapEntry('$key', value),
              ),
            );
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(<String, Object?>{'result': 'ok'}));
            await request.response.close();
            continue;
          }

          request.response.statusCode = 404;
          await request.response.close();
        }
      }());

      try {
        final ToolboxToolset toolset = ToolboxToolset(
          serverUrl: 'http://${server.address.host}:${server.port}',
          toolsetName: 'default',
        );
        final List<BaseTool> tools = await toolset.getTools();
        expect(tools.map((BaseTool tool) => tool.name), <String>['echo_tool']);

        final ToolContext toolContext = Context(
          InvocationContext(
            invocationId: 'inv',
            agent: LlmAgent(name: 'root', model: _NoopModel()),
            session: Session(id: 's1', appName: 'app', userId: 'u1'),
            sessionService: InMemorySessionService(),
          ),
        );
        final Object? result = await tools.first.run(
          args: <String, dynamic>{'text': 'hello'},
          toolContext: toolContext,
        );
        expect(result, 'ok');
        expect(capturedInvocations, hasLength(1));
        expect(capturedInvocations.single['text'], 'hello');
      } finally {
        await server.close(force: true);
      }
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

    test(
      'uses registered default delegate factory and forwards arguments',
      () async {
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
          authTokenGetters: <String, AuthTokenGetter>{'service': () => 'token'},
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
        expect(captured?['boundParams'], <String, Object?>{
          'region': 'us-central1',
        });
        expect(captured?['credentials'], 'cred');
        expect(captured?['additionalHeaders'], <String, String>{'x-adk': '1'});
        expect(captured?['additionalOptions'], <String, Object?>{'timeout': 1});
      },
    );
  });
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}
