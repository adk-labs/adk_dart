import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<Context> _newToolContext({
  Object? credentialService,
  ToolConfirmation? toolConfirmation,
  String? functionCallId,
  BaseArtifactService? artifactService,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'u1',
    sessionId: 's1',
  );
  final InvocationContext invocationContext = InvocationContext(
    invocationId: 'inv_1',
    sessionService: sessionService,
    credentialService: credentialService,
    artifactService: artifactService,
    agent: Agent(name: 'agent', model: _NoopModel()),
    session: session,
  );
  return Context(
    invocationContext,
    functionCallId: functionCallId,
    toolConfirmation: toolConfirmation,
  );
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _EchoAuthTool extends BaseAuthenticatedTool {
  _EchoAuthTool({required super.authConfig})
    : super(name: 'echo_auth', description: 'echo');

  @override
  Future<Object?> runAuthenticated({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
    required AuthCredential? credential,
  }) async {
    return <String, Object?>{
      'value': args['value'],
      'api_key': credential?.apiKey,
    };
  }
}

class _DeclaredTool extends BaseTool {
  _DeclaredTool() : super(name: 'declared', description: 'decl');

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'OBJECT',
        'properties': <String, dynamic>{
          'query': <String, dynamic>{'type': 'STRING'},
        },
        'required': <String>['query'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return args['query'];
  }
}

void main() {
  group('tools batch2 parity', () {
    test('extractText joins text parts only', () {
      final MemoryEntry memory = MemoryEntry(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.text('first'),
            Part.fromFunctionCall(name: 'noop'),
            Part.text('second'),
          ],
        ),
      );
      expect(extractText(memory), 'first second');
    });

    test('getUserChoice marks action as skip summarization', () async {
      final Context context = await _newToolContext();
      final String? value = getUserChoice(<String>['A', 'B'], context);
      expect(value, isNull);
      expect(context.actions.skipSummarization, isTrue);
    });

    test(
      'ForwardingArtifactService delegates to tool context services',
      () async {
        final InMemoryArtifactService artifactService =
            InMemoryArtifactService();
        final Context context = await _newToolContext(
          artifactService: artifactService,
        );
        final ForwardingArtifactService forwarding = ForwardingArtifactService(
          context,
        );

        final int version = await forwarding.saveArtifact(
          appName: 'ignored',
          userId: 'ignored',
          filename: 'memo.txt',
          artifact: Part.text('hello artifact'),
        );
        expect(version, 0);

        final Part? loaded = await forwarding.loadArtifact(
          appName: 'ignored',
          userId: 'ignored',
          filename: 'memo.txt',
        );
        expect(loaded?.text, 'hello artifact');
        expect(
          await forwarding.listArtifactKeys(
            appName: 'ignored',
            userId: 'ignored',
          ),
          contains('memo.txt'),
        );
      },
    );

    test(
      'BaseAuthenticatedTool requests credential when unavailable',
      () async {
        final AuthConfig authConfig = AuthConfig(
          authScheme: 'oauth2',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialType.oauth2,
          ),
        );
        final _EchoAuthTool tool = _EchoAuthTool(authConfig: authConfig);
        final Context context = await _newToolContext(functionCallId: 'call_1');

        final Object? result = await tool.run(
          args: <String, dynamic>{'value': 'v1'},
          toolContext: context,
        );

        expect(result, 'Pending User Authorization.');
        expect(
          context.actions.requestedAuthConfigs.containsKey('call_1'),
          isTrue,
        );
      },
    );

    test(
      'AuthenticatedFunctionTool injects credential when available',
      () async {
        final AuthConfig authConfig = AuthConfig(
          authScheme: 'oauth2',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialType.oauth2,
          ),
        );
        final Context context = await _newToolContext();
        context.state[authResponseStateKey(
          authConfig.credentialKey,
        )] = AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(accessToken: 'token_123'),
        );

        final AuthenticatedFunctionTool tool = AuthenticatedFunctionTool(
          func: ({String? city, AuthCredential? credential}) {
            return '${city ?? ''}:${credential?.oauth2?.accessToken ?? 'none'}';
          },
          name: 'auth_fn',
          description: 'auth fn',
          authConfig: authConfig,
        );

        final Object? result = await tool.run(
          args: <String, dynamic>{'city': 'seoul'},
          toolContext: context,
        );
        expect(result, 'seoul:token_123');
      },
    );

    test('loadWebPage fetches text and filters short lines', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async => server.close(force: true));
      server.listen((HttpRequest request) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('''
<html><body>
<h1>Short</h1>
<p>This line has many words and should be included.</p>
</body></html>
''');
        request.response.close();
      });

      final String text = await loadWebPage(
        'http://${server.address.host}:${server.port}/',
      );
      expect(
        text,
        contains('This line has many words and should be included.'),
      );
      expect(text.contains('Short'), isFalse);
    });

    test('MCP conversion utils convert declaration schema', () {
      final Map<String, Object?> mcpTool = adkToMcpToolType(_DeclaredTool());
      final Map<String, Object?> input =
          mcpTool['inputSchema']! as Map<String, Object?>;
      expect(input['type'], 'object');
      final Map<String, Object?> props =
          input['properties']! as Map<String, Object?>;
      final Map<String, Object?> query =
          props['query']! as Map<String, Object?>;
      expect(query['type'], 'string');
    });

    test('SessionContext starts once and closes', () async {
      int startCount = 0;
      bool closed = false;
      final SessionContext<String> context = SessionContext<String>(
        startSession: () async {
          startCount += 1;
          return 'session';
        },
        closeSession: (String value) async {
          if (value == 'session') {
            closed = true;
          }
        },
      );

      expect(await context.start(), 'session');
      expect(await context.start(), 'session');
      expect(startCount, 1);

      await context.close();
      expect(closed, isTrue);
      await expectLater(context.start(), throwsStateError);
    });
  });
}
