import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingDecisionsClient implements OpenAIDecisionsClient {
  Map<String, Object?>? lastRequest;
  int callCount = 0;
  Map<String, Object?> nextResponse = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> createDecision(
    Map<String, Object?> body, {
    double? timeout,
  }) async {
    callCount += 1;
    lastRequest = body;
    return nextResponse;
  }
}

class _ConflictRetryingRedisClient extends InMemoryRedisStoreClient {
  final List<String> transactionWatchedKeys = <String>[];
  int simulatedConflictsRemaining = 0;
  Future<void> Function(InMemoryRedisStoreClient store)? onFirstTxRead;

  @override
  Future<void> transaction(
    Future<void> Function(RedisStoreClient pipe) action,
    String watchedKey,
  ) async {
    transactionWatchedKeys.add(watchedKey);
    while (true) {
      if (simulatedConflictsRemaining > 0) {
        simulatedConflictsRemaining -= 1;
        // Run action once against a sandboxed view, interleave a concurrent
        // write, and retry as optimistic WATCH/MULTI/EXEC would.
        await super.transaction((RedisStoreClient pipe) async {
          if (onFirstTxRead != null) {
            final hook = onFirstTxRead!;
            onFirstTxRead = null;
            await hook(this);
          }
        }, watchedKey);
        continue;
      }
      await super.transaction(action, watchedKey);
      return;
    }
  }
}

class _ErrorMessageOnlyAgent extends BaseAgent {
  _ErrorMessageOnlyAgent() : super(name: 'err_msg');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      errorMessage: 'Safety filter triggered without errorCode',
    );
  }
}

class _PartialReplyThenErrorModel extends BaseLlm {
  _PartialReplyThenErrorModel() : super(model: 'reply-then-err-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText('First chunk'),
      turnComplete: false,
    );
    yield LlmResponse(
      errorCode: 'INTERNAL',
      errorMessage: 'Upstream failure',
      turnComplete: true,
    );
  }
}

class _EchoUserSessionModel extends BaseLlm {
  _EchoUserSessionModel() : super(model: 'echo-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText('ok'),
      turnComplete: true,
    );
  }
}

void main() {
  group('1. OpenAIDecisionsClassifier upstream parity (aa98d180b)', () {
    test('rejects null question instructions before sending request', () async {
      final _RecordingDecisionsClient client = _RecordingDecisionsClient();
      final OpenAIDecisionsClassifier classifier = OpenAIDecisionsClassifier(
        apiKey: 'sk-test',
        client: client,
      );

      await expectLater(
        () => classifier.classify(
          input: 'hello',
          questions: <String, ClassifierQuestion>{
            'urgent': const Binary(),
          },
        ),
        throwsArgumentError,
      );
      expect(client.callCount, 0);
    });

    test('omits null Choice descriptions and joins Content text parts with empty string', () async {
      final _RecordingDecisionsClient client = _RecordingDecisionsClient()
        ..nextResponse = <String, Object?>{
          'model': 'gpt-6-luna',
          'answers': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'choice',
              'name': 'route',
              'choice': 'technical',
              'probabilities': <Map<String, Object?>>[
                <String, Object?>{'value': 'billing', 'probability': 0.2},
                <String, Object?>{'value': 'technical', 'probability': 0.8},
              ],
            },
          ],
        };

      final OpenAIDecisionsClassifier classifier = OpenAIDecisionsClassifier(
        apiKey: 'sk-test',
        client: client,
      );

      await classifier.classify(
        input: Content(
          role: 'user',
          parts: <Part>[Part.text('Help, '), Part.text('now')],
        ),
        questions: <String, ClassifierQuestion>{
          'route': Choice(
            instructions: 'Route ticket',
            criteria: <String, Object?>{
              'billing': 'Invoices and refunds',
              'technical': null,
            },
          ),
        },
      );

      expect(client.lastRequest!['input'], 'Help, now');
      final List<Object?> sentQuestions =
          client.lastRequest!['questions']! as List<Object?>;
      final Map<String, Object?> q0 = sentQuestions[0]! as Map<String, Object?>;
      final List<Object?> choices = q0['choices']! as List<Object?>;
      expect(choices, <Map<String, Object?>>[
        <String, Object?>{
          'value': 'billing',
          'description': 'Invoices and refunds',
        },
        <String, Object?>{'value': 'technical'},
      ]);
    });

    test('rejects Content containing a non-text Part', () async {
      final _RecordingDecisionsClient client = _RecordingDecisionsClient();
      final OpenAIDecisionsClassifier classifier = OpenAIDecisionsClassifier(
        apiKey: 'sk-test',
        client: client,
      );

      await expectLater(
        () => classifier.classify(
          input: Content(
            role: 'user',
            parts: <Part>[
              Part.text('Look at this'),
              Part.fromInlineData(
                mimeType: 'image/png',
                data: <int>[1, 2, 3],
              ),
            ],
          ),
          questions: <String, ClassifierQuestion>{
            'ok': const Binary(instructions: 'Is this ok?'),
          },
        ),
        throwsArgumentError,
      );
      expect(client.callCount, 0);
    });

    test('matches answers list by name, propagates confidence, and clamps 1e-6 drift', () async {
      final _RecordingDecisionsClient client = _RecordingDecisionsClient()
        ..nextResponse = <String, Object?>{
          'model': 'gpt-6-luna-2026-10-01',
          'answers': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'score',
              'name': 'frustration',
              'score': 2.0000001,
              'probabilities': <Map<String, Object?>>[
                <String, Object?>{'value': 0, 'probability': -1e-9},
                <String, Object?>{'value': 1, 'probability': 0.0},
                <String, Object?>{'value': 2, 'probability': 1.0000001},
              ],
              'confidence': 1.0000001,
            },
            <String, Object?>{
              'type': 'predicate',
              'name': 'urgent',
              'probability': -5e-7,
              'confidence': 0.77,
            },
            <String, Object?>{
              'type': 'choice',
              'name': 'dept',
              'choice': 'billing',
              'probabilities': <Map<String, Object?>>[
                <String, Object?>{'value': 'billing', 'probability': 1.0000005},
                <String, Object?>{'value': 'support', 'probability': -1e-7},
              ],
              'confidence': 0.9,
            },
          ],
        };

      final OpenAIDecisionsClassifier classifier = OpenAIDecisionsClassifier(
        apiKey: 'sk-test',
        client: client,
      );

      final ClassifierResponse response = await classifier.classify(
        input: 'My invoice failed',
        questions: <String, ClassifierQuestion>{
          'urgent': const Binary(instructions: 'Urgent?'),
          'dept': Choice(
            instructions: 'Dept?',
            criteria: <String, Object?>{'billing': null, 'support': null},
          ),
          'frustration': Score(
            instructions: 'Frustration?',
            criteria: <Object?>['Calm', 'Annoyed', 'Angry'],
          ),
        },
      );

      final BinaryAnswer urgent = response.answers['urgent']! as BinaryAnswer;
      expect(urgent.probability, 0.0);
      expect(urgent.confidence, 0.77);

      final ChoiceAnswer dept = response.answers['dept']! as ChoiceAnswer;
      expect(dept.choice, 'billing');
      expect(dept.probabilities, <String, double>{
        'billing': 1.0,
        'support': 0.0,
      });
      expect(dept.confidence, 0.9);

      final ScoreAnswer frustration =
          response.answers['frustration']! as ScoreAnswer;
      expect(frustration.score, 2.0);
      expect(frustration.probabilities, <int, double>{0: 0.0, 1: 0.0, 2: 1.0});
      expect(frustration.confidence, 1.0);
    });

    test('rejects out-of-tolerance probabilities and invalid score key types', () async {
      final _RecordingDecisionsClient outOfRangeClient =
          _RecordingDecisionsClient()
            ..nextResponse = <String, Object?>{
              'answers': <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'predicate',
                  'name': 'urgent',
                  'probability': 1.01,
                },
              ],
            };
      await expectLater(
        () => OpenAIDecisionsClassifier(
          apiKey: 'sk-test',
          client: outOfRangeClient,
        ).classify(
          input: 'hi',
          questions: <String, ClassifierQuestion>{
            'urgent': const Binary(instructions: 'Urgent?'),
          },
        ),
        throwsStateError,
      );

      final _RecordingDecisionsClient badScoreKeyClient =
          _RecordingDecisionsClient()
            ..nextResponse = <String, Object?>{
              'answers': <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'score',
                  'name': 'rating',
                  'score': 1.0,
                  'probabilities': <Map<String, Object?>>[
                    <String, Object?>{'value': '0', 'probability': 0.5},
                    <String, Object?>{'value': '1', 'probability': 0.5},
                  ],
                },
              ],
            };
      await expectLater(
        () => OpenAIDecisionsClassifier(
          apiKey: 'sk-test',
          client: badScoreKeyClient,
        ).classify(
          input: 'hi',
          questions: <String, ClassifierQuestion>{
            'rating': Score(
              instructions: 'Rate',
              criteria: <Object?>['Low', 'High'],
            ),
          },
        ),
        throwsStateError,
      );
    });
  });

  group('2. VMaaS AgentEngineEnvironment > 1 MiB readFile (4c880408b)', () {
    test('reads > 2 MiB file across 3 dd slices on exit code 67', () async {
      final int totalSize = 2 * 1024 * 1024 + 12345;
      final Uint8List expectedBytes = Uint8List.fromList(
        List<int>.generate(totalSize, (int i) => (i * 31) & 0xff),
      );
      final List<int> sliceIndices = <int>[];

      final ShellBackedAgentEngineSandboxClient client =
          ShellBackedAgentEngineSandboxClient(
            commandRunner: ({
              required String sandboxResourceName,
              required String command,
              String? workingDir,
              Duration? timeout,
              Map<String, String>? envVars,
            }) async {
              if (command.contains('stat -L -c %s')) {
                return EnvironmentExecutionResult(
                  exitCode: 67,
                  stdout: '$totalSize\n',
                );
              }
              if (command.contains('dd if=')) {
                final int index = int.parse(
                  RegExp(r'skip=(\d+)').firstMatch(command)!.group(1)!,
                );
                sliceIndices.add(index);
                final int start = index * AgentEngineEnvironment.readSliceBytes;
                final int end =
                    (start + AgentEngineEnvironment.readSliceBytes) < totalSize
                        ? start + AgentEngineEnvironment.readSliceBytes
                        : totalSize;
                return EnvironmentExecutionResult(
                  exitCode: 0,
                  stdout: base64Encode(expectedBytes.sublist(start, end)),
                );
              }
              return const EnvironmentExecutionResult(exitCode: 0);
            },
          );

      final AgentEngineEnvironment env = AgentEngineEnvironment(
        agentEngineResourceName: 'projects/p/locations/us-central1/reasoningEngines/1',
        client: client,
      );

      final List<int> actual = await env.readFile('/workspace/big.bin');
      expect(sliceIndices, <int>[0, 1, 2]);
      expect(actual, equals(expectedBytes));
    });

    test('in-memory fallback readFile supports files larger than 1 MiB', () async {
      final AgentEngineEnvironment env = AgentEngineEnvironment(
        agentEngineResourceName: 'projects/p/locations/us-central1/reasoningEngines/1',
      );
      final Uint8List big = Uint8List.fromList(
        List<int>.generate(1024 * 1024 + 42, (int i) => i & 0xff),
      );
      await env.writeBytes('/workspace/big_mem.bin', big);
      final List<int> readBack = await env.readFile('/workspace/big_mem.bin');
      expect(readBack, equals(big));
    });
  });

  group('3. RedisSessionService transactional scoped state & JSON-safe bytes (6b2d45523, 73dca84ef)', () {
    test('concurrent createSession and appendEvent preserve all app: and user: keys via watched transactions', () async {
      final _ConflictRetryingRedisClient client = _ConflictRetryingRedisClient()
        ..simulatedConflictsRemaining = 1
        ..onFirstTxRead = (InMemoryRedisStoreClient store) async {
          await store.set(
            'adk:session:app_state:my_app',
            jsonEncode(<String, Object?>{'other': 'from_concurrent_writer'}),
          );
        };

      final RedisSessionService service = RedisSessionService(
        redisClient: client,
      );

      // Concurrent createSession calls writing disjoint app:/user: keys.
      final List<Session> created = await Future.wait(<Future<Session>>[
        service.createSession(
          appName: 'my_app',
          userId: 'user_1',
          sessionId: 's1',
          state: <String, Object?>{'app:k1': 'v1', 'user:u1': 'a'},
        ),
        service.createSession(
          appName: 'my_app',
          userId: 'user_1',
          sessionId: 's2',
          state: <String, Object?>{'app:k2': 'v2', 'user:u2': 'b'},
        ),
      ]);

      // Concurrent appendEvent calls writing disjoint app:/user: deltas.
      await Future.wait(<Future<Event>>[
        service.appendEvent(
          session: created[0],
          event: Event(
            invocationId: 'inv1',
            author: 'agent',
            actions: EventActions(
              stateDelta: <String, Object?>{'app:ev1': 1, 'user:uev1': 10},
            ),
          ),
        ),
        service.appendEvent(
          session: created[1],
          event: Event(
            invocationId: 'inv2',
            author: 'agent',
            actions: EventActions(
              stateDelta: <String, Object?>{'app:ev2': 2, 'user:uev2': 20},
            ),
          ),
        ),
      ]);

      final Session? reloaded = await service.getSession(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 's1',
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.state['app:other'], 'from_concurrent_writer');
      expect(reloaded.state['app:k1'], 'v1');
      expect(reloaded.state['app:k2'], 'v2');
      expect(reloaded.state['app:ev1'], 1);
      expect(reloaded.state['app:ev2'], 2);
      expect(reloaded.state['user:u1'], 'a');
      expect(reloaded.state['user:u2'], 'b');
      expect(reloaded.state['user:uev1'], 10);
      expect(reloaded.state['user:uev2'], 20);
      expect(
        client.transactionWatchedKeys,
        containsAll(<String>[
          'adk:session:app_state:my_app',
          'adk:session:user_state:my_app:user_1',
        ]),
      );
    });

    test('base64-encodes non-UTF-8 bytes in createSession and appendEvent while keeping valid UTF-8 decoded', () async {
      final RedisSessionService service = RedisSessionService();
      final Uint8List pngBytes = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]);
      final Uint8List utf8Bytes = Uint8List.fromList(utf8.encode('hello'));

      final Session session = await service.createSession(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 's_bytes',
        state: <String, Object?>{
          'app:logo': pngBytes,
          'user:greeting': utf8Bytes,
          'session_blob': pngBytes,
        },
      );

      expect(session.state['app:logo'], 'iVBORw0KGgo=');
      expect(session.state['user:greeting'], 'hello');
      expect(session.state['session_blob'], 'iVBORw0KGgo=');

      final Uint8List highBytes = Uint8List.fromList(<int>[0xfb, 0xff, 0xfe]);
      final Event appended = await service.appendEvent(
        session: session,
        event: Event(
          invocationId: 'inv_bytes',
          author: 'agent',
          actions: EventActions(
            stateDelta: <String, Object?>{
              'app:badge': highBytes,
              'user:avatar': pngBytes,
              'screenshot': pngBytes,
            },
          ),
        ),
      );
      // Returned event and in-memory session preserve raw Uint8List.
      expect(appended.actions.stateDelta['screenshot'], pngBytes);
      expect(session.state['screenshot'], pngBytes);

      final Session? reloaded = await service.getSession(
        appName: 'my_app',
        userId: 'user_1',
        sessionId: 's_bytes',
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.state['app:badge'], '+//+');
      expect(reloaded.state['user:avatar'], 'iVBORw0KGgo=');
      expect(reloaded.state['screenshot'], 'iVBORw0KGgo=');
      expect(
        reloaded.events.single.actions.stateDelta['screenshot'],
        'iVBORw0KGgo=',
      );
    });
  });

  group('4. TeamsRunner aadObjectId and error event handling (c4376a657)', () {
    test('TeamsActivity.fromJson parses aadObjectId/aad_object_id and prefers it for userId', () {
      final TeamsActivity camel = TeamsActivity.fromJson(<String, Object?>{
        'type': 'message',
        'text': 'hi',
        'from': <String, Object?>{
          'id': '29:channel-user-1',
          'aadObjectId': 'aad-uuid-1',
        },
        'conversation': <String, Object?>{'id': 'conv-1'},
      });
      expect(camel.fromId, '29:channel-user-1');
      expect(camel.fromAadObjectId, 'aad-uuid-1');
      expect(camel.userId, 'aad-uuid-1');

      final TeamsActivity snake = TeamsActivity.fromJson(<String, Object?>{
        'type': 'message',
        'text': 'hi',
        'from_property': <String, Object?>{
          'id': '29:channel-user-2',
          'aad_object_id': 'aad-uuid-2',
        },
        'conversation': <String, Object?>{'id': 'conv-2'},
      });
      expect(snake.fromId, '29:channel-user-2');
      expect(snake.fromAadObjectId, 'aad-uuid-2');
      expect(snake.userId, 'aad-uuid-2');

      final TeamsActivity fallback = TeamsActivity.fromJson(<String, Object?>{
        'type': 'message',
        'text': 'hi',
        'from': <String, Object?>{
          'id': '29:channel-only',
          'aadObjectId': '',
        },
        'conversation': <String, Object?>{'id': 'conv-3'},
      });
      expect(fallback.userId, '29:channel-only');
    });

    test('TeamsRunner keys sessions by aadObjectId across different channel from.ids', () async {
      final InMemorySessionService sessionService = InMemorySessionService();
      final InMemoryRunner runner = InMemoryRunner(
        agent: LlmAgent(name: 'teams_agent', model: _EchoUserSessionModel()),
        appName: 'teams_aad_app',
      );
      // Reuse runner's sessionService to inspect stored sessions.
      final SimpleTeamsAgentApplication app = SimpleTeamsAgentApplication();
      final TeamsRunner teamsRunner = TeamsRunner(runner, app);
      final TeamsHttpApp httpApp = teamsRunner.createApp(null);

      await httpApp.handleMessagesPayload(<String, Object?>{
        'type': 'message',
        'text': 'hello',
        'from': <String, Object?>{
          'id': '29:ephemeral-chat-id',
          'aadObjectId': 'entra-oid-42',
        },
        'conversation': <String, Object?>{'id': 'conv:thread;1'},
      });
      await teamsRunner.waitForBackgroundTasks();

      final Session? byAad = await runner.sessionService.getSession(
        appName: 'teams_aad_app',
        userId: 'entra-oid-42',
        sessionId: sessionIdForConversation('conv:thread;1'),
      );
      final Session? byRaw = await runner.sessionService.getSession(
        appName: 'teams_aad_app',
        userId: '29:ephemeral-chat-id',
        sessionId: sessionIdForConversation('conv:thread;1'),
      );
      expect(byAad, isNotNull);
      expect(byRaw, isNull);
      await sessionService.listSessions(appName: 'teams_aad_app');
    });

    test('TeamsRunner sends generic error reply for errorMessage-only events and error events after a prior reply', () async {
      final TeamsRunner errorMsgRunner = TeamsRunner(
        InMemoryRunner(
          agent: _ErrorMessageOnlyAgent(),
          appName: 'teams_err_msg_app',
        ),
        SimpleTeamsAgentApplication(),
      );
      final List<Object> replies1 = await errorMsgRunner
          .createApp(null)
          .handleMessagesPayload(<String, Object?>{
            'type': 'message',
            'text': 'hi',
            'from': <String, Object?>{'id': 'u1'},
            'conversation': <String, Object?>{'id': 'c1'},
          });
      await errorMsgRunner.waitForBackgroundTasks();
      expect(replies1.last, 'Sorry, something went wrong while handling your message.');

      final TeamsRunner replyThenErrRunner = TeamsRunner(
        InMemoryRunner(
          agent: LlmAgent(
            name: 'reply_then_err',
            model: _PartialReplyThenErrorModel(),
          ),
          appName: 'teams_reply_err_app',
        ),
        SimpleTeamsAgentApplication(),
      );
      final List<Object> replies2 = await replyThenErrRunner
          .createApp(null)
          .handleMessagesPayload(<String, Object?>{
            'type': 'message',
            'text': 'hi',
            'from': <String, Object?>{'id': 'u1'},
            'conversation': <String, Object?>{'id': 'c2'},
          });
      await replyThenErrRunner.waitForBackgroundTasks();
      expect(
        replies2.whereType<String>().toList(),
        <String>[
          'First chunk',
          'Sorry, something went wrong while handling your message.',
        ],
      );
    });
  });
}
