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

InvocationContext _newInvocationContext() {
  final LlmAgent agent = LlmAgent(
    name: 'root_agent',
    model: _NoopModel(),
    disallowTransferToParent: true,
    disallowTransferToPeers: true,
  );
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_auto_trace',
    agent: agent,
    session: Session(id: 'session_1', appName: 'app', userId: 'user_1'),
  );
}

void main() {
  test('records run, agent, model, and tool spans', () async {
    final AdkTracer localTracer = AdkTracer();
    final AutoTracingPlugin plugin = AutoTracingPlugin(tracer: localTracer);
    final InvocationContext invocationContext = _newInvocationContext();
    final Context callbackContext = Context(invocationContext);
    final ToolContext toolContext = Context(
      invocationContext,
      functionCallId: 'fn_1',
    );
    final BaseTool tool = _FakeTool();

    await plugin.beforeRunCallback(invocationContext: invocationContext);
    await plugin.beforeAgentCallback(
      agent: invocationContext.agent,
      callbackContext: callbackContext,
    );
    await plugin.beforeModelCallback(
      callbackContext: callbackContext,
      llmRequest: LlmRequest(model: 'gemini-test'),
    );
    await plugin.afterModelCallback(
      callbackContext: callbackContext,
      llmResponse: LlmResponse(
        content: Content.modelText('hello'),
        finishReason: 'STOP',
      ),
    );
    await plugin.beforeToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{'city': 'Seoul'},
      toolContext: toolContext,
    );
    await plugin.afterToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{'city': 'Seoul'},
      toolContext: toolContext,
      result: <String, dynamic>{'weather': 'sunny'},
    );
    await plugin.afterAgentCallback(
      agent: invocationContext.agent,
      callbackContext: callbackContext,
    );
    await plugin.afterRunCallback(invocationContext: invocationContext);

    final List<TraceSpanRecord> spans = localTracer.finishedSpans;
    expect(spans.map((TraceSpanRecord span) => span.name), <String>[
      'adk.model gemini-test',
      'adk.tool fake_tool',
      'adk.agent root_agent',
      'adk.run root_agent',
    ]);
    expect(spans[0].attributes['adk.auto_tracing.kind'], 'model');
    expect(spans[0].attributes['gen_ai.request.model'], 'gemini-test');
    expect(spans[0].attributes['gen_ai.response.finish_reasons'], <String>[
      'stop',
    ]);
    expect(spans[1].attributes['gen_ai.tool.name'], 'fake_tool');
    expect(spans[1].attributes['adk.fn.arg.tool_args'], contains('Seoul'));
    expect(spans[2].attributes['gen_ai.operation.name'], 'invoke_agent');
    expect(spans[3].attributes['gcp.vertex.agent.session_id'], 'session_1');
  });

  test('afterRun closes leaked short-circuited model spans', () async {
    final AdkTracer localTracer = AdkTracer();
    final AutoTracingPlugin plugin = AutoTracingPlugin(tracer: localTracer);
    final InvocationContext invocationContext = _newInvocationContext();
    final Context callbackContext = Context(invocationContext);

    await plugin.beforeRunCallback(invocationContext: invocationContext);
    await plugin.beforeModelCallback(
      callbackContext: callbackContext,
      llmRequest: LlmRequest(model: 'cached-model'),
    );

    await plugin.afterRunCallback(invocationContext: invocationContext);

    final List<TraceSpanRecord> spans = localTracer.finishedSpans;
    expect(spans.map((TraceSpanRecord span) => span.name), <String>[
      'adk.model cached-model',
      'adk.run root_agent',
    ]);
    expect(spans.first.attributes['adk.auto_tracing.closed_by_cleanup'], true);
  });

  test('records tool errors and keeps error propagation untouched', () async {
    final AdkTracer localTracer = AdkTracer();
    final InMemoryAdkMetricsRecorder metricsRecorder =
        InMemoryAdkMetricsRecorder();
    final AutoTracingPlugin plugin = AutoTracingPlugin(
      tracer: localTracer,
      metricsRecorder: metricsRecorder,
    );
    final InvocationContext invocationContext = _newInvocationContext();
    final ToolContext toolContext = Context(
      invocationContext,
      functionCallId: 'fn_1',
    );
    final BaseTool tool = _FakeTool();

    await plugin.beforeToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{'a': 1},
      toolContext: toolContext,
    );
    final Map<String, dynamic>? handled = await plugin.onToolErrorCallback(
      tool: tool,
      toolArgs: <String, dynamic>{'a': 1},
      toolContext: toolContext,
      error: const FormatException('boom'),
    );

    expect(handled, isNull);
    final TraceSpanRecord span = localTracer.finishedSpans.single;
    expect(span.name, 'adk.tool fake_tool');
    expect(span.attributes['adk.auto_tracing.completed'], false);
    expect(span.attributes['error.type'], 'FormatException');
    expect(span.attributes['adk.fn.exc_repr'], contains('boom'));

    final AdkMetricRecord duration = metricsRecorder.records.firstWhere((
      AdkMetricRecord record,
    ) {
      return record.name == genAiToolExecutionDurationMetric;
    });
    expect(duration.attributes['gen_ai.tool.name'], 'fake_tool');
    expect(duration.attributes['error.type'], 'FormatException');
    final AdkMetricRecord responseSize = metricsRecorder.records.firstWhere((
      AdkMetricRecord record,
    ) {
      return record.name == genAiToolResponseSizeMetric;
    });
    expect(responseSize.value, 0);
  });

  test('records lifecycle metrics from traced callbacks and events', () async {
    final AdkTracer localTracer = AdkTracer();
    final InMemoryAdkMetricsRecorder metricsRecorder =
        InMemoryAdkMetricsRecorder();
    final AutoTracingPlugin plugin = AutoTracingPlugin(
      tracer: localTracer,
      metricsRecorder: metricsRecorder,
    );
    final InvocationContext invocationContext = _newInvocationContext()
      ..userContent = Content(
        role: 'user',
        parts: <Part>[
          Part.text('hello'),
          Part.fromInlineData(mimeType: 'text/plain', data: <int>[1, 2]),
        ],
      );
    final Context callbackContext = Context(invocationContext);
    final ToolContext toolContext = Context(
      invocationContext,
      functionCallId: 'fn_1',
    );
    final BaseTool tool = _FakeTool();

    await plugin.beforeRunCallback(invocationContext: invocationContext);
    await plugin.beforeAgentCallback(
      agent: invocationContext.agent,
      callbackContext: callbackContext,
    );
    await plugin.beforeToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{'city': 'Seoul', 'count': 2},
      toolContext: toolContext,
    );
    await plugin.afterToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{'city': 'Seoul', 'count': 2},
      toolContext: toolContext,
      result: <String, dynamic>{'weather': 'sunny'},
    );
    await plugin.onEventCallback(
      invocationContext: invocationContext,
      event: Event(
        invocationId: invocationContext.invocationId,
        author: invocationContext.agent.name,
        content: Content(
          role: 'user',
          parts: <Part>[
            Part.fromFunctionResponse(
              name: 'fake_tool',
              response: <String, dynamic>{'weather': 'sunny'},
              id: 'fn_1',
            ),
            Part.fromInlineData(mimeType: 'image/png', data: <int>[1, 2, 3]),
          ],
        ),
      ),
    );
    await plugin.onEventCallback(
      invocationContext: invocationContext,
      event: Event(
        invocationId: invocationContext.invocationId,
        author: invocationContext.agent.name,
        content: Content.modelText('response'),
      ),
    );
    await plugin.afterAgentCallback(
      agent: invocationContext.agent,
      callbackContext: callbackContext,
    );
    await plugin.afterRunCallback(invocationContext: invocationContext);

    AdkMetricRecord metric(String name) {
      return metricsRecorder.records.firstWhere((AdkMetricRecord record) {
        return record.name == name;
      });
    }

    expect(metric(genAiAgentInvocationDurationMetric).unit, 'ms');
    expect(metric(genAiAgentRequestSizeMetric).value, 7);
    expect(metric(genAiAgentResponseSizeMetric).value, 8);
    expect(metric(genAiToolRequestSizeMetric).value, 5);
    expect(metric(genAiToolResponseSizeMetric).value, 3);
    expect(
      metric(genAiToolExecutionDurationMetric).attributes,
      containsPair('gen_ai.tool.name', 'fake_tool'),
    );
  });
}
