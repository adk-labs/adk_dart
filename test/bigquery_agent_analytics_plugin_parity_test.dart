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

    test('logs final visible agent responses', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
      );

      final InvocationContext invocationContext = _newInvocationContext(
        invocationId: 'inv_agent_response',
      );
      await plugin.onEventCallback(
        invocationContext: invocationContext,
        event: Event(
          id: 'event_final',
          invocationId: 'inv_agent_response',
          author: 'root_agent',
          branch: 'branch_1',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.text('visible answer'),
              Part.text('internal thought', thought: true),
            ],
          ),
        ),
      );

      final Map<String, Object?> row = sink.rows.singleWhere(
        (Map<String, Object?> row) => row['event_type'] == 'AGENT_RESPONSE',
      );
      final Map<String, Object?> content = Map<String, Object?>.from(
        row['content']! as Map,
      );
      expect(content['response'], contains('visible answer'));
      expect(content['response'], isNot(contains('internal thought')));

      final Map<String, Object?> attributes =
          (jsonDecode(row['attributes'] as String) as Map).map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
      expect(attributes['source_event_id'], 'event_final');
      expect(attributes['source_event_author'], 'root_agent');
      expect(attributes['source_event_branch'], 'branch_1');
    });

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

    test('native insertAll sink serializes cyclic rows safely', () async {
      final _QueuedHttpClient httpClient = _QueuedHttpClient(
        responses: <http.Response>[http.Response('{}', 200)],
      );
      final BigQueryInsertAllEventSink sink = BigQueryInsertAllEventSink(
        projectId: 'project',
        datasetId: 'dataset',
        tableId: 'agent_events',
        httpClient: httpClient,
        accessTokenProvider: () async => 'token-123',
      );
      final Map<String, Object?> cyclicPayload = <String, Object?>{
        'value': 'kept',
      };
      cyclicPayload['self'] = cyclicPayload;

      await sink.append(<String, Object?>{
        'event_type': 'A',
        'payload': cyclicPayload,
      });
      await sink.close();

      final Map<String, Object?> payload =
          (jsonDecode(httpClient.recordedCalls.single.body) as Map).map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
      final List<Object?> rows = payload['rows'] as List<Object?>;
      final Map<String, Object?> row = (rows.single as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Map<String, Object?> json = (row['json'] as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Map<String, Object?> loggedPayload = (json['payload'] as Map).map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );

      expect(loggedPayload['value'], 'kept');
      expect(loggedPayload['self'], '[cycle detected]');
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

    test('default sink is native insertAll sink', () {
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
      );
      expect(plugin.sink, isA<BigQueryInsertAllEventSink>());
    });

    test('logs multimodal content_parts when enabled', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
        config: BigQueryLoggerConfig(logMultiModalContent: true),
      );

      final InvocationContext invocationContext = _newInvocationContext(
        invocationId: 'inv_content_parts_enabled',
      );
      await plugin.onUserMessageCallback(
        invocationContext: invocationContext,
        userMessage: Content(
          role: 'user',
          parts: <Part>[
            Part.text('hello'),
            Part.fromInlineData(mimeType: 'image/png', data: <int>[1, 2, 3]),
          ],
        ),
      );

      expect(sink.rows, hasLength(1));
      final List<Object?> parts =
          sink.rows.first['content_parts'] as List<Object?>;
      expect(parts, isNotEmpty);
    });

    test('offloads inline media content_parts to GCS references', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final List<Map<String, Object?>> uploads = <Map<String, Object?>>[];
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
        config: BigQueryLoggerConfig(
          gcsBucketName: 'bucket',
          connectionId: 'connection',
          gcsUploadProvider:
              ({
                required List<int> data,
                required String contentType,
                required String path,
              }) async {
                uploads.add(<String, Object?>{
                  'data': List<int>.from(data),
                  'contentType': contentType,
                  'path': path,
                });
                return 'gs://bucket/$path';
              },
        ),
      );

      await plugin.onUserMessageCallback(
        invocationContext: _newInvocationContext(invocationId: 'inv_gcs'),
        userMessage: Content(
          role: 'user',
          parts: <Part>[
            Part.fromInlineData(mimeType: 'image/png', data: <int>[1, 2, 3]),
          ],
        ),
      );

      expect(uploads, hasLength(1));
      expect(uploads.single['data'], <int>[1, 2, 3]);
      expect(uploads.single['contentType'], 'image/png');
      expect(uploads.single['path'], endsWith('.png'));

      final List<Object?> parts =
          sink.rows.first['content_parts'] as List<Object?>;
      final Map<String, Object?> part = parts.single as Map<String, Object?>;
      expect(part['storage_mode'], 'GCS_REFERENCE');
      expect(part['uri'], startsWith('gs://bucket/'));
      expect(part['text'], '[MEDIA OFFLOADED]');

      final Map<String, Object?> objectRef =
          part['object_ref'] as Map<String, Object?>;
      expect(objectRef['authorizer'], 'connection');
      expect(objectRef['uri'], part['uri']);
      expect(objectRef['details'], contains('image/png'));
    });

    test('omits multimodal content_parts when disabled', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
        config: BigQueryLoggerConfig(logMultiModalContent: false),
      );

      final InvocationContext invocationContext = _newInvocationContext(
        invocationId: 'inv_content_parts_disabled',
      );
      await plugin.onUserMessageCallback(
        invocationContext: invocationContext,
        userMessage: Content.userText('hello'),
      );

      expect(sink.rows, hasLength(1));
      final List<Object?> parts =
          sink.rows.first['content_parts'] as List<Object?>;
      expect(parts, isEmpty);
    });

    test('content formatter failure does not drop event', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
        config: BigQueryLoggerConfig(
          contentFormatter: (Object? _, String _) {
            throw StateError('formatter failed');
          },
        ),
      );

      final InvocationContext invocationContext = _newInvocationContext(
        invocationId: 'inv_formatter_error',
      );
      final CallbackContext callbackContext = Context(invocationContext);
      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('hello')],
        ),
      );

      expect(sink.rows, hasLength(1));
      expect(sink.rows.first['event_type'], 'LLM_REQUEST');
      expect(sink.rows.first['content'], isNull);
      expect(sink.rows.first['content_parts'], isEmpty);
    });

    test('marks cyclic analytics payloads as truncated', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final Map<String, Object?> cyclicPayload = <String, Object?>{
        'value': 'kept',
      };
      cyclicPayload['self'] = cyclicPayload;
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: sink,
        config: BigQueryLoggerConfig(
          contentFormatter: (Object? _, String _) => cyclicPayload,
        ),
      );

      await plugin.beforeModelCallback(
        callbackContext: Context(_newInvocationContext()),
        llmRequest: LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('hello')],
        ),
      );

      final Map<String, Object?> content = Map<String, Object?>.from(
        sink.rows.single['content']! as Map,
      );
      expect(content['value'], 'kept');
      expect(content['self'], '[cycle detected]');
      expect(sink.rows.single['is_truncated'], isTrue);
    });

    test('creates analytics views on startup when enabled', () async {
      final List<List<String>> capturedStatements = <List<String>>[];
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: InMemoryBigQueryEventSink(),
        analyticsViewExecutor: (List<String> statements) async {
          capturedStatements.add(List<String>.from(statements));
        },
      );

      await plugin.beforeRunCallback(
        invocationContext: _newInvocationContext(invocationId: 'inv_views'),
      );

      expect(capturedStatements, hasLength(1));
      expect(
        capturedStatements.single.first,
        contains(
          'CREATE OR REPLACE VIEW `project.dataset.v_invocation_starting`',
        ),
      );
      expect(
        capturedStatements.single.last,
        contains("WHERE event_type = 'HITL_INPUT_REQUEST_COMPLETED'"),
      );
    });

    test('create views can be disabled via config override', () async {
      int createCalls = 0;
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: InMemoryBigQueryEventSink(),
        analyticsViewExecutor: (List<String> statements) async {
          createCalls += 1;
        },
        configOverrides: <String, Object?>{'create_views': false},
      );

      await plugin.beforeRunCallback(
        invocationContext: _newInvocationContext(invocationId: 'inv_no_views'),
      );

      expect(createCalls, 0);
    });

    test(
      'manual analytics view refresh replays generated statements',
      () async {
        final List<List<String>> capturedStatements = <List<String>>[];
        final BigQueryAgentAnalyticsPlugin plugin =
            BigQueryAgentAnalyticsPlugin(
              projectId: 'project',
              datasetId: 'dataset',
              sink: InMemoryBigQueryEventSink(),
              analyticsViewExecutor: (List<String> statements) async {
                capturedStatements.add(List<String>.from(statements));
              },
            );

        await plugin.beforeRunCallback(
          invocationContext: _newInvocationContext(invocationId: 'inv_refresh'),
        );
        await plugin.createAnalyticsViews();

        expect(capturedStatements, hasLength(2));
        expect(capturedStatements[0], isNotEmpty);
        expect(capturedStatements[1], equals(capturedStatements[0]));
      },
    );

    test('treats concurrent analytics view conflicts as non-fatal', () async {
      int createCalls = 0;
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'project',
        datasetId: 'dataset',
        sink: InMemoryBigQueryEventSink(),
        analyticsViewExecutor: (List<String> statements) async {
          createCalls += 1;
          throw StateError('HTTP 409 Conflict');
        },
      );

      await plugin.beforeRunCallback(
        invocationContext: _newInvocationContext(invocationId: 'inv_conflict'),
      );
      await plugin.createAnalyticsViews();

      expect(createCalls, 2);
    });
  });
}
