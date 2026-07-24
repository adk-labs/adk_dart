// Unit tests for recent adk-python upstream feature syncs and bug fixes.
library;

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('1. RunConfig user labels', () {
    test('RunConfig labels are stored and copied via copyWith', () {
      final RunConfig config = RunConfig(
        labels: <String, String>{
          'billing_id': 'proj-123',
          'environment': 'prod',
        },
      );

      expect(config.labels, <String, String>{
        'billing_id': 'proj-123',
        'environment': 'prod',
      });

      final RunConfig copied = config.copyWith(
        labels: <String, String>{
          'billing_id': 'proj-456',
        },
      );
      expect(copied.labels, <String, String>{'billing_id': 'proj-456'});
    });

    test('BasicLlmRequestProcessor merges RunConfig labels into LlmRequest', () async {
      final LlmAgent agent = LlmAgent(
        name: 'test_agent',
        model: 'gemini-1.5-flash',
        generateContentConfig: GenerateContentConfig(
          labels: <String, String>{'agent_label': 'val1'},
        ),
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );

      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-1',
        agent: agent,
        session: session,
        runConfig: RunConfig(
          labels: <String, String>{
            'goog-originating-logical-product-id': 'prod1',
          },
        ),
      );

      final LlmRequest llmRequest = LlmRequest();
      final BasicLlmRequestProcessor processor = BasicLlmRequestProcessor();

      await for (final Event _ in processor.runAsync(invocationContext, llmRequest)) {}

      expect(llmRequest.config.labels, <String, String>{
        'agent_label': 'val1',
        'goog-originating-logical-product-id': 'prod1',
      });
    });
  });

  group('2. AnthropicLlm finish_reason mapping', () {
    test('toGoogleFinishReason maps all stop_reason variants accurately', () {
      expect(AnthropicLlm.toGoogleFinishReason('end_turn'), 'STOP');
      expect(AnthropicLlm.toGoogleFinishReason('stop_sequence'), 'STOP');
      expect(AnthropicLlm.toGoogleFinishReason('tool_use'), 'STOP');
      expect(AnthropicLlm.toGoogleFinishReason('pause_turn'), 'STOP');
      expect(AnthropicLlm.toGoogleFinishReason('max_tokens'), 'MAX_TOKENS');
      expect(AnthropicLlm.toGoogleFinishReason('refusal'), 'SAFETY');
      expect(AnthropicLlm.toGoogleFinishReason(null), null);
      expect(AnthropicLlm.toGoogleFinishReason('unknown_reason'), 'FINISH_REASON_UNSPECIFIED');
    });
  });

  group('3. VertexAiSessionService dual filter', () {
    test('afterTimestamp is preserved when GetSessionConfig also specifies numRecentEvents', () {
      final GetSessionConfig config = GetSessionConfig(
        numRecentEvents: 5,
        afterTimestamp: 1700000000.0,
      );

      expect(config.numRecentEvents, 5);
      expect(config.afterTimestamp, 1700000000.0);
    });
  });

  group('4. BigQueryAgentAnalyticsPlugin finalResponseToolNames', () {
    test('logs AGENT_RESPONSE when a completed tool matches finalResponseToolNames', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryLoggerConfig config = BigQueryLoggerConfig(
        finalResponseToolNames: <String>{'submit_final_response'},
      );

      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'test-project',
        datasetId: 'test-dataset',
        config: config,
        sink: sink,
        useBigQueryInsertAllSink: false,
      );

      final BaseTool tool = FunctionTool(
        name: 'submit_final_response',
        description: 'Submit final response to user',
        func: (Map<String, dynamic> args) => 'done',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );

      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-1',
        agent: LlmAgent(name: 'agent', model: 'gemini-1.5-flash'),
        session: session,
      );

      final ToolContext toolContext = ToolContext(invocationContext);

      await plugin.afterToolCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'answer': 'The result is 42.'},
        toolContext: toolContext,
        result: <String, dynamic>{'status': 'SUCCESS'},
      );

      await plugin.flush();

      final List<Map<String, Object?>> rows = sink.rows;
      final List<String> eventTypes = rows.map((r) => r['event_type'] as String).toList();

      expect(eventTypes, contains('TOOL_COMPLETED'));
      expect(eventTypes, contains('AGENT_RESPONSE'));

      final Map<String, Object?> agentResponseRow = rows.firstWhere(
        (r) => r['event_type'] == 'AGENT_RESPONSE',
      );
      expect(agentResponseRow['content'].toString(), contains('The result is 42.'));
    });

    test('does not log AGENT_RESPONSE for unlisted tools', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryLoggerConfig config = BigQueryLoggerConfig(
        finalResponseToolNames: <String>{'submit_final_response'},
      );

      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'test-project',
        datasetId: 'test-dataset',
        config: config,
        sink: sink,
        useBigQueryInsertAllSink: false,
      );

      final BaseTool tool = FunctionTool(
        name: 'other_tool',
        description: 'Helper tool',
        func: (Map<String, dynamic> args) => 'done',
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
      );

      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-1',
        agent: LlmAgent(name: 'agent', model: 'gemini-1.5-flash'),
        session: session,
      );

      final ToolContext toolContext = ToolContext(invocationContext);

      await plugin.afterToolCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'query': 'search'},
        toolContext: toolContext,
        result: <String, dynamic>{'status': 'SUCCESS'},
      );

      await plugin.flush();

      final List<Map<String, Object?>> rows = sink.rows;
      final List<String> eventTypes = rows.map((r) => r['event_type'] as String).toList();

      expect(eventTypes, contains('TOOL_COMPLETED'));
      expect(eventTypes, isNot(contains('AGENT_RESPONSE')));
    });
  });
}
