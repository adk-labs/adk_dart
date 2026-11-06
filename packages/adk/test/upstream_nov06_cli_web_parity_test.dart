import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/cli/cli_eval.dart' as cli_eval;
import 'package:test/test.dart';

class _FailingSaveArtifactService extends InMemoryArtifactService {
  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    String? sessionId,
    required String filename,
    required Part artifact,
    Map<String, Object?>? customMetadata,
  }) async {
    throw StateError('Secret internal storage path /var/private/db failed');
  }
}

class _FailingTriggerModel extends BaseLlm {
  _FailingTriggerModel() : super(model: 'failing-trigger-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    throw Exception('Sensitive database password leaked in exception');
  }
}

class _SimpleReplyModel extends BaseLlm {
  _SimpleReplyModel() : super(model: 'simple-reply-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

class _StringBufferSink implements IOSink {
  final StringBuffer _buffer = StringBuffer();

  String get output => _buffer.toString();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async {
    await for (final List<int> chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<dynamic> close() async {}

  @override
  Future<dynamic> get done async {}

  @override
  Future<dynamic> flush() async {}

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
}

void main() {
  group('Upstream Nov 06 CLI & API Server Parity', () {
    test('3655990f6: validateAgentName and adk create reject non-identifiers and reserved keywords', () async {
      // Valid identifiers succeed.
      expect(() => validateAgentName('my_agent'), returnsNormally);
      expect(() => validateAgentName('_agent_2'), returnsNormally);

      // Non-identifiers are rejected.
      for (final String bad in <String>[
        '',
        '123agent',
        'my-agent',
        'my agent',
        'agent.v1',
        'agent/sub',
      ]) {
        expect(
          () => validateAgentName(bad),
          throwsArgumentError,
          reason: 'Expected "$bad" to be rejected as non-identifier',
        );
      }

      // Reserved keywords are rejected.
      for (final String keyword in <String>[
        'class',
        'def',
        'return',
        'import',
        'from',
        'async',
        'await',
        'True',
        'False',
        'None',
        'lambda',
      ]) {
        expect(
          () => validateAgentName(keyword),
          throwsArgumentError,
          reason: 'Expected keyword "$keyword" to be rejected',
        );
      }

      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_create_name_validation_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final String invalidDir = '${tempDir.path}/my-hyphen-agent';
      await expectLater(
        () => runCreateCommand(projectDir: invalidDir),
        throwsArgumentError,
      );
      expect(Directory(invalidDir).existsSync(), isFalse);

      final _StringBufferSink outSink = _StringBufferSink();
      final _StringBufferSink errSink = _StringBufferSink();
      final int exitCode = await runAdkCli(
        <String>['create', '${tempDir.path}/class'],
        outSink: outSink,
        errSink: errSink,
      );
      expect(exitCode, 1);
      expect(errSink.output, contains('cannot be a reserved keyword'));
    });

    test('f27b8f105: extractW3cTraceContext parses traceparent, tracestate, and baggage and server propagates them to trace spans', () async {
      final W3cTraceContext ctx = extractW3cTraceContext(<String, String>{
        'Traceparent':
            '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
        'Tracestate': 'congo=t61rcWkgMzE',
        'Baggage': 'userId=alice,serverNode=DF%2028;prop=1,env=prod',
      });
      expect(ctx.hasTraceContext, isTrue);
      expect(ctx.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(ctx.parentSpanId, '00f067aa0ba902b7');
      expect(ctx.traceFlags, '01');
      expect(ctx.tracestate, 'congo=t61rcWkgMzE');
      expect(ctx.hasBaggage, isTrue);
      expect(ctx.baggage, <String, String>{
        'userId': 'alice',
        'serverNode': 'DF 28',
        'env': 'prod',
      });

      // Invalid traceparent values are ignored cleanly.
      final W3cTraceContext invalidCtx = extractW3cTraceContext(<String, String>{
        'traceparent':
            'ff-00000000000000000000000000000000-0000000000000000-01',
      });
      expect(invalidCtx.hasTraceContext, isFalse);
      expect(invalidCtx.traceId, isNull);
      expect(invalidCtx.parentSpanId, isNull);

      // End-to-end HTTP server propagation on /run.
      const DevProjectConfig project = DevProjectConfig(
        appName: 'trace_app',
        agentName: 'assistant',
        description: 'Trace test project',
        userId: 'user_1',
      );
      final Agent agent = Agent(
        name: 'assistant',
        model: _SimpleReplyModel(),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Runner runner = Runner(
        appName: 'trace_app',
        agent: agent,
        sessionService: sessionService,
        autoCreateSession: true,
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: runner,
      );
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
      );
      try {
        final Uri baseUri = Uri.parse('http://127.0.0.1:${server.port}');
        final HttpClient client = HttpClient();
        try {
          final HttpClientRequest req = await client.postUrl(
            baseUri.replace(path: '/run'),
          );
          req.headers.contentType = ContentType.json;
          req.headers.set(
            'traceparent',
            '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
          );
          req.headers.set('baggage', 'tenant=acme,region=ap-northeast-2');
          req.write(
            jsonEncode(<String, Object?>{
              'app_name': 'trace_app',
              'user_id': 'user_1',
              'session_id': 'sess_w3c',
              'autoCreateSession': true,
              'new_message': <String, Object?>{
                'role': 'user',
                'parts': <Map<String, Object?>>[
                  <String, Object?>{'text': 'ping'},
                ],
              },
            }),
          );
          final HttpClientResponse res = await req.close();
          expect(res.statusCode, HttpStatus.ok);
          final List<dynamic> events =
              jsonDecode(await utf8.decoder.bind(res).join()) as List<dynamic>;
          expect(events, isNotEmpty);

          final HttpClientRequest traceReq = await client.getUrl(
            baseUri.replace(path: '/debug/trace/session/sess_w3c'),
          );
          final HttpClientResponse traceRes = await traceReq.close();
          expect(traceRes.statusCode, HttpStatus.ok);
          final List<dynamic> spans =
              jsonDecode(await utf8.decoder.bind(traceRes).join())
                  as List<dynamic>;
          expect(spans, isNotEmpty);
          final Map<String, dynamic> span =
              spans.first as Map<String, dynamic>;
          expect(span['trace_id'], '4bf92f3577b34da6a3ce929d0e0e4736');
          expect(span['parent_span_id'], '00f067aa0ba902b7');
          final Map<String, dynamic> attrs =
              span['attributes'] as Map<String, dynamic>;
          expect(attrs['baggage.tenant'], 'acme');
          expect(attrs['baggage.region'], 'ap-northeast-2');
        } finally {
          client.close(force: true);
        }
      } finally {
        await server.close(force: true);
        await runtime.runner.close();
      }
    });

    test('6507ad8da: saving artifact failure returns fixed detail string "Error saving artifact"', () async {
      const DevProjectConfig project = DevProjectConfig(
        appName: 'art_app',
        agentName: 'assistant',
        description: 'Artifact error test',
        userId: 'u1',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      webServerArtifactServiceTestingOverride = _FailingSaveArtifactService();
      addTearDown(() {
        webServerArtifactServiceTestingOverride = null;
      });

      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
      );
      try {
        final Uri baseUri = Uri.parse('http://127.0.0.1:${server.port}');
        final HttpClient client = HttpClient();
        try {
          final HttpClientRequest req = await client.postUrl(
            baseUri.replace(
              path: '/apps/art_app/users/u1/sessions/s1/artifacts',
            ),
          );
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode(<String, Object?>{
              'filename': 'test.txt',
              'artifact': <String, Object?>{'text': 'hello'},
            }),
          );
          final HttpClientResponse res = await req.close();
          expect(res.statusCode, HttpStatus.internalServerError);
          final Map<String, dynamic> body =
              jsonDecode(await utf8.decoder.bind(res).join())
                  as Map<String, dynamic>;
          expect(body['detail'], 'Error saving artifact');
          expect(body['error'], 'Error saving artifact');
          expect('${body['detail']}', isNot(contains('/var/private/db')));
        } finally {
          client.close(force: true);
        }
      } finally {
        await server.close(force: true);
        await runtime.runner.close();
      }
    });

    test('d61f4281d: trigger routes do not leak uncaught exception text to callers and TransientError stores cause', () async {
      final StateError rootCause = StateError('underlying quota failure');
      final TransientError transient = TransientError('429', rootCause);
      expect(transient.message, '429');
      expect(transient.cause, same(rootCause));

      const DevProjectConfig project = DevProjectConfig(
        appName: 'trig_app',
        agentName: 'assistant',
        description: 'Trigger error test',
        userId: 'u1',
      );
      final Agent failingAgent = Agent(
        name: 'assistant',
        model: _FailingTriggerModel(),
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Runner runner = Runner(
        appName: 'trig_app',
        agent: failingAgent,
        sessionService: sessionService,
      );
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: project,
        runner: runner,
      );
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
        triggerSources: const <String>['pubsub'],
      );
      try {
        final Uri baseUri = Uri.parse('http://127.0.0.1:${server.port}');
        final HttpClient client = HttpClient();
        try {
          final HttpClientRequest req = await client.postUrl(
            baseUri.replace(path: '/apps/trig_app/trigger/pubsub'),
          );
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode(<String, Object?>{
              'message': <String, Object?>{
                'data': base64Encode(utf8.encode('hello')),
                'messageId': 'm1',
              },
            }),
          );
          final HttpClientResponse res = await req.close();
          expect(res.statusCode, HttpStatus.internalServerError);
          final Map<String, dynamic> body =
              jsonDecode(await utf8.decoder.bind(res).join())
                  as Map<String, dynamic>;
          expect(body['detail'], 'Internal Server Error');
          expect(
            '${body['detail']}',
            isNot(contains('Sensitive database password')),
          );
        } finally {
          client.close(force: true);
        }
      } finally {
        await server.close(force: true);
        await runtime.runner.close();
      }
    });

    test('5c7a8297e: cli_eval exports PassKMultiRunCriterion and checkPassKCriteriaAgainstNumRuns', () {
      final MultiRunConfig multiRunConfig = MultiRunConfig(
        numRuns: 3,
        crossRunCriteria: <MultiRunCriterion>[
          cli_eval.PassKMultiRunCriterion(
            method: 'pass_at_k',
            k: 2,
            threshold: 0.75,
          ),
        ],
      );
      expect(
        () => cli_eval.checkPassKCriteriaAgainstNumRuns(multiRunConfig, 1),
        throwsArgumentError,
      );
      expect(
        () => cli_eval.checkPassKCriteriaAgainstNumRuns(multiRunConfig, 3),
        returnsNormally,
      );
    });
  });

  group('Upstream Nov 06 ADK Web UI & Dev Server Parity', () {
    test('7b59721 & 9438c88: buildArtifactUrlPath encodes reserved chars and artifact server routes decode them', () async {
      const String trickyName = 'dir/file#1?v=2%name with spaces:中文.txt';
      final String latestPath = buildArtifactUrlPath(
        appName: 'my_app',
        userId: 'u1',
        sessionId: 's1',
        artifactName: trickyName,
      );
      expect(
        latestPath,
        '/apps/my_app/users/u1/sessions/s1/artifacts/dir%2Ffile%231%3Fv%3D2%25name%20with%20spaces%3A%E4%B8%AD%E6%96%87.txt',
      );
      final String versionPath = buildArtifactUrlPath(
        appName: 'my_app',
        userId: 'u1',
        sessionId: 's1',
        artifactName: trickyName,
        versionId: 0,
      );
      expect(
        versionPath,
        '$latestPath/versions/0',
      );

      const DevProjectConfig project = DevProjectConfig(
        appName: 'my_app',
        agentName: 'assistant',
        description: 'Artifact encoding test',
        userId: 'u1',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: project);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: project,
        port: 0,
        enableWebUi: false,
      );
      try {
        final Uri baseUri = Uri.parse('http://127.0.0.1:${server.port}');
        final HttpClient client = HttpClient();
        try {
          // 1. Save artifact with reserved characters in filename.
          final HttpClientRequest saveReq = await client.postUrl(
            baseUri.replace(
              path: '/apps/my_app/users/u1/sessions/s1/artifacts',
            ),
          );
          saveReq.headers.contentType = ContentType.json;
          saveReq.write(
            jsonEncode(<String, Object?>{
              'filename': trickyName,
              'artifact': <String, Object?>{'text': 'special artifact payload'},
            }),
          );
          final HttpClientResponse saveRes = await saveReq.close();
          expect(saveRes.statusCode, HttpStatus.ok);
          await saveRes.drain<void>();

          // 2. Fetch latest artifact via percent-encoded URL path.
          final HttpClientRequest getLatestReq = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}$latestPath'),
          );
          final HttpClientResponse getLatestRes = await getLatestReq.close();
          expect(getLatestRes.statusCode, HttpStatus.ok);
          final Map<String, dynamic> latestJson =
              jsonDecode(await utf8.decoder.bind(getLatestRes).join())
                  as Map<String, dynamic>;
          expect(latestJson['text'], 'special artifact payload');

          // 3. Fetch specific artifact version via percent-encoded URL path.
          final HttpClientRequest getVerReq = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}$versionPath'),
          );
          final HttpClientResponse getVerRes = await getVerReq.close();
          expect(getVerRes.statusCode, HttpStatus.ok);
          final Map<String, dynamic> verJson =
              jsonDecode(await utf8.decoder.bind(getVerRes).join())
                  as Map<String, dynamic>;
          expect(verJson['text'], 'special artifact payload');
        } finally {
          client.close(force: true);
        }
      } finally {
        await server.close(force: true);
        await runtime.runner.close();
      }
    });

    test('60a516e: SseLineFramer carries partial run_sse lines across chunks and flushes on completion', () {
      final SseLineFramer framer = SseLineFramer();

      // Chunk 1 ends mid-JSON.
      final List<Map<String, Object?>> batch1 = framer.addTextChunk(
        'data: {"id":"evt_1","text":"hel',
      );
      expect(batch1, isEmpty);
      expect(framer.pendingPartialLine, 'data: {"id":"evt_1","text":"hel');

      // Chunk 2 finishes evt_1 with \r\n, emits evt_2 with \n, and starts evt_3 without a trailing newline.
      final List<Map<String, Object?>> batch2 = framer.addTextChunk(
        'lo"}\r\ndata: {"id":"evt_2","text":"world"}\n\ndata: {"id":"evt_3","partial":true}',
      );
      expect(batch2, <Map<String, Object?>>[
        <String, Object?>{'id': 'evt_1', 'text': 'hello'},
        <String, Object?>{'id': 'evt_2', 'text': 'world'},
      ]);
      expect(
        framer.pendingPartialLine,
        'data: {"id":"evt_3","partial":true}',
      );

      // Stream completion flushes evt_3 even without a trailing newline.
      final List<Map<String, Object?>> flushed = framer.flush();
      expect(flushed, <Map<String, Object?>>[
        <String, Object?>{'id': 'evt_3', 'partial': true},
      ]);
      expect(framer.pendingPartialLine, isEmpty);
    });

    test('ae60fcd: openExternalLinksInNewTabHtml opens HTTP/HTTPS links in new tab safely and preserves internal/non-http links', () {
      const String inputHtml = '''
<p>
  <a href="https://google.github.io/adk-docs/">Docs</a>
  <a href="http://example.com/test">HTTP</a>
  <a href="/relative/path">Relative</a>
  <a href="#section-1">Anchor</a>
  <a href="mailto:test@example.com">Email</a>
  <a href="javascript:alert(1)">Script</a>
</p>
''';
      final String outputHtml = openExternalLinksInNewTabHtml(inputHtml);
      expect(
        outputHtml,
        contains(
          '<a href="https://google.github.io/adk-docs/" target="_blank" rel="noopener noreferrer">Docs</a>',
        ),
      );
      expect(
        outputHtml,
        contains(
          '<a href="http://example.com/test" target="_blank" rel="noopener noreferrer">HTTP</a>',
        ),
      );
      expect(outputHtml, contains('<a href="/relative/path">Relative</a>'));
      expect(outputHtml, contains('<a href="#section-1">Anchor</a>'));
      expect(
        outputHtml,
        contains('<a href="mailto:test@example.com">Email</a>'),
      );
      expect(
        outputHtml,
        contains('<a href="javascript:alert(1)">Script</a>'),
      );
    });

    test('f62b82a: computeSystemInstructionFlagsByAgent scopes system-instruction change detection per agent', () {
      final List<Map<String, Object?>> spans = <Map<String, Object?>>[
        <String, Object?>{
          'label': 'call_llm',
          'start_time': 1,
          'attrEventId': 'e1',
          'attrAgentName': 'coordinator',
          'attrSystemInstruction': 'You are the coordinator.',
        },
        <String, Object?>{
          'label': 'call_llm',
          'start_time': 2,
          'attrEventId': 'e2',
          'attrAgentName': 'specialist',
          'attrSystemInstruction': 'You are the specialist.',
        },
        <String, Object?>{
          'label': 'call_llm',
          'start_time': 3,
          'attrEventId': 'e3',
          'attrAgentName': 'coordinator',
          'attrSystemInstruction': 'You are the coordinator.',
        },
        <String, Object?>{
          'label': 'call_llm',
          'start_time': 4,
          'attrEventId': 'e4',
          'attrAgentName': 'coordinator',
          'attrSystemInstruction': 'You are the updated coordinator.',
        },
      ];

      final List<Map<String, Object?>> evaluated =
          computeSystemInstructionFlagsByAgent(spans);
      // Crossing from coordinator -> specialist -> coordinator with unchanged per-agent instructions does NOT flag e2 or e3.
      expect(evaluated[0]['systemInstructionChanged'], isFalse);
      expect(evaluated[1]['systemInstructionChanged'], isFalse);
      expect(evaluated[2]['systemInstructionChanged'], isFalse);
      // Actual change within coordinator between e3 and e4 IS flagged.
      expect(evaluated[3]['systemInstructionChanged'], isTrue);
    });

    test('9512e34: computeSessionUsageMetadataSummary includes Cache Creation Tokens and Total Cache Creation Tokens', () {
      final Map<String, Object?> summary = computeSessionUsageMetadataSummary(
        <Map<String, Object?>>[
          <String, Object?>{
            'invocationId': 'inv_1',
            'timestamp': 1700000000,
            'modelVersion': 'gemini-2.5-pro',
            'cacheCreationTokenCount': 120,
            'usageMetadata': <String, Object?>{
              'promptTokenCount': 200,
              'cachedContentTokenCount': 50,
              'candidatesTokenCount': 80,
              'totalTokenCount': 330,
            },
          },
          <String, Object?>{
            'invocationId': 'inv_2',
            'timestamp': 1700000010,
            'modelVersion': 'gemini-2.5-pro',
            'usageMetadata': <String, Object?>{
              'promptTokenCount': 100,
              'cacheCreationTokenCount': 30,
              'candidatesTokenCount': 40,
              'totalTokenCount': 170,
            },
          },
        ],
      );

      final List<Map<String, Object?>> rows =
          summary['rows'] as List<Map<String, Object?>>;
      expect(
        rows,
        contains(
          equals(<String, Object?>{
            'key': 'Total Cache Creation Tokens',
            'value': 150,
          }),
        ),
      );
      final List<Map<String, Object?>> tableData =
          summary['tableData'] as List<Map<String, Object?>>;
      expect(tableData[0]['Cache Creation Tokens'], 120);
      expect(tableData[1]['Cache Creation Tokens'], 30);
      final List<String> columns = summary['displayedColumns'] as List<String>;
      expect(columns, contains('Cache Creation Tokens'));
    });

    test('Bundled browser main-NZEGJ4FM.js contains all Nov 06 adk-web updates', () async {
      final File bundleFile = File(
        'lib/src/cli/browser/main-NZEGJ4FM.js',
      );
      final String js = await bundleFile.readAsString();
      expect(
        js,
        contains(r'/artifacts/${encodeURIComponent(r)}'),
      );
      expect(
        js,
        contains('openExternalLinksInNewTab()'),
      );
      expect(
        js,
        contains('rel","noopener noreferrer"'),
      );
      expect(
        js,
        contains('"Cache Creation Tokens"'),
      );
    });
  });
}
