import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:adk/src/dev/cli.dart';
import 'package:test/test.dart';

class _CaptureSink {
  _CaptureSink() : _controller = StreamController<List<int>>() {
    _controller.stream.listen(_bytes.addAll);
    sink = IOSink(_controller.sink);
  }

  final StreamController<List<int>> _controller;
  final List<int> _bytes = <int>[];
  late final IOSink sink;

  Future<String> closeAndRead() async {
    await sink.flush();
    await sink.close();
    await _controller.done;
    return utf8.decode(_bytes);
  }
}

class _Part7StubModel extends BaseLlm {
  _Part7StubModel() : super(model: 'part7-stub-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('part7 stub response'));
  }
}


class _Part7LiveHoldAgent extends BaseAgent {
  _Part7LiveHoldAgent({required super.name});

  final Completer<void> holdCompleter = Completer<void>();

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(invocationId: 'inv_hold_async', author: name);
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(invocationId: 'inv_hold_live', author: name);
    await holdCompleter.future;
  }
}

void main() {
  setUpAll(() {
    LLMRegistry.register(
      supportedModels: <RegExp>[
        RegExp(r'^part7-stub-model$'),
        RegExp(r'^gemini-2\.5-flash$'),
      ],
      factory: (String m) => _Part7StubModel(),
    );
  });

  group('Part 7 Coverage: web_server & cli final branches', () {
    test('web_server eval storage URI parsing and directory resolution', () {
      final Directory tempDir = Directory.systemTemp.createTempSync('web_eval_res_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. memory://
      final Object? memManagers = resolveEvalManagersTesting(
        baseDir: tempDir.path,
        evalStorageUri: 'memory://',
      );
      expect(memManagers, isNotNull);

      // 2. gs://
      final Object? gcsManagers = resolveEvalManagersTesting(
        baseDir: tempDir.path,
        evalStorageUri: 'gs://my-bucket/evals',
      );
      expect(gcsManagers, isNotNull);

      // 3. file:// valid
      final Object? fileManagers = resolveEvalManagersTesting(
        baseDir: tempDir.path,
        evalStorageUri: 'file://${tempDir.path}',
      );
      expect(fileManagers, isNotNull);

      // 4. file:// with non-local authority -> ArgumentError
      expect(
        () => resolveEvalManagersTesting(
          baseDir: tempDir.path,
          evalStorageUri: 'file://remote-host/path',
        ),
        throwsArgumentError,
      );

      // 5. file:// with empty path -> ArgumentError
      expect(
        () => resolveEvalManagersTesting(
          baseDir: tempDir.path,
          evalStorageUri: 'file://',
        ),
        throwsArgumentError,
      );

      // 6. unsupported scheme -> ArgumentError
      expect(
        () => resolveEvalManagersTesting(
          baseDir: tempDir.path,
          evalStorageUri: 'ftp://ftp.example.com/dir',
        ),
        throwsArgumentError,
      );

      // 7. empty candidate -> baseDir
      final Object? baseManagers = resolveEvalManagersTesting(
        baseDir: tempDir.path,
        evalStorageUri: '   ',
      );
      expect(baseManagers, isNotNull);
    });

    test('web_server internal parsing helpers and serializers', () {
      // 1. _parseNodeStatus variants
      expect(parseNodeStatusForTesting(NodeStatus.running), NodeStatus.running);
      expect(parseNodeStatusForTesting(0), NodeStatus.values[0]);
      expect(parseNodeStatusForTesting('0'), NodeStatus.values[0]);
      expect(parseNodeStatusForTesting(999), isNull);
      expect(parseNodeStatusForTesting('NodeStatus.completed'), NodeStatus.completed);
      expect(parseNodeStatusForTesting('in-progress'), isNull);
      expect(parseNodeStatusForTesting('invalid_status_xyz'), isNull);
      expect(parseNodeStatusForTesting(null), isNull);

      // 2. _parseQueryBool variants
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 1}, const <String>['flag']), isTrue);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 0}, const <String>['flag']), isFalse);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': '1'}, const <String>['flag']), isTrue);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'true'}, const <String>['flag']), isTrue);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'yes'}, const <String>['flag']), isTrue);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'y'}, const <String>['flag']), isTrue);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': '0'}, const <String>['flag']), isFalse);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'false'}, const <String>['flag']), isFalse);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'no'}, const <String>['flag']), isFalse);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'n'}, const <String>['flag']), isFalse);
      expect(parseQueryBoolForTesting(<String, dynamic>{'flag': 'other'}, const <String>['flag']), isNull);
      expect(parseQueryBoolForTesting(<String, dynamic>{}, const <String>['flag']), isNull);

      // 3. _isTruthy and _stripOptionalQuotes
      expect(isTruthyForTesting('true'), isTrue);
      expect(isTruthyForTesting('1'), isTrue);
      expect(isTruthyForTesting('yes'), isTrue);
      expect(isTruthyForTesting('y'), isTrue);
      expect(isTruthyForTesting('no'), isFalse);
      expect(isTruthyForTesting(null), isFalse);

      expect(stripOptionalQuotesForTesting('"hello"'), 'hello');
      expect(stripOptionalQuotesForTesting('hello'), 'hello');
      expect(stripOptionalQuotesForTesting('""'), '');
      expect(stripOptionalQuotesForTesting(''), '');

      // 4. _normalizeUrlPrefix
      expect(normalizeUrlPrefixForTesting('/api/'), '/api');
      expect(normalizeUrlPrefixForTesting('/api'), '/api');
      expect(normalizeUrlPrefixForTesting('/'), isNull);
      expect(() => normalizeUrlPrefixForTesting('no-leading-slash'), throwsArgumentError);

      // 5. _contentTypeForFile
      expect(contentTypeForFileTesting('index.html').mimeType, 'text/html');
      expect(contentTypeForFileTesting('main.js').mimeType, 'application/javascript');
      expect(contentTypeForFileTesting('style.css').mimeType, 'text/css');
      expect(contentTypeForFileTesting('icon.svg').mimeType, 'image/svg+xml');
      expect(contentTypeForFileTesting('data.json').mimeType, 'application/json');
      expect(contentTypeForFileTesting('image.png').mimeType, 'image/png');
      expect(contentTypeForFileTesting('photo.jpg').mimeType, 'image/jpeg');
      expect(contentTypeForFileTesting('photo.jpeg').mimeType, 'image/jpeg');
      expect(contentTypeForFileTesting('image.webp').mimeType, 'image/webp');
      expect(contentTypeForFileTesting('font.woff2').mimeType, 'font/woff2');
      expect(contentTypeForFileTesting('other.bin').mimeType, 'application/octet-stream');

      // 6. _evalMetricFromName
      expect(evalMetricFromNameTesting('final_response_exact_match'), EvalMetric.finalResponseExactMatch);
      expect(evalMetricFromNameTesting('finalresponseexactmatch'), EvalMetric.finalResponseExactMatch);
      expect(evalMetricFromNameTesting('final_response_contains'), EvalMetric.finalResponseContains);
      expect(evalMetricFromNameTesting('finalresponsecontains'), EvalMetric.finalResponseContains);
      expect(evalMetricFromNameTesting('unknown_metric'), isNull);

      // 7. _parseRunEvalMetrics
      final List<EvalMetric> parsed1 = parseRunEvalMetricsTesting(<String, dynamic>{
        'eval_metrics': <dynamic>[
          'final_response_exact_match',
          <String, dynamic>{'metric_name': 'final_response_contains'},
          <String, dynamic>{'name': 'final_response_exact_match'},
          'unknown',
        ],
      });
      expect(parsed1.length, 3);

      final List<EvalMetric> parsedEmpty = parseRunEvalMetricsTesting(<String, dynamic>{
        'eval_metrics': <dynamic>['unknown'],
      });
      expect(parsedEmpty, <EvalMetric>[EvalMetric.finalResponseExactMatch]);

      // 8. _parseContentPart and _contentPartToJson
      // FunctionCall
      final Part pCall = parseContentPartTesting(<String, dynamic>{
        'function_call': <String, dynamic>{
          'name': 'calc',
          'args': <String, dynamic>{'x': 10},
          'id': 'call_1',
        },
      });
      expect(pCall.functionCall?.name, 'calc');
      expect(pCall.functionCall?.id, 'call_1');
      final Map<String, Object?> callJson = contentPartToJsonTesting(pCall);
      expect(callJson.containsKey('function_call'), isTrue);

      // FunctionResponse
      final Part pResp = parseContentPartTesting(<String, dynamic>{
        'function_response': <String, dynamic>{
          'name': 'calc',
          'response': <String, dynamic>{'res': 20},
          'id': 'call_1',
        },
      });
      expect(pResp.functionResponse?.name, 'calc');
      final Map<String, Object?> respJson = contentPartToJsonTesting(pResp);
      expect(respJson.containsKey('function_response'), isTrue);

      // InlineData with base64
      final String b64 = base64Encode(utf8.encode('image-bytes'));
      final Part pInline1 = parseContentPartTesting(<String, dynamic>{
        'inline_data': <String, dynamic>{
          'mime_type': 'image/png',
          'data': b64,
          'display_name': 'MyImage',
        },
      });
      expect(pInline1.inlineData?.mimeType, 'image/png');
      expect(utf8.decode(pInline1.inlineData!.data), 'image-bytes');
      final Map<String, Object?> inlineJson = contentPartToJsonTesting(pInline1);
      expect(inlineJson.containsKey('inline_data'), isTrue);

      // InlineData with raw string not valid base64 (falls back to utf8.encode)
      final Part pInline2 = parseContentPartTesting(<String, dynamic>{
        'inline_data': <String, dynamic>{
          'data': 'non-base64-text-data!',
        },
      });
      expect(utf8.decode(pInline2.inlineData!.data), 'non-base64-text-data!');

      // InlineData with list of ints
      final Part pInline3 = parseContentPartTesting(<String, dynamic>{
        'inline_data': <String, dynamic>{
          'data': <int>[65, 66, 67],
        },
      });
      expect(utf8.decode(pInline3.inlineData!.data), 'ABC');

      // FileData
      final Part pFile = parseContentPartTesting(<String, dynamic>{
        'file_data': <String, dynamic>{
          'file_uri': 'gs://bucket/file.pdf',
          'mime_type': 'application/pdf',
          'display_name': 'Doc',
        },
      });
      expect(pFile.fileData?.fileUri, 'gs://bucket/file.pdf');
      final Map<String, Object?> fileJson = contentPartToJsonTesting(pFile);
      expect(fileJson.containsKey('file_data'), isTrue);

      // 9. A2A part serialization & deserialization
      final A2aPart a2aTextMeta = A2aPart.text('hello', metadata: <String, Object?>{'tag': 'greet'});
      final Map<String, Object?> a2aTextJson = a2aPartToJsonTesting(a2aTextMeta);
      expect(a2aTextJson['metadata'], <String, Object?>{'tag': 'greet'});
      final A2aPart restoredText = a2aPartFromJsonTesting(a2aTextJson);
      expect(restoredText.textPart?.text, 'hello');

      final A2aPart a2aFileUri = A2aPart.fileUri(
        'https://example.com/doc.pdf',
        mimeType: 'application/pdf',
        metadata: <String, Object?>{'owner': 'user'},
      );
      final Map<String, Object?> a2aUriJson = a2aPartToJsonTesting(a2aFileUri);
      expect(a2aUriJson['kind'], 'file');
      final A2aPart restoredUri = a2aPartFromJsonTesting(a2aUriJson);
      expect(restoredUri.filePart?.file is A2aFileWithUri, isTrue);

      final A2aPart a2aFileBytes = A2aPart.fileBytes(
        'base64bytes',
        mimeType: 'text/plain',
        metadata: <String, Object?>{'owner': 'agent'},
      );
      final Map<String, Object?> a2aBytesJson = a2aPartToJsonTesting(a2aFileBytes);
      expect(a2aBytesJson['kind'], 'file');
      final A2aPart restoredBytes = a2aPartFromJsonTesting(a2aBytesJson);
      expect(restoredBytes.filePart?.file is A2aFileWithBytes, isTrue);

      // 10. Origin / CORS header helpers
      expect(originAllowedTesting('https://app.example.com', <String>['regex:https://.*\\.example\\.com']), isTrue);
      expect(originAllowedTesting('https://evil.com', <String>['regex:https://.*\\.example\\.com']), isFalse);
      expect(originAllowedTesting('https://app.example.com', <String>['regex:']), isFalse);
    });

    test('web_server dev routes: build_graph, build_graph_image, debug traces', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('web_dev_routes_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'dev_route_agent',
        agentName: 'dev_route_agent',
        description: 'dev route agent test',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        port: 0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      });

      // 1. GET /dev/build_graph/{appName}
      final HttpClientRequest reqGraph = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/build_graph/dev_route_agent'),
      );
      final HttpClientResponse respGraph = await reqGraph.close();
      expect(respGraph.statusCode, HttpStatus.ok);
      final String graphBody = await utf8.decoder.bind(respGraph).join();
      expect(jsonDecode(graphBody), isA<Map<String, dynamic>>());

      // 2. GET /dev/build_graph_image/{appName}
      final HttpClientRequest reqImg = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/build_graph_image/dev_route_agent'),
      );
      final HttpClientResponse respImg = await reqImg.close();
      expect(respImg.statusCode, anyOf(HttpStatus.ok, HttpStatus.notFound));
      await respImg.drain<void>();

      // 3. GET /dev/apps/{appName}/build_graph
      final HttpClientRequest reqAppGraph = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/dev_route_agent/build_graph'),
      );
      final HttpClientResponse respAppGraph = await reqAppGraph.close();
      expect(respAppGraph.statusCode, HttpStatus.ok);
      await respAppGraph.drain<void>();

      // 4. GET /dev/apps/{appName}/build_graph_image
      final HttpClientRequest reqAppImg = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/dev_route_agent/build_graph_image'),
      );
      final HttpClientResponse respAppImg = await reqAppImg.close();
      expect(respAppImg.statusCode, anyOf(HttpStatus.ok, HttpStatus.notFound));
      await respAppImg.drain<void>();

      // 5. GET /dev/apps/{appName}/debug/trace/{event_id} (missing -> 404)
      final HttpClientRequest reqTraceEvt = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/dev_route_agent/debug/trace/non_existent_evt'),
      );
      final HttpClientResponse respTraceEvt = await reqTraceEvt.close();
      expect(respTraceEvt.statusCode, HttpStatus.notFound);
      await respTraceEvt.drain<void>();

      // 6. GET /dev/apps/{appName}/debug/trace/session/{session_id}
      final HttpClientRequest reqTraceSess = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/dev_route_agent/debug/trace/session/non_existent_sess'),
      );
      final HttpClientResponse respTraceSess = await reqTraceSess.close();
      expect(respTraceSess.statusCode, HttpStatus.ok);
      final String sessTraceBody = await utf8.decoder.bind(respTraceSess).join();
      expect(jsonDecode(sessTraceBody), <dynamic>[]);

      // 7. Forwarding /dev/apps/{appName}/... to standard python routes
      final HttpClientRequest reqDevAppsFwd = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev/apps/dev_route_agent/users/u1/sessions'),
      );
      final HttpClientResponse respDevAppsFwd = await reqDevAppsFwd.close();
      expect(respDevAppsFwd.statusCode, HttpStatus.ok);
      await respDevAppsFwd.drain<void>();
    });

    test('web_server eventarc trigger, bad JSON and error handling', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('web_trigger_evt_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'trigger_test_agent',
        agentName: 'trigger_test_agent',
        description: 'trigger test agent',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        port: 0,
        triggerSources: const <String>['pubsub', 'eventarc'],
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      });

      // 1. POST /apps/{appName}/trigger/eventarc with CloudEvents headers
      final HttpClientRequest reqEventarc = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/trigger_test_agent/trigger/eventarc'),
      );
      reqEventarc.headers.set('ce-id', 'evt_123');
      reqEventarc.headers.set('ce-type', 'google.cloud.storage.object.v1.finalized');
      reqEventarc.headers.set('ce-source', '//storage.googleapis.com/projects/_/buckets/my-bucket');
      reqEventarc.headers.set('content-type', 'application/json');
      reqEventarc.write(jsonEncode(<String, dynamic>{
        'bucket': 'my-bucket',
        'name': 'data.csv',
      }));
      final HttpClientResponse respEventarc = await reqEventarc.close();
      expect(respEventarc.statusCode, HttpStatus.ok);
      final String evtBody = await utf8.decoder.bind(respEventarc).join();
      expect(jsonDecode(evtBody), isA<Map<String, dynamic>>());

      // 2. POST /apps/{appName}/trigger/eventarc with invalid JSON body -> 400 FormatException
      final HttpClientRequest reqBadJson = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/trigger_test_agent/trigger/eventarc'),
      );
      reqBadJson.headers.set('content-type', 'application/json');
      reqBadJson.write('invalid-json{{{');
      final HttpClientResponse respBadJson = await reqBadJson.close();
      expect(respBadJson.statusCode, HttpStatus.badRequest);
      await respBadJson.drain<void>();

      // 3. POST /apps/{appName}/trigger/unsupported -> 404
      final HttpClientRequest reqUnknown = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/trigger_test_agent/trigger/unsupported'),
      );
      reqUnknown.write('{}');
      final HttpClientResponse respUnknown = await reqUnknown.close();
      expect(respUnknown.statusCode, HttpStatus.notFound);
      await respUnknown.drain<void>();
    });

    test('web_server A2A task routes, cancel, subscribe, pushnotificationconfig and errors', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('web_a2a_rpc_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'a2a_rpc_agent',
        agentName: 'a2a_rpc_agent',
        description: 'a2a rpc agent',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        port: 0,
        a2a: true,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      });

      // 1. tasks:cancel on non-existent task -> -32004 / ok with jsonrpc envelope
      final HttpClientRequest reqCancelNotFound = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_rpc_agent/v1/tasks/missing_task_123:cancel'),
      );
      reqCancelNotFound.headers.set('content-type', 'application/json');
      reqCancelNotFound.write(jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'rpc_1',
        'method': 'tasks/cancel',
        'params': <String, dynamic>{'taskId': 'missing_task_123'},
      }));
      final HttpClientResponse respCancelNotFound = await reqCancelNotFound.close();
      expect(respCancelNotFound.statusCode, HttpStatus.ok);
      final String cancelNotFoundBody = await utf8.decoder.bind(respCancelNotFound).join();
      expect(cancelNotFoundBody, contains('-32004'));

      // 1b. tasks:cancel without jsonrpc envelope -> 404
      final HttpClientRequest reqCancelPlain = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_rpc_agent/v1/tasks/missing_task_123:cancel'),
      );
      reqCancelPlain.headers.set('content-type', 'application/json');
      reqCancelPlain.write('{}');
      final HttpClientResponse respCancelPlain = await reqCancelPlain.close();
      expect(respCancelPlain.statusCode, HttpStatus.notFound);
      await respCancelPlain.drain<void>();

      // 2. tasks:subscribe on non-existent task -> -32004 / ok with jsonrpc envelope
      final HttpClientRequest reqSubNotFound = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_rpc_agent/v1/tasks/missing_sub_123:subscribe'),
      );
      reqSubNotFound.headers.set('content-type', 'application/json');
      reqSubNotFound.write(jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'rpc_2',
        'method': 'tasks/subscribe',
        'params': <String, dynamic>{'taskId': 'missing_sub_123'},
      }));
      final HttpClientResponse respSubNotFound = await reqSubNotFound.close();
      expect(respSubNotFound.statusCode, HttpStatus.ok);
      await respSubNotFound.drain<void>();

      // 3. GET /a2a/a2a_rpc_agent/v1/tasks/missing_task_123/pushnotificationconfigs -> -32004
      final HttpClientRequest reqPushGet = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_rpc_agent/v1/tasks/missing_task_123/pushnotificationconfigs'),
      );
      final HttpClientResponse respPushGet = await reqPushGet.close();
      expect(respPushGet.statusCode, HttpStatus.notFound);
      await respPushGet.drain<void>();

      // 4. Unknown RPC method -> -32601 Method Not Found
      final HttpClientRequest reqUnknownRpc = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_rpc_agent'),
      );
      reqUnknownRpc.headers.set('content-type', 'application/json');
      reqUnknownRpc.write(jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'rpc_4',
        'method': 'non_existent_rpc_method',
      }));
      final HttpClientResponse respUnknownRpc = await reqUnknownRpc.close();
      expect(respUnknownRpc.statusCode, HttpStatus.ok);
      final String unknownBody = await utf8.decoder.bind(respUnknownRpc).join();
      expect(jsonDecode(unknownBody)['error']['code'], -32601);

      // 5. Malformed JSON RPC request -> -32602 Bad Request
      final HttpClientRequest reqBadRpc = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/a2a/a2a_rpc_agent'),
      );
      reqBadRpc.headers.set('content-type', 'application/json');
      reqBadRpc.write('bad-json-rpc{');
      final HttpClientResponse respBadRpc = await reqBadRpc.close();
      expect(respBadRpc.statusCode, HttpStatus.badRequest);
      await respBadRpc.drain<void>();
    });

    test('web_server legacy routes and artifact HTTP error codes', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('web_legacy_art_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'legacy_art_agent',
        agentName: 'legacy_art_agent',
        description: 'legacy art agent',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        port: 0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      });

      // 1. GET /api/sessions (legacy list sessions)
      final HttpClientRequest reqListSess = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions'),
      );
      final HttpClientResponse respListSess = await reqListSess.close();
      expect(respListSess.statusCode, HttpStatus.ok);
      final String listSessBody = await utf8.decoder.bind(respListSess).join();
      expect(jsonDecode(listSessBody)['sessions'], isA<List<dynamic>>());

      // 2. GET /api/sessions/missing_sess/events -> 404
      final HttpClientRequest reqGetEvts = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions/missing_sess/events'),
      );
      final HttpClientResponse respGetEvts = await reqGetEvts.close();
      expect(respGetEvts.statusCode, HttpStatus.notFound);
      await respGetEvts.drain<void>();

      // 3. POST /api/sessions/sess_123/messages with empty text -> 400
      final HttpClientRequest reqEmptyMsg = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/sessions/sess_123/messages'),
      );
      reqEmptyMsg.headers.set('content-type', 'application/json');
      reqEmptyMsg.write(jsonEncode(<String, dynamic>{'text': ''}));
      final HttpClientResponse respEmptyMsg = await reqEmptyMsg.close();
      expect(respEmptyMsg.statusCode, HttpStatus.badRequest);
      await respEmptyMsg.drain<void>();

      // 4. Artifact routes with invalid version id -> 400
      final HttpClientRequest reqBadVer = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/legacy_art_agent/users/u1/sessions/s1/artifacts/art1/versions/not_a_number'),
      );
      final HttpClientResponse respBadVer = await reqBadVer.close();
      expect(respBadVer.statusCode, HttpStatus.badRequest);
      await respBadVer.drain<void>();

      // 5. Artifact route with version not found -> 404
      final HttpClientRequest reqMissingVer = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/legacy_art_agent/users/u1/sessions/s1/artifacts/art1/versions/999'),
      );
      final HttpClientResponse respMissingVer = await reqMissingVer.close();
      expect(respMissingVer.statusCode, HttpStatus.notFound);
      await respMissingVer.drain<void>();

      // 6. Artifact route method not allowed -> 405
      final HttpClientRequest reqMethodNotAllowed = await client.deleteUrl(
        Uri.parse('http://127.0.0.1:${server.port}/apps/legacy_art_agent/users/u1/sessions/s1/artifacts'),
      );
      final HttpClientResponse respMethodNotAllowed = await reqMethodNotAllowed.close();
      expect(respMethodNotAllowed.statusCode, HttpStatus.methodNotAllowed);
      await respMethodNotAllowed.drain<void>();
    });

    test('web_server dev-ui routes, redirects, config and SPA fallback', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('web_dev_ui_proj_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'dev_ui_agent',
        agentName: 'dev_ui_agent',
        description: 'dev ui agent test',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        logoText: 'Test Logo',
        logoImageUrl: 'http://example.com/logo.png',
        avatarConfig: <String, String>{'dev_ui_agent': 'http://example.com/avatar.png'},
        port: 0,
      );
      final HttpClient client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await runtime.runner.close();
      });

      // 1. Root / redirects to /dev-ui/
      final HttpClientRequest reqRoot = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      reqRoot.followRedirects = false;
      final HttpClientResponse respRoot = await reqRoot.close();
      expect(respRoot.statusCode, HttpStatus.found);
      expect(respRoot.headers.value('location'), '/dev-ui/');
      await respRoot.drain<void>();

      // 2. /dev-ui redirects to /dev-ui/
      final HttpClientRequest reqDevUi = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui'),
      );
      reqDevUi.followRedirects = false;
      final HttpClientResponse respDevUi = await reqDevUi.close();
      expect(respDevUi.statusCode, HttpStatus.found);
      expect(respDevUi.headers.value('location'), '/dev-ui/');
      await respDevUi.drain<void>();

      // 3. /dev-ui/config returns config JSON
      final HttpClientRequest reqConfig = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/config'),
      );
      final HttpClientResponse respConfig = await reqConfig.close();
      expect(respConfig.statusCode, HttpStatus.ok);
      final String configBody = await utf8.decoder.bind(respConfig).join();
      expect(jsonDecode(configBody)['logo_text'], 'Test Logo');

      // 4. /dev-ui/assets/config/runtime-config.json
      final HttpClientRequest reqRuntimeConf = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/assets/config/runtime-config.json'),
      );
      final HttpClientResponse respRuntimeConf = await reqRuntimeConf.close();
      expect(respRuntimeConf.statusCode, HttpStatus.ok);
      final String runtimeBody = await utf8.decoder.bind(respRuntimeConf).join();
      expect(jsonDecode(runtimeBody), isA<Map<String, dynamic>>());

      // 5. /dev-ui/foo..bar -> 400 Bad Request
      final HttpClientRequest reqBadPath = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/foo..bar'),
      );
      final HttpClientResponse respBadPath = await reqBadPath.close();
      expect(respBadPath.statusCode, HttpStatus.badRequest);
      await respBadPath.drain<void>();

      // 6. /dev-ui/index.html -> serves index.html
      final HttpClientRequest reqHtml = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/index.html'),
      );
      final HttpClientResponse respHtml = await reqHtml.close();
      expect(respHtml.statusCode, HttpStatus.ok);
      expect(respHtml.headers.contentType?.mimeType, 'text/html');
      await respHtml.drain<void>();

      // 7. /dev-ui/dashboard/settings (SPA route) -> serves index.html
      final HttpClientRequest reqSpa = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/dashboard/settings'),
      );
      final HttpClientResponse respSpa = await reqSpa.close();
      expect(respSpa.statusCode, HttpStatus.ok);
      expect(respSpa.headers.contentType?.mimeType, 'text/html');
      await respSpa.drain<void>();

      // 8. /dev-ui/missing_image.png (missing asset with extension) -> 404
      final HttpClientRequest reqMissing = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/dev-ui/missing_image.png'),
      );
      final HttpClientResponse respMissing = await reqMissing.close();
      expect(respMissing.statusCode, HttpStatus.notFound);
      await respMissing.drain<void>();
    });

    test('web_server WebSocket live limits: message size and max sessions', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('web_live_limits_');
      addTearDown(() => projectDir.deleteSync(recursive: true));

      final DevProjectConfig config = DevProjectConfig(
        appName: 'live_limits_agent',
        agentName: 'live_limits_agent',
        description: 'live limits agent',
      );
      final _Part7LiveHoldAgent holdAgent = _Part7LiveHoldAgent(name: 'live_limits_agent');
      final InMemoryRunner holdRunner = InMemoryRunner(agent: holdAgent, appName: 'live_limits_agent');
      final DevAgentRuntime runtime = DevAgentRuntime(config: config, runner: holdRunner);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        port: 0,
        autoCreateSession: true,
        maxLiveMessageBytes: 100, // Small limit for testing
        maxLiveSessions: 1,       // Allow only 1 concurrent session
      );
      addTearDown(() async {
        if (!holdAgent.holdCompleter.isCompleted) {
          holdAgent.holdCompleter.complete();
        }
        await server.close(force: true);
        await runtime.runner.close();
      });

      // First WebSocket connection succeeds with required query params
      final WebSocket ws1 = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/run_live?app_name=live_limits_agent&user_id=u1&session_id=s1',
      );
      ws1.listen((_) {}, onError: (_) {});

      // Second WebSocket connection should be rejected with 503 (too many concurrent sessions)
      final HttpClient client = HttpClient();
      final HttpClientRequest req2 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/run_live?app_name=live_limits_agent&user_id=u2&session_id=s2'),
      );
      req2.headers.set('Connection', 'Upgrade');
      req2.headers.set('Upgrade', 'websocket');
      req2.headers.set('Sec-WebSocket-Version', '13');
      req2.headers.set('Sec-WebSocket-Key', 'x3JJHMbDL1EzLkh9GBhXDw==');
      final HttpClientResponse resp2 = await req2.close();
      expect(resp2.statusCode, HttpStatus.serviceUnavailable);
      await resp2.drain<void>();
      client.close(force: true);

      // Sending a message larger than 100 bytes on ws1 should close with messageTooBig (1009)
      final String largeMsg = jsonEncode(<String, dynamic>{
        'text': 'A' * 200,
      });
      ws1.add(largeMsg);
      await ws1.done;
      expect(ws1.closeCode, WebSocketStatus.messageTooBig);
      if (!holdAgent.holdCompleter.isCompleted) {
        holdAgent.holdCompleter.complete();
      }
    });

    test('cli top-level error catches: FileSystemException, FormatException, StateError, ArgumentError', () async {
      // 1. FileSystemException -> exit 1
      final _CaptureSink errFs = _CaptureSink();
      final int codeFs = await runAdkCli(
        <String>['run', '/non_existent_folder_path_12345/sub/file.yaml'],
        errSink: errFs.sink,
      );
      expect(codeFs, 1);
      final String textFs = await errFs.closeAndRead();
      expect(textFs, contains('Filesystem error:'));

      // 2. FormatException -> exit 1 (passing JSON list to --sampler_config_file_path expecting JSON object)
      final Directory tempDir = Directory.systemTemp.createTempSync('cli_fmt_err_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: tempDir.path);
      final File badSampler = File('${tempDir.path}${Platform.pathSeparator}bad_sampler.json');
      badSampler.writeAsStringSync('[1, 2, 3]');

      final _CaptureSink errFmt = _CaptureSink();
      final int codeFmt = await runAdkCli(
        <String>[
          'optimize',
          tempDir.path,
          '--sampler_config_file_path',
          badSampler.path,
        ],
        errSink: errFmt.sink,
      );
      expect(codeFmt, 1);
      final String textFmt = await errFmt.closeAndRead();
      expect(textFmt, contains('Config parse error:'));

      // 3. StateError -> exit 1 (eval set not found)
      final _CaptureSink errState = _CaptureSink();
      final int codeState = await runAdkCli(
        <String>['eval', tempDir.path, 'non_existent_eval_set_xyz'],
        errSink: errState.sink,
      );
      expect(codeState, 1);
      final String textState = await errState.closeAndRead();
      expect(textState, contains('Runtime error:'));

      // 4. ArgumentError -> exit 1 (unsupported eval storage URI)
      final _CaptureSink errArg = _CaptureSink();
      final int codeArg = await runAdkCli(
        <String>['eval', tempDir.path, 'default_set', '--eval_storage_uri', 'ftp://unsupported'],
        errSink: errArg.sink,
      );
      expect(codeArg, 1);
      final String textArg = await errArg.closeAndRead();
      expect(textArg, contains('Argument error:'));
    });

    test('cli helper formatting: displayHost IPv6 and writeRunEvents edge cases', () {
      // 1. IPv6 display host
      final InternetAddress v6 = InternetAddress('::1');
      expect(displayHostForTesting(v6), '[::1]');
      final InternetAddress v4 = InternetAddress('127.0.0.1');
      expect(displayHostForTesting(v4), '127.0.0.1');

      // 2. _writeRunEvents with session: null
      final _CaptureSink sinkJsonl = _CaptureSink();
      final Event evt = Event(
        invocationId: 'inv_1',
        author: 'model',
        content: Content.modelText('test jsonl text'),
        actions: EventActions(stateDelta: <String, Object?>{'x': 1}),
      );
      writeRunEventsForTesting(<Event>[evt], out: sinkJsonl.sink, jsonl: true, session: null);

      // 3. _writeEventTexts with no text response
      final _CaptureSink sinkNoText = _CaptureSink();
      final Event evtNoText = Event(
        invocationId: 'inv_2',
        author: 'system',
        content: Content(role: 'model', parts: <Part>[]),
      );
      writeRunEventsForTesting(<Event>[evtNoText], out: sinkNoText.sink, jsonl: false, session: null);
    });

    test('cli interactive run loop: empty line, exit, quit and null', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('cli_interactive_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final List<String?> inputs = <String?>[
        '',      // empty line: loops
        'hello', // valid message
        'quit',  // exit condition
      ];
      int inputIdx = 0;
      final _CaptureSink outSink = _CaptureSink();

      final int code = await runAdkCli(
        <String>['run', projectDir.path],
        outSink: outSink.sink,
        readLine: () {
          if (inputIdx < inputs.length) {
            return inputs[inputIdx++];
          }
          return null;
        },
      );
      expect(code, 0);
      final String output = await outSink.closeAndRead();
      expect(output, contains('[user]: '));
    });

    test('cli conformance replay mismatches: event count, content and format', () async {
      final Directory projectDir = Directory.systemTemp.createTempSync('conf_mismatches_app_');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      await createDevProject(projectDirPath: projectDir.path);

      final DevProjectConfig config = DevProjectConfig(
        appName: 'test_conf_agent',
        agentName: 'test_conf_agent',
        description: 'conformance test agent',
      );
      final DevAgentRuntime runtime = DevAgentRuntime(config: config);
      final HttpServer server = await startAdkDevWebServer(
        runtime: runtime,
        project: config,
        agentsDir: projectDir.path,
        port: 0,
      );
      addTearDown(() async {
        await server.close(force: true);
        await runtime.runner.close();
      });

      final Directory specsDir = Directory.systemTemp.createTempSync('conf_mismatches_specs_');
      addTearDown(() => specsDir.deleteSync(recursive: true));

      final Directory testCaseDir = Directory('${specsDir.path}${Platform.pathSeparator}core${Platform.pathSeparator}case1');
      testCaseDir.createSync(recursive: true);

      // Spec with 0 user messages so replay tests only the session comparison logic
      File('${testCaseDir.path}${Platform.pathSeparator}spec.yaml').writeAsStringSync('''
agent: test_conf_agent
description: Replay mismatch verification
user_messages: []
''');
      File('${testCaseDir.path}${Platform.pathSeparator}generated-recordings.yaml').writeAsStringSync('recordings: []\n');

      // 1. Invalid format (List instead of Map) in generated-session.yaml -> format error
      File('${testCaseDir.path}${Platform.pathSeparator}generated-session.yaml').writeAsStringSync('''
- item1
- item2
''');

      final _CaptureSink out1 = _CaptureSink();
      final int code1 = await runAdkCli(
        <String>[
          'conformance',
          'test',
          specsDir.path,
          '--mode',
          'replay',
          '--streaming_mode',
          'none',
          '--base_url',
          'http://127.0.0.1:${server.port}',
        ],
        outSink: out1.sink,
      );
      expect(code1, 1);
      final String text1 = await out1.closeAndRead();
      expect(text1, contains('Recorded session file format is invalid.'));

      // 2. Event count mismatch
      File('${testCaseDir.path}${Platform.pathSeparator}generated-session.yaml').writeAsStringSync('''
events:
  - id: e1
    author: user
''');
      final _CaptureSink out2 = _CaptureSink();
      final int code2 = await runAdkCli(
        <String>[
          'conformance',
          'test',
          specsDir.path,
          '--mode',
          'replay',
          '--streaming_mode',
          'none',
          '--base_url',
          'http://127.0.0.1:${server.port}',
        ],
        outSink: out2.sink,
      );
      expect(code2, 1);
      final String text2 = await out2.closeAndRead();
      expect(text2, contains('Event count mismatch'));

      // 3. Session map content mismatch
      File('${testCaseDir.path}${Platform.pathSeparator}generated-session.yaml').writeAsStringSync('''
events: []
user_id: different_recorded_user_xyz
''');
      final _CaptureSink out3 = _CaptureSink();
      final int code3 = await runAdkCli(
        <String>[
          'conformance',
          'test',
          specsDir.path,
          '--mode',
          'replay',
          '--streaming_mode',
          'none',
          '--base_url',
          'http://127.0.0.1:${server.port}',
        ],
        outSink: out3.sink,
      );
      expect(code3, 1);
      final String text3 = await out3.closeAndRead();
      expect(text3, contains('session mismatch'));
    });
  });
}
