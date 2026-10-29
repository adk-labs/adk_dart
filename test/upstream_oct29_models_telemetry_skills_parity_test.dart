import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

class _FakeSkillGcsStore implements SkillGcsStore {
  _FakeSkillGcsStore(this.blobs);

  final Map<String, List<int>> blobs;

  @override
  Future<List<String>> listBlobNames(String bucketName, {String? prefix}) async {
    final String effectivePrefix = prefix ?? '';
    return blobs.keys
        .where((String key) => key.startsWith(effectivePrefix))
        .toList(growable: false);
  }

  @override
  Future<List<int>?> downloadBlob(String bucketName, String blobName) async {
    final List<int>? bytes = blobs[blobName];
    return bytes == null ? null : List<int>.from(bytes);
  }
}

class _FailingTool extends BaseTool {
  _FailingTool({super.name = 'failing_tool'})
    : super(description: 'Tool that fails or pauses');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'error': 'failed'};
  }
}

class _RecordingAnthropicTransport implements AnthropicRestTransport {
  final List<Map<String, Object?>> capturedRequests = <Map<String, Object?>>[];
  Map<String, Object?> nextResponse = <String, Object?>{
    'content': <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': 'done'},
    ],
    'stop_reason': 'end_turn',
    'usage': <String, Object?>{
      'input_tokens': 10,
      'cache_read_input_tokens': 5,
      'cache_creation_input_tokens': 2,
      'output_tokens': 4,
    },
  };

  @override
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async {
    capturedRequests.add(Map<String, Object?>.from(request));
    return nextResponse;
  }

  @override
  Stream<Map<String, Object?>> streamMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) {
    throw UnimplementedError();
  }
}

class _SseHttpClient extends http.BaseClient {
  _SseHttpClient(this.sseBody);

  final String sseBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(sseBody)]),
      200,
      headers: const <String, String>{'content-type': 'text/event-stream'},
    );
  }
}

class _FakeContainerRuntimeClient implements ContainerRuntimeClient {
  _FakeContainerRuntimeClient({this.onExec});

  final FutureOr<DockerExecResult> Function(
    List<String> command,
    String? workingDirectory,
  )?
  onExec;
  final List<List<String>> recordedCommands = <List<String>>[];

  @override
  Future<void> buildImage({
    required String dockerPath,
    required String imageTag,
  }) async {}

  @override
  Future<String> startContainer({required String imageTag}) async =>
      'container-123';

  @override
  Future<DockerExecResult> exec({
    required String containerId,
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    recordedCommands.add(List<String>.from(command));
    if (onExec != null) {
      return await onExec!(command, workingDirectory);
    }
    if (command.contains('which')) {
      return DockerExecResult(exitCode: 0, stdout: '/usr/bin/python3\n');
    }
    return DockerExecResult(exitCode: 0, stdout: '');
  }

  @override
  Future<void> stopContainer({required String containerId}) async {}

  @override
  Future<bool> isAvailable() async => true;
}

InvocationContext _createInvocationContext({
  String invocationId = 'inv_test',
  List<Event>? events,
}) {
  final Session session = Session(
    id: 'session_1',
    appName: 'app',
    userId: 'user_1',
    events: events,
  );
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: LlmAgent(name: 'root_agent', instruction: 'Helpful assistant.'),
    session: session,
  );
}

Map<String, Object?> _usageMap(LlmResponse response) {
  final Object? raw = response.usageMetadata;
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return const <String, Object?>{};
}

void main() {
  group('1. Anthropic LLM truncated tool calls, tool_choice, and token usage', () {
    test('messageToLlmResponse discards truncated tool_use on max_tokens and model_context_window_exceeded', () {
      for (final String stopReason in <String>[
        'max_tokens',
        'model_context_window_exceeded',
      ]) {
        final LlmResponse response =
            AnthropicLlm.messageToLlmResponse(<String, Object?>{
              'content': <Map<String, Object?>>[
                <String, Object?>{'type': 'text', 'text': 'Calling tool...'},
                <String, Object?>{
                  'type': 'tool_use',
                  'id': 'toolu_1',
                  'name': 'get_weather',
                  'input': <String, Object?>{'city': 'Seoul'},
                },
              ],
              'stop_reason': stopReason,
              'usage': <String, Object?>{
                'input_tokens': 10,
                'output_tokens': 25,
              },
            });

        expect(response.errorCode, 'MAX_TOKENS');
        expect(response.errorMessage, contains(stopReason));
        expect(response.finishReason, 'MAX_TOKENS');
        expect(response.content, isNull);
        final Map<String, Object?> usage = _usageMap(response);
        expect(usage['prompt_token_count'], 10);
        expect(usage['candidates_token_count'], 25);
      }
    });

    test('streaming discards truncated tool_use when stop_reason is max_tokens', () async {
      final AnthropicLlm llm = AnthropicLlm(
        model: 'claude-sonnet-4-20250514',
        streamInvoker: ({required Map<String, Object?> request}) async* {
          yield <String, Object?>{
            'type': 'message_start',
            'message': <String, Object?>{
              'usage': <String, Object?>{
                'input_tokens': 12,
                'cache_read_input_tokens': 3,
                'cache_creation_input_tokens': 5,
                'output_tokens': 0,
              },
            },
          };
          yield <String, Object?>{
            'type': 'content_block_start',
            'index': 0,
            'content_block': <String, Object?>{
              'type': 'tool_use',
              'id': 'toolu_trunc',
              'name': 'query_db',
            },
          };
          yield <String, Object?>{
            'type': 'content_block_delta',
            'index': 0,
            'delta': <String, Object?>{
              'type': 'input_json_delta',
              'partial_json': '{"sql": "SELECT *',
            },
          };
          yield <String, Object?>{
            'type': 'content_block_stop',
            'index': 0,
          };
          yield <String, Object?>{
            'type': 'message_delta',
            'delta': <String, Object?>{'stop_reason': 'max_tokens'},
            'usage': <String, Object?>{
              'input_tokens': 20,
              'cache_read_input_tokens': 4,
              'cache_creation_input_tokens': 6,
              'output_tokens': 50,
            },
          };
        },
      );

      final List<LlmResponse> responses = await llm
          .generateContent(
            LlmRequest(
              model: 'claude-sonnet-4-20250514',
              contents: <Content>[Content.userText('run query')],
            ),
            stream: true,
          )
          .toList();

      expect(responses, hasLength(1));
      final LlmResponse finalResponse = responses.single;
      expect(finalResponse.errorCode, 'MAX_TOKENS');
      expect(finalResponse.finishReason, 'MAX_TOKENS');
      expect(finalResponse.content, isNull);
      final Map<String, Object?> usage = _usageMap(finalResponse);
      // 20 uncached + 4 cached + 6 cache creation = 30 total prompt tokens
      expect(usage['prompt_token_count'], 30);
      expect(usage['cached_content_token_count'], 4);
      expect(usage['cache_creation_input_tokens'], 6);
      expect(usage['candidates_token_count'], 50);
      expect(usage['total_token_count'], 80);
    });

    test('tool_choice mapping and thinking mode fallback from ANY to auto', () async {
      final _RecordingAnthropicTransport transport =
          _RecordingAnthropicTransport();
      final AnthropicLlm llm = AnthropicLlm(
        model: 'claude-sonnet-4-20250514',
        restTransport: transport,
        environment: const <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
      );

      final ToolDeclaration toolDecl = ToolDeclaration(
        functionDeclarations: <FunctionDeclaration>[
          FunctionDeclaration(name: 'my_tool', description: 'test tool'),
        ],
      );

      // 1) mode: ANY without thinking -> tool_choice: {'type': 'any'}
      final List<LlmResponse> anyRes = await llm
          .generateContent(
            LlmRequest(
              model: 'claude-sonnet-4-20250514',
              contents: <Content>[Content.userText('hi')],
              config: GenerateContentConfig(
                tools: <ToolDeclaration>[toolDecl],
                toolConfig: LlmToolConfig(
                  functionCallingConfig: FunctionCallingConfig(
                    mode: FunctionCallingConfigMode.any,
                  ),
                ),
              ),
            ),
          )
          .toList();
      expect(transport.capturedRequests.last['tool_choice'], <String, Object?>{
        'type': 'any',
      });
      final Map<String, Object?> usage = _usageMap(anyRes.single);
      // Prompt tokens = 10 + 5 + 2 = 17
      expect(usage['prompt_token_count'], 17);
      expect(usage['cached_content_token_count'], 5);
      expect(usage['cache_creation_input_tokens'], 2);

      // 2) mode: ANY with thinking enabled -> falls back to {'type': 'auto'}
      await llm
          .generateContent(
            LlmRequest(
              model: 'claude-sonnet-4-20250514',
              contents: <Content>[Content.userText('think and call')],
              config: GenerateContentConfig(
                tools: <ToolDeclaration>[toolDecl],
                thinkingConfig: <String, Object?>{'thinkingBudget': 1024},
                toolConfig: LlmToolConfig(
                  functionCallingConfig: FunctionCallingConfig(
                    mode: FunctionCallingConfigMode.any,
                  ),
                ),
              ),
            ),
          )
          .toList();
      expect(transport.capturedRequests.last['tool_choice'], <String, Object?>{
        'type': 'auto',
      });

      // 3) mode: NONE -> tool_choice is {'type': 'none'}
      await llm
          .generateContent(
            LlmRequest(
              model: 'claude-sonnet-4-20250514',
              contents: <Content>[Content.userText('no tools')],
              config: GenerateContentConfig(
                tools: <ToolDeclaration>[toolDecl],
                toolConfig: LlmToolConfig(
                  functionCallingConfig: FunctionCallingConfig(
                    mode: FunctionCallingConfigMode.none,
                  ),
                ),
              ),
            ),
          )
          .toList();
      expect(transport.capturedRequests.last['tool_choice'], <String, Object?>{
        'type': 'none',
      });
    });
  });

  group('2. Apigee LLM streaming tool call index inference', () {
    test('appends argument-only delta chunks without index to active tool call', () async {
      final String sseBody = <String>[
        'data: ${jsonEncode(<String, Object?>{
          'id': 'chatcmpl-1',
          'model': 'gpt-4o',
          'choices': <Object?>[
            <String, Object?>{
              'index': 0,
              'delta': <String, Object?>{
                'role': 'assistant',
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'index': 0,
                    'id': 'call_abc',
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': 'get_weather',
                      'arguments': '{"city":',
                    },
                  },
                ],
              },
            },
          ],
        })}',
        // Subsequent delta chunk omits `index`, `id`, and `name`.
        'data: ${jsonEncode(<String, Object?>{
          'id': 'chatcmpl-1',
          'model': 'gpt-4o',
          'choices': <Object?>[
            <String, Object?>{
              'index': 0,
              'delta': <String, Object?>{
                'tool_calls': <Object?>[
                  <String, Object?>{
                    'function': <String, Object?>{
                      'arguments': '"Seoul"}',
                    },
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        })}',
        'data: [DONE]',
        '',
      ].join('\n\n');

      final ApigeeLlm llm = ApigeeLlm(
        model: 'apigee/openai/v1/gpt-4o',
        proxyUrl: 'https://proxy.example.com',
        customHeaders: const <String, String>{'x-test': '1'},
        completionsClient: ChatCompletionsHttpClient(
          httpClient: _SseHttpClient(sseBody),
        ),
      );

      final List<LlmResponse> responses = await llm
          .generateContent(
            LlmRequest(
              model: 'apigee/openai/v1/gpt-4o',
              contents: <Content>[Content.userText('weather in Seoul')],
            ),
            stream: true,
          )
          .toList();

      final LlmResponse finalResponse = responses.last;
      final List<Part> functionCallParts = finalResponse.content!.parts
          .where((Part p) => p.functionCall != null)
          .toList();
      expect(functionCallParts, hasLength(1));
      expect(functionCallParts.single.functionCall!.id, 'call_abc');
      expect(functionCallParts.single.functionCall!.name, 'get_weather');
      expect(functionCallParts.single.functionCall!.args, <String, dynamic>{
        'city': 'Seoul',
      });
    });
  });

  group('3. Reflect & Retry Tool and Model Plugins paused invocation handling', () {
    test('isPausedInvocation detects open long-running tool calls, confirmations, and auth requests', () {
      final InvocationContext unpaused = _createInvocationContext(
        invocationId: 'inv_1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[Part.text('Normal reply')],
            ),
          ),
        ],
      );
      expect(isPausedInvocation(unpaused), isFalse);

      // Confirmation requested
      final InvocationContext confirmationPaused = _createInvocationContext(
        invocationId: 'inv_1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'root_agent',
            actions: EventActions(
              requestedToolConfirmations: <String, ToolConfirmation>{
                'fc_confirm': ToolConfirmation(hint: 'Please confirm'),
              },
            ),
          ),
        ],
      );
      expect(isPausedInvocation(confirmationPaused), isTrue);

      // Auth config requested
      final InvocationContext authPaused = _createInvocationContext(
        invocationId: 'inv_1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'root_agent',
            actions: EventActions(
              requestedAuthConfigs: <String, Object>{
                'fc_auth': <String, Object?>{'scheme': 'oauth2'},
              },
            ),
          ),
        ],
      );
      expect(isPausedInvocation(authPaused), isTrue);

      // Open long-running tool call (no matching FunctionResponse yet)
      final InvocationContext lroPaused = _createInvocationContext(
        invocationId: 'inv_1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'root_agent',
            longRunningToolIds: <String>{'fc_lro'},
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'long_job',
                  args: <String, dynamic>{},
                  id: 'fc_lro',
                ),
              ],
            ),
          ),
        ],
      );
      expect(isPausedInvocation(lroPaused), isTrue);

      // Resolved long-running tool call
      final InvocationContext lroResolved = _createInvocationContext(
        invocationId: 'inv_1',
        events: <Event>[
          ...lroPaused.session.events,
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'long_job',
                  response: <String, dynamic>{'status': 'done'},
                  id: 'fc_lro',
                ),
              ],
            ),
          ),
        ],
      );
      expect(isPausedInvocation(lroResolved), isFalse);
    });

    test('ReflectAndRetryToolPlugin skips retry on pending confirmation/auth and preserves counters across paused run', () async {
      final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
        maxRetries: 2,
        throwExceptionIfRetryExceeded: true,
      );
      final _FailingTool tool = _FailingTool();
      final InvocationContext pausedCtx = _createInvocationContext(
        invocationId: 'inv_pause',
        events: <Event>[
          Event(
            invocationId: 'inv_pause',
            author: 'root_agent',
            actions: EventActions(
              requestedToolConfirmations: <String, ToolConfirmation>{
                'call_confirm': ToolConfirmation(hint: 'confirm?'),
              },
            ),
          ),
        ],
      );

      // 1) When functionCallId is in requestedToolConfirmations, afterToolCallback returns null
      final ToolContext confirmToolCtx = Context(
        pausedCtx,
        functionCallId: 'call_confirm',
        eventActions: EventActions(
          requestedToolConfirmations: <String, ToolConfirmation>{
            'call_confirm': ToolConfirmation(hint: 'confirm?'),
          },
        ),
      );
      final Map<String, dynamic>? confirmResult = await plugin.afterToolCallback(
        tool: tool,
        toolArgs: <String, dynamic>{},
        toolContext: confirmToolCtx,
        result: <String, dynamic>{'error': 'Unauthorized'},
      );
      expect(confirmResult, isNull);

      // 2) Normal tool exception increments counter (retry 1 of 2)
      final ToolContext normalToolCtx = Context(
        pausedCtx,
        functionCallId: 'call_fail_1',
      );
      final Map<String, dynamic>? retry1 = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{},
        toolContext: normalToolCtx,
        error: Exception('boom'),
      );
      expect(retry1?['response_type'], reflectAndRetryResponseType);

      // 3) afterRunCallback while invocation is paused keeps the failure counter!
      await plugin.afterRunCallback(invocationContext: pausedCtx);

      // 4) Second failure in the same paused invocation reaches retry 2 of 2
      final Map<String, dynamic>? retry2 = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{},
        toolContext: normalToolCtx,
        error: Exception('boom again'),
      );
      expect(retry2?['response_type'], reflectAndRetryResponseType);

      // 5) Third failure exceeds maxRetries (2) because counter was preserved
      await expectLater(
        () => plugin.onToolErrorCallback(
          tool: tool,
          toolArgs: <String, dynamic>{},
          toolContext: normalToolCtx,
          error: Exception('boom 3'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('4. Telemetry metrics, SpanKind, SQLite migration, and gen_ai.system', () {
    late InMemoryAdkMetricsRecorder metricsRecorder;

    setUp(() {
      metricsRecorder = InMemoryAdkMetricsRecorder();
      setAdkMetricsRecorder(metricsRecorder);
      tracer.clear();
    });

    tearDown(() {
      resetAdkMetricsRecorderForTest();
    });

    test('records workflow and client operation duration histograms with explicit bucket advisories', () {
      expect(agentDurationBucketBounds, isNotEmpty);
      expect(workflowDurationBucketBounds, isNotEmpty);
      expect(operationDurationBucketBounds, isNotEmpty);
      expect(tokenUsageBucketBounds, isNotEmpty);

      recordWorkflowInvocationDuration(
        'wf_agent',
        const Duration(milliseconds: 1250),
      );
      recordClientOperationDuration(
        'wf_agent',
        const Duration(milliseconds: 420),
        operationName: 'generate_content',
        requestModel: 'gemini-2.5-flash',
        error: TimeoutException('slow'),
      );

      final List<AdkMetricRecord> metrics = metricsRecorder.records;
      final AdkMetricRecord wfRecord = metrics.firstWhere(
        (AdkMetricRecord r) =>
            r.name == genAiWorkflowInvocationDurationMetric,
      );
      expect(wfRecord.value, 1.25);
      expect(wfRecord.unit, 's');
      expect(
        wfRecord.explicitBucketBoundariesAdvisory,
        workflowDurationBucketBounds,
      );
      expect(wfRecord.attributes['gen_ai.agent.name'], 'wf_agent');

      final AdkMetricRecord opRecord = metrics.firstWhere(
        (AdkMetricRecord r) => r.name == genAiClientOperationDurationMetric,
      );
      expect(opRecord.value, 0.42);
      expect(
        opRecord.explicitBucketBoundariesAdvisory,
        operationDurationBucketBounds,
      );
      expect(opRecord.attributes['error.type'], 'TimeoutException');
    });

    test('SqliteSpanExporter persists SpanKind and migrates legacy v0 schema', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk_sqlite_span_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final String dbPath = '${tempDir.path}/traces.db';
      // Create legacy v0 database without `kind` column.
      final sqlite3.Database legacyDb = sqlite3.sqlite3.open(dbPath);
      legacyDb.execute('''
        CREATE TABLE spans (
          span_id TEXT PRIMARY KEY,
          trace_id TEXT NOT NULL,
          parent_span_id TEXT,
          name TEXT NOT NULL,
          start_time_unix_nano INTEGER,
          end_time_unix_nano INTEGER,
          session_id TEXT,
          invocation_id TEXT,
          event_id TEXT,
          attributes_json TEXT NOT NULL DEFAULT '{}'
        )
      ''');
      legacyDb.execute('''
        INSERT INTO spans (span_id, trace_id, name, session_id, attributes_json)
        VALUES ('0000000000000010', '00000000000000000000000000000001', 'legacy_op', 'sess_1', '{}')
      ''');
      legacyDb.close();

      // Opening SqliteSpanExporter should migrate the table and set user_version = 1.
      final SqliteSpanExporter exporter = SqliteSpanExporter(dbPath: dbPath);
      addTearDown(exporter.shutdown);

      final List<ReadableSpan> migratedSpans = exporter.getAllSpansForSession(
        'sess_1',
      );
      expect(migratedSpans, hasLength(1));
      expect(migratedSpans.single.kind, SpanKind.internal);

      exporter.export(<ReadableSpan>[
        ReadableSpan(
          name: 'generate_content',
          context: const SpanContext(
            traceId: 0x2,
            spanId: 0x20,
            isRemote: false,
            traceFlags: TraceFlags.sampled,
            traceState: TraceState(),
          ),
          kind: SpanKind.client,
          attributes: <String, Object?>{'gcp.vertex.agent.session_id': 'sess_1'},
        ),
      ]);

      final List<ReadableSpan> allSpans = exporter.getAllSpansForSession(
        'sess_1',
      );
      final ReadableSpan clientSpan = allSpans.firstWhere(
        (ReadableSpan s) => s.name == 'generate_content',
      );
      expect(clientSpan.kind, SpanKind.client);
    });

    test('AdkTracer sets error.type on uncaught span exceptions and resolves gen_ai.system accurately', () async {
      expect(resolveErrorType(ArgumentError('bad')), contains('ArgumentError'));
      expect(
        () => tracer.inSpan(
          'failing_span',
          (TraceSpanRecord span) => throw StateError('span failure'),
        ),
        throwsStateError,
      );
      final TraceSpanRecord failedSpan = tracer.finishedSpans.last;
      expect(failedSpan.attributes['error.type'], 'StateError');

      final InvocationContext ctx = _createInvocationContext();
      await useInferenceSpan<void>(
        LlmRequest(model: 'claude-3-7-sonnet-20250219'),
        ctx,
        Event(invocationId: 'inv_1', author: 'agent'),
        (GenerateContentSpan? _) async {},
      );
      final TraceSpanRecord claudeSpan = tracer.finishedSpans.last;
      expect(claudeSpan.attributes['gen_ai.system'], 'anthropic');

      await useInferenceSpan<void>(
        LlmRequest(model: 'gemini-2.5-pro'),
        ctx,
        Event(invocationId: 'inv_1', author: 'agent'),
        (GenerateContentSpan? _) async {},
      );
      final TraceSpanRecord geminiSpan = tracer.finishedSpans.last;
      expect(geminiSpan.attributes['gen_ai.system'], 'gcp.gemini');

      await useInferenceSpan<void>(
        LlmRequest(model: 'llama-3.3-70b'),
        ctx,
        Event(invocationId: 'inv_1', author: 'agent'),
        (GenerateContentSpan? _) async {},
      );
      final TraceSpanRecord otherSpan = tracer.finishedSpans.last;
      expect(otherSpan.attributes['gen_ai.system'], '_other');
    });
  });

  group('5. ElevenLabs CJK sentence splitting and maxChars fallback', () {
    test('splits streaming text on CJK punctuation and enforces maxChars fallback', () async {
      Stream<String> textStream() async* {
        yield 'こんにちは。元気ですか？「はい！」';
        yield '0123456789ABCDEF';
      }

      final List<String> sentences = await splitElevenLabsTtsSentences(
        textStream(),
        maxChars: 10,
      ).toList();
      expect(
        sentences,
        <String>[
          'こんにちは。',
          '元気ですか？',
          '「はい！」',
          '0123456789',
          'ABCDEF',
        ],
      );
    });
  });

  group('6. BigQuery built-in AI/ML skill and blocked-mode query hints', () {
    test('getBigQuerySkill loads bigquery-ai-ml skill with references', () {
      expect(availableBigQuerySkills, contains('bigquery-ai-ml'));
      final Skill skill = getBigQuerySkill();
      expect(skill.name, 'bigquery-ai-ml');
      expect(skill.description, isNotEmpty);
      expect(skill.instructions, contains('AI.GENERATE'));
      expect(skill.resources.listReferences(), containsAll(<String>[
        'ai_generate.md',
        'ml_contribution_analysis.md',
      ]));
      expect(skill.resources.getReference('ai_generate.md'), contains('AI.'));
      expect(
        skill.resources.getReference('ml_contribution_analysis.md'),
        contains('CREATE MODEL'),
      );

      expect(
        () => getBigQuerySkill('non-existent-skill'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('analyzeContribution and detectAnomalies mention execute_sql when WriteMode.blocked', () async {
      final ToolContext toolContext = Context(_createInvocationContext());
      final Map<String, Object?> contribResult = await analyzeContribution(
        projectId: 'p',
        inputData: 'SELECT 1',
        contributionMetric: 'SUM(x)',
        dimensionIdCols: <String>['dim1'],
        isTestCol: 'is_test',
        credentials: const <String, Object?>{'accessToken': 'tok'},
        settings: BigQueryToolConfig(writeMode: WriteMode.blocked),
        toolContext: toolContext,
      );
      expect(contribResult['status'], 'ERROR');
      expect('${contribResult['error_details']}', contains('execute_sql'));

      final Map<String, Object?> anomalyResult = await detectAnomalies(
        projectId: 'p',
        historyData: 'SELECT 1',
        timesSeriesTimestampCol: 'ts',
        timesSeriesDataCol: 'val',
        credentials: const <String, Object?>{'accessToken': 'tok'},
        settings: BigQueryToolConfig(writeMode: WriteMode.blocked),
        toolContext: toolContext,
      );
      expect(anomalyResult['status'], 'ERROR');
      expect('${anomalyResult['error_details']}', contains('execute_sql'));
    });
  });

  group('7. ContainerCodeExecutor inputDir/outputDir validation and file collection', () {
    test('rejects equal or nested inputDir and outputDir', () {
      expect(
        () => ContainerCodeExecutor(
          image: 'python:3.11',
          inputDir: '/tmp/work',
          outputDir: '/tmp/work',
          runtimeClient: _FakeContainerRuntimeClient(),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ContainerCodeExecutor(
          image: 'python:3.11',
          inputDir: '/tmp/work',
          outputDir: '/tmp/work/outputs',
          runtimeClient: _FakeContainerRuntimeClient(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('stages inputFiles, runs in outputDir, collects outputs, and rejects user:-prefixed files', () async {
      final _FakeContainerRuntimeClient runtime = _FakeContainerRuntimeClient(
        onExec: (List<String> command, String? workingDirectory) {
          if (command.contains('which')) {
            return DockerExecResult(exitCode: 0, stdout: '/usr/bin/python3\n');
          }
          final String joined = command.join(' ');
          if (joined.contains('os.walk')) {
            return DockerExecResult(
              exitCode: 0,
              stdout: jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'name': 'chart.png',
                  'size': 4,
                  'content': base64Encode(<int>[137, 80, 78, 71]),
                },
              ]),
            );
          }
          return DockerExecResult(exitCode: 0, stdout: 'ok\n');
        },
      );

      final ContainerCodeExecutor executor = ContainerCodeExecutor(
        image: 'python:3.11',
        runtimeClient: runtime,
      );
      final CodeExecutionResult result = await executor.executeCode(
        _createInvocationContext(),
        CodeExecutionInput(
          code: 'print("ok")',
          inputFiles: <CodeExecutionFile>[
            CodeExecutionFile(
              name: 'data.csv',
              content: base64Encode(utf8.encode('a,b\n1,2\n')),
              mimeType: 'text/csv',
            ),
          ],
        ),
      );

      expect(result.stdout, 'ok\n');
      expect(result.outputFiles, hasLength(1));
      expect(result.outputFiles.single.name, 'chart.png');
      expect(result.outputFiles.single.mimeType, 'image/png');

      // Rejects user:-prefixed output file name
      final _FakeContainerRuntimeClient badNameRuntime =
          _FakeContainerRuntimeClient(
            onExec: (List<String> command, String? workingDirectory) {
              if (command.contains('which')) {
                return DockerExecResult(
                  exitCode: 0,
                  stdout: '/usr/bin/python3\n',
                );
              }
              if (command.join(' ').contains('os.walk')) {
                return DockerExecResult(
                  exitCode: 0,
                  stdout: jsonEncode(<Map<String, Object?>>[
                    <String, Object?>{
                      'name': 'user:secret.txt',
                      'size': 2,
                      'content': base64Encode(<int>[65, 66]),
                    },
                  ]),
                );
              }
              return DockerExecResult(exitCode: 0, stdout: '');
            },
          );
      final ContainerCodeExecutor badNameExecutor = ContainerCodeExecutor(
        image: 'python:3.11',
        runtimeClient: badNameRuntime,
      );
      await expectLater(
        () => badNameExecutor.executeCode(
          _createInvocationContext(),
          CodeExecutionInput(code: 'print(1)'),
        ),
        throwsStateError,
      );
    });
  });

  group('8. Skills GCS path validation and whole-line frontmatter delimiters', () {
    test('loadSkillFromGcsDir rejects traversal, backslash, null-byte, and empty segments in skillId', () async {
      final _FakeSkillGcsStore store = _FakeSkillGcsStore(<String, List<int>>{});
      for (final String badId in <String>[
        '',
        '/',
        '..',
        'foo/../bar',
        r'foo\bar',
        'foo//bar',
        'foo\x00bar',
      ]) {
        await expectLater(
          () => loadSkillFromGcsDir('bucket', badId, storageStore: store),
          throwsA(isA<ArgumentError>()),
          reason: 'Expected ArgumentError for skillId="$badId"',
        );
      }
    });

    test('SKILL.md frontmatter allows --- inside YAML values and requires whole-line closing ---', () async {
      final String validMd =
          '---\n'
          'name: demo-skill\n'
          'description: "Step 1 --- Step 2"\n'
          '---\n'
          'Body with --- inline.';
      final _FakeSkillGcsStore store = _FakeSkillGcsStore(<String, List<int>>{
        'demo-skill/SKILL.md': utf8.encode(validMd),
      });
      final Skill skill = await loadSkillFromGcsDir(
        'bucket',
        'demo-skill',
        storageStore: store,
      );
      expect(skill.name, 'demo-skill');
      expect(skill.description, 'Step 1 --- Step 2');
      expect(skill.instructions, 'Body with --- inline.');

      final String unclosedMd =
          '---\n'
          'name: broken-skill\n'
          'description: "has --- inline but no closing line"\n';
      final _FakeSkillGcsStore badStore = _FakeSkillGcsStore(<String, List<int>>{
        'broken-skill/SKILL.md': utf8.encode(unclosedMd),
      });
      await expectLater(
        () => loadSkillFromGcsDir(
          'bucket',
          'broken-skill',
          storageStore: badStore,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('9. VMaaS AgentEngineEnvironment timeout cap and chunked file I/O', () {
    test('caps execution timeout at 570s, enforces 1 MiB read limit, and chunks large writes', () async {
      Duration? recordedTimeout;
      final List<String> executedCommands = <String>[];
      final Uint8List smallBytes = Uint8List.fromList(utf8.encode('hello vmaas'));

      final ShellBackedAgentEngineSandboxClient client =
          ShellBackedAgentEngineSandboxClient(
            commandRunner: ({
              required String sandboxResourceName,
              required String command,
              String? workingDir,
              Duration? timeout,
              Map<String, String>? envVars,
            }) async {
              recordedTimeout = timeout;
              executedCommands.add(command);
              if (command.contains('stat -L -c %s')) {
                if (command.contains('oversize.bin')) {
                  return const EnvironmentExecutionResult(
                    exitCode: 67,
                    stdout: '2000000\n',
                  );
                }
                return EnvironmentExecutionResult(
                  exitCode: 0,
                  stdout: '${smallBytes.length}\n',
                );
              }
              if (command.contains('dd if=')) {
                return EnvironmentExecutionResult(
                  exitCode: 0,
                  stdout: base64Encode(smallBytes),
                );
              }
              if (command.contains('mktemp')) {
                return const EnvironmentExecutionResult(
                  exitCode: 0,
                  stdout: '/workspace/.adk_stage.ABC123\n',
                );
              }
              return const EnvironmentExecutionResult(exitCode: 0);
            },
          );

      final AgentEngineEnvironment env = AgentEngineEnvironment(
        agentEngineResourceName:
            'projects/p/locations/us-central1/reasoningEngines/1',
        client: client,
      );

      // 1) Timeout > 570s is capped to 570s
      await env.execute('echo hi', timeout: const Duration(seconds: 900));
      expect(recordedTimeout, const Duration(seconds: 570));

      // 2) readFile reads via stat + dd
      final List<int> readResult = await env.readFile('/workspace/small.txt');
      expect(utf8.decode(readResult), 'hello vmaas');

      // 3) readFile throws StateError when file exceeds 1 MiB
      await expectLater(
        () => env.readFile('/workspace/oversize.bin'),
        throwsStateError,
      );

      // 4) writeBytes > 64 MiB throws ArgumentError
      await expectLater(
        () => env.writeBytes(
          '/workspace/huge.bin',
          Uint8List(AgentEngineEnvironment.maxWriteFileBytes + 1),
        ),
        throwsA(isA<ArgumentError>()),
      );

      // 5) writeBytes with > 96 KiB base64 stages via mktemp in chunks
      executedCommands.clear();
      final Uint8List mediumPayload = Uint8List(80 * 1024);
      await env.writeBytes('/workspace/medium.bin', mediumPayload);
      expect(
        executedCommands.any((String cmd) => cmd.contains('mktemp')),
        isTrue,
      );
      expect(
        executedCommands.any((String cmd) => cmd.contains('mv -fT')),
        isTrue,
      );
    });
  });

  group('10. AgentRegistry authProviderBindings continueUri and scopes resolution', () {
    test('extracts scopes and continueUri from authProviderBindings and allows caller override', () async {
      final AgentRegistry registry = AgentRegistry(
        projectId: 'test-proj',
        location: 'global',
        authHeadersProvider: () async => <String, String>{
          'Authorization': 'Bearer tok',
        },
        httpGetProvider: (Uri uri, {required Map<String, String> headers}) async {
          return AgentRegistryHttpResponse(
            statusCode: 200,
            body: <String, Object?>{
              'displayName': 'Bound MCP',
              'mcpServerId': 'mcp-bound-1',
              'interfaces': <Map<String, Object?>>[
                <String, Object?>{
                  'url': 'https://mcp.bound.example.com',
                  'protocolBinding': 'JSONRPC',
                },
              ],
              'authProviderBindings': <Map<String, Object?>>[
                <String, Object?>{
                  'updateTime': '2026-10-01T10:00:00Z',
                  'authProviderBinding': <String, Object?>{
                    'authProvider': 'projects/p/locations/l/authProviders/old',
                    'scopes': <String>['scope.old'],
                    'continueUri': 'https://old.example.com/callback',
                  },
                },
                <String, Object?>{
                  'updateTime': '2026-10-20T12:30:00.500Z',
                  'authProviderBinding': <String, Object?>{
                    'authProvider': 'projects/p/locations/l/authProviders/new',
                    'scopes': <String>['scope.read', 'scope.write'],
                    'continueUri': 'https://new.example.com/callback',
                  },
                },
              ],
            },
          );
        },
      );

      final AgentRegistrySingleMcpToolset toolset =
          await registry.getMcpToolset(
                'projects/p/locations/l/mcpServers/bound',
              )
              as AgentRegistrySingleMcpToolset;

      final GcpAuthProviderScheme scheme =
          toolset.authScheme as GcpAuthProviderScheme;
      expect(scheme.name, 'projects/p/locations/l/authProviders/new');
      expect(scheme.scopes, <String>['scope.read', 'scope.write']);
      expect(scheme.continueUri, 'https://new.example.com/callback');
      expect(toolset.authConfig, isNotNull);

      // Caller continueUri overrides binding's continueUri
      final AgentRegistrySingleMcpToolset overriddenToolset =
          await registry.getMcpToolset(
                'projects/p/locations/l/mcpServers/bound',
                continueUri: 'https://override.example.com/cb',
              )
              as AgentRegistrySingleMcpToolset;
      final GcpAuthProviderScheme overriddenScheme =
          overriddenToolset.authScheme as GcpAuthProviderScheme;
      expect(overriddenScheme.continueUri, 'https://override.example.com/cb');
    });
  });
}
