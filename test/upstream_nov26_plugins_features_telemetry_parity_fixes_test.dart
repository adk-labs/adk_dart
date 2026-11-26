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

class _FailingTool extends BaseTool {
  _FailingTool() : super(name: 'test_tool_id', description: 'Failing tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    throw StateError('boom');
  }
}

Context _newToolContext(String invocationId) {
  final InvocationContext invCtx = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's_$invocationId', appName: 'app', userId: 'u1'),
  );
  return Context(invCtx, functionCallId: 'call_1');
}

Map<String, AgentEngineSpan> _recordAgentEngineSpans(
  AgentEngineTelemetryContext ctx,
) {
  const TopSpanProcessor processor = TopSpanProcessor();
  final PropagatedTraceContext? remote = ctx.spanContext;
  final String traceIdHex =
      remote?.traceIdHex ?? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  final AgentEngineSpan topSpan = AgentEngineSpan(
    name: 'invocation',
    context: PropagatedTraceContext(
      traceIdHex: traceIdHex,
      spanIdHex: '1111111111111111',
      traceFlags: remote?.traceFlags ?? TraceFlags.sampled,
      isRemote: false,
      traceState: remote?.traceState ?? const TraceState(),
    ),
    parent: remote,
  );
  processor.onStart(topSpan, parentContext: ctx);

  final AgentEngineSpan childSpan = AgentEngineSpan(
    name: 'child',
    context: PropagatedTraceContext(
      traceIdHex: traceIdHex,
      spanIdHex: '2222222222222222',
      traceFlags: topSpan.context.traceFlags,
      isRemote: false,
    ),
    parent: topSpan.context,
  );
  processor.onStart(childSpan, parentContext: ctx);

  return <String, AgentEngineSpan>{
    topSpan.name: topSpan,
    childSpan.name: childSpan,
  };
}

void main() {
  group('1. ReflectAndRetryToolPlugin custom guidance replacement (03b4fbcee)', () {
    test('string guidance replaces default guidance including empty string', () async {
      final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
        maxRetries: 1,
        throwExceptionIfRetryExceeded: false,
        reflectionGuidance: 'Custom retry guidance.',
        retryExceededGuidance: 'Custom exceeded guidance.',
      );
      final _FailingTool tool = _FailingTool();
      final Context ctx = _newToolContext('inv_replace');
      final Exception err = FormatException('Timed out');

      final Map<String, dynamic>? first = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'q': 'hello'},
        toolContext: ctx,
        error: err,
      );
      final Map<String, dynamic>? exceeded = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'q': 'hello'},
        toolContext: ctx,
        error: err,
      );

      expect(first, <String, dynamic>{
        'response_type': reflectAndRetryResponseType,
        'error_type': 'FormatException',
        'error_details': '$err',
        'retry_count': 1,
        'reflection_guidance': 'Custom retry guidance.',
      });
      expect(exceeded, <String, dynamic>{
        'response_type': reflectAndRetryResponseType,
        'error_type': 'FormatException',
        'error_details': '$err',
        'retry_count': 1,
        'reflection_guidance': 'Custom exceeded guidance.',
      });

      final ReflectAndRetryToolPlugin emptyPlugin = ReflectAndRetryToolPlugin(
        maxRetries: 1,
        reflectionGuidance: '',
      );
      final Map<String, dynamic>? emptyResp = await emptyPlugin
          .onToolErrorCallback(
            tool: tool,
            toolArgs: <String, dynamic>{},
            toolContext: _newToolContext('inv_empty'),
            error: Exception('boom'),
          );
      expect(emptyResp!['reflection_guidance'], '');
    });

    test('ToolReflectionContext carries toolName and defaultGuidance for sync/async callbacks', () async {
      final _FailingTool tool = _FailingTool();
      final Context ctx = _newToolContext('inv_ctx');
      final Exception err = FormatException('Invalid arg');
      final List<ToolReflectionContext> captured = <ToolReflectionContext>[];

      final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
        maxRetries: 1,
        throwExceptionIfRetryExceeded: false,
        reflectionGuidance: (ToolReflectionContext reflectionContext) {
          captured.add(reflectionContext);
          return '${reflectionContext.defaultGuidance}\nNever retry 404s.';
        },
        retryExceededGuidance: (ToolReflectionContext reflectionContext) async {
          captured.add(reflectionContext);
          return 'Async exceeded for ${reflectionContext.toolName} '
              '(${reflectionContext.retryCount}/${reflectionContext.maxRetries})';
        },
      );

      final ReflectAndRetryToolPlugin defaultPlugin = ReflectAndRetryToolPlugin(
        maxRetries: 1,
        throwExceptionIfRetryExceeded: false,
      );

      final Map<String, dynamic>? first = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'x': 1},
        toolContext: ctx,
        error: err,
      );
      final Map<String, dynamic>? exceeded = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'x': 1},
        toolContext: ctx,
        error: err,
      );
      final Map<String, dynamic>? defaultFirst = await defaultPlugin
          .onToolErrorCallback(
            tool: tool,
            toolArgs: <String, dynamic>{'x': 1},
            toolContext: _newToolContext('inv_def'),
            error: err,
          );

      expect(captured, hasLength(2));
      expect(captured[0].toolName, 'test_tool_id');
      expect(captured[0].tool, same(tool));
      expect(captured[0].toolArgs, <String, dynamic>{'x': 1});
      expect(captured[0].error, same(err));
      expect(captured[0].errorDetails, contains('Invalid arg'));
      expect(captured[0].retryCount, 1);
      expect(captured[0].maxRetries, 1);
      expect(captured[0].toolContext, same(ctx));
      expect(
        captured[0].defaultGuidance,
        defaultFirst!['reflection_guidance'],
      );
      expect(
        first!['reflection_guidance'],
        '${defaultFirst['reflection_guidance']}\nNever retry 404s.',
      );
      expect(
        captured[1].defaultGuidance,
        contains('retry limit has been exceeded'),
      );
      expect(
        exceeded!['reflection_guidance'],
        'Async exceeded for test_tool_id (1/1)',
      );
    });

    test('exceeded guidance is not called when throwing and null callback falls back', () async {
      bool called = false;
      final ReflectAndRetryToolPlugin throwingPlugin =
          ReflectAndRetryToolPlugin(
            maxRetries: 1,
            throwExceptionIfRetryExceeded: true,
            retryExceededGuidance: (ToolReflectionContext _) {
              called = true;
              return 'unused';
            },
          );
      final _FailingTool tool = _FailingTool();
      final Context ctx = _newToolContext('inv_throw');
      await throwingPlugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{},
        toolContext: ctx,
        error: Exception('boom'),
      );
      await expectLater(
        throwingPlugin.onToolErrorCallback(
          tool: tool,
          toolArgs: <String, dynamic>{},
          toolContext: ctx,
          error: Exception('boom'),
        ),
        throwsException,
      );
      expect(called, isFalse);

      final ReflectAndRetryToolPlugin fallbackPlugin =
          ReflectAndRetryToolPlugin(
            maxRetries: 1,
            reflectionGuidance: (ToolReflectionContext _) => null,
          );
      final Map<String, dynamic>? resp = await fallbackPlugin
          .onToolErrorCallback(
            tool: tool,
            toolArgs: <String, dynamic>{},
            toolContext: _newToolContext('inv_null_fallback'),
            error: Exception('boom'),
          );
      expect(resp!['reflection_guidance'], contains('**Reflection Guidance:**'));
    });

    test('invalid guidance type throws at construction and non-string callback throws TypeError', () async {
      expect(
        () => ReflectAndRetryToolPlugin(reflectionGuidance: <String>['line']),
        throwsArgumentError,
      );
      expect(
        () => ReflectAndRetryToolPlugin(retryExceededGuidance: 1),
        throwsArgumentError,
      );

      final ReflectAndRetryToolPlugin badCallbackPlugin =
          ReflectAndRetryToolPlugin(
            maxRetries: 1,
            reflectionGuidance: (ToolReflectionContext _) => 42,
          );
      await expectLater(
        badCallbackPlugin.onToolErrorCallback(
          tool: _FailingTool(),
          toolArgs: <String, dynamic>{},
          toolContext: _newToolContext('inv_bad_cb'),
          error: Exception('boom'),
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('2. Feature Registry Parity (ea298d4bd, 983383519, ed76f9450, e738c26fe)', () {
    setUp(() {
      resetFeatureRegistryForTest();
    });

    test('feature stages and defaults match upstream commits', () {
      expect(
        getFeatureConfig(FeatureName.bigQueryToolConfig),
        isA<FeatureConfig>()
            .having((FeatureConfig c) => c.stage, 'stage', FeatureStage.stable)
            .having((FeatureConfig c) => c.defaultOn, 'defaultOn', isTrue),
      );
      expect(
        getFeatureConfig(FeatureName.dataAgentToolConfig),
        isA<FeatureConfig>()
            .having((FeatureConfig c) => c.stage, 'stage', FeatureStage.stable)
            .having((FeatureConfig c) => c.defaultOn, 'defaultOn', isTrue),
      );
      expect(
        getFeatureConfig(FeatureName.mongodbSessionService),
        isA<FeatureConfig>()
            .having(
              (FeatureConfig c) => c.stage,
              'stage',
              FeatureStage.experimental,
            )
            .having((FeatureConfig c) => c.defaultOn, 'defaultOn', isTrue),
      );
      expect(
        getFeatureConfig(FeatureName.toolArgsMatcher),
        isA<FeatureConfig>()
            .having(
              (FeatureConfig c) => c.stage,
              'stage',
              FeatureStage.experimental,
            )
            .having((FeatureConfig c) => c.defaultOn, 'defaultOn', isTrue),
      );
      expect(FeatureName.mcpModernProtocol.value, 'MCP_MODERN_PROTOCOL');
      expect(
        getFeatureConfig(FeatureName.mcpModernProtocol),
        isA<FeatureConfig>()
            .having(
              (FeatureConfig c) => c.stage,
              'stage',
              FeatureStage.experimental,
            )
            .having((FeatureConfig c) => c.defaultOn, 'defaultOn', isFalse),
      );
      expect(isFeatureEnabled(FeatureName.mcpModernProtocol), isFalse);
      expect(
        isFeatureEnabled(
          FeatureName.mcpModernProtocol,
          environment: <String, String>{'ADK_ENABLE_MCP_MODERN_PROTOCOL': '1'},
        ),
        isTrue,
      );
    });
  });

  group('3. Agent Engine Telemetry Propagation & TopSpanProcessor (f27b8f105)', () {
    const String traceIdHex = '4bf92f3577b34da6a3ce929d0e0e4736';
    const String remoteSpanIdHex = '00f067aa0ba902b7';
    const String wellFormedTraceparent = '00-$traceIdHex-$remoteSpanIdHex-01';
    const String supportIdValue = 'support-id-value';

    const List<String> rejectedTraceparents = <String>[
      'x',
      '00-abc-zz-01',
      '',
      '00',
      '-',
      '00-$traceIdHex-$remoteSpanIdHex',
      '00-00000000000000000000000000000000-$remoteSpanIdHex-01',
      'ff-$traceIdHex-$remoteSpanIdHex-01',
    ];

    test('rejected Google-Agent-Engine-Traceparent is ignored and still allows spans', () {
      for (final String badValue in rejectedTraceparents) {
        final AgentEngineTelemetryContext ctx = getPropagatedContext(
          <String, String>{googleAeTraceparentHeader: badValue},
          environment: const <String, String>{},
        );
        expect(ctx.getBaggage(traceparentBaggageKey), isNull);
        expect(ctx.spanContext, isNull);
        final Map<String, AgentEngineSpan> spans = _recordAgentEngineSpans(ctx);
        expect(spans.keys.toSet(), <String>{'invocation', 'child'});
      }
    });

    test('rejected traceparent in baggage still produces child spans safely', () {
      const TopSpanProcessor processor = TopSpanProcessor();
      for (final String badValue in rejectedTraceparents) {
        final AgentEngineTelemetryContext ctx = AgentEngineTelemetryContext(
          baggage: <String, String>{traceparentBaggageKey: badValue},
        );
        final AgentEngineSpan top = AgentEngineSpan(
          name: 'invocation',
          context: const PropagatedTraceContext(
            traceIdHex: traceIdHex,
            spanIdHex: '1111111111111111',
            traceFlags: TraceFlags.sampled,
          ),
          parent: const PropagatedTraceContext(
            traceIdHex: traceIdHex,
            spanIdHex: '9999999999999999',
            traceFlags: TraceFlags.sampled,
          ),
        );
        processor.onStart(top, parentContext: ctx);
        expect(
          top.attributes.containsKey(googleTraceparentSupportAttributeKey),
          isFalse,
        );
      }
    });

    test('Google-Agent-Engine-Traceparent marks top span and records traceparent supportID', () {
      final AgentEngineTelemetryContext ctx = getPropagatedContext(
        <String, String>{
          googleAeTraceparentHeader: wellFormedTraceparent,
          googleTraceparentHeader: supportIdValue,
        },
        environment: const <String, String>{},
      );
      expect(ctx.getBaggage(traceparentBaggageKey), wellFormedTraceparent);
      expect(ctx.getBaggage(googleTraceparentBaggageKey), supportIdValue);

      final Map<String, AgentEngineSpan> spans = _recordAgentEngineSpans(ctx);
      expect(spans['invocation']!.parent?.spanIdHex, remoteSpanIdHex);
      expect(
        spans['invocation']!.attributes[googleTraceparentSupportAttributeKey],
        supportIdValue,
      );
      expect(
        spans['child']!.attributes.containsKey(
          googleTraceparentSupportAttributeKey,
        ),
        isFalse,
      );
    });

    test('rejected AE header leaves top span parentless with supportID', () {
      final AgentEngineTelemetryContext ctx = getPropagatedContext(
        <String, String>{
          googleAeTraceparentHeader: 'x',
          googleTraceparentHeader: supportIdValue,
        },
        environment: const <String, String>{},
      );
      final Map<String, AgentEngineSpan> spans = _recordAgentEngineSpans(ctx);
      expect(spans['invocation']!.parent, isNull);
      expect(
        spans['invocation']!.attributes[googleTraceparentSupportAttributeKey],
        supportIdValue,
      );
      expect(
        spans['child']!.attributes.containsKey(
          googleTraceparentSupportAttributeKey,
        ),
        isFalse,
      );
    });

    test('standard traceparent and tracestate extract parent span off Agent Engine', () {
      final AgentEngineTelemetryContext ctx = getPropagatedContext(
        <String, String>{
          googleTraceparentHeader: wellFormedTraceparent,
          'tracestate': 'congo=t61rcWkgMzE',
        },
        environment: const <String, String>{},
      );
      final Map<String, AgentEngineSpan> spans = _recordAgentEngineSpans(ctx);

      expect(spans['invocation']!.context.traceIdHex, traceIdHex);
      expect(spans['invocation']!.parent?.spanIdHex, remoteSpanIdHex);
      expect(
        spans['invocation']!.parent?.traceState.values['congo'],
        't61rcWkgMzE',
      );
      expect(
        spans['invocation']!.attributes[googleTraceparentSupportAttributeKey],
        wellFormedTraceparent,
      );
      expect(
        spans['child']!.attributes.containsKey(
          googleTraceparentSupportAttributeKey,
        ),
        isFalse,
      );
    });

    test('standard traceparent is only supportID on Agent Engine', () {
      final AgentEngineTelemetryContext ctx = getPropagatedContext(
        <String, String>{googleTraceparentHeader: wellFormedTraceparent},
        environment: const <String, String>{
          googleCloudAgentEngineIdEnvVar: '123',
        },
      );
      final Map<String, AgentEngineSpan> spans = _recordAgentEngineSpans(ctx);

      expect(ctx.getBaggage(traceparentBaggageKey), isNull);
      expect(spans['invocation']!.parent, isNull);
      expect(
        spans['invocation']!.attributes[googleTraceparentSupportAttributeKey],
        wellFormedTraceparent,
      );
      expect(
        spans['child']!.attributes.containsKey(
          googleTraceparentSupportAttributeKey,
        ),
        isFalse,
      );
    });

    test('standard traceparent does not reparent an existing upstream server span', () {
      const PropagatedTraceContext serverSpanContext = PropagatedTraceContext(
        traceIdHex: '11111111111111111111111111111111',
        spanIdHex: '2222222222222222',
        traceFlags: TraceFlags.sampled,
        isRemote: false,
      );
      final AgentEngineTelemetryContext upstreamCtx =
          AgentEngineTelemetryContext(spanContext: serverSpanContext);

      final AgentEngineTelemetryContext ctx = getPropagatedContext(
        <String, String>{googleTraceparentHeader: wellFormedTraceparent},
        baseContext: upstreamCtx,
        environment: const <String, String>{},
      );
      expect(ctx.spanContext, same(serverSpanContext));
      expect(ctx.getBaggage(traceparentBaggageKey), isNull);
      expect(
        ctx.getBaggage(googleTraceparentBaggageKey),
        wellFormedTraceparent,
      );
    });

    test('Google-Agent-Engine-Traceparent takes precedence over standard traceparent', () {
      const String otherTraceparent =
          '00-11111111111111111111111111111111-2222222222222222-01';
      final AgentEngineTelemetryContext ctx = getPropagatedContext(
        <String, String>{
          googleAeTraceparentHeader: wellFormedTraceparent,
          googleTraceparentHeader: otherTraceparent,
        },
        environment: const <String, String>{},
      );
      final Map<String, AgentEngineSpan> spans = _recordAgentEngineSpans(ctx);
      expect(spans['invocation']!.context.traceIdHex, traceIdHex);
      expect(spans['invocation']!.parent?.spanIdHex, remoteSpanIdHex);
      expect(
        spans['invocation']!.attributes[googleTraceparentSupportAttributeKey],
        otherTraceparent,
      );
    });

    test('W3C baggage is extracted and caller-supplied reserved keys are stripped', () {
      final AgentEngineTelemetryContext withHeader = getPropagatedContext(
        <String, String>{
          googleTraceparentHeader: wellFormedTraceparent,
          'baggage':
              'tenant_id=acme,env=prod,traceparent=spoofed,google_traceparent=spoofed',
        },
        environment: const <String, String>{},
      );
      expect(withHeader.getBaggage('tenant_id'), 'acme');
      expect(withHeader.getBaggage('env'), 'prod');
      expect(
        withHeader.getBaggage(traceparentBaggageKey),
        wellFormedTraceparent,
      );
      expect(
        withHeader.getBaggage(googleTraceparentBaggageKey),
        wellFormedTraceparent,
      );

      final AgentEngineTelemetryContext withoutHeader = getPropagatedContext(
        <String, String>{
          'baggage':
              'tenant_id=acme,traceparent=spoofed,google_traceparent=spoofed',
        },
        environment: const <String, String>{},
      );
      expect(withoutHeader.getBaggage('tenant_id'), 'acme');
      expect(withoutHeader.getBaggage(traceparentBaggageKey), isNull);
      expect(withoutHeader.getBaggage(googleTraceparentBaggageKey), isNull);

      final AgentEngineTelemetryContext fromUpstream = getPropagatedContext(
        const <String, String>{},
        baseContext: AgentEngineTelemetryContext(
          baggage: const <String, String>{
            traceparentBaggageKey: 'spoofed',
            googleTraceparentBaggageKey: 'spoofed',
          },
        ),
        environment: const <String, String>{},
      );
      expect(fromUpstream.baggage, isEmpty);
    });
  });
}
