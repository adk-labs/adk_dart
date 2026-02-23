import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

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
  });
}
