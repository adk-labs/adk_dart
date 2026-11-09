import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _SyncCustomEvaluator extends Evaluator {
  _SyncCustomEvaluator({
    required this.onEvaluate,
  });

  final EvaluationResult Function(
    List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  ) onEvaluate;

  @override
  EvaluationResult evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    return onEvaluate(
      actualInvocations,
      expectedInvocations,
      conversationScenario,
    );
  }
}

class _FakeUnaryOrStreamingA2aClient implements A2aClient {
  _FakeUnaryOrStreamingA2aClient({required this.streaming});

  final bool streaming;

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) async* {
    if (streaming) {
      // Streaming emits the intermediate FC task update followed by the terminal FR task update.
      final A2aTask fcTask = A2aTask(
        id: 'task-stream-1',
        contextId: 'ctx-1',
        status: A2aTaskStatus(
          state: A2aTaskState.working,
          message: A2aMessage(
            messageId: 'msg-fc',
            role: A2aRole.agent,
            parts: <A2aPart>[
              A2aPart.data(
                <String, Object?>{
                  'id': 'fc-1',
                  'name': finishTaskToolName,
                  'args': <String, Object?>{'result': '42'},
                },
                metadata: <String, Object?>{
                  getAdkMetadataKey(a2aDataPartMetadataTypeKey):
                      a2aDataPartMetadataTypeFunctionCall,
                },
              ),
            ],
          ),
        ),
      );
      yield (fcTask, null);

      final A2aTask completedTask = A2aTask(
        id: 'task-stream-1',
        contextId: 'ctx-1',
        status: A2aTaskStatus(state: A2aTaskState.completed),
        artifacts: <A2aArtifact>[
          A2aArtifact(
            artifactId: 'art-1',
            parts: <A2aPart>[
              A2aPart.data(
                <String, Object?>{
                  'id': 'fc-1',
                  'name': finishTaskToolName,
                  'response': <String, Object?>{
                    'result': finishTaskSuccessResult,
                  },
                },
                metadata: <String, Object?>{
                  getAdkMetadataKey(a2aDataPartMetadataTypeKey):
                      a2aDataPartMetadataTypeFunctionResponse,
                },
              ),
            ],
          ),
        ],
      );
      yield (completedTask, null);
    } else {
      // Unary A2A response: single completed A2aTask where artifacts hold the
      // terminal finish_task FR and history holds the finish_task FC.
      final A2aTask unaryTask = A2aTask(
        id: 'task-unary-1',
        contextId: 'ctx-1',
        status: A2aTaskStatus(state: A2aTaskState.completed),
        history: <A2aMessage>[
          A2aMessage(
            messageId: 'msg-hist-1',
            role: A2aRole.agent,
            parts: <A2aPart>[
              A2aPart.data(
                <String, Object?>{
                  'id': 'fc-1',
                  'name': finishTaskToolName,
                  'args': <String, Object?>{'result': '42'},
                },
                metadata: <String, Object?>{
                  getAdkMetadataKey(a2aDataPartMetadataTypeKey):
                      a2aDataPartMetadataTypeFunctionCall,
                },
              ),
              A2aPart.data(
                <String, Object?>{
                  'id': 'fc-1',
                  'name': finishTaskToolName,
                  'response': <String, Object?>{
                    'result': finishTaskSuccessResult,
                  },
                },
                metadata: <String, Object?>{
                  getAdkMetadataKey(a2aDataPartMetadataTypeKey):
                      a2aDataPartMetadataTypeFunctionResponse,
                },
              ),
            ],
          ),
        ],
        artifacts: <A2aArtifact>[
          A2aArtifact(
            artifactId: 'art-1',
            parts: <A2aPart>[
              A2aPart.data(
                <String, Object?>{
                  'id': 'fc-1',
                  'name': finishTaskToolName,
                  'response': <String, Object?>{
                    'result': finishTaskSuccessResult,
                  },
                },
                metadata: <String, Object?>{
                  getAdkMetadataKey(a2aDataPartMetadataTypeKey):
                      a2aDataPartMetadataTypeFunctionResponse,
                },
              ),
            ],
          ),
        ],
      );
      yield (unaryTask, null);
    }
  }
}

class _FakeA2aClientFactory implements A2aClientFactory {
  _FakeA2aClientFactory({required this.streaming});

  final bool streaming;

  @override
  A2aClient create(AgentCard agentCard) =>
      _FakeUnaryOrStreamingA2aClient(streaming: streaming);
}

class _ScriptedHostModel extends BaseLlm {
  _ScriptedHostModel() : super(model: 'scripted-host');

  int _step = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (_step == 0) {
      _step += 1;
      yield LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              id: 'call-remote-1',
              name: 'remote_worker',
              args: <String, dynamic>{'request': 'q'},
            ),
          ],
        ),
      );
    } else {
      yield LlmResponse(content: Content.modelText('done'));
    }
  }
}

void main() {
  group('Upstream Nov 09 A2A & Evaluation Parity', () {
    test('findFinishTaskArgsFromHistory resolves finish_task args from unary A2A response history metadata', () {
      final Event frEvent = Event(
        author: 'remote_worker',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionResponse(
              id: 'fc-1',
              name: finishTaskToolName,
              response: <String, dynamic>{'result': finishTaskSuccessResult},
            ),
          ],
        ),
        customMetadata: <String, dynamic>{
          'a2a:response': <String, Object?>{
            'id': 'task-1',
            'history': <Object?>[
              <String, Object?>{
                'role': 'ROLE_AGENT',
                'parts': <Object?>[
                  <String, Object?>{
                    'data': <String, Object?>{
                      'id': 'fc-1',
                      'name': finishTaskToolName,
                      'args': <String, Object?>{'result': '42'},
                    },
                    'metadata': <String, Object?>{'adk_type': 'function_call'},
                  },
                  <String, Object?>{
                    'data': <String, Object?>{
                      'id': 'fc-1',
                      'name': finishTaskToolName,
                      'response': <String, Object?>{
                        'result': finishTaskSuccessResult,
                      },
                    },
                    'metadata': <String, Object?>{
                      'adk_type': 'function_response',
                    },
                  },
                ],
              },
            ],
          },
        },
      );
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[],
      );

      final Map<String, dynamic>? args = findFinishTaskArgsFromHistory(
        session,
        completedFrEvent: frEvent,
      );
      expect(args, <String, dynamic>{'result': '42'});
    });

    for (final bool streaming in <bool>[true, false]) {
      test(
        'RemoteA2aAgent(mode: "task") sub_agent returns remote task output (streaming=$streaming)',
        () async {
          final RemoteA2aAgent proxy = RemoteA2aAgent(
            name: 'remote_worker',
            description: 'Remote worker',
            agentCard: AgentCard(
              name: 'remote_worker',
              description: 'Remote worker',
              url: 'http://localhost:8000',
              version: '0.0.1',
            ),
            a2aClientFactory: _FakeA2aClientFactory(streaming: streaming),
            mode: 'task',
          );

          final LlmAgent host = LlmAgent(
            name: 'host',
            model: _ScriptedHostModel(),
            subAgents: <BaseAgent>[proxy],
          );

          final InMemoryRunner runner = InMemoryRunner(agent: host);
          final Session session = await runner.sessionService.createSession(
            appName: runner.appName,
            userId: 'u1',
            sessionId: 's1',
          );

          final List<Event> events = await runner
              .runAsync(
                userId: 'u1',
                sessionId: session.id,
                newMessage: Content.userText('go'),
              )
              .toList();

          final List<FunctionResponse> toolResponses = <FunctionResponse>[
            for (final Event event in events)
              for (final FunctionResponse fr in event.getFunctionResponses())
                if (fr.name == 'remote_worker') fr,
          ];
          expect(toolResponses, hasLength(1));
          expect(toolResponses.single.response, <String, dynamic>{
            'result': '42',
          });
          await runner.close();
        },
      );
    }

    test('CustomMetricEvaluator sync function yields to event loop, preserves threshold on original, and sees evalClientLabel', () async {
      const String metricPath = 'test_module.nov09_sync_metric';
      final List<bool> labelsSeen = <bool>[];
      final List<double?> receivedThresholds = <double?>[];
      bool heartbeatRanBeforeSyncMetric = false;

      registerCustomMetricFunction(metricPath, (
        EvalMetricSpec evalMetric,
        List<Invocation> actualInvocations,
        List<Invocation>? expectedInvocations,
        ConversationScenario? conversationScenario,
      ) {
        labelsSeen.add(getClientLabels().contains(evalClientLabel));
        receivedThresholds.add(evalMetric.threshold);
        expect(heartbeatRanBeforeSyncMetric, isTrue);
        return EvaluationResult(
          overallScore: 0.9,
          overallEvalStatus: EvalStatus.passed,
        );
      });
      addTearDown(() => unregisterCustomMetricFunction(metricPath));

      final EvalMetricSpec originalMetric = EvalMetricSpec(
        metricName: 'custom_sync_metric',
        threshold: 0.8,
        customFunctionPath: metricPath,
      );
      final CustomMetricEvaluator evaluator = CustomMetricEvaluator(
        evalMetric: originalMetric,
        customFunctionPath: metricPath,
      );

      late final Future<List<EvaluationResult>> evaluationFuture;
      clientLabelContext(evalClientLabel, () {
        evaluationFuture = Future.wait(<Future<EvaluationResult>>[
          evaluator.evaluateInvocations(actualInvocations: <Invocation>[]),
          evaluator.evaluateInvocations(actualInvocations: <Invocation>[]),
        ]);
      });

      // Because synchronous custom metrics are scheduled on the event loop
      // rather than running synchronously in the caller frame, microtasks
      // scheduled immediately after invocation run before the sync body.
      scheduleMicrotask(() {
        heartbeatRanBeforeSyncMetric = true;
      });

      final List<EvaluationResult> results = await evaluationFuture;
      expect(
        results.map((EvaluationResult r) => r.overallScore).toList(),
        <double?>[0.9, 0.9],
      );
      expect(labelsSeen, <bool>[true, true]);
      expect(receivedThresholds, <double?>[null, null]);
      expect(originalMetric.threshold, 0.8);
    });

    test('LocalEvalService.evaluate runs synchronous Evaluator off caller frame and propagates evalClientLabel', () async {
      final List<bool> labelsSeen = <bool>[];
      int enteredCount = 0;

      final MetricEvaluatorRegistry registry = MetricEvaluatorRegistry();
      registry.registerEvaluator(
        metricInfo: MetricInfo(
          metricName: 'sync_metric',
          description: 'Synchronous test metric.',
          metricValueInfo: MetricValueInfo(
            interval: Interval(minValue: 0.0, maxValue: 1.0),
          ),
        ),
        evaluatorFactory: (EvalMetricSpec spec) => _SyncCustomEvaluator(
          onEvaluate: (
            List<Invocation> actualInvocations,
            List<Invocation>? expectedInvocations,
            ConversationScenario? conversationScenario,
          ) {
            enteredCount += 1;
            labelsSeen.add(getClientLabels().contains(evalClientLabel));
            return EvaluationResult(
              overallScore: 1.0,
              overallEvalStatus: EvalStatus.passed,
              perInvocationResults: <PerInvocationResult>[
                for (int i = 0; i < actualInvocations.length; i += 1)
                  PerInvocationResult(
                    actualInvocation: actualInvocations[i],
                    expectedInvocation:
                        expectedInvocations != null &&
                            i < expectedInvocations.length
                        ? expectedInvocations[i]
                        : null,
                    score: 1.0,
                    evalStatus: EvalStatus.passed,
                  ),
              ],
            );
          },
        ),
      );

      final Agent dummyAgent = Agent(
        name: 'dummy_agent',
        model: _ScriptedHostModel(),
      );
      final LocalEvalService service = LocalEvalService(
        rootAgent: dummyAgent,
        metricEvaluatorRegistry: registry,
      );

      final Invocation invocation = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'hello'},
          ],
        },
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            <String, Object?>{'text': 'world'},
          ],
        },
      );
      final EvalCase case0 = EvalCase(
        evalId: 'case_0',
        conversation: <Invocation>[invocation],
      );
      final EvalCase case1 = EvalCase(
        evalId: 'case_1',
        conversation: <Invocation>[invocation],
      );

      final EvaluateRequest request = EvaluateRequest(
        inferenceResults: <InferenceResult>[
          InferenceResult(
            appName: 'test_app',
            evalSetId: 'test_eval_set',
            evalCaseId: 'case_0',
            inferences: <Invocation>[invocation],
            sessionId: 'session_0',
          ),
          InferenceResult(
            appName: 'test_app',
            evalSetId: 'test_eval_set',
            evalCaseId: 'case_1',
            inferences: <Invocation>[invocation],
            sessionId: 'session_1',
          ),
        ],
        evalCasesById: <String, EvalCase>{
          'case_0': case0,
          'case_1': case1,
        },
        evaluateConfig: EvaluateConfig(
          evalMetricSpecs: <EvalMetricSpec>[
            EvalMetricSpec(metricName: 'sync_metric', threshold: 0.5),
          ],
          parallelism: 2,
        ),
      );

      final List<EvalCaseResult> results = await service
          .evaluate(request)
          .toList();

      expect(results, hasLength(2));
      expect(enteredCount, 2);
      expect(labelsSeen, <bool>[true, true]);
      expect(
        results.every(
          (EvalCaseResult r) => r.finalEvalStatus == EvalStatus.passed,
        ),
        isTrue,
      );
    });
  });
}
