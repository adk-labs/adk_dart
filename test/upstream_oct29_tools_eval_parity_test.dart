import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/apps/base_events_summarizer.dart';
import 'package:adk_dart/src/artifacts/base_artifact_service.dart';
import 'package:adk_dart/src/artifacts/in_memory_artifact_service.dart';
import 'package:adk_dart/src/evaluation/agent_evaluator.dart';
import 'package:adk_dart/src/evaluation/app_details.dart';
import 'package:adk_dart/src/evaluation/eval_case.dart';
import 'package:adk_dart/src/evaluation/eval_metrics.dart';
import 'package:adk_dart/src/evaluation/eval_rubrics.dart';
import 'package:adk_dart/src/evaluation/eval_set.dart';
import 'package:adk_dart/src/evaluation/evaluator.dart';
import 'package:adk_dart/src/evaluation/final_response_match_v1.dart';
import 'package:adk_dart/src/evaluation/final_response_match_v2.dart';
import 'package:adk_dart/src/evaluation/llm_as_judge_utils.dart';
import 'package:adk_dart/src/evaluation/response_evaluator.dart';
import 'package:adk_dart/src/evaluation/rubric_based_multi_turn_trajectory_evaluator.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/event_actions.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/skills/skill.dart';
import 'package:adk_dart/src/tools/agent_tool.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/tools/load_artifacts_tool.dart';
import 'package:adk_dart/src/tools/load_web_page.dart';
import 'package:adk_dart/src/tools/openapi_tool/common/common.dart';
import 'package:adk_dart/src/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.dart';
import 'package:adk_dart/src/tools/openapi_tool/openapi_spec_parser/rest_api_tool.dart';
import 'package:adk_dart/src/tools/retrieval/base_retrieval_tool.dart';
import 'package:adk_dart/src/tools/set_model_response_tool.dart';
import 'package:adk_dart/src/tools/tool_context.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:test/test.dart';

enum _TestPriority {
  low(1),
  high(2);

  const _TestPriority(this.value);
  final int value;
}

class _TestRetrievalTool extends BaseRetrievalTool {
  _TestRetrievalTool()
    : super(name: 'search_kb', description: 'Searches knowledge base.');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return args['query'];
  }
}

class _SequenceLlm extends BaseLlm {
  _SequenceLlm(this.responses) : super(model: 'mock-llm');

  final List<LlmResponse> Function(LlmRequest request, int callIndex) responses;
  final List<LlmRequest> seenRequests = <LlmRequest>[];
  int _callCount = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final int idx = _callCount++;
    seenRequests.add(request);
    for (final LlmResponse response in responses(request, idx)) {
      yield response;
    }
  }
}

class _CountingSummarizer extends BaseEventsSummarizer {
  int callCount = 0;

  @override
  Future<Event?> maybeSummarizeEvents({required List<Event> events}) async {
    callCount += 1;
    return Event(
      invocationId: Event.newId(),
      author: 'user',
      content: Content.userText('Compacted summary'),
      actions: EventActions(
        compaction: EventCompaction(
          startTimestamp: events.first.timestamp,
          endTimestamp: events.last.timestamp,
          compactedContent: Content.userText('Compacted summary'),
        ),
      ),
    );
  }
}

Future<ToolContext> _createToolContext({
  BaseArtifactService? artifactService,
  EventsCompactionConfig? eventsCompactionConfig,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'test_app',
    userId: 'user_1',
    sessionId: 'session_1',
  );
  final LlmAgent rootAgent = LlmAgent(
    name: 'root_agent',
    model: _SequenceLlm((_, _) => <LlmResponse>[
      LlmResponse(content: Content.modelText('ok')),
    ]),
  );
  final InvocationContext invocationContext = InvocationContext(
    sessionService: sessionService,
    artifactService: artifactService ?? InMemoryArtifactService(),
    invocationId: 'inv_1',
    agent: rootAgent,
    session: session,
    eventsCompactionConfig: eventsCompactionConfig,
  );
  return Context(invocationContext, functionCallId: 'fc_1');
}

void main() {
  group('95dd267c2: AgentTool inputSchema validation error return', () {
    final Map<String, Object?> strictSchema = <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'count': <String, Object?>{'type': 'integer'},
      },
      'required': <String>['count'],
    };

    test('AgentTool returns validation error dict without setting skipSummarization', () async {
      final LlmAgent subAgent = LlmAgent(
        name: 'sub_agent',
        description: 'Sub agent with schema',
        inputSchema: strictSchema,
        model: _SequenceLlm((_, _) => <LlmResponse>[
          LlmResponse(content: Content.modelText('valid run')),
        ]),
      );
      final AgentTool tool = AgentTool(
        agent: subAgent,
        skipSummarization: true,
      );
      final ToolContext toolContext = await _createToolContext();

      final Object? badResult = await tool.run(
        args: <String, dynamic>{'count': 'not_an_int'},
        toolContext: toolContext,
      );
      expect(badResult, isA<Map<String, Object?>>());
      final Map<String, Object?> errorMap = badResult! as Map<String, Object?>;
      expect(
        errorMap['error'],
        contains('Invoking `sub_agent()` failed due to argument validation errors:'),
      );
      expect(toolContext.actions.skipSummarization, isNot(true));

      final Object? validResult = await tool.run(
        args: <String, dynamic>{'count': 42},
        toolContext: toolContext,
      );
      expect(validResult, 'valid run');
      expect(toolContext.actions.skipSummarization, isTrue);
    });

    test('SingleTurnAgentTool and TaskAgentTool return validation error dict', () async {
      final LlmAgent subAgent = LlmAgent(
        name: 'single_turn_sub',
        inputSchema: strictSchema,
        model: _SequenceLlm((_, _) => <LlmResponse>[
          LlmResponse(content: Content.modelText('ok')),
        ]),
      );
      final SingleTurnAgentTool singleTurnTool = SingleTurnAgentTool(
        agent: subAgent,
        skipSummarization: true,
      );
      final TaskAgentTool taskTool = TaskAgentTool(
        agent: subAgent,
        skipSummarization: true,
      );
      final ToolContext toolContext = await _createToolContext();

      final Object? res1 = await singleTurnTool.run(
        args: <String, dynamic>{},
        toolContext: toolContext,
      );
      expect(
        (res1 as Map<String, Object?>)['error'],
        contains('Invoking `single_turn_sub()` failed due to argument validation errors:'),
      );
      expect(toolContext.actions.skipSummarization, isNot(true));

      final Object? res2 = await taskTool.run(
        args: <String, dynamic>{},
        toolContext: toolContext,
      );
      expect(
        (res2 as Map<String, Object?>)['error'],
        contains('Invoking `single_turn_sub()` failed due to argument validation errors:'),
      );
      expect(toolContext.actions.skipSummarization, isNot(true));
    });
  });

  group('ae8323b6d: AgentTool nested token-threshold compaction', () {
    test('compacts nested history at caller token threshold and skips post-invocation compaction', () async {
      final _CountingSummarizer summarizer = _CountingSummarizer();
      final EventsCompactionConfig callerConfig = EventsCompactionConfig(
        compactionInterval: 1,
        overlapSize: 0,
        tokenThreshold: 50,
        eventRetentionSize: 1,
        summarizer: summarizer,
      );

      final FunctionTool dummyTool = FunctionTool(
        func: ({required String input}) => 'tool_result:$input',
        name: 'step_tool',
        description: 'Step tool',
      );

      final _SequenceLlm nestedLlm = _SequenceLlm((LlmRequest req, int callIdx) {
        if (callIdx == 0) {
          return <LlmResponse>[
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'step_tool',
                    args: <String, dynamic>{'input': '1'},
                    id: 'call_1',
                  ),
                ],
              ),
              usageMetadata: <String, Object?>{'promptTokenCount': 100},
            ),
          ];
        }
        if (callIdx == 1) {
          return <LlmResponse>[
            LlmResponse(
              content: Content(
                role: 'model',
                parts: <Part>[
                  Part.fromFunctionCall(
                    name: 'step_tool',
                    args: <String, dynamic>{'input': '2'},
                    id: 'call_2',
                  ),
                ],
              ),
              usageMetadata: <String, Object?>{'promptTokenCount': 20},
            ),
          ];
        }
        return <LlmResponse>[
          LlmResponse(
            content: Content.modelText('final nested answer'),
            usageMetadata: <String, Object?>{'promptTokenCount': 200},
          ),
        ];
      });

      final LlmAgent nestedAgent = LlmAgent(
        name: 'nested_agent',
        model: nestedLlm,
        tools: <Object>[dummyTool],
      );
      final AgentTool agentTool = AgentTool(agent: nestedAgent);
      final ToolContext toolContext = await _createToolContext(
        eventsCompactionConfig: callerConfig,
      );

      final Object? result = await agentTool.run(
        args: <String, dynamic>{'request': 'run multi-step'},
        toolContext: toolContext,
      );
      expect(result, 'final nested answer');
      // In-flow compaction ran once after callIdx 0 exceeded tokenThreshold (100 >= 50),
      // and post-invocation compaction did NOT run after the final turn.
      expect(summarizer.callCount, 1);
    });

    test('does not mutate caller EventsCompactionConfig summarizer when null', () async {
      final EventsCompactionConfig callerConfig = EventsCompactionConfig(
        tokenThreshold: 50,
        eventRetentionSize: 1,
      );
      final LlmAgent nestedAgent = LlmAgent(
        name: 'nested_agent',
        model: _SequenceLlm((_, _) => <LlmResponse>[
          LlmResponse(content: Content.modelText('done')),
        ]),
      );
      final AgentTool agentTool = AgentTool(agent: nestedAgent);
      final ToolContext toolContext = await _createToolContext(
        eventsCompactionConfig: callerConfig,
      );

      await agentTool.run(
        args: <String, dynamic>{'request': 'hello'},
        toolContext: toolContext,
      );
      expect(callerConfig.summarizer, isNull);
    });
  });

  group('0c053dd5a: LoadArtifactsTool processArtifactNames filtering', () {
    test('filters hidden artifacts from run and processLlmRequest', () async {
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      await artifactService.saveArtifact(
        appName: 'test_app',
        userId: 'user_1',
        sessionId: 'session_1',
        filename: 'visible.txt',
        artifact: Part.text('visible content'),
      );
      await artifactService.saveArtifact(
        appName: 'test_app',
        userId: 'user_1',
        sessionId: 'session_1',
        filename: 'secret.txt',
        artifact: Part.text('secret content'),
      );
      await artifactService.saveArtifact(
        appName: 'test_app',
        userId: 'user_1',
        sessionId: 'session_1',
        filename: 'user:secret.txt',
        artifact: Part.text('user secret content'),
      );

      final LoadArtifactsTool tool = LoadArtifactsTool(
        processArtifactNames: (List<String> names, ToolContext context) {
          return names
              .where((String name) => !name.contains('secret'))
              .toList(growable: false);
        },
      );

      final ToolContext toolContext = await _createToolContext(
        artifactService: artifactService,
      );

      final Object? runResult = await tool.run(
        args: <String, dynamic>{
          'artifact_names': <String>['visible.txt', 'secret.txt'],
        },
        toolContext: toolContext,
      );
      expect(runResult, <String, Object?>{
        'artifact_names': <String>['visible.txt'],
        'status':
            'artifact contents temporarily inserted and removed. to access these artifacts, call load_artifacts tool again.',
      });

      final LlmRequest llmRequest = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['visible.txt', 'secret.txt'],
                },
              ),
            ],
          ),
        ],
      );
      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: llmRequest,
      );

      expect(
        llmRequest.config.systemInstruction,
        contains('["visible.txt"]'),
      );
      expect(
        llmRequest.config.systemInstruction,
        isNot(contains('secret.txt')),
      );
      final String appendedTexts = llmRequest.contents
          .expand((Content c) => c.parts)
          .map((Part p) => p.text ?? '')
          .join('\n');
      expect(appendedTexts, contains('visible content'));
      expect(appendedTexts, isNot(contains('secret content')));
    });
  });

  group('4d0cd985f: reject URLs with backslash in authority', () {
    test('loadWebPage rejects raw and percent-encoded backslashes in authority', () async {
      await expectLater(
        () => loadWebPage(r'https://evil.com\@trusted.com/path'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => loadWebPage('https://evil.com%5c@trusted.com/path'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('RestApiTool rejects URLs with backslash in authority', () async {
      final RestApiTool tool = RestApiTool(
        name: 'get_item',
        description: 'Get item',
        endpoint: OperationEndpoint(
          baseUrl: r'https://evil.com\@trusted.com',
          path: '/items',
          method: 'get',
        ),
        operation: <String, Object?>{
          'operationId': 'getItem',
          'responses': <String, Object?>{
            '200': <String, Object?>{'description': 'ok'},
          },
        },
      );
      final ToolContext toolContext = await _createToolContext();
      final Map<String, Object?> result = await tool.call(
        args: <String, dynamic>{},
        toolContext: toolContext,
      );
      expect(
        result['error'].toString(),
        contains('Backslash in url authority'),
      );
    });
  });

  group('5cc364b75: BaseRetrievalTool required query declaration', () {
    test('declares query parameter as required', () {
      final _TestRetrievalTool tool = _TestRetrievalTool();
      final FunctionDeclaration? decl = tool.getDeclaration();
      expect(decl, isNotNull);
      expect(decl!.parameters['required'], <String>['query']);
    });
  });

  group('1d81896aa: OpenAPI query parameter style and explode', () {
    test('OperationParser and OpenApiSpecParser preserve style and explode', () {
      final Map<String, Object?> spec = <String, Object?>{
        'openapi': '3.0.0',
        'info': <String, Object?>{'title': 'Test API', 'version': '1.0.0'},
        'servers': <Object?>[
          <String, Object?>{'url': 'https://example.com'},
        ],
        'paths': <String, Object?>{
          '/search': <String, Object?>{
            'get': <String, Object?>{
              'operationId': 'searchItems',
              'parameters': <Object?>[
                <String, Object?>{
                  'name': 'tags',
                  'in': 'query',
                  'style': 'pipeDelimited',
                  'explode': false,
                  'schema': <String, Object?>{
                    'type': 'array',
                    'items': <String, Object?>{'type': 'string'},
                  },
                },
                <String, Object?>{
                  'name': 'filter',
                  'in': 'query',
                  'style': 'deepObject',
                  'explode': true,
                  'schema': <String, Object?>{
                    'type': 'object',
                    'properties': <String, Object?>{
                      'color': <String, Object?>{'type': 'string'},
                    },
                  },
                },
              ],
              'responses': <String, Object?>{
                '200': <String, Object?>{'description': 'ok'},
              },
            },
          },
        },
      };

      final List<ParsedOperation> ops = OpenApiSpecParser().parse(spec);
      expect(ops, hasLength(1));
      final RestApiTool roundTrip = RestApiTool.fromParsedOperation(ops.first);
      expect(roundTrip, isNotNull);
      final ApiParameter tagsParam = ops.first.parameters.firstWhere(
        (ApiParameter p) => p.originalName == 'tags',
      );
      expect(tagsParam.style, 'pipeDelimited');
      expect(tagsParam.explode, isFalse);
      final ApiParameter filterParam = ops.first.parameters.firstWhere(
        (ApiParameter p) => p.originalName == 'filter',
      );
      expect(filterParam.style, 'deepObject');
      expect(filterParam.explode, isTrue);
    });

    test('RestApiTool serializes form, deepObject, spaceDelimited, and pipeDelimited query params', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));

      Uri? lastRequestedUri;
      server.listen((HttpRequest req) async {
        lastRequestedUri = req.uri;
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(<String, Object?>{'ok': true}));
        await req.response.close();
      });

      final RestApiTool tool = RestApiTool(
        name: 'search_items',
        description: 'Search items',
        allowPrivateNetworkAccess: true,
        endpoint: OperationEndpoint(
          baseUrl: 'http://127.0.0.1:${server.port}',
          path: '/items',
          method: 'get',
        ),
        operation: <String, Object?>{
          'operationId': 'searchItems',
          'parameters': <Object?>[
            <String, Object?>{
              'name': 'repeated_tags',
              'in': 'query',
              'style': 'form',
              'explode': true,
              'schema': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
            },
            <String, Object?>{
              'name': 'pipe_tags',
              'in': 'query',
              'style': 'pipeDelimited',
              'explode': false,
              'schema': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
            },
            <String, Object?>{
              'name': 'space_tags',
              'in': 'query',
              'style': 'spaceDelimited',
              'explode': false,
              'schema': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
            },
            <String, Object?>{
              'name': 'deep_filter',
              'in': 'query',
              'style': 'deepObject',
              'explode': true,
              'schema': <String, Object?>{'type': 'object'},
            },
            <String, Object?>{
              'name': 'exploded_obj',
              'in': 'query',
              'style': 'form',
              'explode': true,
              'schema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'allowed_key': <String, Object?>{'type': 'string'},
                  'pipe_tags': <String, Object?>{'type': 'string'},
                },
                'additionalProperties': false,
              },
            },
            <String, Object?>{
              'name': 'unexploded_obj',
              'in': 'query',
              'style': 'form',
              'explode': false,
              'schema': <String, Object?>{'type': 'object'},
            },
          ],
          'responses': <String, Object?>{
            '200': <String, Object?>{'description': 'ok'},
          },
        },
      );

      final ToolContext toolContext = await _createToolContext();
      await tool.call(
        args: <String, dynamic>{
          'repeated_tags': <String>['a', 'b'],
          'pipe_tags': <String>['x', 'y'],
          'space_tags': <String>['m', 'n'],
          'deep_filter': <String, Object?>{'role': 'admin'},
          'exploded_obj': <String, Object?>{
            'allowed_key': 'yes',
            'undeclared_key': 'dropped',
            'pipe_tags': 'cannot_clobber',
          },
          'unexploded_obj': <String, Object?>{'k1': 'v1', 'k2': 'v2'},
        },
        toolContext: toolContext,
      );

      expect(lastRequestedUri, isNotNull);
      expect(lastRequestedUri!.queryParametersAll['repeated_tags'], <String>['a', 'b']);
      expect(lastRequestedUri!.queryParameters['pipe_tags'], 'x|y');
      expect(lastRequestedUri!.queryParameters['space_tags'], 'm n');
      expect(lastRequestedUri!.queryParameters['deep_filter[role]'], 'admin');
      expect(lastRequestedUri!.queryParameters['allowed_key'], 'yes');
      expect(lastRequestedUri!.queryParameters.containsKey('undeclared_key'), isFalse);
      expect(lastRequestedUri!.queryParameters['unexploded_obj'], 'k1,v1,k2,v2');
    });
  });

  group('4c66a0091, 571670d9f, ce92e9247, 047815043: Evaluation fixes', () {
    test('4c66a0091: parseCritique handles fallback invalid field', () {
      expect(
        parseCritique(
          '{"is_the_agent_response_invalid": "almost", "reasoning": "close"}',
        ),
        Label.invalid,
      );
      expect(
        parseCritique(
          '{"is_the_agent_response_invalid": "partially_valid", "reasoning": "partial"}',
        ),
        Label.invalid,
      );
      expect(
        parseCritique(
          '{"is_the_agent_response_invalid": "false", "reasoning": "good"}',
        ),
        Label.valid,
      );
      expect(
        parseCritique(
          '{"is_the_agent_response_invalid": "unknown_verdict", "reasoning": "?"}',
        ),
        Label.notFound,
      );
    });

    test('571670d9f: RougeEvaluator and ResponseEvaluator skip thought parts', () async {
      final Invocation actual = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'What is 2+2?'},
          ],
        },
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            <String, Object?>{'text': 'Let me think...', 'thought': true},
            <String, Object?>{'text': '4'},
          ],
        },
      );
      final Invocation expected = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'What is 2+2?'},
          ],
        },
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            <String, Object?>{'text': 'Internal reasoning', 'thought': true},
            <String, Object?>{'text': '4'},
          ],
        },
      );

      final EvaluationResult v1Result = await RougeEvaluator(
        EvalMetricSpec(
          metricName: PrebuiltMetrics.responseMatchScore.value,
          threshold: 0.8,
        ),
      ).evaluateInvocations(
        actualInvocations: <Invocation>[actual],
        expectedInvocations: <Invocation>[expected],
      );
      expect(v1Result.overallScore, 1.0);

      final EvaluationResult respResult = await ResponseEvaluator(
        threshold: 0.8,
        metricName: PrebuiltMetrics.responseMatchScore.value,
      ).evaluateInvocations(
        actualInvocations: <Invocation>[actual],
        expectedInvocations: <Invocation>[expected],
      );
      expect(respResult.overallScore, 1.0);
    });

    test('ce92e9247: AgentEvaluator.evaluateEvalSet accepts runtime BaseAgent and App', () async {
      final LlmAgent runtimeAgent = LlmAgent(
        name: 'runtime_agent',
        model: _SequenceLlm((_, _) => <LlmResponse>[
          LlmResponse(content: Content.modelText('hello world')),
        ]),
      );
      final App runtimeApp = App(name: 'runtime_app', rootAgent: runtimeAgent);
      final EvalSet evalSet = EvalSet(
        evalSetId: 'set_1',
        evalCases: <EvalCase>[
          EvalCase(
            evalId: 'case_1',
            conversation: <Invocation>[
              Invocation(
                userContent: <String, Object?>{
                  'role': 'user',
                  'parts': <Object?>[
                    <String, Object?>{'text': 'Say hello'},
                  ],
                },
                finalResponse: <String, Object?>{
                  'role': 'model',
                  'parts': <Object?>[
                    <String, Object?>{'text': 'hello world'},
                  ],
                },
              ),
            ],
          ),
        ],
      );

      await AgentEvaluator.evaluateEvalSet(
        agentModule: runtimeAgent,
        evalSet: evalSet,
        criteria: <String, double>{
          PrebuiltMetrics.responseMatchScore.value: 0.9,
        },
      );
      await AgentEvaluator.evaluateEvalSet(
        agentModule: runtimeApp,
        evalSet: evalSet,
        criteria: <String, double>{
          PrebuiltMetrics.responseMatchScore.value: 0.9,
        },
      );
    });

    test('047815043: RubricBasedMultiTurnTrajectoryEvaluator formats built-in and per-agent tools', () async {
      String? capturedPrompt;
      final RubricBasedMultiTurnTrajectoryEvaluator evaluator =
          RubricBasedMultiTurnTrajectoryEvaluator(
            EvalMetricSpec(
              metricName: 'multi_turn_trajectory_quality_v1',
              threshold: 0.5,
              criterion: RubricsBasedCriterion(
                threshold: 0.5,
                rubrics: <Rubric>[
                  Rubric(
                    rubricId: 'r1',
                    rubricContent: RubricContent(textProperty: 'Uses tools properly'),
                  ),
                ],
              ),
            ),
            autoRaterInvoker: ({
              required String prompt,
              required JudgeModelOptions judgeModelOptions,
            }) async {
              capturedPrompt = prompt;
              return LlmResponse(
                content: Content.modelText(
                  '[{"property": "Uses tools properly", "verdict": "yes", "rationale": "ok"}]',
                ),
              );
            },
          );

      final List<Invocation> invocations = <Invocation>[
        Invocation(
          userContent: <String, Object?>{'role': 'user', 'parts': <Object?>[]},
          appDetails: AppDetails(
            agentDetails: <String, AgentDetails>{
              'search_agent': AgentDetails(
                name: 'search_agent',
                instructions: 'Search the web.',
                toolDeclarations: <Object?>[
                  <String, Object?>{
                    'function_declarations': <Object?>[
                      <String, Object?>{
                        'name': 'lookup_doc',
                        'description': 'Looks up a document.',
                      },
                    ],
                    'google_search': <String, Object?>{},
                  },
                ],
              ),
              'code_agent': AgentDetails(
                name: 'code_agent',
                instructions: 'Run code.',
                toolDeclarations: <Object?>[
                  <String, Object?>{
                    'code_execution': <String, Object?>{},
                  },
                ],
              ),
            },
          ),
        ),
      ];

      await evaluator.evaluateInvocations(actualInvocations: invocations);
      expect(capturedPrompt, isNotNull);
      expect(
        capturedPrompt,
        contains(
          'Agent: search_agent\n'
          '- lookup_doc: Looks up a document.\n'
          '- google_search (built-in)\n\n'
          'Agent: code_agent\n'
          '- code_execution (built-in)',
        ),
      );
    });
  });

  group('799fc9459, 27cdf7fb5, 82fe029b8, 3700f0d1b, e2e9336a7: Additional Oct 29 parity items', () {
    test('799fc9459: all 16 promoted toolset and integration features are stable', () {
      const List<FeatureName> promoted = <FeatureName>[
        FeatureName.bigQueryToolset,
        FeatureName.bigtableToolSettings,
        FeatureName.bigtableToolset,
        FeatureName.computerUse,
        FeatureName.dataAgentToolset,
        FeatureName.daytonaEnvironment,
        FeatureName.e2bEnvironment,
        FeatureName.gcsAdminToolset,
        FeatureName.gcsToolSettings,
        FeatureName.gcsToolset,
        FeatureName.mcpToolset,
        FeatureName.openapiToolset,
        FeatureName.pubsubToolConfig,
        FeatureName.pubsubToolset,
        FeatureName.spannerAdminToolset,
        FeatureName.spannerToolset,
        FeatureName.spannerToolSettings,
        FeatureName.spannerVectorStore,
        FeatureName.toolboxToolset,
      ];
      for (final FeatureName feature in promoted) {
        final FeatureConfig? config = getFeatureConfig(feature);
        expect(config, isNotNull, reason: '$feature must be registered');
        expect(config!.stage, FeatureStage.stable, reason: '$feature should be stable');
        expect(config.defaultOn, isTrue, reason: '$feature should default on');
      }
    });

    test('27cdf7fb5: InMemoryArtifactService keeps scopes separate when identifiers contain / or %', () async {
      final InMemoryArtifactService service = InMemoryArtifactService();
      await service.saveArtifact(
        appName: 'team/project',
        userId: 'alice',
        sessionId: 's1',
        filename: 'report.txt',
        artifact: Part.text('scope A'),
      );
      await service.saveArtifact(
        appName: 'team',
        userId: 'project/alice',
        sessionId: 's1',
        filename: 'report.txt',
        artifact: Part.text('scope B'),
      );
      await service.saveArtifact(
        appName: 'team%2Fproject',
        userId: 'alice',
        sessionId: 's1',
        filename: 'report.txt',
        artifact: Part.text('scope C'),
      );

      final Part? loadedA = await service.loadArtifact(
        appName: 'team/project',
        userId: 'alice',
        sessionId: 's1',
        filename: 'report.txt',
      );
      final Part? loadedB = await service.loadArtifact(
        appName: 'team',
        userId: 'project/alice',
        sessionId: 's1',
        filename: 'report.txt',
      );
      final Part? loadedC = await service.loadArtifact(
        appName: 'team%2Fproject',
        userId: 'alice',
        sessionId: 's1',
        filename: 'report.txt',
      );
      expect(loadedA?.text, 'scope A');
      expect(loadedB?.text, 'scope B');
      expect(loadedC?.text, 'scope C');

      final List<String> keysA = await service.listArtifactKeys(
        appName: 'team/project',
        userId: 'alice',
        sessionId: 's1',
      );
      expect(keysA, <String>['report.txt']);
    });

    test('82fe029b8: FunctionTool converts Enum tool arguments to the declared member', () async {
      _TestPriority? receivedPriority;
      final FunctionTool tool = FunctionTool(
        name: 'set_priority',
        description: 'Sets priority',
        func: ({required _TestPriority priority}) {
          receivedPriority = priority;
          return priority.name;
        },
        declaration: FunctionDeclaration(
          name: 'set_priority',
          description: 'Sets priority',
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'priority': <String, dynamic>{
                'type': 'string',
                'enum': _TestPriority.values,
              },
            },
            'required': <String>['priority'],
          },
        ),
      );
      final ToolContext toolContext = await _createToolContext();

      // Match by enum member name
      await tool.run(
        args: <String, dynamic>{'priority': 'high'},
        toolContext: toolContext,
      );
      expect(receivedPriority, _TestPriority.high);

      // Match by stringified non-string custom value ("1")
      await tool.run(
        args: <String, dynamic>{'priority': '1'},
        toolContext: toolContext,
      );
      expect(receivedPriority, _TestPriority.low);
    });

    test('3700f0d1b: SetModelResponseTool accepts declared field names and normalizes aliased schemas', () async {
      final SetModelResponseTool tool = SetModelResponseTool(<String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'user_name': <String, dynamic>{
            'type': 'string',
            'alias': 'userName',
          },
          'fullName': <String, dynamic>{
            'type': 'string',
            'field_name': 'full_name',
          },
        },
      });
      final ToolContext toolContext = await _createToolContext();

      final Object? fromAlias = await tool.run(
        args: <String, dynamic>{
          'userName': 'alice',
          'fullName': 'Alice Smith',
        },
        toolContext: toolContext,
      );
      expect(fromAlias, <String, dynamic>{
        'user_name': 'alice',
        'full_name': 'Alice Smith',
      });

      final Object? fromDeclared = await tool.run(
        args: <String, dynamic>{
          'user_name': 'bob',
          'full_name': 'Bob Jones',
        },
        toolContext: toolContext,
      );
      expect(fromDeclared, <String, dynamic>{
        'user_name': 'bob',
        'full_name': 'Bob Jones',
      });
    });

    test('e2e9336a7: validateAppName and Frontmatter reject names with a trailing newline', () {
      expect(() => validateAppName('valid_app\n'), throwsArgumentError);
      expect(
        () => Frontmatter(name: 'valid-skill\n', description: 'desc'),
        throwsArgumentError,
      );
    });
  });
}
