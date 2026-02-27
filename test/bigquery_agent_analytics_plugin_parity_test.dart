import 'dart:collection';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _RecordedHttpCall {
  _RecordedHttpCall({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _QueuedHttpClient extends http.BaseClient {
  _QueuedHttpClient({required List<http.Response> responses})
    : _responses = Queue<http.Response>.from(responses);

  final Queue<http.Response> _responses;
  final List<_RecordedHttpCall> recordedCalls = <_RecordedHttpCall>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_responses.isEmpty) {
      throw StateError('No queued response for ${request.url}.');
    }
    final http.Response response = _responses.removeFirst();
    final List<int> bodyBytes = await request.finalize().toBytes();
    recordedCalls.add(
      _RecordedHttpCall(
        uri: request.url,
        headers: Map<String, String>.from(request.headers),
        body: utf8.decode(bodyBytes),
      ),
    );
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(response.body)]),
      response.statusCode,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _FakeTool extends BaseTool {
  _FakeTool() : super(name: 'fake_tool', description: 'fake tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

InvocationContext _newInvocationContext({String invocationId = 'inv_bq'}) {
  final Agent rootAgent = Agent(
    name: 'root_agent',
    model: _NoopModel(),
    instruction: 'Root instruction',
  );

  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: rootAgent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  group('bigquery analytics plugin parity', () {
    test(
      'logs invocation and model/tool events with expected event types',
      () async {
        final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
        final BigQueryAgentAnalyticsPlugin plugin =
            BigQueryAgentAnalyticsPlugin(
              projectId: 'project',
              datasetId: 'dataset',
              sink: sink,
            );

        final InvocationContext invocationContext = _newInvocationContext();
        final CallbackContext callbackContext = Context(invocationContext);

        await plugin.beforeRunCallback(invocationContext: invocationContext);
        await plugin.beforeAgentCallback(
          agent: invocationContext.agent,
          callbackContext: callbackContext,
        );
        await plugin.beforeModelCallback(
          callbackContext: callbackContext,
          llmRequest: LlmRequest(
            model: 'gemini-2.5-flash',
            contents: <Content>[Content.userText('hello')],
          ),
        );
        await plugin.afterModelCallback(
          callbackContext: callbackContext,
          llmResponse: LlmResponse(content: Content.modelText('hi there')),
        );
        await plugin.beforeToolCallback(
          tool: _FakeTool(),
          toolArgs: <String, dynamic>{'q': 'hello'},
          toolContext: Context(invocationContext, functionCallId: 'fc_1'),
        );
        await plugin.afterToolCallback(
          tool: _FakeTool(),
          toolArgs: <String, dynamic>{'q': 'hello'},
          toolContext: Context(invocationContext, functionCallId: 'fc_1'),
          result: <String, dynamic>{'answer': 'ok'},
        );
        await plugin.afterAgentCallback(
          agent: invocationContext.agent,
          callbackContext: callbackContext,
        );
        await plugin.afterRunCallback(invocationContext: invocationContext);

        final List<String?> eventTypes = sink.rows
            .map((Map<String, Object?> row) => row['event_type'] as String?)
            .toList(growable: false);

        expect(eventTypes, contains('INVOCATION_STARTING'));
        expect(eventTypes, contains('AGENT_STARTING'));
        expect(eventTypes, contains('LLM_REQUEST'));
        expect(eventTypes, contains('LLM_RESPONSE'));
        expect(eventTypes, contains('TOOL_STARTING'));
        expect(eventTypes, contains('TOOL_COMPLETED'));
        expect(eventTypes, contains('AGENT_COMPLETED'));
        expect(eventTypes, contains('INVOCATION_COMPLETED'));
      },
    );

    test(
      'captures HITL request/completion events from content parts',
      () async {
        final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
        final BigQueryAgentAnalyticsPlugin plugin =
            BigQueryAgentAnalyticsPlugin(
              projectId: 'project',
              datasetId: 'dataset',
              sink: sink,
            );

        final InvocationContext invocationContext = _newInvocationContext(
          invocationId: 'inv_hitl',
        );

        await plugin.onEventCallback(
          invocationContext: invocationContext,
          event: Event(
            invocationId: 'inv_hitl',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'adk_request_confirmation',
                  args: <String, dynamic>{'reason': 'approve?'},
                ),
                Part.fromFunctionResponse(
                  name: 'adk_request_confirmation',
                  response: <String, dynamic>{'approved': true},
                ),
              ],
            ),
          ),
        );

        await plugin.onUserMessageCallback(
          invocationContext: invocationContext,
          userMessage: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'adk_request_input',
                response: <String, dynamic>{'text': 'final answer'},
              ),
            ],
          ),
        );

        final List<String?> eventTypes = sink.rows
            .map((Map<String, Object?> row) => row['event_type'] as String?)
            .toList(growable: false);

        expect(eventTypes, contains('HITL_CONFIRMATION_REQUEST'));
        expect(eventTypes, contains('HITL_CONFIRMATION_REQUEST_COMPLETED'));
        expect(eventTypes, contains('HITL_INPUT_REQUEST_COMPLETED'));
      },
    );

    test('respects allowlist/denylist gating', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
        config: BigQueryLoggerConfig(
          eventAllowlist: <String>['LLM_REQUEST'],
          eventDenylist: <String>['TOOL_STARTING'],
        ),
      );

      final InvocationContext invocationContext = _newInvocationContext(
        invocationId: 'inv_filters',
      );
      final CallbackContext callbackContext = Context(invocationContext);

      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: LlmRequest(model: 'gemini', contents: <Content>[]),
      );
      await plugin.beforeToolCallback(
        tool: _FakeTool(),
        toolArgs: <String, dynamic>{},
        toolContext: Context(invocationContext, functionCallId: 'fc_1'),
      );

      final List<String?> eventTypes = sink.rows
          .map((Map<String, Object?> row) => row['event_type'] as String?)
          .toList(growable: false);

      expect(eventTypes, <String?>['LLM_REQUEST']);
    });

    test('native insertAll sink batches rows with auth header', () async {
      final _QueuedHttpClient httpClient = _QueuedHttpClient(
        responses: <http.Response>[http.Response('{}', 200)],
      );
      final BigQueryInsertAllEventSink sink = BigQueryInsertAllEventSink(
        projectId: 'project',
        datasetId: 'dataset',
        tableId: 'agent_events',
        maxBatchSize: 2,
        httpClient: httpClient,
        accessTokenProvider: () async => 'token-123',
      );

      await sink.append(<String, Object?>{'event_type': 'A', 'value': 1});
      await sink.append(<String, Object?>{'event_type': 'B', 'value': 2});
      await sink.close();

      expect(httpClient.recordedCalls, hasLength(1));
      final _RecordedHttpCall call = httpClient.recordedCalls.single;
      expect(call.uri.toString(), contains('/insertAll'));
      expect(call.headers['authorization'], 'Bearer token-123');
      final Map<String, Object?> payload = (jsonDecode(call.body) as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final List<Object?> rows = payload['rows'] as List<Object?>;
      expect(rows, hasLength(2));
      final Map<String, Object?> firstRow = (rows.first as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      expect((firstRow['json'] as Map)['event_type'], 'A');
    });

    test('plugin can use native insertAll sink', () async {
      final _QueuedHttpClient httpClient = _QueuedHttpClient(
        responses: <http.Response>[
          http.Response('{}', 200),
          http.Response('{}', 200),
        ],
      );
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        useBigQueryInsertAllSink: true,
        accessToken: 'token-xyz',
        httpClient: httpClient,
        config: BigQueryLoggerConfig(batchSize: 1),
      );

      final InvocationContext context = _newInvocationContext(
        invocationId: 'inv_native',
      );
      await plugin.beforeRunCallback(invocationContext: context);
      await plugin.afterRunCallback(invocationContext: context);

      expect(httpClient.recordedCalls.length, greaterThanOrEqualTo(2));
      expect(
        httpClient.recordedCalls.first.headers['authorization'],
        'Bearer token-xyz',
      );
    });
  });
}
