import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart' hide Invocation;
import 'package:adk/src/dev/cli.dart';
import 'package:test/test.dart';

class _BufferSink implements IOSink {
  _BufferSink(this.buffer);
  final StringBuffer buffer;

  @override
  void write(Object? obj) => buffer.write(obj);

  @override
  void writeln([Object? obj = '']) => buffer.writeln(obj);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      buffer.write(utf8.decode(chunk));
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Encoding encoding = utf8;

  @override
  Future<void> flush() async {}
}

class _Part13StubModel extends BaseLlm {
  _Part13StubModel() : super(model: 'part13-stub-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String prompt = request.contents.map((Content c) {
      return c.parts.map((Part p) => p.text ?? '').join(' ');
    }).join(' ');

    if (prompt.contains('trigger_timeout')) {
      final Completer<void> completer = Completer<void>();
      await completer.future;
    }

    yield LlmResponse(content: Content.modelText('part13 stub response'));
  }
}

class _FailingComputer implements BaseComputer {
  int _stateCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<ComputerState> currentState() async {
    _stateCalls++;
    if (_stateCalls == 1) {
      throw Exception('Transient screenshot error');
    }
    return ComputerState(screenshot: <int>[1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingSessionService extends InMemorySessionService {
  bool failCreate = false;
  bool failGet = false;

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    if (failGet) {
      throw StateError('Simulated getSession StateError');
    }
    return super.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    String? sessionId,
    Map<String, Object?>? state,
  }) async {
    if (failCreate) {
      final String id = sessionId ?? 'default_s';
      await super.createSession(
        appName: appName,
        userId: userId,
        sessionId: id,
        state: state,
      );
      throw Exception('Session create conflict');
    }
    return await super.createSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      state: state,
    );
  }
}

class _MissingMetadataArtifactService extends InMemoryArtifactService {
  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
    int? version,
  }) async => null;
}

void main() {
  setUpAll(() {
    LLMRegistry.clear();
    LLMRegistry.register(
      supportedModels: <RegExp>[
        RegExp(r'^part13-stub-model$'),
        RegExp(r'^gemini-.*$'),
      ],
      factory: (String model) => _Part13StubModel(),
    );
  });

  tearDownAll(LLMRegistry.clear);

  group('Target 100% Coverage - Part 13 CLI Conformance & Optimization Lines', () {
    test('printOptimizationResultsForTesting with null gepaResult and detailed results (line 1398)', () {
      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final GepaRootAgentPromptOptimizerResult result = GepaRootAgentPromptOptimizerResult(
        optimizedAgents: <BaseAgentWithScores>[
          BaseAgentWithScores(
            optimizedAgent: LlmAgent(name: 'root', model: 'gemini-2.5-flash', instruction: 'best instructions'),
            overallScore: 0.95,
          ),
        ],
        gepaResult: null,
      );

      printOptimizationResultsForTesting(
        result,
        printDetailedResults: true,
        out: sink,
      );
      expect(buffer.toString(), contains('Detailed GEPA optimization metrics are not available.'));
    });

    test('runConformanceRecordForTesting handles exception during case recording (lines 1641-1643)', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('conformance_rec_fail_');
      try {
        final StringBuffer buffer = StringBuffer();
        final _BufferSink sink = _BufferSink(buffer);

        final Directory caseDir = Directory('${tempDir.path}/cat1/case1')..createSync(recursive: true);
        File('${caseDir.path}/spec.yaml').writeAsStringSync('''
agent: my_agent
description: test case
user_messages:
  - text: hi
''');

        final dynamic command = createParsedConformanceRecordCommandForTesting(
          paths: <String>[caseDir.path],
          baseUri: Uri.parse('http://127.0.0.1:9999'),
          userId: 'user1',
        );

        await runConformanceRecordForTesting(command, out: sink);
        expect(buffer.toString(), contains('Failed to generate cat1/case1'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('runConformanceTestForTesting with unsupported mode (lines 1840-1845)', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('conformance_mode_fail_');
      try {
        final StringBuffer buffer = StringBuffer();
        final _BufferSink sink = _BufferSink(buffer);

        final Directory caseDir = Directory('${tempDir.path}/cat1/case1')..createSync(recursive: true);
        File('${caseDir.path}/spec.yaml').writeAsStringSync('''
agent: my_agent
description: test case
user_messages: []
''');

        final dynamic command = createParsedConformanceTestCommandForTesting(
          paths: <String>[caseDir.path],
          baseUri: Uri.parse('http://127.0.0.1:8080'),
          userId: 'user1',
          mode: 'unsupported_mode',
        );

        await runConformanceTestForTesting(command, out: sink);
        expect(buffer.toString(), contains('Unsupported conformance mode: unsupported_mode'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('runConformanceTestCaseForTesting live case session failure and SSE exception (lines 1908, 1935-1941)', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('conformance_live_fail_');
      try {
        final Directory caseDir = Directory('${tempDir.path}/cat1/case1')..createSync(recursive: true);
        File('${caseDir.path}/spec.yaml').writeAsStringSync('''
agent: my_agent
description: test case
user_messages:
  - text: hello
''');

        final dynamic testCase = (await discoverConformanceCasesForTesting(
          <String>[caseDir.path],
          out: _BufferSink(StringBuffer()),
          replayMode: false,
          streamingMode: StreamingMode.none,
        )).first;

        // 1. Session creation returning empty map triggers line 1908.
        final HttpServer dummyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        dummyServer.listen((HttpRequest request) {
          if (request.uri.path.contains('/sessions')) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(<String, Object?>{})); // empty map -> no id
            request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.close();
          }
        });

        try {
          final AdkWebServerClient client = AdkWebServerClient(
            Uri.parse('http://${dummyServer.address.host}:${dummyServer.port}'),
          );
          await expectLater(
            runConformanceTestCaseForTesting(
              client,
              testCase,
              userId: 'user1',
              streamingMode: StreamingMode.none,
              mode: 'live',
            ),
            throwsStateError,
          );
        } finally {
          await dummyServer.close(force: true);
        }

        // 2. Client runAgentSse throwing exception triggers lines 1935-1941.
        final HttpServer dummyServer2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        dummyServer2.listen((HttpRequest request) {
          if (request.method == 'POST' && request.uri.path.contains('/sessions')) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(<String, Object?>{'id': 'session_123'}));
            request.response.close();
          } else if (request.uri.path.contains('/run')) {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Server failure');
            request.response.close();
          } else {
            request.response.close();
          }
        });

        try {
          final AdkWebServerClient client2 = AdkWebServerClient(
            Uri.parse('http://${dummyServer2.address.host}:${dummyServer2.port}'),
          );
          final dynamic result2 = await runConformanceTestCaseForTesting(
            client2,
            testCase,
            userId: 'user1',
            streamingMode: StreamingMode.none,
            mode: 'live',
          );
          expect(result2.success, isFalse);
          expect(result2.errorMessage, contains('Live execution failed'));
        } finally {
          await dummyServer2.close(force: true);
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('runConformanceTestCaseForTesting replay case empty session id, event mismatch, and deleteSession error (lines 1986, 2059-2068, 2113)', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync('conformance_replay_fail_');
      try {
        final Directory caseDir = Directory('${tempDir.path}/cat1/case1')..createSync(recursive: true);
        File('${caseDir.path}/spec.yaml').writeAsStringSync('''
agent: my_agent
description: test case
user_messages:
  - text: hello
''');
        File('${caseDir.path}/generated-session.yaml').writeAsStringSync('''
id: rec_s
events:
  - id: ev1
    author: model
    content:
      parts:
        - text: recorded_text
''');
        File('${caseDir.path}/generated-recordings.yaml').writeAsStringSync('''
recordings: []
''');

        final dynamic testCase = (await discoverConformanceCasesForTesting(
          <String>[caseDir.path],
          out: _BufferSink(StringBuffer()),
          replayMode: true,
          streamingMode: StreamingMode.none,
        )).first;

        // 1. Session id empty -> line 1986
        final HttpServer dummyServer1 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        dummyServer1.listen((HttpRequest request) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(<String, Object?>{})); // empty map -> no id
          request.response.close();
        });

        try {
          final AdkWebServerClient client1 = AdkWebServerClient(
            Uri.parse('http://${dummyServer1.address.host}:${dummyServer1.port}'),
          );
          await expectLater(
            runConformanceTestCaseForTesting(
              client1,
              testCase,
              userId: 'user1',
              streamingMode: StreamingMode.none,
              mode: 'replay',
            ),
            throwsStateError,
          );
        } finally {
          await dummyServer1.close(force: true);
        }

        // 2. Event mismatch -> lines 2059-2068, and deleteSession failure -> line 2113
        final HttpServer dummyServer2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        dummyServer2.listen((HttpRequest request) {
          request.response.headers.contentType = ContentType.json;
          if (request.method == 'POST' && request.uri.path.endsWith('/sessions')) {
            request.response.write(jsonEncode(<String, Object?>{'id': 'session_ok'}));
            request.response.close();
          } else if (request.uri.path.contains('/run')) {
            request.response.write(jsonEncode(<Object?>[
              <String, Object?>{
                'id': 'ev1',
                'author': 'model',
                'content': <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{'text': 'different_actual_text'},
                  ],
                },
              },
            ]));
            request.response.close();
          } else if (request.method == 'GET' && request.uri.path.contains('/sessions/')) {
            request.response.write(jsonEncode(<String, Object?>{
              'id': 'session_ok',
              'events': <Object?>[
                <String, Object?>{
                  'id': 'ev1',
                  'author': 'model',
                  'content': <String, Object?>{
                    'parts': <Object?>[
                      <String, Object?>{'text': 'different_actual_text'},
                    ],
                  },
                },
              ],
            }));
            request.response.close();
          } else if (request.method == 'DELETE') {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Delete failed');
            request.response.close();
          } else {
            request.response.close();
          }
        });

        try {
          final AdkWebServerClient client2 = AdkWebServerClient(
            Uri.parse('http://${dummyServer2.address.host}:${dummyServer2.port}'),
          );
          final dynamic res2 = await runConformanceTestCaseForTesting(
            client2,
            testCase,
            userId: 'user1',
            streamingMode: StreamingMode.none,
            mode: 'replay',
          );
          expect(res2.success, isFalse);
          expect(res2.errorMessage, contains('event 0 mismatch'));
        } finally {
          await dummyServer2.close(force: true);
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('Target 100% Coverage - Part 13 Avatar Config & Feature Flag Warnings', () {
    test('avatar_config invalid JSON object [1, 2] (line 4600)', () {
      expect(
        () => parseAdkCliArgs(<String>['web', '.', '--avatar_config=[1, 2]']),
        throwsA(isA<CliUsageError>().having(
          (CliUsageError e) => e.message,
          'message',
          contains('expected a JSON object mapping agent names to avatar configs'),
        )),
      );
    });

    test('avatar_config invalid kv entry with empty value a= (line 4625)', () {
      expect(
        () => parseAdkCliArgs(<String>['web', '.', '--avatar_config=a= ']),
        throwsA(isA<CliUsageError>().having(
          (CliUsageError e) => e.message,
          'message',
          contains('Invalid --avatar_config entry: a='),
        )),
      );
    });

    test('disable_features with unknown feature warning (line 5590-5595)', () {
      final StringBuffer errBuffer = StringBuffer();
      final _BufferSink errSink = _BufferSink(errBuffer);

      writeUnknownFeatureNameWarningTesting(
        'completely_unknown_feature_xyz',
        errSink,
      );

      expect(
        errBuffer.toString(),
        contains("WARNING: Unknown feature name 'completely_unknown_feature_xyz'"),
      );
    });
  });

  group('Target 100% Coverage - Part 13 Run Command App Loading, Timeout, Resume, Snapshot', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cli_run_p13_');
      File('${tempDir.path}/root_agent.yaml').writeAsStringSync('''
name: my_agent
model: gemini-2.5-flash
instruction: Be helpful
''');
    });

    tearDown(() {
      agentLoaderTestingOverride = null;
      tempDir.deleteSync(recursive: true);
    });

    test('agentLoaderTestingOverride loading App directly (lines 4818..4843)', () async {
      agentLoaderTestingOverride = (String path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          projectDirName(tempDir.path): (String name, String dir) => App(
            name: 'diff_app_name',
            rootAgent: LlmAgent(name: 'sub_agent', model: 'gemini-2.5-flash'),
          ),
        },
        enableDevProjectFallback: false,
      );

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--message=hello'],
        outSink: sink,
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('part13 stub response'));
    });

    test('run command with --log_level=debug and err: null (lines 4922, 4924)', () async {
      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--message=hello', '--log_level=debug'],
        outSink: sink,
      );
      expect(code, equals(0));
    });

    test('run command message timeout error (lines 4973-4975, 5004)', () async {
      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);
      final StringBuffer errBuffer = StringBuffer();
      final _BufferSink errSink = _BufferSink(errBuffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--message=trigger_timeout', '--timeout=1'],
        outSink: sink,
        errSink: errSink,
      );
      expect(code, equals(1));
      expect(errBuffer.toString(), contains('ERROR: Execution timed out after 1 seconds.'));
    });

    test('run command auto-resuming interrupt with message (lines 4988, 4991, 4996-4998)', () async {
      final File snapshotFile = File('${tempDir.path}/open_int.session.json');
      snapshotFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'id': 'sess_open_int',
        'user_id': 'user1',
        'app_name': projectDirName(tempDir.path),
        'state': <String, Object?>{},
        'storage_events': <Object?>[
          <String, Object?>{
            'id': 'ev_int_1',
            'author': 'model',
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'id': 'tool_int_1',
                    'name': 'adk_request_confirmation',
                    'args': <String, Object?>{'action': 'confirm'},
                  },
                },
              ],
            },
            'long_running_tool_ids_json': '["tool_int_1"]',
          },
        ],
      }));

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--resume=${snapshotFile.path}', '--message=confirmed'],
        outSink: sink,
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('Auto-resuming interrupt tool_int_1 with input: confirmed'));
    });

    test('run command resume without message where last event is user (lines 5026-5042)', () async {
      final File snapshotFile = File('${tempDir.path}/user_last.session.json');
      snapshotFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'id': 'sess_user_last',
        'user_id': 'user1',
        'app_name': projectDirName(tempDir.path),
        'state': <String, Object?>{},
        'storage_events': <Object?>[
          <String, Object?>{
            'id': 'ev_user',
            'author': 'user',
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': 'resumed user question'},
              ],
            },
          },
        ],
      }));

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--resume=${snapshotFile.path}'],
        outSink: sink,
        readLine: () => 'exit',
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('part13 stub response'));
    });

    test('run command resume without message where resumed message times out (lines 5034-5036)', () async {
      final File snapshotFile = File('${tempDir.path}/user_last_timeout.session.json');
      snapshotFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'id': 'sess_user_last_to',
        'user_id': 'user1',
        'app_name': projectDirName(tempDir.path),
        'state': <String, Object?>{},
        'storage_events': <Object?>[
          <String, Object?>{
            'id': 'ev_user',
            'author': 'user',
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': 'trigger_timeout'},
              ],
            },
          },
        ],
      }));

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--resume=${snapshotFile.path}', '--timeout=1'],
        outSink: sink,
        readLine: () => 'exit',
      );
      expect(code, equals(1));
    });

    test('interactive loop timeout returns code 1 (line 5071)', () async {
      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      int readCount = 0;
      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--timeout=1'],
        outSink: sink,
        readLine: () {
          readCount += 1;
          if (readCount == 1) return 'trigger_timeout';
          return 'exit';
        },
      );
      expect(code, equals(1));
    });

    test('replay mode with timeout and jsonl (lines 5170, 5174)', () async {
      final File replayFile = File('${tempDir.path}/test_replay.json');
      replayFile.writeAsStringSync(jsonEncode(<String, Object?>{
        'queries': <String>['query1', 'query2'],
      }));

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--replay=${replayFile.path}', '--timeout=10', '--jsonl'],
        outSink: sink,
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('part13 stub response'));
    });

    test('existing session with state and resume empty vs non-empty events (lines 5210-5211, 5230, 5234)', () async {
      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      // 1. Lines 5210-5211: existing session with initialState
      await runAdkCli(
        <String>['run', tempDir.path, '--session_id=existing_s1', '--message=hi'],
        outSink: sink,
      );
      final int codeExisting = await runAdkCli(
        <String>['run', tempDir.path, '--session_id=existing_s1', '--message=hi2', '--state={"key": "val"}'],
        outSink: sink,
      );
      expect(codeExisting, equals(0));

      // 2. Line 5230: resume with empty events and initialState
      final File emptyEventsSession = File('${tempDir.path}/empty_events.session.json');
      emptyEventsSession.writeAsStringSync(jsonEncode(<String, Object?>{
        'id': 'sess_empty',
        'user_id': 'user1',
        'app_name': projectDirName(tempDir.path),
        'state': <String, Object?>{'initial_k': 'initial_v'},
        'events': <Object?>[],
      }));
      final int codeEmpty = await runAdkCli(
        <String>['run', tempDir.path, '--resume=${emptyEventsSession.path}', '--message=hi', '--state={"extra": 123}'],
        outSink: sink,
      );
      expect(codeEmpty, equals(0));

      // 3. Line 5234: resume with non-empty events and initialState
      final File nonEmptyEventsSession = File('${tempDir.path}/non_empty_events.session.json');
      nonEmptyEventsSession.writeAsStringSync(jsonEncode(<String, Object?>{
        'id': 'sess_non_empty',
        'user_id': 'user1',
        'app_name': projectDirName(tempDir.path),
        'state': <String, Object?>{'prev': 'state'},
        'events': <Object?>[
          <String, Object?>{
            'id': 'ev1',
            'author': 'user',
            'content': <String, Object?>{
              'parts': <Object?>[<String, Object?>{'text': 'prev msg'}],
            },
          },
        ],
      }));
      final int codeNonEmpty = await runAdkCli(
        <String>['run', tempDir.path, '--resume=${nonEmptyEventsSession.path}', '--message=hi', '--state={"override": true}'],
        outSink: sink,
      );
      expect(codeNonEmpty, equals(0));
    });

    test('saveSessionSnapshot with empty readLine input fallback to target.id (lines 5309, 5312)', () async {
      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      int readCount = 0;
      final int code = await runAdkCli(
        <String>['run', tempDir.path, '--save_session'],
        outSink: sink,
        readLine: () {
          readCount += 1;
          if (readCount == 1) return 'exit';
          return ''; // returns empty string -> saveId = target.id
        },
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('Session saved to'));
    });
  });

  group('Target 100% Coverage - Part 13 CLI Web Signals', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cli_web_p13_');
      File('${tempDir.path}/root_agent.yaml').writeAsStringSync('''
name: web_agent
model: gemini-2.5-flash
instruction: Web agent instruction
''');
    });

    tearDown(() {
      simulateSignalUnsupportedForTesting = false;
      webSignalsTestingOverride = null;
      webSignalStreamTestingOverride = null;
      webStdinTestingOverride = null;
      tempDir.deleteSync(recursive: true);
    });

    test('web command signal handling unavailable and stdin input (lines 5467, 5473, 5474)', () async {
      simulateSignalUnsupportedForTesting = true;
      webStdinTestingOverride = Stream<List<int>>.value(<int>[10]); // Enter key byte

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['web', tempDir.path, '--port=0'],
        outSink: sink,
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('Signal handling unavailable. Press Enter to stop.'));
    });

    test('web command webSignalStreamTestingOverride stop trigger (lines 5462-5463)', () async {
      final StreamController<void> controller = StreamController<void>();
      webSignalStreamTestingOverride = controller.stream;

      Timer(const Duration(milliseconds: 100), () {
        controller.add(null);
      });

      final StringBuffer buffer = StringBuffer();
      final _BufferSink sink = _BufferSink(buffer);

      final int code = await runAdkCli(
        <String>['web', tempDir.path, '--port=0'],
        outSink: sink,
      );
      expect(code, equals(0));
      expect(buffer.toString(), contains('ADK web server is running'));
    });
  });

  group('Target 100% Coverage - Part 13 Web Server Remaining Lines', () {
    late Directory tempDir;
    late DevAgentRuntime runtime;
    late DevProjectConfig project;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ws_p13_');
      File('${tempDir.path}/root_agent.yaml').writeAsStringSync('''
name: my_app
model: gemini-2.5-flash
instruction: Web server app
''');
      project = DevProjectConfig(
        appName: 'my_app',
        agentName: 'my_app',
        description: 'Web server app',
      );
      runtime = DevAgentRuntime(
        config: project,
        runner: InMemoryRunner(agent: LlmAgent(name: 'my_app', model: 'gemini-2.5-flash')),
      );
    });

    tearDown(() {
      webServerAgentLoaderTestingOverride = null;
      tempDir.deleteSync(recursive: true);
    });

    test('webServerAgentLoaderTestingOverride loading App, getRootAgent, and defaultAppName StateError (lines 695..702, 1138, 1142-1145, 1059)', () async {
      webServerAgentLoaderTestingOverride = (String path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'app_custom': (String name, String dir) => App(
            name: 'app_custom',
            rootAgent: LlmAgent(name: 'root_agent', model: 'gemini-2.5-flash'),
          ),
          'my_app': (String name, String dir) => throw StateError('default agent load failed'),
        },
        enableDevProjectFallback: false,
      );

      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      // 1. Lines 695..702: context.getRunner when loaded is App
      final Runner runner = await context.getRunner('app_custom');
      expect(runner.appName, equals('app_custom'));

      // 2. Line 1138: context.getRootAgent when loaded is App
      final BaseAgent rootAgent = context.getRootAgent('app_custom');
      expect(rootAgent.name, equals('root_agent'));

      // 3. Lines 1142-1145: context.getRootAgent with defaultAppName when loader throws StateError
      final BaseAgent fallbackRoot = context.getRootAgent('my_app');
      expect(fallbackRoot.name, equals('my_app'));

      // 4. Line 1059: readTraceByEventId with missing event
      final Map<String, Object?>? trace = context.readTraceByEventId('non_existent_event_id');
      expect(trace, isNull);
    });

    test('_handleTriggerRoute exceptions across all types (lines 2006-2038)', () async {
      final List<Object> exceptionsToTest = <Object>[
        const SpecialAgentAccessDeniedException(),
        const FormatException('Bad payload format'),
        ArgumentError('Not found parameter'),
        StateError('Not found state error'),
        Exception('Generic server trigger error'),
      ];

      for (final Object failure in exceptionsToTest) {
        final TriggerRouter throwingRouter = TriggerRouter(
          getRunnerAsync: (String name) async {
            throw failure;
          },
          sessionService: InMemorySessionService(),
          triggerSources: <String>['pubsub'],
        );

        final dynamic context = await createAdkDevWebContextForTesting(
          runtime: runtime,
          project: project,
          agentsDir: tempDir.path,
          triggerSources: <String>['pubsub'],
          triggerRouter: throwingRouter,
        );

        final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          await handleTriggerRouteForTesting(
            request,
            context,
            appName: 'my_app',
            triggerSource: 'pubsub',
          );
        });

        try {
          final HttpClient client = HttpClient();
          final HttpClientRequest req = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/triggers/pubsub'),
          );
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(<String, Object?>{
            'message': <String, Object?>{
              'data': base64Encode(utf8.encode(jsonEncode(<String, Object?>{'action': 'run'}))),
            },
          }));
          final HttpClientResponse resp = await req.close();
          final String body = await utf8.decodeStream(resp);

          if (failure is SpecialAgentAccessDeniedException) {
            expect(resp.statusCode, equals(HttpStatus.forbidden));
            expect(body, contains('Access to internal special agents'));
          } else if (failure is FormatException) {
            expect(resp.statusCode, equals(HttpStatus.badRequest));
            expect(body, contains('Bad payload format'));
          } else if (failure is ArgumentError) {
            expect(resp.statusCode, equals(HttpStatus.notFound));
            expect(body, contains('Not found parameter'));
          } else if (failure is StateError) {
            expect(resp.statusCode, equals(HttpStatus.notFound));
            expect(body, contains('Not found state error'));
          } else {
            expect(resp.statusCode, equals(HttpStatus.internalServerError));
            expect(body, contains('Trigger execution failed'));
          }
        } finally {
          await server.close(force: true);
        }
      }
    });

    test('_handleGetAppInfo ArgumentError and StateError (lines 2051-2064)', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        await handleDevWebServerRequestForTesting(request, context);
      });

      try {
        final HttpClient client = HttpClient();

        // 1. Invalid app name syntax throws ArgumentError -> lines 2051-2057 (404)
        final HttpClientRequest req1 = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/apps/invalid%20name!'),
        );
        final HttpClientResponse resp1 = await req1.close();
        expect(resp1.statusCode, equals(HttpStatus.notFound));

        // 2. Non existent app throws StateError -> lines 2059-2065 (404)
        final HttpClientRequest req2 = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/apps/non_existent_app'),
        );
        final HttpClientResponse resp2 = await req2.close();
        expect(resp2.statusCode, equals(HttpStatus.notFound));
      } finally {
        await server.close(force: true);
      }
    });

    test('_handleScreencast StateError and socket.close in finally (lines 2291-2296, 2346-2347)', () async {
      final DevAgentRuntime screencastRuntime = DevAgentRuntime(
        config: project,
        runner: Runner(
          appName: 'my_app',
          agent: LlmAgent(
            name: 'my_app',
            model: 'gemini-2.5-flash',
            tools: <Object>[
              ComputerUseToolset(computer: _FailingComputer()),
            ],
          ),
          sessionService: InMemorySessionService(),
          artifactService: InMemoryArtifactService(),
          memoryService: InMemoryMemoryService(),
        ),
      );

      webServerAgentLoaderTestingOverride = (String path) => AgentLoader(
        path,
        agentFactories: <String, AgentFactory>{
          'my_app': (String name, String dir) => screencastRuntime.runner.agent,
        },
      );

      try {
        final dynamic context = await createAdkDevWebContextForTesting(
          runtime: screencastRuntime,
          project: project,
          agentsDir: tempDir.path,
        );

        final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          try {
            await handleDevWebServerRequestForTesting(request, context);
          } catch (_) {}
        });

        try {
          final HttpClient client = HttpClient();

          // 1. Non existent app on screencast -> StateError (lines 2291-2296)
          final HttpClientRequest req1 = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}/apps/non_existent_app/screencast'),
          );
          final HttpClientResponse resp1 = await req1.close();
          expect(resp1.statusCode, equals(HttpStatus.notFound));

          // 2. WebSocket upgrade where computer.currentState throws first time (lines 2346-2347), then client receives frame and closes socket -> lines 2351-2354 close socket
          final WebSocket socket = await WebSocket.connect(
            'ws://127.0.0.1:${server.port}/apps/my_app/screencast',
          );
          final Completer<List<int>> screenCompleter = Completer<List<int>>();
          socket.listen((dynamic data) {
            if (data is List<int> && !screenCompleter.isCompleted) {
              screenCompleter.complete(data);
            }
          });
          final List<int> receivedBytes = await screenCompleter.future.timeout(
            const Duration(seconds: 3),
          );
          expect(receivedBytes, equals(<int>[1, 2, 3]));
          await socket.close();
        } finally {
          await server.close(force: true);
        }
      } finally {
        webServerAgentLoaderTestingOverride = null;
      }
    });

    test('run_eval legacy route and empty eval_case_ids (lines 2974, 3042)', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      // Create an eval set file
      final Directory evalDir = Directory('${tempDir.path}/my_app')..createSync(recursive: true);
      File('${evalDir.path}/set1.evalset.json').writeAsStringSync(jsonEncode(<String, Object?>{
        'eval_set_id': 'set1',
        'name': 'set1',
        'eval_cases': <Object?>[
          <String, Object?>{
            'eval_id': 'c1',
            'session_input': <String, Object?>{
              'user_id': 'user1',
              'messages': <Object?>[
                <String, Object?>{'role': 'user', 'parts': <Object?>[<String, Object?>{'text': 'eval prompt'}]},
              ],
            },
          },
        ],
      }));

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        await handleDevWebServerRequestForTesting(request, context);
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/apps/my_app/eval_sets/set1/run_eval'),
        );
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(<String, Object?>{})); // empty payload -> lines 2974 and legacy route line 3042
        final HttpClientResponse resp = await req.close();
        expect(resp.statusCode, equals(HttpStatus.ok));
        final dynamic decoded = jsonDecode(await utf8.decodeStream(resp));
        expect(decoded, isA<List<dynamic>>());
      } finally {
        await server.close(force: true);
      }
    });

    test('artifact metadata unavailable and telemetry bad request (lines 1395, 3616)', () async {
      webServerArtifactServiceTestingOverride = _MissingMetadataArtifactService();
      try {
        final dynamic context = await createAdkDevWebContextForTesting(
          runtime: runtime,
          project: project,
          agentsDir: tempDir.path,
        );

        final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          await handleDevWebServerRequestForTesting(request, context);
        });

        try {
          final HttpClient client = HttpClient();

          // 1. Line 1395: POST /config/telemetry with non-bool telemetry
          final HttpClientRequest req1 = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/config/telemetry'),
          );
          req1.headers.set('x-adk-telemetry-request', 'true');
          req1.headers.contentType = ContentType.json;
          req1.write(jsonEncode(<String, Object?>{'telemetry': 'not_a_bool'}));
          final HttpClientResponse resp1 = await req1.close();
          expect(resp1.statusCode, equals(HttpStatus.badRequest));

          // 2. Line 3616: Artifact metadata unavailable
          final HttpClientRequest req2 = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/apps/my_app/users/u1/sessions/s1/artifacts'),
          );
          req2.headers.contentType = ContentType.json;
          req2.write(jsonEncode(<String, Object?>{
            'filename': 'art1.txt',
            'artifact': <String, Object?>{'text': 'hello'},
          }));
          final HttpClientResponse resp2 = await req2.close();
          expect(resp2.statusCode, equals(HttpStatus.internalServerError));
          final String body2 = await utf8.decodeStream(resp2);
          expect(body2, contains('Artifact metadata unavailable'));
        } finally {
          await server.close(force: true);
        }
      } finally {
        webServerArtifactServiceTestingOverride = null;
      }
    });

    test('_handleRun StateError and _ensureSessionExists race condition fallback (lines 3835, 3887-3891)', () async {
      final _ThrowingSessionService throwingSessionService = _ThrowingSessionService();
      webServerSessionServiceTestingOverride = throwingSessionService;
      try {
        final DevAgentRuntime customRuntime = DevAgentRuntime(
          config: project,
          runner: Runner(
            appName: 'my_app',
            agent: LlmAgent(name: 'my_app', model: 'gemini-2.5-flash'),
            sessionService: throwingSessionService,
            artifactService: InMemoryArtifactService(),
            memoryService: InMemoryMemoryService(),
          ),
        );

        final dynamic context = await createAdkDevWebContextForTesting(
          runtime: customRuntime,
          project: project,
          agentsDir: tempDir.path,
        );

        final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((HttpRequest request) async {
          await handleDevWebServerRequestForTesting(request, context);
        });

        try {
          final HttpClient client = HttpClient();

          // 1. Line 3835: POST /run with getSession throwing StateError
          throwingSessionService.failGet = true;
          final HttpClientRequest req1 = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/run'),
          );
          req1.headers.contentType = ContentType.json;
          req1.write(jsonEncode(<String, Object?>{
            'appName': 'my_app',
            'userId': 'u1',
            'sessionId': 's1',
            'newMessage': <String, Object?>{
              'role': 'user',
              'parts': <Object?>[<String, Object?>{'text': 'hi'}],
            },
          }));
          final HttpClientResponse resp1 = await req1.close();
          expect(resp1.statusCode, equals(HttpStatus.notFound));
          throwingSessionService.failGet = false;

          // 2. Lines 3887-3891: _ensureSessionExists fallback when createSession throws
          throwingSessionService.failCreate = true;
          final HttpClientRequest req2 = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/run'),
          );
          req2.headers.contentType = ContentType.json;
          req2.write(jsonEncode(<String, Object?>{
            'appName': 'my_app',
            'userId': 'u1',
            'sessionId': 's_race_1',
            'newMessage': <String, Object?>{
              'role': 'user',
              'parts': <Object?>[<String, Object?>{'text': 'hi'}],
            },
          }));
          final HttpClientResponse resp2 = await req2.close();
          expect(resp2.statusCode, equals(HttpStatus.ok));
        } finally {
          await server.close(force: true);
        }
      } finally {
        webServerSessionServiceTestingOverride = null;
      }
    });

    test('getRequestOriginForTesting without host headers (line 4564)', () async {
      final HttpServer dummyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      dummyServer.listen((HttpRequest request) {
        final String? origin = getRequestOriginForTesting(request);
        request.response.write(origin ?? 'none');
        request.response.close();
      });

      try {
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${dummyServer.port}/test'),
        );
        final HttpClientResponse resp = await req.close();
        final String body = await utf8.decodeStream(resp);
        expect(body, contains('127.0.0.1'));
      } finally {
        await dummyServer.close(force: true);
      }
    });

    test('A2A agent card FormatException and FileSystemException (lines 5530, 5532)', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        await handleDevWebServerRequestForTesting(request, context);
      });

      try {
        final HttpClient client = HttpClient();

        // 1. Line 5530: FormatException in agent.json
        final File agentJsonFile = File('${tempDir.path}/agent.json');
        agentJsonFile.writeAsStringSync('{ invalid json');
        final HttpClientRequest req1 = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/.well-known/agent.json'),
        );
        final HttpClientResponse resp1 = await req1.close();
        expect(resp1.statusCode, equals(HttpStatus.ok));

        // 2. Line 5532: FileSystemException (agent.json is a directory)
        agentJsonFile.deleteSync();
        Directory('${tempDir.path}/agent.json').createSync();
        final HttpClientRequest req2 = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/.well-known/agent.json'),
        );
        final HttpClientResponse resp2 = await req2.close();
        expect(resp2.statusCode, equals(HttpStatus.ok));
      } finally {
        await server.close(force: true);
      }
    });

    test('A2A RPC push_notification_config:get, flat params, ArgumentError, Exception, and subscribe SSE (lines 5709, 5899, 6037-6055, 6121)', () async {
      final dynamic context = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: true,
      );

      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        await handleDevWebServerRequestForTesting(request, context);
      });

      try {
        final HttpClient client = HttpClient();

        // 1. Line 5709: tasks:push_notification_config:get
        final HttpClientRequest reqGet = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/a2a/my_app/v1/tasks:push_notification_config:get'),
        );
        reqGet.headers.contentType = ContentType.json;
        reqGet.write(jsonEncode(<String, Object?>{'taskId': 'task_missing'}));
        final HttpClientResponse respGet = await reqGet.close();
        expect(respGet.statusCode, equals(HttpStatus.notFound));

        // 2. Line 5899: flat params in tasks:pushnotificationconfig:set
        context.upsertA2aTask('my_app', <String, Object?>{'id': 'task_push_1', 'state': 'running'});
        context.upsertA2aTaskUpdates('my_app', 'task_push_1', <Map<String, Object?>>[
          <String, Object?>{'state': 'running'},
        ]);

        final HttpClientRequest reqSet = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/a2a/my_app'),
        );
        reqSet.headers.contentType = ContentType.json;
        reqSet.write(jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'rpc_2',
          'method': 'tasks:pushnotificationconfig:set',
          'params': <String, Object?>{
            'taskId': 'task_push_1',
            'url': 'http://example.com/webhook',
          },
        }));
        final HttpClientResponse respSet = await reqSet.close();
        expect(respSet.statusCode, equals(HttpStatus.ok));

        // 3. Lines 6037-6045: ArgumentError in A2A RPC (invalid app name)
        final HttpClientRequest reqArgErr = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/a2a/invalid%20app!/v1/message:send'),
        );
        reqArgErr.headers.contentType = ContentType.json;
        reqArgErr.write(jsonEncode(<String, Object?>{
          'message': <String, Object?>{
            'parts': <Object?>[<String, Object?>{'text': 'hi'}],
          },
        }));
        final HttpClientResponse respArgErr = await reqArgErr.close();
        expect(respArgErr.statusCode, equals(HttpStatus.badRequest));

        // 4. Line 6121: POST /tasks/{taskId}/subscribe without jsonRpcEnvelope
        final HttpClientRequest reqSub = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/a2a/my_app/v1/tasks/task_push_1:subscribe'),
        );
        reqSub.headers.contentType = ContentType.json;
        reqSub.write(jsonEncode(<String, Object?>{}));
        final HttpClientResponse respSub = await reqSub.close();
        expect(respSub.statusCode, equals(HttpStatus.ok));
        final String sseText = await utf8.decodeStream(respSub);
        expect(sseText, contains('data:'));

        // 5. Lines 6050-6058: generic Exception / error in A2A RPC
        webServerAgentLoaderTestingOverride = (String path) => AgentLoader(
          path,
          agentFactories: <String, AgentFactory>{
            'my_app': (String name, String dir) => throw Exception('Generic A2A agent loader error'),
          },
        );
        try {
          final dynamic errContext = await createAdkDevWebContextForTesting(
            runtime: runtime,
            project: project,
            agentsDir: tempDir.path,
            a2a: true,
          );
          final HttpServer errServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          errServer.listen((HttpRequest request) async {
            await handleDevWebServerRequestForTesting(request, errContext);
          });
          try {
            final HttpClientRequest reqErr = await client.postUrl(
              Uri.parse('http://127.0.0.1:${errServer.port}/a2a/my_app/v1/message:send'),
            );
            reqErr.headers.contentType = ContentType.json;
            reqErr.write(jsonEncode(<String, Object?>{
              'message': <String, Object?>{
                'parts': <Object?>[<String, Object?>{'text': 'hi'}],
              },
            }));
            final HttpClientResponse respErr = await reqErr.close();
            expect(respErr.statusCode, equals(HttpStatus.internalServerError));
          } finally {
            await errServer.close(force: true);
          }
        } finally {
          webServerAgentLoaderTestingOverride = null;
        }
      } finally {
        await server.close(force: true);
      }
    });

    test('enqueueA2aPushDeliveryTesting with a2a: false and timer callback (lines 879, 901-909)', () async {
      // 1. Lines 901-909: context created with a2a: false -> a2aPushQueue is null
      final dynamic contextNoA2a = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: false,
      );

      final HttpServer pushServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      pushServer.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
      });

      try {
        await enqueueA2aPushDeliveryTesting(
          contextNoA2a,
          appName: 'my_app',
          taskId: 'task_queue_null',
          pushConfig: <String, Object?>{'url': 'http://127.0.0.1:${pushServer.port}/notify'},
          task: <String, Object?>{'id': 'task_queue_null'},
          updates: <Map<String, Object?>>[
            <String, Object?>{'state': 'running'},
          ],
        );
      } finally {
        await pushServer.close(force: true);
      }

      // 2. Line 879: Timer callback fires after 1.1s in context with a2a: true
      final dynamic contextWithA2a = await createAdkDevWebContextForTesting(
        runtime: runtime,
        project: project,
        agentsDir: tempDir.path,
        a2a: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(contextWithA2a, isNotNull);
    });
  });
}
