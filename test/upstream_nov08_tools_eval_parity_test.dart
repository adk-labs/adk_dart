import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/evaluation/eval_case.dart';
import 'package:adk_dart/src/evaluation/eval_case_result_multi_run_aggregator.dart';
import 'package:adk_dart/src/evaluation/eval_config.dart';
import 'package:adk_dart/src/evaluation/eval_metrics.dart';
import 'package:adk_dart/src/evaluation/eval_result.dart';
import 'package:adk_dart/src/evaluation/eval_rubrics.dart';
import 'package:adk_dart/src/evaluation/evaluator.dart';
import 'package:adk_dart/src/evaluation/final_response_match_v2.dart';
import 'package:adk_dart/src/evaluation/hallucinations_v1.dart';
import 'package:adk_dart/src/evaluation/llm_as_judge.dart';
import 'package:adk_dart/src/evaluation/llm_as_judge_utils.dart';
import 'package:adk_dart/src/evaluation/rubric_based_multi_turn_trajectory_evaluator.dart';
import 'package:adk_dart/src/evaluation/vertex_ai_eval_facade.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_session_manager.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_tool.dart';
import 'package:adk_dart/src/tools/tool_context.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:test/test.dart';

enum _Priority {
  low('LOW'),
  high('HIGH');

  const _Priority(this.value);
  final String value;
}

enum _PlainColor { red, blue }

class _CustomPreprocessFunctionTool extends FunctionTool {
  _CustomPreprocessFunctionTool({
    required super.func,
    super.name,
    super.requireConfirmation,
  });

  @override
  Map<String, dynamic> preprocessArgs(
    Map<String, dynamic> args, [
    FunctionDeclaration? declaration,
  ]) {
    final Map<String, dynamic> copy = super.preprocessArgs(args, declaration);
    copy['injected'] = 'custom_value';
    return copy;
  }
}

class _FakeJudgeLlm extends BaseLlm {
  _FakeJudgeLlm(this.responses) : super(model: 'fake-judge');

  final List<LlmResponse> responses;
  final List<String> prompts = <String>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String prompt = request.contents
        .expand((Content c) => c.parts)
        .map((Part p) => p.text ?? '')
        .join('\n');
    prompts.add(prompt);
    if (_index < responses.length) {
      yield responses[_index++];
    }
  }
}

Future<ToolContext> _createToolContext({String functionCallId = 'call_1'}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'test_app',
    userId: 'user_1',
    sessionId: 'session_1',
  );
  final LlmAgent agent = LlmAgent(
    name: 'test_agent',
    model: _FakeJudgeLlm(const <LlmResponse>[]),
  );
  final InvocationContext invocationContext = InvocationContext(
    sessionService: sessionService,
    invocationId: 'inv_1',
    agent: agent,
    session: session,
  );
  return ToolContext(invocationContext, functionCallId: functionCallId);
}

void main() {
  group('FunctionTool enumMembersToValues & requireConfirmation (669f55bba)', () {
    test('enumMembersToValues converts single Enum and List<Enum> to wire values', () {
      final Object modelObj = Object();
      final Map<String, dynamic> converted = FunctionTool.enumMembersToValues(
        <String, dynamic>{
          'priority': _Priority.high,
          'plain': _PlainColor.blue,
          'plain_list': <_PlainColor>[_PlainColor.red, _PlainColor.blue],
          'priorities': <_Priority>[_Priority.low, _Priority.high],
          'mixed': <Object>[_Priority.low, 'raw', 42],
          'model': modelObj,
        },
      );

      expect(converted['priority'], 'HIGH');
      expect(converted['plain'], 'blue');
      expect(converted['priorities'], <String>['LOW', 'HIGH']);
      expect(converted['mixed'], <Object>['LOW', 'raw', 42]);
      expect(identical(converted['model'], modelObj), isTrue);
    });

    test(
      'requireConfirmation callable receives raw enum values when FUNCTION_TOOL_ARG_VALIDATION is disabled',
      () async {
        final List<Object?> capturedPriorities = <Object?>[];
        final FunctionTool tool = FunctionTool(
          name: 'set_priority',
          func: ({required Object priority}) => 'ok:$priority',
          requireConfirmation: (Map<String, dynamic> args) {
            capturedPriorities.add(args['priority']);
            return args['priority'] == 'HIGH';
          },
          declaration: FunctionDeclaration(
            name: 'set_priority',
            parameters: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'priority': <String, Object?>{
                  'type': 'string',
                  'enumValues': _Priority.values,
                },
              },
            },
          ),
        );

        final ToolContext toolContext = await _createToolContext();
        await withTemporaryFeatureOverrideAsync(
          FeatureName.functionToolArgValidation,
          false,
          () async {
            final bool needsConfirm = await tool.checkRequireConfirmation(
              <String, dynamic>{'priority': 'HIGH'},
              toolContext,
            );
            expect(needsConfirm, isTrue);
            expect(capturedPriorities.single, 'HIGH');
            expect(capturedPriorities.single, isNot(isA<_Priority>()));

            final Object? runResult = await tool.run(
              args: <String, dynamic>{'priority': 'HIGH'},
              toolContext: toolContext,
            );
            expect(runResult, isA<Map<String, Object?>>());
            expect(capturedPriorities.last, 'HIGH');
          },
        );
      },
    );

    test(
      'requireConfirmation callable receives Enum members when FUNCTION_TOOL_ARG_VALIDATION is enabled',
      () async {
        final List<Object?> capturedPriorities = <Object?>[];
        final FunctionTool tool = FunctionTool(
          name: 'set_priority',
          func: ({required Object priority}) => 'ok:$priority',
          requireConfirmation: (Map<String, dynamic> args) {
            capturedPriorities.add(args['priority']);
            return args['priority'] == _Priority.high;
          },
          declaration: FunctionDeclaration(
            name: 'set_priority',
            parameters: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'priority': <String, Object?>{
                  'type': 'string',
                  'enumValues': _Priority.values,
                },
              },
            },
          ),
        );

        final ToolContext toolContext = await _createToolContext();
        await withTemporaryFeatureOverrideAsync(
          FeatureName.functionToolArgValidation,
          true,
          () async {
            final bool needsConfirm = await tool.checkRequireConfirmation(
              <String, dynamic>{'priority': 'HIGH'},
              toolContext,
            );
            expect(needsConfirm, isTrue);
            expect(capturedPriorities.single, _Priority.high);

            final Object? runResult = await tool.run(
              args: <String, dynamic>{'priority': 'HIGH'},
              toolContext: toolContext,
            );
            expect(runResult, isA<Map<String, Object?>>());
            expect(capturedPriorities.last, _Priority.high);
          },
        );
      },
    );

    test('custom subclass preprocessArgs is passed through to requireConfirmation', () async {
      Map<String, dynamic>? capturedArgs;
      final _CustomPreprocessFunctionTool tool = _CustomPreprocessFunctionTool(
        name: 'custom_tool',
        func: ({required String x, String? injected}) => '$x:$injected',
        requireConfirmation: (Map<String, dynamic> args) {
          capturedArgs = Map<String, dynamic>.from(args);
          return false;
        },
      );

      final ToolContext toolContext = await _createToolContext();
      final bool confirm = await tool.checkRequireConfirmation(
        <String, dynamic>{'x': 'hello'},
        toolContext,
      );
      expect(confirm, isFalse);
      expect(capturedArgs?['injected'], 'custom_value');
    });
  });

  group('McpSessionManager case-insensitive header overrides (58d1ebe32)', () {
    test('mergeHeaders replaces base header regardless of casing', () {
      final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
        url: 'https://example.com/mcp',
        headers: <String, String>{
          'authorization': 'Bearer base-token',
          'X-Custom-Header': 'base-val',
          'User-Agent': 'BaseAgent/1.0',
        },
      );

      final Map<String, String>? merged = McpSessionManager.instance.mergeHeaders(
        params,
        additionalHeaders: <String, String>{
          'Authorization': 'Bearer override-token',
          'x-custom-header': 'override-val',
          'USER-AGENT': 'OverrideAgent/2.0',
        },
      );

      expect(merged, isNotNull);
      expect(merged!.containsKey('authorization'), isFalse);
      expect(merged['Authorization'], 'Bearer override-token');
      expect(merged.containsKey('X-Custom-Header'), isFalse);
      expect(merged['x-custom-header'], 'override-val');
      expect(merged['user-agent'], contains('OverrideAgent/2.0'));
      expect(merged['user-agent'], isNot(contains('BaseAgent/1.0')));
    });
  });

  group('McpTool retry on session terminated (10711d053)', () {
    tearDown(() {
      McpSessionManager.instance.clear();
    });

    test('retries once on a fresh session when server reports session terminated', () async {
      final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
        url: 'https://mcp-retry.example.com/mcp',
      );
      int callCount = 0;
      McpSessionManager.instance.registerToolExecutor(
        connectionParams: params,
        toolName: 'echo_tool',
        executor: (Map<String, dynamic> args, {Map<String, String>? headers}) {
          callCount += 1;
          if (callCount == 1) {
            throw McpJsonRpcException(
              method: 'tools/call',
              code: -32600,
              message: 'Session terminated',
            );
          }
          return <String, Object?>{'ok': true, 'attempt': callCount, 'args': args};
        },
      );

      final McpTool tool = McpTool(
        mcpTool: McpBaseTool(name: 'echo_tool', description: 'Echo tool'),
        connectionParams: params,
        sessionManager: McpSessionManager.instance,
      );

      final ToolContext toolContext = await _createToolContext();
      final Object? result = await tool.runAuthenticated(
        args: <String, dynamic>{'q': 'ping'},
        toolContext: toolContext,
        credential: null,
      );

      expect(callCount, 2);
      expect(result, <String, Object?>{
        'ok': true,
        'attempt': 2,
        'args': <String, dynamic>{'q': 'ping'},
      });
    });

    test('propagates error if retry also fails with session terminated', () async {
      final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
        url: 'https://mcp-retry-fail.example.com/mcp',
      );
      int callCount = 0;
      McpSessionManager.instance.registerToolExecutor(
        connectionParams: params,
        toolName: 'always_terminated',
        executor: (Map<String, dynamic> args, {Map<String, String>? headers}) {
          callCount += 1;
          throw McpHttpStatusException(
            uri: Uri.parse('https://mcp-retry-fail.example.com/mcp'),
            statusCode: 404,
            body: 'Session terminated by server',
          );
        },
      );

      final McpTool tool = McpTool(
        mcpTool: McpBaseTool(name: 'always_terminated'),
        connectionParams: params,
        sessionManager: McpSessionManager.instance,
      );

      final ToolContext toolContext = await _createToolContext();
      await withTemporaryFeatureOverrideAsync(
        FeatureName.mcpGracefulErrorHandling,
        false,
        () async {
          await expectLater(
            () => tool.runAuthenticated(
              args: const <String, dynamic>{},
              toolContext: toolContext,
              credential: null,
            ),
            throwsA(isA<McpHttpStatusException>()),
          );
        },
      );
      expect(callCount, 2);
    });

    test('does not retry non-session-terminated errors', () async {
      final StreamableHTTPConnectionParams params = StreamableHTTPConnectionParams(
        url: 'https://mcp-no-retry.example.com/mcp',
      );
      int callCount = 0;
      McpSessionManager.instance.registerToolExecutor(
        connectionParams: params,
        toolName: 'fail_once',
        executor: (Map<String, dynamic> args, {Map<String, String>? headers}) {
          callCount += 1;
          throw StateError('Internal tool crash');
        },
      );

      final McpTool tool = McpTool(
        mcpTool: McpBaseTool(name: 'fail_once'),
        connectionParams: params,
        sessionManager: McpSessionManager.instance,
      );

      final ToolContext toolContext = await _createToolContext();
      await withTemporaryFeatureOverrideAsync(
        FeatureName.mcpGracefulErrorHandling,
        false,
        () async {
          await expectLater(
            () => tool.runAuthenticated(
              args: const <String, dynamic>{},
              toolContext: toolContext,
              credential: null,
            ),
            throwsA(isA<StateError>()),
          );
        },
      );
      expect(callCount, 1);
    });
  });

  group('Evaluation thought-part filtering (dd7161f7a) & pass@k aggregator (c44adfd68)', () {
    test('getTextFromContent skips thought parts on Map, Content, and Invocation', () {
      expect(
        getTextFromContent(<String, Object?>{
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'The user said hi.', 'thought': true},
          ],
        }),
        '',
      );

      expect(
        getTextFromContent(<String, Object?>{
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'The user said hi.', 'thought': true},
            <String, Object?>{'text': 'Hello! How can I help you?'},
          ],
        }),
        'Hello! How can I help you?',
      );

      final Content content = Content(
        role: 'model',
        parts: <Part>[
          Part.text('Internal reasoning', thought: true),
          Part.text('Visible answer'),
        ],
      );
      expect(getTextFromContent(content), 'Visible answer');

      final Invocation invocation = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'Hi'},
          ],
        },
        intermediateData: InvocationEvents(
          invocationEvents: <InvocationEvent>[
            InvocationEvent(
              author: 'agent',
              content: <String, Object?>{
                'role': 'model',
                'parts': <Map<String, Object?>>[
                  <String, Object?>{'text': 'Thinking step 1', 'thought': true},
                  <String, Object?>{'text': 'Intermediate visible'},
                ],
              },
            ),
          ],
        ),
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'Thinking step 2', 'thought': true},
            <String, Object?>{'text': 'Final visible'},
          ],
        },
      );
      expect(
        getTextFromContent(
          invocation,
          includeIntermediateResponsesInFinal: true,
        ),
        'Intermediate visible\nFinal visible',
      );
    });

    test('FinalResponseMatchV2Evaluator ignores thought parts in auto-rater response', () {
      final FinalResponseMatchV2Evaluator evaluator =
          FinalResponseMatchV2Evaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetrics.finalResponseMatchV2.value,
              threshold: 0.8,
              criterion: LlmAsAJudgeCriterion(threshold: 0.8),
            ),
          );

      final AutoRaterScore score = evaluator.convertAutoRaterResponseToScore(
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.text(
                '{"is_the_agent_response_valid": "invalid"}',
                thought: true,
              ),
              Part.text(
                '{"reasoning": "Matches reference.", "is_the_agent_response_valid": "valid"}',
              ),
            ],
          ),
        ),
      );
      expect(score.score, 1.0);
    });

    test('HallucinationsV1Evaluator ignores thought parts in context and steps', () async {
      final _FakeJudgeLlm fakeLlm = _FakeJudgeLlm(<LlmResponse>[
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.text('<sentence>hallucinated thought</sentence>', thought: true),
              Part.text('<sentence>Visible response.</sentence>'),
            ],
          ),
        ),
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.text(
                'sentence: Visible response.\n'
                'label: unsupported\n'
                'rationale: thought fake\n'
                'supporting_excerpt: null\n'
                'contradicting_excerpt: null',
                thought: true,
              ),
              Part.text(
                'sentence: Visible response.\n'
                'label: supported\n'
                'rationale: grounded\n'
                'supporting_excerpt: User prompt\n'
                'contradicting_excerpt: null',
              ),
            ],
          ),
        ),
      ]);

      final HallucinationsV1Evaluator evaluator = HallucinationsV1Evaluator(
        EvalMetricSpec(
          metricName: PrebuiltMetrics.hallucinationsV1.value,
          threshold: 0.8,
          criterion: HallucinationsCriterion(
            threshold: 0.8,
            evaluateIntermediateNlResponses: true,
          ),
        ),
        llmFactory: (String _) => fakeLlm,
      );

      final Invocation actual = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'User prompt'},
          ],
        },
        intermediateData: InvocationEvents(
          invocationEvents: <InvocationEvent>[
            InvocationEvent(
              author: 'agent',
              content: <String, Object?>{
                'role': 'model',
                'parts': <Map<String, Object?>>[
                  <String, Object?>{
                    'text': 'Secret intermediate thought',
                    'thought': true,
                  },
                ],
              },
            ),
          ],
        ),
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'Secret final thought', 'thought': true},
            <String, Object?>{'text': 'Visible response.'},
          ],
        },
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[actual],
      );
      expect(result.overallScore, 1.0);
      expect(fakeLlm.prompts, hasLength(2));
      for (final String prompt in fakeLlm.prompts) {
        expect(prompt, isNot(contains('Secret intermediate thought')));
        expect(prompt, isNot(contains('Secret final thought')));
      }
    });

    test('RubricBasedMultiTurnTrajectoryEvaluator excludes thought parts from dialogue', () async {
      String? capturedPrompt;
      final RubricBasedMultiTurnTrajectoryEvaluator evaluator =
          RubricBasedMultiTurnTrajectoryEvaluator(
            EvalMetricSpec(
              metricName: 'multi_turn_trajectory_quality_v1',
              threshold: 0.8,
              criterion: RubricsBasedCriterion(
                threshold: 0.8,
                rubrics: <Rubric>[
                  Rubric(
                    rubricId: 'r1',
                    rubricContent: RubricContent(textProperty: 'Polite response'),
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
                  'Property: Polite response\nVerdict: yes\nRationale: ok',
                ),
              );
            },
          );

      await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          Invocation(
            userContent: <String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': 'User thought', 'thought': true},
                <String, Object?>{'text': 'Hello agent'},
              ],
            },
            intermediateData: InvocationEvents(
              invocationEvents: <InvocationEvent>[
                InvocationEvent(
                  author: 'helper',
                  content: <String, Object?>{
                    'role': 'model',
                    'parts': <Map<String, Object?>>[
                      <String, Object?>{'text': 'Helper secret thought', 'thought': true},
                      <String, Object?>{'text': 'Helper intermediate message'},
                    ],
                  },
                ),
              ],
            ),
            finalResponse: <String, Object?>{
              'role': 'model',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': 'Final secret thought', 'thought': true},
                <String, Object?>{'text': 'Hello user!'},
              ],
            },
          ),
        ],
      );

      expect(capturedPrompt, isNotNull);
      expect(capturedPrompt, contains('USER TURN 1: Hello agent'));
      expect(capturedPrompt, contains('AGENT (helper) TURN 1: Helper intermediate message'));
      expect(capturedPrompt, contains('AGENT (helper) TURN 1: Hello user!'));
      expect(capturedPrompt, isNot(contains('User thought')));
      expect(capturedPrompt, isNot(contains('Helper secret thought')));
      expect(capturedPrompt, isNot(contains('Final secret thought')));
    });

    test('VertexAiEvalFacade excludes thought parts while MultiTurnVertexAiEvalFacade.mapInvocationTurn preserves them', () async {
      List<Map<String, String?>>? capturedDataset;
      final VertexAiEvalFacade singleTurn = VertexAiEvalFacade(
        threshold: 0.5,
        metricName: 'coherence',
        expectedInvocationsRequired: true,
        evalInvoker: ({
          required List<Map<String, String?>> dataset,
          required List<String> metrics,
        }) async {
          capturedDataset = dataset;
          return VertexAiEvalOutput(
            summaryMetrics: <VertexAiEvalSummaryMetric>[
              VertexAiEvalSummaryMetric(meanScore: 0.9),
            ],
          );
        },
      );

      final Invocation actual = Invocation(
        invocationId: 'inv-1',
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'User hidden thought', 'thought': true},
            <String, Object?>{'text': 'What is 2+2?'},
          ],
        },
        intermediateData: InvocationEvents(
          invocationEvents: <InvocationEvent>[
            InvocationEvent(
              author: 'agent',
              content: <String, Object?>{
                'role': 'model',
                'parts': <Map<String, Object?>>[
                  <String, Object?>{'text': 'Intermediate thought', 'thought': true},
                ],
              },
            ),
          ],
        ),
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'Let me calculate 2+2', 'thought': true},
            <String, Object?>{'text': '4'},
          ],
        },
      );
      final Invocation expected = Invocation(
        userContent: actual.userContent,
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Map<String, Object?>>[
            <String, Object?>{'text': 'Reference thought', 'thought': true},
            <String, Object?>{'text': '4'},
          ],
        },
      );

      await singleTurn.evaluateInvocations(
        actualInvocations: <Invocation>[actual],
        expectedInvocations: <Invocation>[expected],
      );

      expect(capturedDataset, isNotNull);
      expect(capturedDataset!.single['prompt'], 'What is 2+2?');
      expect(capturedDataset!.single['reference'], '4');
      expect(capturedDataset!.single['response'], '4');

      final MultiTurnVertexAiEvalFacade multiTurn = MultiTurnVertexAiEvalFacade(
        threshold: 0.5,
        metricName: 'multi_turn_chat_quality',
      );
      final Map<String, Object?> mappedTurn = multiTurn.mapInvocationTurn(0, actual);
      final List<Object?> events = mappedTurn['events'] as List<Object?>;
      expect(events, hasLength(3));
      final Map<String, Object?> finalEvent = events.last as Map<String, Object?>;
      final List<Object?> finalParts = finalEvent['parts'] as List<Object?>;
      expect(
        (finalParts.first as Map<String, Object?>)['thought'],
        isTrue,
      );
    });

    test('EvalCaseResultMultiRunAggregator report-only pass@k without threshold is always informational and never changes verdict', () {
      EvalCaseResult makeRun(int repetitionIndex, EvalStatus status, double score) {
        return EvalCaseResult(
          evalSetId: 'set_1',
          evalId: 'case_1',
          finalEvalStatus: status,
          overallEvalMetricResults: <EvalMetricResultSpec>[
            EvalMetricResultSpec(
              metricName: 'response_match_score',
              threshold: 0.8,
              score: score,
              evalStatus: status,
            ),
          ],
          evalMetricResultPerInvocation: const <EvalMetricResultPerInvocation>[],
          sessionId: 'sess_$repetitionIndex',
          repetitionIndex: repetitionIndex,
        );
      }

      final List<MultiRunCaseResult> summaryZero =
          EvalCaseResultMultiRunAggregator.aggregate(
            <EvalCaseResult>[
              makeRun(0, EvalStatus.failed, 0.1),
              makeRun(1, EvalStatus.failed, 0.2),
            ],
            multiRunConfig: MultiRunConfig(
              numRuns: 2,
              crossRunCriteria: <MultiRunCriterion>[
                PassKMultiRunCriterion(
                  method: 'pass_at_k',
                  k: 2,
                  threshold: null,
                ),
              ],
            ),
          );
      expect(
        summaryZero.single.crossRunResults.single.status,
        EvalStatus.informational,
      );
      expect(summaryZero.single.crossRunResults.single.value, 0.0);
      expect(summaryZero.single.finalEvalStatus, EvalStatus.failed);

      final List<MultiRunCaseResult> summaryPassed =
          EvalCaseResultMultiRunAggregator.aggregate(
            <EvalCaseResult>[
              makeRun(0, EvalStatus.passed, 0.9),
              makeRun(1, EvalStatus.failed, 0.2),
            ],
            multiRunConfig: MultiRunConfig(
              numRuns: 2,
              crossRunCriteria: <MultiRunCriterion>[
                PassKMultiRunCriterion(
                  method: 'pass_hat_k',
                  k: 2,
                  threshold: null,
                ),
              ],
            ),
          );
      expect(
        summaryPassed.single.crossRunResults.single.status,
        EvalStatus.informational,
      );
      expect(summaryPassed.single.crossRunResults.single.value, 0.0);
    });
  });
}
