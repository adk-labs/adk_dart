import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _ScriptedLlm extends BaseLlm {
  _ScriptedLlm({
    super.model = 'gemini-2.5-flash',
    required this.responder,
  });

  final Stream<LlmResponse> Function(LlmRequest request) responder;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    return responder(request);
  }
}

class _CustomSecretStr {
  _CustomSecretStr(this.secret);
  final String secret;

  @override
  String toString() => secret;
}

class SecretStr extends _CustomSecretStr {
  SecretStr(super.secret);
}

class Credentials {
  Credentials(this.token);
  final String token;

  Map<String, Object?> toJson() => <String, Object?>{'token': token};

  @override
  String toString() => 'Credentials($token)';
}

class _WrapperDto {
  _WrapperDto({required this.label, required this.credential});

  final String label;
  final Object credential;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'credential': credential,
  };
}

class _FinishTool extends BaseTool {
  _FinishTool() : super(name: 'submit_final_answer', description: 'Submit');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'submitted': true};
  }
}

class _FailingAgent extends BaseAgent {
  _FailingAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    throw StateError('child_boom api_key="sk-secret-child-key');
  }
}

Map<String, Object?> _decodeAttributes(Map<String, Object?> row) {
  final Object? raw = row['attributes'];
  if (raw is String) {
    return (jsonDecode(raw) as Map).map(
      (Object? k, Object? v) => MapEntry('$k', v),
    );
  }
  if (raw is Map) {
    return raw.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

void main() {
  tearDown(() {
    resetAdkMetricsRecorderForTest();
    resetGenAiInstrumentationDetectorForTest();
    LlmAgent.setDefaultModel(LlmAgent.defaultModel);
  });

  group('1. 5ce1d0c15: nested AgentTool state isolation, responseTextKey, sanitization, eval SQL', () {
    test('AgentTool stamps parentInvocationId only when includePlugins is true and copyWith preserves it', () async {
      String? capturedWithPluginsParentInvId;
      String? capturedWithoutPluginsParentInvId;

      final BasePlugin observerPlugin = _CallbackCapturePlugin(
        onBeforeRun: (InvocationContext ctx) {
          capturedWithPluginsParentInvId = ctx.parentInvocationId;
        },
      );

      final Agent childWithPlugins = Agent(
        name: 'child_with_plugins',
        model: _ScriptedLlm(
          responder: (_) async* {
            yield LlmResponse(content: Content.modelText('ok from child 1'));
          },
        ),
      );

      final BaseAgent inspectWithoutPluginsChild = _InlineInspectAgent(
        name: 'child_without_plugins',
        onRun: (InvocationContext ctx) {
          capturedWithoutPluginsParentInvId = ctx.parentInvocationId;
        },
      );

      final AgentTool toolWithPlugins = AgentTool(
        agent: childWithPlugins,
        includePlugins: true,
      );
      final AgentTool toolWithoutPlugins = AgentTool(
        agent: inspectWithoutPluginsChild,
        includePlugins: false,
      );

      int step = 0;
      final Agent outerAgent = Agent(
        name: 'outer_agent',
        model: _ScriptedLlm(
          responder: (_) async* {
            step += 1;
            if (step == 1) {
              yield LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      id: 'fc_1',
                      name: 'child_with_plugins',
                      args: <String, dynamic>{'request': 'go'},
                    ),
                    Part.fromFunctionCall(
                      id: 'fc_2',
                      name: 'child_without_plugins',
                      args: <String, dynamic>{'request': 'go'},
                    ),
                  ],
                ),
              );
            } else {
              yield LlmResponse(content: Content.modelText('outer done'));
            }
          },
        ),
        tools: <Object>[toolWithPlugins, toolWithoutPlugins],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session outerSession = await sessionService.createSession(
        appName: 'test_app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        appName: 'test_app',
        agent: outerAgent,
        sessionService: sessionService,
        plugins: <BasePlugin>[observerPlugin],
      );

      String? outerInvocationId;
      await for (final Event event in runner.runAsync(
        userId: 'u1',
        sessionId: outerSession.id,
        newMessage: Content.userText('run both'),
      )) {
        outerInvocationId ??= event.invocationId;
      }

      // First beforeRunCallback was outer (null), second was childWithPlugins (outerInvocationId).
      expect(outerInvocationId, isNotNull);
      expect(capturedWithPluginsParentInvId, equals(outerInvocationId));
      expect(capturedWithoutPluginsParentInvId, isNull);

      final InvocationContext baseCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_child',
        agent: outerAgent,
        session: outerSession,
      )..parentInvocationId = 'inv_parent';
      expect(baseCtx.copyWith().parentInvocationId, 'inv_parent');
    });

    test('BigQueryAgentAnalyticsPlugin isolates 3-level nested AgentTool runs and stamps parent_session_id / parent_invocation_id', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin bqPlugin =
          BigQueryAgentAnalyticsPlugin(
            projectId: 'proj',
            datasetId: 'ds',
            sink: sink,
            config: BigQueryLoggerConfig(createViews: false),
          );

      final Agent innerAgent = Agent(
        name: 'inner_agent',
        model: _ScriptedLlm(
          responder: (_) async* {
            yield LlmResponse(content: Content.modelText('inner reply'));
          },
        ),
      );
      int middleStep = 0;
      final Agent middleAgent = Agent(
        name: 'middle_agent',
        model: _ScriptedLlm(
          responder: (_) async* {
            middleStep += 1;
            if (middleStep == 1) {
              yield LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      id: 'fc_inner',
                      name: 'inner_agent',
                      args: <String, dynamic>{'request': 'ask inner'},
                    ),
                  ],
                ),
              );
            } else {
              yield LlmResponse(content: Content.modelText('middle reply'));
            }
          },
        ),
        tools: <Object>[AgentTool(agent: innerAgent)],
      );
      int outerStep = 0;
      final Agent outerAgent = Agent(
        name: 'outer_agent',
        model: _ScriptedLlm(
          responder: (_) async* {
            outerStep += 1;
            if (outerStep == 1) {
              yield LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      id: 'fc_middle',
                      name: 'middle_agent',
                      args: <String, dynamic>{'request': 'ask middle'},
                    ),
                  ],
                ),
              );
            } else {
              yield LlmResponse(content: Content.modelText('outer final'));
            }
          },
        ),
        tools: <Object>[AgentTool(agent: middleAgent)],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session outerSession = await sessionService.createSession(
        appName: 'nested_app',
        userId: 'u1',
        sessionId: 'outer_session_1',
      );
      final Runner runner = Runner(
        appName: 'nested_app',
        agent: outerAgent,
        sessionService: sessionService,
        plugins: <BasePlugin>[bqPlugin],
      );

      await runner
          .runAsync(
            userId: 'u1',
            sessionId: outerSession.id,
            newMessage: Content.userText('start chain'),
          )
          .drain<void>();

      expect(sink.rows, isNotEmpty);
      final Set<String?> traceIds = sink.rows
          .map((Map<String, Object?> r) => r['trace_id'] as String?)
          .toSet();
      expect(traceIds, hasLength(1));

      for (final Map<String, Object?> row in sink.rows) {
        if (row['span_id'] != null) {
          expect(
            row['span_id'],
            isNot(equals(row['parent_span_id'])),
            reason: 'Self-loop on ${row['event_type']}',
          );
        }
      }

      final List<Map<String, Object?>> outerRows = sink.rows
          .where((Map<String, Object?> r) => r['session_id'] == 'outer_session_1')
          .toList();
      final List<Map<String, Object?>> middleRows = sink.rows
          .where((Map<String, Object?> r) => r['agent'] == 'middle_agent')
          .toList();
      final List<Map<String, Object?>> innerRows = sink.rows
          .where((Map<String, Object?> r) => r['agent'] == 'inner_agent')
          .toList();

      expect(outerRows, isNotEmpty);
      expect(middleRows, isNotEmpty);
      expect(innerRows, isNotEmpty);

      final String outerInvId = outerRows.first['invocation_id'] as String;
      final String middleInvId = middleRows.first['invocation_id'] as String;
      final String middleSessionId = middleRows.first['session_id'] as String;

      for (final Map<String, Object?> row in outerRows) {
        final Map<String, Object?> attrs = _decodeAttributes(row);
        final Map<String, Object?> adk = Map<String, Object?>.from(
          attrs['adk'] as Map,
        );
        expect(attrs['root_agent_name'], 'outer_agent');
        expect(adk.containsKey('parent_session_id'), isFalse);
        expect(adk.containsKey('parent_invocation_id'), isFalse);
      }

      for (final Map<String, Object?> row in middleRows) {
        final Map<String, Object?> attrs = _decodeAttributes(row);
        final Map<String, Object?> adk = Map<String, Object?>.from(
          attrs['adk'] as Map,
        );
        expect(attrs['root_agent_name'], 'middle_agent');
        expect(adk['parent_session_id'], 'outer_session_1');
        expect(adk['parent_invocation_id'], outerInvId);
      }

      for (final Map<String, Object?> row in innerRows) {
        final Map<String, Object?> attrs = _decodeAttributes(row);
        final Map<String, Object?> adk = Map<String, Object?>.from(
          attrs['adk'] as Map,
        );
        expect(attrs['root_agent_name'], 'inner_agent');
        expect(adk['parent_session_id'], middleSessionId);
        expect(adk['parent_invocation_id'], middleInvId);
      }

      // Verify nested root INVOCATION_STARTING parent_span_id links to parent's TOOL_STARTING span_id.
      final Map<String, Object?> outerToolStarting = outerRows.firstWhere(
        (Map<String, Object?> r) => r['event_type'] == 'TOOL_STARTING',
      );
      final Map<String, Object?> middleInvStarting = middleRows.firstWhere(
        (Map<String, Object?> r) => r['event_type'] == 'INVOCATION_STARTING',
      );
      expect(
        middleInvStarting['parent_span_id'],
        equals(outerToolStarting['span_id']),
      );
    });

    test('concurrent, short-circuited, and errored nested AgentTool runs preserve parent state and fail error_traceback closed', () async {
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin bqPlugin =
          BigQueryAgentAnalyticsPlugin(
            projectId: 'proj',
            datasetId: 'ds',
            sink: sink,
            config: BigQueryLoggerConfig(createViews: false),
          );

      final Agent workerA = Agent(
        name: 'worker_a',
        model: _ScriptedLlm(
          responder: (_) async* {
            await Future<void>.delayed(const Duration(milliseconds: 15));
            yield LlmResponse(content: Content.modelText('worker A done'));
          },
        ),
      );
      final Agent workerB = Agent(
        name: 'worker_b',
        model: _ScriptedLlm(
          responder: (_) async* {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            yield LlmResponse(content: Content.modelText('worker B done'));
          },
        ),
      );

      int step = 0;
      final Agent coordinator = Agent(
        name: 'coordinator',
        model: _ScriptedLlm(
          responder: (_) async* {
            step += 1;
            if (step == 1) {
              yield LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      id: 'fc_a',
                      name: 'worker_a',
                      args: <String, dynamic>{'request': 'go a'},
                    ),
                    Part.fromFunctionCall(
                      id: 'fc_b',
                      name: 'worker_b',
                      args: <String, dynamic>{'request': 'go b'},
                    ),
                  ],
                ),
              );
            } else {
              yield LlmResponse(content: Content.modelText('all done'));
            }
          },
        ),
        tools: <Object>[AgentTool(agent: workerA), AgentTool(agent: workerB)],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session s1 = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 'coord_sess',
      );
      final Runner runner = Runner(
        appName: 'app',
        agent: coordinator,
        sessionService: sessionService,
        plugins: <BasePlugin>[bqPlugin],
      );
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: s1.id,
            newMessage: Content.userText('parallel'),
          )
          .drain<void>();

      final Map<String, Object?> coordCompleted = sink.rows.singleWhere(
        (Map<String, Object?> r) =>
            r['session_id'] == 'coord_sess' &&
            r['event_type'] == 'INVOCATION_COMPLETED',
      );
      expect(_decodeAttributes(coordCompleted)['root_agent_name'], 'coordinator');

      // Test onAgentErrorCallback / onRunErrorCallback fail-closed error_traceback and no self-loops
      final InvocationContext errCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_err_1',
        agent: _FailingAgent(name: 'failing_agent'),
        session: Session(id: 's_err', appName: 'app', userId: 'u1'),
      );
      await bqPlugin.beforeRunCallback(invocationContext: errCtx);
      final CallbackContext cbErrCtx = Context(errCtx);
      // Call onAgentErrorCallback WITHOUT beforeAgentCallback: must NOT pop invocation span or self-loop!
      await bqPlugin.onAgentErrorCallback(
        agent: errCtx.agent,
        callbackContext: cbErrCtx,
        error: StateError('unclosed quote api_key="sk-live-secret'),
        errorTraceback: 'Stack frame 0: harmless line without secret',
      );
      await bqPlugin.onModelErrorCallback(
        callbackContext: cbErrCtx,
        llmRequest: LlmRequest(model: 'gemini-2.5-flash', contents: <Content>[]),
        error: Exception('model timeout'),
      );
      await bqPlugin.onRunErrorCallback(
        invocationContext: errCtx,
        error: StateError('unclosed quote api_key="sk-live-secret'),
      );

      final Map<String, Object?> agentErrRow = sink.rows.singleWhere(
        (Map<String, Object?> r) =>
            r['invocation_id'] == 'inv_err_1' &&
            r['event_type'] == 'AGENT_ERROR',
      );
      expect(agentErrRow['error_message'], '[REDACTED_SENSITIVE_TEXT]');
      expect(
        (agentErrRow['content'] as Map)['error_traceback'],
        '[REDACTED_SENSITIVE_TEXT]',
      );
      expect(agentErrRow['is_truncated'], isTrue);
      if (agentErrRow['span_id'] != null) {
        expect(
          agentErrRow['span_id'],
          isNot(equals(agentErrRow['parent_span_id'])),
        );
      }

      final Map<String, Object?> llmErrRow = sink.rows.singleWhere(
        (Map<String, Object?> r) =>
            r['invocation_id'] == 'inv_err_1' && r['event_type'] == 'LLM_ERROR',
      );
      if (llmErrRow['span_id'] != null) {
        expect(llmErrRow['span_id'], isNot(equals(llmErrRow['parent_span_id'])));
      }

      // Short-circuited nested run where beforeRunCallback short-circuits BEFORE BigQueryAgentAnalyticsPlugin
      final InMemoryBigQueryEventSink shortSink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin shortBq = BigQueryAgentAnalyticsPlugin(
        projectId: 'proj',
        datasetId: 'ds',
        sink: shortSink,
        config: BigQueryLoggerConfig(createViews: false),
      );
      final BasePlugin shortCircuitChildOnly = _ConditionalShortCircuitPlugin(
        targetAgentName: 'short_child',
      );
      final Agent shortChild = Agent(
        name: 'short_child',
        model: _ScriptedLlm(responder: (_) async* {}),
      );
      int shortOuterStep = 0;
      final Agent shortOuter = Agent(
        name: 'short_outer',
        model: _ScriptedLlm(
          responder: (_) async* {
            shortOuterStep += 1;
            if (shortOuterStep == 1) {
              yield LlmResponse(
                content: Content(
                  role: 'model',
                  parts: <Part>[
                    Part.fromFunctionCall(
                      id: 'fc_s',
                      name: 'short_child',
                      args: <String, dynamic>{'request': 'ping'},
                    ),
                  ],
                ),
              );
            } else {
              yield LlmResponse(content: Content.modelText('outer survived'));
            }
          },
        ),
        tools: <Object>[AgentTool(agent: shortChild)],
      );
      final Session shortSess = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 'short_outer_sess',
      );
      final Runner shortRunner = Runner(
        appName: 'app',
        agent: shortOuter,
        sessionService: sessionService,
        plugins: <BasePlugin>[shortCircuitChildOnly, shortBq],
      );
      await shortRunner
          .runAsync(
            userId: 'u1',
            sessionId: shortSess.id,
            newMessage: Content.userText('go'),
          )
          .drain<void>();

      final List<Map<String, Object?>> childShortRows = shortSink.rows
          .where((Map<String, Object?> r) => r['agent'] == 'short_child')
          .toList();
      expect(childShortRows, isNotEmpty);
      for (final Map<String, Object?> row in childShortRows) {
        final Map<String, Object?> adk = Map<String, Object?>.from(
          _decodeAttributes(row)['adk'] as Map,
        );
        expect(adk['parent_session_id'], 'short_outer_sess');
        expect(adk['parent_invocation_id'], isNotNull);
      }
    });

    test('BigQueryLoggerConfig.responseTextKey validates config and extracts sanitized text_summary', () async {
      expect(
        () => BigQueryLoggerConfig(responseTextKey: ''),
        throwsArgumentError,
      );
      expect(
        () => BigQueryLoggerConfig(responseTextKey: '   '),
        throwsArgumentError,
      );
      expect(
        () => BigQueryAgentAnalyticsPlugin(
          projectId: 'proj',
          datasetId: 'ds',
          sink: InMemoryBigQueryEventSink(),
          configOverrides: <String, Object?>{'response_text_key': '  '},
        ),
        throwsArgumentError,
      );

      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'proj',
        datasetId: 'ds',
        sink: sink,
        config: BigQueryLoggerConfig(
          createViews: false,
          responseTextKey: 'answer',
          finalResponseToolNames: <String>{'submit_final_answer'},
        ),
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final InvocationContext ctx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_resp_key',
        agent: Agent(
          name: 'structured_agent',
          model: _ScriptedLlm(responder: (_) async* {}),
        ),
        session: Session(id: 's_resp', appName: 'app', userId: 'u1'),
      );

      // 1. Structured JSON AGENT_RESPONSE via onEventCallback
      // 1a. Prose with live credential in answer -> sanitized in place into text_summary
      await plugin.onEventCallback(
        invocationContext: ctx,
        event: Event(
          id: 'ev_struct_ok',
          invocationId: 'inv_resp_key',
          author: 'structured_agent',
          content: Content.modelText(
            jsonEncode(<String, Object?>{
              'answer': 'Order #42 shipped with Bearer secret_tok_99',
              'confidence': 0.98,
            }),
          ),
        ),
      );

      // 1b. Bracket-led prose without live credential (`[INFO] ... [REDACTED]`) -> rescued into text_summary
      await plugin.onEventCallback(
        invocationContext: ctx,
        event: Event(
          id: 'ev_struct_bracket_ok',
          invocationId: 'inv_resp_key',
          author: 'structured_agent',
          content: Content.modelText(
            jsonEncode(<String, Object?>{
              'answer': '[INFO] Order #42 shipped with Bearer [REDACTED]',
              'confidence': 0.99,
            }),
          ),
        ),
      );

      // 2. Malformed JSON container in answer value -> collapses to sentinel -> text_summary omitted
      await plugin.onEventCallback(
        invocationContext: ctx,
        event: Event(
          id: 'ev_struct_bad',
          invocationId: 'inv_resp_key',
          author: 'structured_agent',
          content: Content.modelText(
            jsonEncode(<String, Object?>{
              'answer': '{"token": "[REDACTED]", broken',
              'confidence': 0.5,
            }),
          ),
        ),
      );

      // 3. finalResponseToolNames via afterToolCallback
      final ToolContext toolCtx = Context(ctx, functionCallId: 'fc_fin');
      await plugin.beforeToolCallback(
        tool: _FinishTool(),
        toolArgs: <String, dynamic>{
          'answer': 'Final tool summary',
          'score': 10,
        },
        toolContext: toolCtx,
      );
      await plugin.afterToolCallback(
        tool: _FinishTool(),
        toolArgs: <String, dynamic>{
          'answer': 'Final tool summary',
          'score': 10,
        },
        toolContext: toolCtx,
        result: <String, dynamic>{'submitted': true},
      );

      final List<Map<String, Object?>> responseRows = sink.rows
          .where((Map<String, Object?> r) => r['event_type'] == 'AGENT_RESPONSE')
          .toList();
      expect(responseRows, hasLength(4));

      final Map<String, Object?> firstContent = Map<String, Object?>.from(
        responseRows[0]['content'] as Map,
      );
      expect(
        firstContent['text_summary'],
        'Order #42 shipped with Bearer [REDACTED]',
      );
      expect(firstContent['response'], isNotNull);
      expect(responseRows[0]['is_truncated'], isTrue);

      final Map<String, Object?> bracketContent = Map<String, Object?>.from(
        responseRows[1]['content'] as Map,
      );
      expect(
        bracketContent['text_summary'],
        '[INFO] Order #42 shipped with Bearer [REDACTED]',
      );

      final Map<String, Object?> secondContent = Map<String, Object?>.from(
        responseRows[2]['content'] as Map,
      );
      expect(secondContent.containsKey('text_summary'), isFalse);
      expect(secondContent['response'], isNotNull);

      final Map<String, Object?> thirdContent = Map<String, Object?>.from(
        responseRows[3]['content'] as Map,
      );
      expect(thirdContent['text_summary'], 'Final tool summary');
      expect((thirdContent['response'] as Map)['score'], 10);
    });

    test('HybridContentParser and escape-canonicalized credential sanitization fail closed on malformed JSON markers while rescuing safe prose', () {
      // Safe bracket-led prose & already-redacted log prose are rescued
      expect(
        HybridContentParser.sanitizeRawText('[INFO] token=[REDACTED] retrying'),
        equals(('[INFO] token=[REDACTED] retrying', false)),
      );
      expect(
        HybridContentParser.sanitizeRawText(r'C:\Users\alice\notes.txt'),
        equals((r'C:\Users\alice\notes.txt', false)),
      );

      // Malformed JSON containers carrying live or already-redacted credential markers fail closed
      expect(
        HybridContentParser.sanitizeRawText('{"token": "[REDACTED]", broken'),
        equals(('[UNPARSEABLE_JSON_BLOB]', true)),
      );
      expect(
        HybridContentParser.sanitizeRawText('[{"api_key": "sk-live-123"'),
        equals(('[UNPARSEABLE_JSON_BLOB]', true)),
      );

      // Escaped ASCII credential markers in diagnostic prose fail closed to [REDACTED_SENSITIVE_TEXT]
      expect(
        HybridContentParser.sanitizeRawText(r'Error: \u0061pi_key=secret123'),
        equals(('[REDACTED_SENSITIVE_TEXT]', true)),
      );
      expect(
        HybridContentParser.sanitizeRawText('Error: %61ccess_token=secret123'),
        equals(('[REDACTED_SENSITIVE_TEXT]', true)),
      );
    });

    test('eval SQL filters nested SessionEvents and excludes all sanitization sentinels', () {
      final String sessionSql = buildEvalSessionQuerySql(
        'proj.ds.agent_events',
      );
      final String turnSql = buildEvalTurnQuerySql('proj.ds.agent_events');

      for (final String sql in <String>[sessionSql, turnSql]) {
        expect(sql, contains('SessionEvents AS ('));
        expect(
          sql,
          contains("JSON_VALUE(attributes, '\$.adk.parent_session_id') IS NULL"),
        );
        expect(sql, contains('FROM\n      SessionEvents'));
        expect(sql, isNot(contains('TypedEvents AS (\n    SELECT\n      *,\n      FROM\n      RawEvents')));
        expect(sql, contains("'[FORMATTER_FAILED]'"));
        expect(sql, contains("'[FORMATTING FAILED]'"));
        expect(sql, contains("'[UNPARSEABLE_JSON_BLOB]'"));
        expect(sql, contains("'[REDACTED_SENSITIVE_TEXT]'"));
        expect(
          sql,
          contains(
            'r"\' [|] (?:call: |resp: |Executable code |Code execution result )"',
          ),
        );
      }
    });
  });

  group('2. b6952874a: credential masking in telemetry serializer and AutoTracingPlugin', () {
    test('isCredentialType and isCredentialArgName classify credential names and types accurately', () {
      expect(isCredentialArgName('api_key'), isTrue);
      expect(isCredentialArgName('X-API-Key'), isTrue);
      expect(isCredentialArgName('accessToken'), isTrue);
      expect(isCredentialArgName('oauth2Credentials'), isTrue);
      expect(isCredentialArgName('client_secret'), isTrue);
      expect(isCredentialArgName('Authorization'), isTrue);

      expect(isCredentialArgName('max_output_tokens'), isFalse);
      expect(isCredentialArgName('tokenizer'), isFalse);
      expect(isCredentialArgName('key_field'), isFalse);
      expect(isCredentialArgName('author'), isFalse);

      final AuthCredential authCred = AuthCredential(
        authType: AuthCredentialTypes.apiKey,
        apiKey: 'sk-top-secret',
      );
      expect(isCredentialType(authCred), isTrue);
      expect(isCredentialType(SecretStr('my-secret')), isTrue);
      expect(isCredentialType(Credentials('ya29.secret')), isTrue);
      expect(isCredentialType(<String, Object?>{'token': 'cursor'}), isFalse);
    });

    test('safeJsonSerialize masks live credentials, DTOs, live AuthConfig, and dumped AuthConfig secrets while keeping ordinary dicts intact', () {
      final AuthCredential liveCred = AuthCredential(
        authType: AuthCredentialTypes.oauth2,
        oauth2: OAuth2Auth(
          clientId: 'cid',
          clientSecret: 'super-secret-client',
          accessToken: 'ya29.live-access-token',
          refreshToken: '1//live-refresh-token',
        ),
      );
      final _WrapperDto dto = _WrapperDto(
        label: 'wrapped',
        credential: SecretStr('dto-secret-value'),
      );
      final AuthConfig liveAuthConfig = AuthConfig(
        authScheme: 'oauth2',
        credentialKey: 'live_cred_key',
        rawAuthCredential: liveCred,
      );

      final String serializedLive = safeJsonSerialize(<String, Object?>{
        'live_cred': liveCred,
        'dto': dto,
        'live_auth_config': liveAuthConfig,
        'google_creds': Credentials('ya29.google-cred'),
        'ordinary': <String, Object?>{
          'token': 'next-page-cursor-42',
          'api_key': 'ordinary-label-not-auth-envelope',
        },
      });
      expect(serializedLive, isNot(contains('super-secret-client')));
      expect(serializedLive, isNot(contains('ya29.live-access-token')));
      expect(serializedLive, isNot(contains('1//live-refresh-token')));
      expect(serializedLive, isNot(contains('dto-secret-value')));
      expect(serializedLive, isNot(contains('ya29.google-cred')));

      final Map<String, Object?> decodedLive =
          jsonDecode(serializedLive) as Map<String, Object?>;
      expect(decodedLive['live_cred'], redacted);
      expect((decodedLive['dto'] as Map)['credential'], redacted);
      expect(decodedLive['live_auth_config'], redacted);
      expect(decodedLive['google_creds'], redacted);
      expect(
        (decodedLive['ordinary'] as Map)['token'],
        'next-page-cursor-42',
      );
      expect(
        (decodedLive['ordinary'] as Map)['api_key'],
        'ordinary-label-not-auth-envelope',
      );

      // Dumped AuthConfig / adk_request_credential envelope strips secrets while preserving non-secret structure
      final Map<String, Object?> dumpedAuthConfig = <String, Object?>{
        'auth_scheme': 'oauth2',
        'credential_key': 'cred_key_1',
        'raw_auth_credential': <String, Object?>{
          'auth_type': 'oauth2',
          'oauth2': <String, Object?>{
            'client_id': 'cid',
            'client_secret': 'super-secret-client',
            'access_token': 'ya29.live-access-token',
            'refresh_token': '1//live-refresh-token',
          },
        },
        'exchanged_auth_credential': <String, Object?>{
          'auth_type': 'http',
          'http': <String, Object?>{
            'scheme': 'bearer',
            'credentials': <String, Object?>{
              'username': 'alice',
              'password': 'alice-password',
              'token': 'alice-bearer-jwt',
            },
          },
        },
      };

      final String serializedDumped = safeJsonSerialize(<String, Object?>{
        'requested_auth_configs': <String, Object?>{'cfg1': dumpedAuthConfig},
      });
      expect(serializedDumped, isNot(contains('super-secret-client')));
      expect(serializedDumped, isNot(contains('ya29.live-access-token')));
      expect(serializedDumped, isNot(contains('alice-password')));
      expect(serializedDumped, isNot(contains('alice-bearer-jwt')));
      expect(serializedDumped, contains('cred_key_1'));
      expect(serializedDumped, contains('alice'));

      // Cyclic object graph serializes cyclic back-reference as '<not serializable>'
      final Map<String, Object?> cyclic = <String, Object?>{'ok': 1};
      cyclic['self'] = cyclic;
      expect(safeJsonSerialize(cyclic), '<not serializable>');
    });

    test('traceToolCall, traceMergedToolCalls, and AutoTracingPlugin redact credentials in spans', () {
      final AdkTracer localTracer = AdkTracer();
      final TraceSpanRecord toolSpan = localTracer.startAsCurrentSpan(
        'execute_tool',
      );
      final Event responseEvent = Event(
        id: 'ev_cred_1',
        invocationId: 'inv_1',
        author: 'agent',
        content: Content(
          role: 'user',
          parts: <Part>[
            Part.fromFunctionResponse(
              id: 'fc_auth',
              name: 'adk_request_credential',
              response: <String, Object?>{
                'auth_scheme': 'http',
                'exchanged_auth_credential': <String, Object?>{
                  'auth_type': 'apiKey',
                  'api_key': 'sk-euc-secret-999',
                },
              },
            ),
          ],
        ),
      );
      traceToolCall(
        _FinishTool(),
        <String, Object?>{
          'cred': AuthCredential(
            authType: AuthCredentialTypes.apiKey,
            apiKey: 'sk-arg-secret-111',
          ),
        },
        responseEvent,
        span: toolSpan,
      );
      localTracer.endSpan(toolSpan);

      final String argsJson =
          toolSpan.attributes['gcp.vertex.agent.tool_call_args'] as String;
      final String respJson =
          toolSpan.attributes['gcp.vertex.agent.tool_response'] as String;
      expect(argsJson, isNot(contains('sk-arg-secret-111')));
      expect(argsJson, contains(redacted));
      expect(respJson, isNot(contains('sk-euc-secret-999')));

      final TraceSpanRecord mergedSpan = localTracer.startAsCurrentSpan(
        'execute_tool (merged)',
      );
      traceMergedToolCalls(
        'ev_cred_1',
        responseEvent,
        span: mergedSpan,
      );
      localTracer.endSpan(mergedSpan);
      expect(
        mergedSpan.attributes['gcp.vertex.agent.tool_response'] as String,
        isNot(contains('sk-euc-secret-999')),
      );

      // AutoTracingPlugin helper redaction
      expect(
        formatArgForAutoTracing('apiKey', 'sk-auto-secret'),
        equals(redacted),
      );
      expect(
        safeReprForAutoTracing(<String, Object?>{
          'Authorization': 'Bearer tok-xyz',
          'query': 'weather',
        }),
        allOf(isNot(contains('tok-xyz')), contains(redacted), contains('weather')),
      );
    });
  });

  group('3. 5112046cb: sub-agent telemetry inherits ancestor canonicalModel', () {
    test('sub-agent with unset model inherits parent LlmAgent model across SequentialAgent in both directions', () async {
      // Activate simulated Google GenAI instrumentor (version >= 1.0) so Gemini agents
      // delegate span creation (`gcSpan == null`) while non-Gemini agents emit native spans (`gcSpan != null`).
      setGenAiInstrumentationDetectorForTest(() => true, version: '1.0.0');

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );

      // Case A: Process default is Gemini, parent is Claude -> child inherits Claude (non-Gemini -> emits native span)
      LlmAgent.setDefaultModel('gemini-2.5-flash');
      final Agent childUnderClaude = Agent(name: 'child_under_claude', model: '');
      final SequentialAgent seqUnderClaude = SequentialAgent(
        name: 'seq_under_claude',
        subAgents: <BaseAgent>[childUnderClaude],
      );
      Agent(
        name: 'claude_root',
        model: _ScriptedLlm(
          model: 'claude-sonnet-4-6',
          responder: (_) async* {},
        ),
        subAgents: <BaseAgent>[seqUnderClaude],
      );

      final InvocationContext ctxClaudeChild = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_claude_child',
        agent: childUnderClaude,
        session: session,
      );

      bool claudeChildEmittedNativeSpan = false;
      await useInferenceSpan<void>(
        LlmRequest(
          model: 'claude-sonnet-4-6',
          contents: <Content>[Content.userText('hi')],
        ),
        ctxClaudeChild,
        Event(invocationId: 'inv_claude_child', author: 'child_under_claude'),
        (GenerateContentSpan? gcSpan) async {
          claudeChildEmittedNativeSpan = gcSpan != null;
          expect(gcSpan?.span.attributes['gen_ai.system'], 'anthropic');
        },
        environment: const <String, String>{},
      );
      expect(claudeChildEmittedNativeSpan, isTrue);

      // Case B: Process default is GPT-4o (non-Gemini), parent is Gemini -> child inherits Gemini (delegates to GenAI instrumentor -> gcSpan == null)
      LlmAgent.setDefaultModel(
        _ScriptedLlm(model: 'gpt-4o', responder: (_) async* {}),
      );
      final Agent childUnderGemini = Agent(name: 'child_under_gemini', model: '');
      final SequentialAgent seqUnderGemini = SequentialAgent(
        name: 'seq_under_gemini',
        subAgents: <BaseAgent>[childUnderGemini],
      );
      Agent(
        name: 'gemini_root',
        model: _ScriptedLlm(
          model: 'gemini-2.5-pro',
          responder: (_) async* {},
        ),
        subAgents: <BaseAgent>[seqUnderGemini],
      );

      final InvocationContext ctxGeminiChild = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_gemini_child',
        agent: childUnderGemini,
        session: session,
      );

      bool geminiChildDelegatedToInstrumentor = false;
      await useInferenceSpan<void>(
        LlmRequest(
          model: 'gemini-2.5-pro',
          contents: <Content>[Content.userText('hi')],
        ),
        ctxGeminiChild,
        Event(invocationId: 'inv_gemini_child', author: 'child_under_gemini'),
        (GenerateContentSpan? gcSpan) async {
          geminiChildDelegatedToInstrumentor = gcSpan == null;
        },
        environment: const <String, String>{},
      );
      expect(geminiChildDelegatedToInstrumentor, isTrue);
    });
  });

  group('4. 8d857f47d, 56b25c619, 1de97607c: fallback duration, invoke_agent units, and all-schema inference token metrics', () {
    test('8d857f47d: getElapsedSeconds and useInferenceSpan exclude post-finishReason tool runtime when span times are absent', () async {
      // Direct helper check
      expect(
        getElapsedSeconds(
          fallbackStartMicros: 1000000,
          fallbackEndMicros: 1050000,
        ),
        closeTo(0.05, 1e-6),
      );

      // End-to-end useInferenceSpan where traceInferenceResult marks finishReason before a simulated tool delay
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      setAdkMetricsRecorder(recorder);

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Agent agent = Agent(name: 'dur_agent', model: 'gemini-2.5-flash');
      final InvocationContext invCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_dur',
        agent: agent,
        session: session,
      );

      await useInferenceSpan<void>(
        LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('call tool')],
        ),
        invCtx,
        Event(invocationId: 'inv_dur', author: 'dur_agent'),
        (GenerateContentSpan? gcSpan) async {
          expect(gcSpan, isNotNull);
          traceInferenceResult(
            gcSpan,
            LlmResponse(
              content: Content.modelText('done'),
              finishReason: 'STOP',
            ),
          );
          expect(gcSpan!.endedAtMicros, isNotNull);
          // Simulate 80ms of downstream tool execution inside the generator body
          await Future<void>.delayed(const Duration(milliseconds: 80));
        },
        environment: const <String, String>{},
      );

      // Verify getElapsedSeconds with gcSpan's stamped endedAtMicros excludes the 50ms post-finish delay
      final GenerateContentSpan manualSpan = GenerateContentSpan(
        TraceSpanRecord('call_llm'),
        startTimeMicros: 2000000,
      );
      traceInferenceResult(
        manualSpan,
        LlmResponse(content: Content.modelText('ok'), finishReason: 'STOP'),
      );
      final int? stamped = manualSpan.endedAtMicros;
      expect(stamped, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final double elapsed = getElapsedSeconds(
        fallbackStartMicros: 2000000,
        fallbackEndMicros: manualSpan.endedAtMicros,
      );
      final double elapsedWithoutStamp = getElapsedSeconds(
        fallbackStartMicros: 2000000,
      );
      expect(elapsedWithoutStamp - elapsed, greaterThanOrEqualTo(0.04));
    });

    test('56b25c619: invoke_agent call-count metrics use {inference_call} and {tool_call} semconv units', () async {
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      recordInvokeAgentInferenceCalls('planner', 3, recorder: recorder);
      recordInvokeAgentToolCalls('planner', 2, recorder: recorder);

      final AdkMetricRecord infMetric = recorder.records.singleWhere(
        (AdkMetricRecord r) => r.name == genAiInvokeAgentInferenceCallsMetric,
      );
      final AdkMetricRecord toolMetric = recorder.records.singleWhere(
        (AdkMetricRecord r) => r.name == genAiInvokeAgentToolCallsMetric,
      );
      expect(infMetric.unit, '{inference_call}');
      expect(infMetric.value, 3);
      expect(infMetric.explicitBucketBoundariesAdvisory, callCountBucketBounds);

      expect(toolMetric.unit, '{tool_call}');
      expect(toolMetric.value, 2);
      expect(toolMetric.explicitBucketBoundariesAdvisory, callCountBucketBounds);

      // Verify AutoTracingPlugin emits both metrics for direct calls excluding sub-agent calls
      recorder.clear();
      setAdkMetricsRecorder(recorder);
      final AutoTracingPlugin autoPlugin = AutoTracingPlugin(tracer: AdkTracer());
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session s = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Agent root = Agent(name: 'root_auto', model: 'gemini-2.5-flash');
      final Agent sub = Agent(name: 'sub_auto', model: 'gemini-2.5-flash');
      final InvocationContext rootInv = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_auto',
        agent: root,
        session: s,
      );
      final CallbackContext rootCb = Context(rootInv);
      final CallbackContext subCb = Context(rootInv.copyWith(agent: sub));

      await autoPlugin.beforeAgentCallback(agent: root, callbackContext: rootCb);
      await autoPlugin.beforeModelCallback(
        callbackContext: rootCb,
        llmRequest: LlmRequest(model: 'gemini-2.5-flash', contents: <Content>[]),
      );
      await autoPlugin.afterModelCallback(
        callbackContext: rootCb,
        llmResponse: LlmResponse(content: Content.modelText('ok')),
      );
      await autoPlugin.beforeToolCallback(
        tool: _FinishTool(),
        toolArgs: <String, dynamic>{},
        toolContext: Context(rootInv, functionCallId: 'fc_1'),
      );
      await autoPlugin.afterToolCallback(
        tool: _FinishTool(),
        toolArgs: <String, dynamic>{},
        toolContext: Context(rootInv, functionCallId: 'fc_1'),
        result: <String, dynamic>{},
      );
      // Nested sub-agent does 2 LLM calls — must count on sub_auto, NOT root_auto
      await autoPlugin.beforeAgentCallback(agent: sub, callbackContext: subCb);
      for (int i = 0; i < 2; i += 1) {
        await autoPlugin.beforeModelCallback(
          callbackContext: subCb,
          llmRequest: LlmRequest(model: 'gemini-2.5-flash', contents: <Content>[]),
        );
        await autoPlugin.afterModelCallback(
          callbackContext: subCb,
          llmResponse: LlmResponse(content: Content.modelText('sub')),
        );
      }
      await autoPlugin.afterAgentCallback(agent: sub, callbackContext: subCb);
      await autoPlugin.afterAgentCallback(agent: root, callbackContext: rootCb);

      final AdkMetricRecord rootInf = recorder.records.singleWhere(
        (AdkMetricRecord r) =>
            r.name == genAiInvokeAgentInferenceCallsMetric &&
            r.attributes['gen_ai.agent.name'] == 'root_auto',
      );
      final AdkMetricRecord subInf = recorder.records.singleWhere(
        (AdkMetricRecord r) =>
            r.name == genAiInvokeAgentInferenceCallsMetric &&
            r.attributes['gen_ai.agent.name'] == 'sub_auto',
      );
      expect(rootInf.value, 1);
      expect(rootInf.unit, '{inference_call}');
      expect(subInf.value, 2);
    });

    test('1de97607c: records 7 gen_ai.client.inference.* token metrics in BOTH schema v1 and schema v2', () {
      for (final String schemaOptIn in <String>['1', '2']) {
        final InMemoryAdkMetricsRecorder recorder =
            InMemoryAdkMetricsRecorder();
        final Map<String, String> env = <String, String>{
          adkTelemetrySchemaVersionOptIn: schemaOptIn,
        };
        final LlmRequest request = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[Content.userText('analyze')],
        );
        final List<LlmResponse> responses = <LlmResponse>[
          LlmResponse(
            modelVersion: 'gemini-2.5-flash-001',
            finishReason: 'STOP',
            usageMetadata: <String, Object?>{
              'prompt_token_count': 100,
              'tool_use_prompt_token_count': 20,
              'candidates_token_count': 50,
              'cached_content_token_count': 30,
              'thoughts_token_count': 10,
              'prompt_tokens_details': <Map<String, Object?>>[
                <String, Object?>{
                  'modality': 'MODALITY_UNSPECIFIED',
                  'token_count': 80,
                },
                <String, Object?>{'modality': 'IMAGE', 'token_count': 20},
              ],
              'candidates_tokens_details': <Map<String, Object?>>[
                <String, Object?>{'modality': 'TEXT', 'token_count': 50},
              ],
            },
          ),
        ];

        recordClientTokenUsage(
          agentName: 'analyst',
          llmRequest: request,
          responses: responses,
          environment: env,
          recorder: recorder,
        );
        recordSemconvInferenceTokenUsage(
          llmRequest: request,
          responses: responses,
          environment: env,
          recorder: recorder,
        );

        // Legacy gen_ai.client.token.usage uses 'gemini' in v1 and 'gcp.gemini' in v2
        final List<AdkMetricRecord> legacyRecords = recorder.records
            .where((AdkMetricRecord r) => r.name == genAiClientTokenUsageMetric)
            .toList();
        expect(legacyRecords, isNotEmpty);
        expect(
          legacyRecords.first.attributes['gen_ai.provider.name'],
          schemaOptIn == '1' ? 'gemini' : 'gcp.gemini',
        );

        // All 7 gen_ai.client.inference.* metrics ALWAYS use semconv 'gcp.gemini' in BOTH v1 and v2
        final AdkMetricRecord opIn = recorder.records.singleWhere(
          (AdkMetricRecord r) =>
              r.name == genAiClientInferenceOperationInputTokensMetric,
        );
        final AdkMetricRecord opOut = recorder.records.singleWhere(
          (AdkMetricRecord r) =>
              r.name == genAiClientInferenceOperationOutputTokensMetric,
        );
        expect(opIn.value, 120); // 100 prompt + 20 tool_use_prompt
        expect(opIn.attributes['gen_ai.provider.name'], 'gcp.gemini');
        expect(opOut.value, 60); // 50 candidates + 10 thoughts
        expect(opOut.attributes['gen_ai.provider.name'], 'gcp.gemini');

        // Modality breakdown: 80 text (from MODALITY_UNSPECIFIED), 20 image, 20 unknown remainder
        final List<AdkMetricRecord> usageIn = recorder.records
            .where(
              (AdkMetricRecord r) =>
                  r.name == genAiClientInferenceUsageInputTokensMetric,
            )
            .toList();
        final Map<String, num> inputByModality = <String, num>{
          for (final AdkMetricRecord r in usageIn)
            r.attributes['gen_ai.token.modality']! as String: r.value,
        };
        expect(
          inputByModality,
          equals(<String, num>{'text': 80, 'image': 20, 'unknown': 20}),
        );

        // Cache write was unreported -> 0 under 'unknown'
        final AdkMetricRecord cacheWrite = recorder.records.singleWhere(
          (AdkMetricRecord r) =>
              r.name == genAiClientInferenceUsageCacheWriteInputTokensMetric,
        );
        expect(cacheWrite.value, 0);
        expect(cacheWrite.attributes['gen_ai.token.modality'], 'unknown');
      }

      // Instrumentor version gating: 0.7b1 emits, 1.0b0 suppresses for Gemini
      expect(
        shouldEmitSemconvInferenceTokenMetrics(
          'gemini-2.5-flash',
          hasGenAiInstrumentor: true,
          instrumentorVersion: '0.7b1',
        ),
        isTrue,
      );
      expect(
        shouldEmitSemconvInferenceTokenMetrics(
          'gemini-2.5-flash',
          hasGenAiInstrumentor: true,
          instrumentorVersion: '1.0b0',
        ),
        isFalse,
      );
    });
  });

  group('5. f9d948c58: model_consult advisor uses RunConfig.telemetry and records failed call metrics', () {
    test('ModelConsultTool honors RunConfig.telemetry semconv override and records metrics on advisor failure', () async {
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      setAdkMetricsRecorder(recorder);

      final _ScriptedLlm advisorModel = _ScriptedLlm(
        model: 'gemini-2.5-pro',
        responder: (_) async* {
          yield LlmResponse(
            modelVersion: 'gemini-2.5-pro-001',
            content: Content.modelText('Use approach B.'),
            finishReason: 'STOP',
            usageMetadata: <String, Object?>{
              'prompt_token_count': 45,
              'candidates_token_count': 15,
            },
          );
        },
      );

      final Map<String, String> experimentalEnv = <String, String>{
        'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
      };
      setGenAiInstrumentationDetectorForTest(() => true, version: '0.7b1');

      final ModelConsultTool consultTool = ModelConsultTool(
        model: advisorModel,
        environment: experimentalEnv,
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      // Without RunConfig.telemetry override, experimental env + 0.7b1 instrumentor suppresses ADK duration metric
      final ToolContext suppressedCtx = Context(
        InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_consult_suppressed',
          agent: Agent(name: 'caller_agent', model: 'gemini-2.5-flash'),
          session: session,
          runConfig: RunConfig(),
        ),
        functionCallId: 'fc_adv_0',
      );
      await consultTool.run(
        args: <String, dynamic>{'question': 'Choose A or B'},
        toolContext: suppressedCtx,
      );
      expect(
        recorder.records.any(
          (AdkMetricRecord r) => r.name == genAiClientOperationDurationMetric,
        ),
        isFalse,
      );

      // With RunConfig.telemetry override to 'stable', ADK emits duration + inference token metrics
      recorder.clear();
      final RunConfig runConfig = RunConfig()
        ..telemetry = const TelemetryConfig(
          genaiSemconvStabilityOptIn: 'stable',
        );
      expect(runConfig.copyWith().telemetry?.genaiSemconvStabilityOptIn, 'stable');

      final InvocationContext invCtx = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv_consult',
        agent: Agent(name: 'caller_agent', model: 'gemini-2.5-flash'),
        session: session,
        runConfig: runConfig,
      );
      final ToolContext toolCtx = Context(invCtx, functionCallId: 'fc_adv');

      final Object? adviceResult = await consultTool.run(
        args: <String, dynamic>{'question': 'Choose A or B'},
        toolContext: toolCtx,
      );
      expect((adviceResult as Map)['advice'], 'Use approach B.');

      expect(
        recorder.records.any(
          (AdkMetricRecord r) => r.name == genAiClientOperationDurationMetric,
        ),
        isTrue,
      );
      final AdkMetricRecord advInputHist = recorder.records.singleWhere(
        (AdkMetricRecord r) =>
            r.name == genAiClientInferenceOperationInputTokensMetric,
      );
      expect(advInputHist.value, 45);
      expect(advInputHist.attributes['gen_ai.request.model'], 'gemini-2.5-pro');

      // Now verify failed advisor call still emits duration + all 7 inference token metrics with error.type
      recorder.clear();
      final _ScriptedLlm failingAdvisor = _ScriptedLlm(
        model: 'gemini-2.5-pro',
        responder: (_) async* {
          throw StateError('quota exhausted');
        },
      );
      final ModelConsultTool failingTool = ModelConsultTool(
        model: failingAdvisor,
        environment: experimentalEnv,
      );

      final Object? failResult = await failingTool.run(
        args: <String, dynamic>{'question': 'Will fail'},
        toolContext: toolCtx,
      );
      expect((failResult as Map)['status'], 'error');

      final AdkMetricRecord failedHist = recorder.records.singleWhere(
        (AdkMetricRecord r) =>
            r.name == genAiClientInferenceOperationInputTokensMetric,
      );
      expect(failedHist.value, 0);
      expect(failedHist.attributes['error.type'], isNotNull);
    });
  });
}

class _CallbackCapturePlugin extends BasePlugin {
  _CallbackCapturePlugin({required this.onBeforeRun})
    : super(name: 'callback_capture');

  final void Function(InvocationContext context) onBeforeRun;

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    onBeforeRun(invocationContext);
    return null;
  }
}

class _InlineInspectAgent extends BaseAgent {
  _InlineInspectAgent({required super.name, required this.onRun});

  final void Function(InvocationContext context) onRun;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    onRun(context);
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('inspected'),
    );
  }
}

class _ConditionalShortCircuitPlugin extends BasePlugin {
  _ConditionalShortCircuitPlugin({required this.targetAgentName})
    : super(name: 'conditional_short_circuit');

  final String targetAgentName;

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    if (invocationContext.agent.name == targetAgentName) {
      return Content.modelText('short-circuited child');
    }
    return null;
  }
}
