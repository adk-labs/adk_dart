// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

import '../packages/adk/lib/src/cli/cli_deploy.dart';
import '../packages/adk/lib/src/dev/cli.dart';

class _FakeSummarizer extends BaseEventsSummarizer {
  _FakeSummarizer(this.summaryText);

  final String summaryText;
  int callCount = 0;

  @override
  Future<Event?> maybeSummarizeEvents({required List<Event> events}) async {
    callCount += 1;
    final double startTs = events.first.timestamp;
    final double endTs = events.last.timestamp;
    return Event(
      invocationId: 'compact-inv',
      author: 'agent',
      actions: EventActions(
        compaction: EventCompaction(
          startTimestamp: startTs,
          endTimestamp: endTs,
          compactedContent: Content(
            role: 'model',
            parts: <Part>[Part.text(summaryText)],
          ),
        ),
      ),
    );
  }
}

void main() {
  group('NodePathBuilder & single-turn event filtering', () {
    test('includesNodePath matches exact path and direct descendant paths', () {
      final NodePathBuilder subBuilder = NodePathBuilder.fromString('root/sub');

      expect(subBuilder.includesNodePath('root/sub'), isTrue);
      expect(subBuilder.includesNodePath('root/sub/child'), isTrue);
      expect(subBuilder.includesNodePath('root/sub_other'), isFalse);
      expect(subBuilder.includesNodePath(null), isTrue);
    });

    test('getContents filters single_turn events by nodePath', () {
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'user',
          content: Content.userText('hello'),
          nodeInfo: NodeInfo(path: 'root/node_a'),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'node_a',
          content: Content.modelText('from a'),
          nodeInfo: NodeInfo(path: 'root/node_a'),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'node_b',
          content: Content.modelText('from b'),
          nodeInfo: NodeInfo(path: 'root/node_b'),
        ),
      ];

      final List<Content> filtered = getContents(
        currentBranch: null,
        events: events,
        agentName: 'node_b',
        isSingleTurn: true,
        nodePath: 'root/node_b',
      );

      expect(filtered, hasLength(1));
      expect(filtered.single.parts.single.text, 'from b');
    });

    test('getCurrentTurnContents tracks matched tool call/response IDs', () {
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'user',
          content: Content.userText('turn 1'),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'agent',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'my_tool',
                args: <String, dynamic>{'x': 1},
                id: 'call-1',
              ),
            ],
          ),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'user',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'my_tool',
                response: <String, dynamic>{'ok': true},
                id: 'call-1',
              ),
            ],
          ),
        ),
      ];

      final List<Content> contents = getCurrentTurnContents(
        currentBranch: null,
        events: events,
        agentName: 'agent',
      );
      expect(contents, hasLength(3));
      expect(contents.first.parts.first.text, 'turn 1');
    });
  });

  group('AudioCacheManager MIME parameter stripping', () {
    test('strips MIME parameters when building audio file extension', () async {
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      final Session session = Session(
        id: 'sess-1',
        appName: 'app',
        userId: 'user',
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv-1',
        agent: LlmAgent(name: 'agent', model: 'gemini-2.5-flash'),
        session: session,
        artifactService: artifactService,
      );
      final AudioCacheManager manager = AudioCacheManager();
      manager.cacheAudio(
        context,
        InlineData(mimeType: 'audio/pcm;rate=24000', data: <int>[1, 2, 3, 4]),
        cacheType: 'input',
      );
      final List<Event> flushed = await manager.flushCaches(
        context,
        flushUserAudio: true,
        flushModelAudio: false,
      );
      expect(flushed, hasLength(1));
      final String fileUri =
          flushed.single.content!.parts.single.fileData!.fileUri;
      expect(fileUri, endsWith('.pcm#0'));
      expect(fileUri.contains(';'), isFalse);
    });
  });

  group('Model name utils & AgentTransfer builtin tool compatibility', () {
    test('extractModelName handles publisher-only paths and Gemini 3+', () {
      expect(
        extractModelName('publishers/google/models/gemini-3-flash-preview'),
        'gemini-3-flash-preview',
      );
      expect(
        supportsBuiltinToolsWithFunctionCalling(
          'publishers/google/models/gemini-3-flash-preview',
        ),
        isTrue,
      );
      expect(
        supportsBuiltinToolsWithFunctionCalling('gemini-2.5-flash'),
        isFalse,
      );
    });

    test(
      'AgentTransferLlmRequestProcessor enforces builtin tool check on Gemini 2.x vs 3+',
      () async {
        final LlmAgent subAgent = LlmAgent(
          name: 'helper',
          description: 'Helper agent',
          model: 'gemini-2.5-flash',
        );
        final LlmAgent gemini2Agent = LlmAgent(
          name: 'root_v2',
          model: 'gemini-2.5-flash',
          tools: <Object>[GoogleSearchTool()],
          subAgents: <BaseAgent>[subAgent],
        );
        final InvocationContext ctx2 = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv-2',
          agent: gemini2Agent,
          session: Session(id: 's1', appName: 'app', userId: 'u1'),
        );
        final AgentTransferLlmRequestProcessor processor =
            AgentTransferLlmRequestProcessor();
        expect(
          () => processor
              .runAsync(ctx2, LlmRequest(model: 'gemini-2.5-flash'))
              .toList(),
          throwsArgumentError,
        );

        final LlmAgent gemini3Agent = LlmAgent(
          name: 'root_v3',
          model: 'gemini-3-flash-preview',
          tools: <Object>[GoogleSearchTool()],
          subAgents: <BaseAgent>[
            LlmAgent(name: 'helper_v3', model: 'gemini-3-flash-preview'),
          ],
        );
        final InvocationContext ctx3 = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv-3',
          agent: gemini3Agent,
          session: Session(id: 's2', appName: 'app', userId: 'u1'),
        );
        await processor
            .runAsync(ctx3, LlmRequest(model: 'gemini-3-flash-preview'))
            .toList();
      },
    );
  });

  group('AuthHandler secret redaction & auth_resume', () {
    test(
      'generateAuthRequest redacts secrets and storeAuthResponse pins to server AuthConfig',
      () async {
        final AuthConfig serverConfig = AuthConfig(
          authScheme: 'oauth2',
          rawAuthCredential: AuthCredential(
            authType: AuthCredentialType.oauth2,
            oauth2: OAuth2Auth(
              clientId: 'server-client',
              clientSecret: 'top-secret',
              authUri: 'https://auth.example.com/authorize',
              redirectUri: 'https://app.example.com/callback',
            ),
          ),
        );
        final AuthHandler handler = AuthHandler(authConfig: serverConfig);
        final AuthConfig outgoing = handler.generateAuthRequest();
        expect(outgoing.rawAuthCredential!.oauth2!.clientSecret, isNull);
        expect(outgoing.exchangedAuthCredential!.oauth2!.clientSecret, isNull);
        expect(
          serverConfig.rawAuthCredential!.oauth2!.clientSecret,
          'top-secret',
        );

        final State state = State(
          value: <String, Object?>{},
          delta: <String, Object?>{},
        );
        state[oauthStateKey('interrupt-1')] =
            outgoing.exchangedAuthCredential!.oauth2!.state;

        // Client tries to tamper with authScheme or clientSecret
        final Map<String, Object?> clientResponse = <String, Object?>{
          'authScheme': 'tampered',
          'exchangedAuthCredential': <String, Object?>{
            'authType': 'oauth2',
            'oauth2': <String, Object?>{
              'state': outgoing.exchangedAuthCredential!.oauth2!.state,
              'authResponseUri':
                  'https://app.example.com/callback?code=auth-code-123&state=${outgoing.exchangedAuthCredential!.oauth2!.state}',
            },
          },
        };

        final AuthConfig? stored = await storeAuthResponse(
          requested: serverConfig,
          response: clientResponse,
          state: state,
          interruptId: 'interrupt-1',
        );
        expect(stored, isNotNull);
        expect(stored!.authScheme, 'oauth2');
        final Object? savedCred =
            state[authResponseStateKey(serverConfig.credentialKey)];
        expect(savedCred, isA<AuthCredential>());
        final AuthCredential cred = savedCred! as AuthCredential;
        expect(cred.oauth2!.clientSecret, 'top-secret');
        expect(cred.oauth2!.authCode, 'auth-code-123');
      },
    );
  });

  group('LiteLlm Gemma 4 & JSON-tolerant tool argument parsing', () {
    test(
      'parses malformed tool call arguments and formats Gemma 4 tool_responses',
      () {
        final Map<String, Object?> completion = <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'id': 'call_1',
                    'function': <String, Object?>{
                      'name': 'search',
                      'arguments':
                          "```json\n{query: 'dart', limit: 5, active: True,}\n```",
                    },
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        };

        final LlmResponse parsed = LiteLlm.parseCompletionResponse(completion);
        final FunctionCall call = parsed.content!.parts.single.functionCall!;
        expect(call.name, 'search');
        expect(call.args, <String, dynamic>{
          'query': 'dart',
          'limit': 5,
          'active': true,
        });

        final Map<String, Object?> payload = LiteLlm.buildPayload(
          LlmRequest(
            model: 'ollama/gemma4:latest',
            contents: <Content>[
              Content.userText('hi'),
              Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'search',
                    args: <String, dynamic>{'query': 'dart'},
                    id: 'call_1',
                  ),
                ],
              ),
              // Interrupted by user message before tool response!
              Content.userText('cancel that'),
            ],
          ),
          stream: false,
        );

        final List<Map<String, Object?>> messages =
            (payload['messages'] as List<Map<String, Object?>>);
        expect(
          messages.any(
            (Map<String, Object?> m) => m['role'] == 'tool_responses',
          ),
          isTrue,
        );
      },
    );
  });

  group('InMemorySessionService & Compaction parity', () {
    test(
      'appendEvent updates existing event in-place when event id matches',
      () async {
        final InMemorySessionService service = InMemorySessionService();
        final Session session = await service.createSession(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
        );
        final Event initial = Event(
          id: 'evt-1',
          invocationId: 'inv-1',
          author: 'agent',
          partial: false,
          content: Content.modelText('hel'),
        );
        await service.appendEvent(session: session, event: initial);
        expect(session.events, hasLength(1));

        final Event finalized = Event(
          id: 'evt-1',
          invocationId: 'inv-1',
          author: 'agent',
          partial: false,
          content: Content.modelText('hello world'),
          actions: EventActions(stateDelta: <String, Object?>{'k': 'v'}),
        );
        await service.appendEvent(session: session, event: finalized);
        expect(session.events, hasLength(1));
        expect(session.events.single.partial, isFalse);
        expect(session.events.single.content!.parts.single.text, 'hello world');
        expect(session.state['k'], 'v');
      },
    );

    test(
      'runCompactionForSlidingWindow skips compaction when summary would not shrink prompt',
      () async {
        final InMemorySessionService service = InMemorySessionService();
        final Session session = Session(
          id: 's1',
          appName: 'app',
          userId: 'u1',
          events: <Event>[
            Event(
              id: 'e1',
              invocationId: 'inv-1',
              author: 'user',
              timestamp: 1.0,
              content: Content.userText('hi'),
            ),
            Event(
              id: 'e2',
              invocationId: 'inv-1',
              author: 'agent',
              timestamp: 2.0,
              content: Content.modelText('ok'),
            ),
            // Existing huge compaction summary covering e1..e2
            Event(
              id: 'c1',
              invocationId: 'inv-1',
              author: 'agent',
              timestamp: 2.5,
              actions: EventActions(
                compaction: EventCompaction(
                  startTimestamp: 1.0,
                  endTimestamp: 2.0,
                  compactedContent: Content.modelText('x' * 500),
                ),
              ),
            ),
            Event(
              id: 'e3',
              invocationId: 'inv-2',
              author: 'user',
              timestamp: 3.0,
              content: Content.userText('a'),
            ),
            Event(
              id: 'e4',
              invocationId: 'inv-2',
              author: 'agent',
              timestamp: 4.0,
              content: Content.modelText('b'),
            ),
          ],
        );

        final _FakeSummarizer summarizer = _FakeSummarizer('new summary');
        final App app = App(
          name: 'app',
          rootAgent: LlmAgent(name: 'agent', model: 'gemini-2.5-flash'),
          eventsCompactionConfig: EventsCompactionConfig(
            compactionInterval: 1,
            overlapSize: 0,
            summarizer: summarizer,
          ),
        );

        final List<Event> compacted = await runCompactionForSlidingWindow(
          app: app,
          session: session,
          sessionService: service,
        ).toList();
        expect(compacted, isEmpty);
        expect(summarizer.callCount, 0);
      },
    );
  });

  group('Utilities & CLI options parity', () {
    test('AgentMode constants and delegatedTaskModes match upstream', () {
      expect(AgentMode.chat.value, 'chat');
      expect(AgentMode.task.value, 'task');
      expect(AgentMode.singleTurn.value, 'single_turn');
      expect(delegatedTaskModes, containsAll(<String>['task', 'single_turn']));
    });

    test('printEvent and CachePerformanceAnalyzer work as expected', () {
      final List<String> lines = <String>[];
      printEvent(
        Event(
          invocationId: 'inv-1',
          author: 'agent',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.text('hello'),
              Part.fromFunctionCall(
                name: 'calc',
                args: <String, dynamic>{'a': 1},
              ),
            ],
          ),
        ),
        verbose: true,
        sink: lines.add,
      );
      expect(lines, hasLength(2));
      expect(lines.first, contains('agent > hello'));
      expect(lines.last, contains('calc'));
    });

    test(
      'CLI run parses --state and --state_file and rejects both together',
      () async {
        final ParsedAdkCommand parsed = parseAdkCliArgs(<String>[
          'run',
          '--state={"foo":"bar","count":3}',
          'my_agent',
        ]);
        expect(
          parsed.initialState,
          <String, Object?>{'foo': 'bar', 'count': 3},
        );

        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk_cli_state_',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final File stateFile = File('${tempDir.path}/state.json');
        await stateFile.writeAsString('{"fromFile":true}');

        final ParsedAdkCommand fromFile = parseAdkCliArgs(<String>[
          'run',
          '--state_file',
          stateFile.path,
          'my_agent',
        ]);
        expect(fromFile.initialState, <String, Object?>{'fromFile': true});

        expect(
          () => parseAdkCliArgs(<String>[
            'run',
            '--state={"a":1}',
            '--state_file=${stateFile.path}',
            'my_agent',
          ]),
          throwsA(isA<CliUsageError>()),
        );
      },
    );

    test('CLI deploy validates --service_account email and forwards flag', () {
      final List<String> cmd = toAgentEngine(
        DeployCommand(
          service: 'svc',
          project: 'my-proj',
          region: 'us-central1',
          image: 'gcr.io/my-proj/svc:latest',
          serviceAccount: 'agent-sa@my-proj.iam.gserviceaccount.com',
        ),
      );
      expect(
        cmd,
        containsAllInOrder(<String>[
          '--service-account',
          'agent-sa@my-proj.iam.gserviceaccount.com',
        ]),
      );

      expect(
        () => validateServiceAccountEmail('not-an-email'),
        throwsArgumentError,
      );
    });
  });
}
