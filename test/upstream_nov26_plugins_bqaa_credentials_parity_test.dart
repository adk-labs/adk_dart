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
  _FakeTool() : super(name: 'login_tool', description: 'login tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

String _squashSql(String sql) {
  return sql.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _extractCteBody(String sql, String cteName) {
  final RegExp pattern = RegExp(
    '\\b$cteName AS \\((.*?)\\)(?:,\\s*(?:--[^\\n]*\\n\\s*)*[A-Za-z_][A-Za-z0-9_]* AS \\(|\\s*SELECT\\b)',
    dotAll: true,
  );
  final RegExpMatch? match = pattern.firstMatch(sql);
  if (match == null) {
    throw StateError('CTE $cteName not found in SQL');
  }
  return _squashSql(match.group(1)!);
}

void main() {
  group('1. e3dbdc172: credential_names and AutoTracingPlugin redaction', () {
    test('credentialArgNames and credentialArgSuffixes include new secret keys', () {
      expect(
        credentialArgNames,
        containsAll(<String>[
          'passwd',
          'secret_key',
          'secret_access_key',
          'x_amz_signature',
          'x_goog_signature',
        ]),
      );
      expect(
        credentialArgSuffixes,
        containsAll(<String>[
          '_passwd',
          '_secret_key',
          '_secret_access_key',
        ]),
      );
    });

    test('isCredentialArgName matches secret spellings and spares ordinary names', () {
      const List<String> secretNames = <String>[
        'secret_key',
        'secretKey',
        'stripe_secret_key',
        'db_secret_key',
        'stripeSecretKey',
        'aws_secret_access_key',
        'AWS_SECRET_ACCESS_KEY',
        'awsSecretAccessKey',
        'secret_access_key',
        'passwd',
        'db_passwd',
        'dbPasswd',
        'x_amz_signature',
        'X-Amz-Signature',
        'x_goog_signature',
        'X-Goog-Signature',
        'openai_api_key',
        'service_account_credentials',
      ];
      for (final String name in secretNames) {
        expect(isCredentialArgName(name), isTrue, reason: 'Expected $name');
      }

      const List<String> ordinaryNames = <String>[
        'secretary',
        'passage',
        'key_count',
        'prompt_token_count',
        'signature',
        'sig',
        'google_access_id',
        'user',
      ];
      for (final String name in ordinaryNames) {
        expect(isCredentialArgName(name), isFalse, reason: 'Expected $name');
      }
    });

    test('formatArgForAutoTracing and AutoTracingPlugin keep secret_key/passwd out of spans', () async {
      const String sentinel = 'SUPER_SECRET_SENTINEL_VALUE';
      expect(formatArgForAutoTracing('secret_key', sentinel), redacted);
      expect(formatArgForAutoTracing('stripe_secret_key', sentinel), redacted);
      expect(
        formatArgForAutoTracing('aws_secret_access_key', sentinel),
        redacted,
      );
      expect(formatArgForAutoTracing('passwd', sentinel), redacted);
      expect(formatArgForAutoTracing('db_passwd', sentinel), redacted);
      expect(formatArgForAutoTracing('x_amz_signature', sentinel), redacted);
      expect(formatArgForAutoTracing('x_goog_signature', sentinel), redacted);

      expect(formatArgForAutoTracing('secretary', 'bob'), 'bob');
      expect(formatArgForAutoTracing('passage', 'chapter one'), 'chapter one');
      expect(formatArgForAutoTracing('key_count', 3), '3');
      expect(formatArgForAutoTracing('signature', 'sig_obj'), 'sig_obj');

      final AdkTracer localTracer = AdkTracer();
      final AutoTracingPlugin plugin = AutoTracingPlugin(tracer: localTracer);
      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_cred_args',
        agent: LlmAgent(
          name: 'root_agent',
          model: _NoopModel(),
          disallowTransferToParent: true,
          disallowTransferToPeers: true,
        ),
        session: Session(id: 's1', appName: 'app', userId: 'u1'),
      );
      final ToolContext toolContext = Context(
        invocationContext,
        functionCallId: 'fc_1',
      );
      final BaseTool tool = _FakeTool();

      final Map<String, dynamic> toolArgs = <String, dynamic>{
        'user': 'alice',
        'token': sentinel,
        'api_key': sentinel,
        'refresh_token': sentinel,
        'secret_key': sentinel,
        'stripe_secret_key': sentinel,
        'aws_secret_access_key': sentinel,
        'passwd': sentinel,
        'db_passwd': sentinel,
        'x_amz_signature': sentinel,
        'x_goog_signature': sentinel,
        'secretary': 'bob',
        'passage': 'chapter one',
        'key_count': 3,
      };

      await plugin.beforeToolCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
      );
      await plugin.afterToolCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        result: <String, dynamic>{'user': 'alice'},
      );

      final TraceSpanRecord span = localTracer.finishedSpans.single;
      final String renderedArgs =
          span.attributes['adk.fn.arg.tool_args'] as String;
      expect(renderedArgs, isNot(contains(sentinel)));
      expect(renderedArgs, contains('secret_key: $redacted'));
      expect(renderedArgs, contains('stripe_secret_key: $redacted'));
      expect(renderedArgs, contains('aws_secret_access_key: $redacted'));
      expect(renderedArgs, contains('passwd: $redacted'));
      expect(renderedArgs, contains('db_passwd: $redacted'));
      expect(renderedArgs, contains('x_amz_signature: $redacted'));
      expect(renderedArgs, contains('x_goog_signature: $redacted'));
      expect(renderedArgs, contains('user: alice'));
      expect(renderedArgs, contains('secretary: bob'));
      expect(renderedArgs, contains('passage: chapter one'));
      expect(renderedArgs, contains('key_count: 3'));
    });
  });

  group('2. 851b7707a: BQAA eval SQL deterministic tiebreakers and SessionRollup root_agent', () {
    test('TurnRollup breaks timestamp ties by event_id', () {
      for (final String sql in <String>[
        buildEvalSessionQuerySql('proj.ds.agent_events'),
        buildEvalTurnQuerySql('proj.ds.agent_events'),
      ]) {
        final String turnRollup = _extractCteBody(sql, 'TurnRollup');
        expect(
          turnRollup,
          contains(
            'user_id IGNORE NULLS ORDER BY timestamp, event_id LIMIT 1',
          ),
        );
        expect(
          turnRollup,
          contains(
            'root_agent_name IGNORE NULLS ORDER BY timestamp, event_id LIMIT 1',
          ),
        );
        expect(
          turnRollup,
          contains('agent IGNORE NULLS ORDER BY timestamp, event_id LIMIT 1'),
        );
      }
    });

    test('AgentRows projects event_id and AgentLatest uses timestamp DESC, event_id DESC', () {
      for (final String sql in <String>[
        buildEvalSessionQuerySql('proj.ds.agent_events'),
        buildEvalTurnQuerySql('proj.ds.agent_events'),
      ]) {
        final String agentRows = _extractCteBody(sql, 'AgentRows');
        expect(agentRows, contains('timestamp, event_id,'));

        final String agentLatest = _extractCteBody(sql, 'AgentLatest');
        for (final String column in const <String>[
          'instruction',
          'description',
          'sub_agents',
          'tool_declarations',
        ]) {
          expect(
            agentLatest,
            contains(
              '$column IGNORE NULLS ORDER BY timestamp DESC, event_id DESC LIMIT 1',
            ),
          );
        }
      }
    });

    test('SessionRollup uses invocation_id tiebreakers and aggregates root_agent from Turns', () {
      final String sessionQuerySql = buildEvalSessionQuerySql(
        'proj.ds.agent_events',
      );
      final String sessionViewSql = buildEvalSessionViewSql(
        'proj.ds.agent_events',
      );

      for (final String sql in <String>[sessionQuerySql, sessionViewSql]) {
        final String sessionRollup = _extractCteBody(sql, 'SessionRollup');
        expect(
          sessionRollup,
          contains(
            'user_id IGNORE NULLS ORDER BY turn_start_timestamp, invocation_id LIMIT 1',
          ),
        );
        expect(
          sessionRollup,
          contains(
            'root_agent IGNORE NULLS ORDER BY turn_start_timestamp, invocation_id LIMIT 1',
          ),
        );
        expect(sessionRollup, isNot(contains('first_root_agent_name')));
        expect(sessionRollup, isNot(contains('first_agent')));
      }
    });
  });

  group('3. 3e322e9a9: BQAA eval SQL scoped_system_prompt resolution', () {
    test('AgentRows extracts system_prompt, AgentLatest aggregates scoped_system_prompt, and AgentConfigs prefers it', () {
      final List<String> sqls = <String>[
        buildEvalSessionQuerySql('proj.ds.agent_events'),
        buildEvalTurnQuerySql('proj.ds.agent_events'),
        buildEvalSessionViewSql('proj.ds.agent_events'),
        buildEvalTurnViewSql('proj.ds.agent_events'),
      ];

      for (final String sql in sqls) {
        final String agentRows = _extractCteBody(sql, 'AgentRows');
        expect(
          agentRows,
          contains(
            "IF( event_type = 'LLM_REQUEST' "
            "AND JSON_TYPE(JSON_QUERY(content, '\$.system_prompt')) = 'string' "
            "AND TRIM(JSON_VALUE(content, '\$.system_prompt')) != '', "
            "JSON_VALUE(content, '\$.system_prompt'), NULL ) AS system_prompt",
          ),
        );

        final String agentLatest = _extractCteBody(sql, 'AgentLatest');
        expect(
          agentLatest,
          contains(
            'ARRAY_AGG( system_prompt IGNORE NULLS ORDER BY timestamp, event_id LIMIT 1 )[SAFE_OFFSET(0)] AS scoped_system_prompt',
          ),
        );

        final String agentConfigs = _extractCteBody(sql, 'AgentConfigs');
        expect(
          agentConfigs,
          contains(
            "'instruction', COALESCE( NULLIF(instruction, ''), scoped_system_prompt, logged_system_prompt, '' )",
          ),
        );

        final String sessionAgentPrompts = _extractCteBody(
          sql,
          'SessionAgentPrompts',
        );
        expect(
          sessionAgentPrompts,
          contains('AS logged_system_prompt'),
        );
      }
    });
  });
}
