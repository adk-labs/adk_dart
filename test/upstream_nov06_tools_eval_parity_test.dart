import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _MemoryEchoModel extends BaseLlm {
  _MemoryEchoModel({required this.onGenerate}) : super(model: 'memory-echo');

  final Future<String> Function(LlmRequest request) onGenerate;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String text = await onGenerate(request);
    yield LlmResponse(content: Content.modelText(text));
  }
}

class _ClosingToolset extends BaseToolset {
  bool closed = false;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return const <BaseTool>[];
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _NullScreenshotComputer extends BaseComputer {
  @override
  Future<ComputerState> currentState() async {
    return ComputerState(screenshot: null, url: 'https://example.com');
  }

  @override
  Future<ComputerState> openWebBrowser() => currentState();

  @override
  Future<ComputerState> clickAt(int x, int y) => currentState();

  @override
  Future<ComputerState> hoverAt(int x, int y) => currentState();

  @override
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) => currentState();

  @override
  Future<ComputerState> scrollDocument(String direction) => currentState();

  @override
  Future<ComputerState> scrollAt(
    int x,
    int y,
    String direction,
    int magnitude,
  ) => currentState();

  @override
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) => currentState();

  @override
  Future<ComputerState> keyCombination(List<String> keys) => currentState();

  @override
  Future<ComputerState> wait(int seconds) => currentState();

  @override
  Future<ComputerState> goBack() => currentState();

  @override
  Future<ComputerState> goForward() => currentState();

  @override
  Future<ComputerState> search() => currentState();

  @override
  Future<ComputerState> navigate(String url) => currentState();

  @override
  Future<(int, int)> screenSize() async => (1280, 720);

  @override
  Future<ComputerEnvironment> environment() async =>
      ComputerEnvironment.environmentBrowser;
}

class _CapturingCodeExecutor extends BaseCodeExecutor {
  CodeExecutionInput? lastInput;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    return CodeExecutionResult(stdout: 'ok', stderr: '');
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    lastInput = codeExecutionInput;
    return CodeExecutionResult(stdout: 'ok', stderr: '');
  }
}

class _ConcurrencyTrackingInvoker {
  _ConcurrencyTrackingInvoker({
    required this.delay,
    required this.responseBuilder,
  });

  final Duration delay;
  final String Function(String prompt, int callIndex) responseBuilder;
  int activeCalls = 0;
  int maxObservedConcurrency = 0;
  int totalCalls = 0;

  Future<LlmResponse> invoke({
    required String prompt,
    required JudgeModelOptions judgeModelOptions,
  }) async {
    activeCalls += 1;
    totalCalls += 1;
    final int callIdx = totalCalls;
    if (activeCalls > maxObservedConcurrency) {
      maxObservedConcurrency = activeCalls;
    }
    try {
      await Future<void>.delayed(delay);
      return LlmResponse(
        content: Content.modelText(responseBuilder(prompt, callIdx)),
      );
    } finally {
      activeCalls -= 1;
    }
  }
}

class _ConcurrencyTrackingJudgeLlm extends BaseLlm {
  _ConcurrencyTrackingJudgeLlm({
    required this.delay,
    required this.responseBuilder,
  }) : super(model: 'concurrency-judge');

  final Duration delay;
  final String Function(LlmRequest request, int callIndex) responseBuilder;
  int activeCalls = 0;
  int maxObservedConcurrency = 0;
  int totalCalls = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    activeCalls += 1;
    totalCalls += 1;
    final int callIdx = totalCalls;
    if (activeCalls > maxObservedConcurrency) {
      maxObservedConcurrency = activeCalls;
    }
    try {
      await Future<void>.delayed(delay);
      yield LlmResponse(
        content: Content.modelText(responseBuilder(request, callIdx)),
      );
    } finally {
      activeCalls -= 1;
    }
  }
}

class _TestLlmAsJudge extends LlmAsJudge {
  _TestLlmAsJudge({
    required super.evalMetric,
    required super.autoRaterInvoker,
  }) : super(
         expectedInvocationsRequired: false,
       );

  @override
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  ) {
    final String userText =
        actualInvocation.userContent['parts'] is List &&
            (actualInvocation.userContent['parts'] as List).isNotEmpty
        ? '${((actualInvocation.userContent['parts'] as List).first as Map)['text'] ?? ''}'
        : '';
    return 'Rate invocation: $userText';
  }

  @override
  AutoRaterScore convertAutoRaterResponseToScore(
    LlmResponse autoRaterResponse,
  ) {
    final String text =
        autoRaterResponse.content?.parts.firstOrNull?.text ?? '';
    return AutoRaterScore(score: text.contains('PASS') ? 1.0 : 0.0);
  }

  @override
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  ) {
    final double avg =
        perInvocationSamples
            .map((PerInvocationResult r) => r.score ?? 0.0)
            .reduce((double a, double b) => a + b) /
        perInvocationSamples.length;
    return PerInvocationResult(
      actualInvocation: perInvocationSamples.first.actualInvocation,
      expectedInvocation: perInvocationSamples.first.expectedInvocation,
      score: avg,
      evalStatus: avg >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
    );
  }

  @override
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    final double avg =
        perInvocationResults
            .map((PerInvocationResult r) => r.score ?? 0.0)
            .reduce((double a, double b) => a + b) /
        perInvocationResults.length;
    return EvaluationResult(
      overallScore: avg,
      overallEvalStatus: avg >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
      perInvocationResults: perInvocationResults,
    );
  }
}

class _TestRubricEvaluator extends RubricBasedEvaluator {
  _TestRubricEvaluator({
    required super.evalMetric,
    required super.autoRaterInvoker,
  });

  @override
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  ) {
    createEffectiveRubricsList(actualInvocation.rubrics);
    return 'Evaluate rubrics for invocation ${actualInvocation.invocationId}';
  }
}

Future<ToolContext> _buildToolContext({
  BaseMemoryService? memoryService,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'parent_app',
    userId: 'parent_user',
    sessionId: 'parent_session',
  );
  final InvocationContext invocationContext = InvocationContext(
    sessionService: sessionService,
    artifactService: InMemoryArtifactService(),
    memoryService: memoryService,
    invocationId: 'inv_parent',
    agent: Agent(
      name: 'parent_agent',
      model: _MemoryEchoModel(onGenerate: (_) async => 'parent'),
    ),
    session: session,
  );
  return ToolContext(invocationContext);
}

void main() {
  group('Upstream Nov 06 Tools Parity', () {
    test('4e0ac64e3 & 73cfd62ed: AgentTool shares parent memoryService and closes child runner in finally', () async {
      final InMemoryMemoryService parentMemory = InMemoryMemoryService();
      final Session seededSession = Session(
        id: 'mem_sess',
        appName: 'child_agent',
        userId: 'user',
        events: <Event>[
          Event(
            invocationId: 'inv_mem',
            author: 'user',
            content: Content.userText('Secret project codename is AURORA.'),
          ),
        ],
      );
      await parentMemory.addSessionToMemory(seededSession);

      final _ClosingToolset closingToolset = _ClosingToolset();
      bool memoryWasShared = false;
      final FunctionTool checkMemoryTool = FunctionTool(
        name: 'check_memory',
        description: 'Searches memory for AURORA',
        func: (ToolContext toolContext) async {
          final SearchMemoryResponse res = await toolContext.searchMemory(
            'AURORA',
          );
          memoryWasShared = res.memories.isNotEmpty;
          return <String, Object?>{'found': memoryWasShared};
        },
      );

      final Agent childAgent = Agent(
        name: 'child_agent',
        model: _MemoryEchoModel(
          onGenerate: (LlmRequest req) async {
            return 'AURORA_CONFIRMED';
          },
        ),
        tools: <Object>[checkMemoryTool, closingToolset],
        beforeAgentCallback: (CallbackContext ctx) async {
          if (identical(ctx.invocationContext.memoryService, parentMemory)) {
            memoryWasShared = true;
          }
          return null;
        },
      );

      final AgentTool agentTool = AgentTool(agent: childAgent);
      final ToolContext toolContext = await _buildToolContext(
        memoryService: parentMemory,
      );
      final Object? result = await agentTool.run(
        args: <String, dynamic>{'request': 'Check codename'},
        toolContext: toolContext,
      );

      expect(result, 'AURORA_CONFIRMED');
      expect(memoryWasShared, isTrue);
      expect(closingToolset.closed, isTrue);
    });

    test('90d352bdf: AgentTool accepts inputSchema args using aliases and serializes by canonical field name', () async {
      String? receivedPayload;
      final Map<String, Object?> customSchema = <String, Object?>{
        'type': 'object',
        'alias_generator': 'to_camel',
        'properties': <String, Object?>{
          'first_name': <String, Object?>{
            'type': 'string',
            'alias': 'givenName',
          },
          'last_name': <String, Object?>{
            'type': 'string',
          },
          'nested_id': <String, Object?>{
            'type': 'string',
            'validation_alias': <Object?>['meta', 'id'],
          },
          'optional_tag': <String, Object?>{
            'type': 'string',
          },
          'country': <String, Object?>{
            'type': 'string',
            'default': 'KR',
          },
        },
        'required': <String>['first_name', 'last_name', 'nested_id'],
      };

      final Agent childAgent = Agent(
        name: 'schema_child',
        inputSchema: customSchema,
        model: _MemoryEchoModel(
          onGenerate: (LlmRequest request) async {
            receivedPayload = request.contents.last.parts.first.text;
            return 'processed';
          },
        ),
      );

      final AgentTool agentTool = AgentTool(agent: childAgent);
      final ToolContext toolContext = await _buildToolContext();
      await agentTool.run(
        args: <String, dynamic>{
          'givenName': 'Ada',
          'lastName': 'Lovelace',
          'meta': <String, Object?>{'id': 'id-42'},
          'optionalTag': null,
        },
        toolContext: toolContext,
      );

      expect(receivedPayload, isNotNull);
      final Map<String, dynamic> decoded =
          jsonDecode(receivedPayload!) as Map<String, dynamic>;
      expect(decoded, <String, Object?>{
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'nested_id': 'id-42',
        'country': 'KR',
      });
      expect(decoded.containsKey('optional_tag'), isFalse);
    });

    test('19e3d5b4a: BaseTool.fromConfig and VertexAiRagRetrieval.fromConfig unwrap optional parameter types', () {
      expect(
        BaseTool.unwrapOptionalParameterType('List<VertexAiRagResource>?'),
        'List<VertexAiRagResource>',
      );
      expect(
        BaseTool.unwrapOptionalParameterType('VertexAiRagResource | None'),
        'VertexAiRagResource',
      );

      final ToolArgsConfig argsConfig = ToolArgsConfig(
        values: <String, Object?>{
          'name': 'rag_search',
          'description': 'Search Vertex AI RAG corpora',
          'rag_corpora': <String>['projects/p/locations/l/ragCorpora/c1'],
          'rag_resources': <Map<String, Object?>>[
            <String, Object?>{
              'rag_corpus': 'projects/p/locations/l/ragCorpora/c2',
            },
          ],
          'similarity_top_k': 5,
          'vector_distance_threshold': 0.75,
        },
      );

      final VertexAiRagRetrieval tool = VertexAiRagRetrieval.fromConfig(
        argsConfig,
        '/tmp/root_agent.yaml',
      );
      expect(tool.name, 'rag_search');
      expect(
        tool.vertexRagStore.ragCorpora,
        <String>['projects/p/locations/l/ragCorpora/c1'],
      );
      expect(tool.vertexRagStore.ragResources, hasLength(1));
      expect(
        tool.vertexRagStore.ragResources!.first.path,
        'projects/p/locations/l/ragCorpora/c2',
      );
      expect(tool.vertexRagStore.similarityTopK, 5);
      expect(tool.vertexRagStore.vectorDistanceThreshold, 0.75);
    });

    test('a702e3c08: setResourceLimits enforces limits set to 0', () {
      final List<(String, (int, int))> applied = <(String, (int, int))>[];
      setResourceLimits(
        BashToolPolicy(
          maxMemoryBytes: 0,
          maxFileSizeBytes: 0,
          maxChildProcesses: 0,
        ),
        (String resource, (int, int) limits) {
          applied.add((resource, limits));
        },
      );
      expect(applied, <(String, (int, int))>[
        (ResourceLimit.rlimitCore, (0, 0)),
        (ResourceLimit.rlimitAs, (0, 0)),
        (ResourceLimit.rlimitFsize, (0, 0)),
        (ResourceLimit.rlimitNproc, (0, 0)),
      ]);
    });

    test('8f8e0c270: ComputerState allows null screenshot and ComputerUseTool handles missing screenshot', () async {
      final ComputerState state = ComputerState();
      expect(state.screenshot, isNull);

      final _NullScreenshotComputer computer = _NullScreenshotComputer();
      final ComputerUseTool tool = ComputerUseTool(
        name: 'click_at',
        description: 'Clicks at coordinates',
        screenSize: (1280, 720),
        virtualScreenSize: (1000, 1000),
        func: (Map<String, dynamic> args) => computer.clickAt(
          args['x'] as int,
          args['y'] as int,
        ),
      );
      final ToolContext toolContext = await _buildToolContext();
      final Object? result = await tool.run(
        args: <String, dynamic>{'x': 500, 'y': 500},
        toolContext: toolContext,
      );
      expect(result, <String, Object?>{
        'image': <String, Object?>{'mimetype': 'image/png', 'data': ''},
        'url': 'https://example.com',
      });
    });

    test('89ae4d353: load_web_page countWords keeps Chinese and Japanese lines without spaces', () {
      const String chineseLine = '人工智能正在深刻改变软件开发的方式与未来';
      const String japaneseLine = '人工知能はソフトウェア開発の未来を大きく変えています';
      const String shortNav = 'Home About';

      expect(isUnspacedLetter('中'), isTrue);
      expect(isUnspacedLetter('あ'), isTrue);
      expect(isUnspacedLetter('ア'), isTrue);
      expect(isUnspacedLetter('A'), isFalse);

      expect(countWords(chineseLine), greaterThan(3));
      expect(countWords(japaneseLine), greaterThan(3));
      expect(countWords(shortNav), lessThanOrEqualTo(3));
    });

    test('ff61524bb: SkillToolset validates script paths/extensions and builds shell-escaped commands', () async {
      final _CapturingCodeExecutor executor = _CapturingCodeExecutor();
      final Skill skill = Skill(
        frontmatter: Frontmatter(
          name: 'data-helper',
          description: 'Runs data scripts',
        ),
        instructions: 'Use scripts to process data.',
        resources: Resources(
          scripts: <String, Script>{
            'run.py': Script(src: 'print("hello")'),
            'notes.txt': Script(src: 'not executable'),
          },
        ),
      );
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[skill],
        codeExecutor: executor,
      );
      final List<BaseTool> tools = await toolset.getTools();
      final BaseTool runScriptTool = tools.firstWhere(
        (BaseTool t) => t.name == 'run_skill_script',
      );

      final FunctionDeclaration decl = runScriptTool.getDeclaration()!;
      final Map<String, Object?> props =
          decl.parameters['properties'] as Map<String, Object?>;
      expect(props.containsKey('command'), isFalse);

      final ToolContext toolContext = await _buildToolContext();

      // Unsupported extension is rejected before codeExecution.
      final Map<String, Object?> badExt =
          await runScriptTool.run(
                args: <String, dynamic>{
                  'skill_name': 'data-helper',
                  'script_path': 'notes.txt',
                },
                toolContext: toolContext,
              )
              as Map<String, Object?>;
      expect(badExt['error_code'], 'UNSUPPORTED_SCRIPT_TYPE');
      expect('${badExt['error']}', contains('Unsupported script type'));
      expect(executor.lastInput, isNull);

      // Valid script builds shell-escaped command and converts positional args to strings.
      final Map<String, Object?> okRes =
          await runScriptTool.run(
                args: <String, dynamic>{
                  'skill_name': 'data-helper',
                  'script_path': 'run.py',
                  'args': <Object?>['hello world', 42, true],
                },
                toolContext: toolContext,
              )
              as Map<String, Object?>;
      expect(okRes['status'], 'success');
      expect(executor.lastInput, isNotNull);
      expect(
        executor.lastInput!.code,
        contains('["scripts/run.py","hello world","42","true"]'),
      );

      expect(
        buildSkillSystemInstruction(scriptExecutionEnabled: true),
        contains('`run_skill_script`'),
      );
    });

    test('2717d54bb: mcpSdkOperationalMajorVersion is 1', () {
      expect(mcpSdkOperationalMajorVersion, 1);
    });
  });

  group('Upstream Nov 06 Evaluation Parity', () {
    test('5c7a8297e: pass@k and pass^k aggregation methods, PassKMultiRunCriterion, and checkPassKCriteriaAgainstNumRuns', () {
      final List<RunResult> runs = <RunResult>[
        RunResult(status: EvalStatus.passed),
        RunResult(status: EvalStatus.failed),
        RunResult(status: EvalStatus.passed),
        RunResult(status: EvalStatus.passed),
      ];

      // 3 passed out of 4 decided:
      // pass@2 = 1 - C(1, 2)/C(4, 2) = 1 - 0/6 = 1.0
      // pass^2 = C(3, 2)/C(4, 2) = 3/6 = 0.5
      expect(passAtK(runs, 2), closeTo(1.0, 1e-9));
      expect(passHatK(runs, 2), closeTo(0.5, 1e-9));
      expect(passAtK(runs, 5), isNull);
      expect(passHatK(runs, 5), isNull);

      final Map<String, AggregationMethod> builtIns =
          getBuiltInAggregationMethods();
      final AggregationMethod passAt2 = builtIns['pass_at_k']!.withK(2);
      final AggregationMethod passHat2 = builtIns['pass_hat_k']!.withK(2);
      expect(passAt2.compute(runs), closeTo(1.0, 1e-9));
      expect(passHat2.compute(runs), closeTo(0.5, 1e-9));

      final EvalConfig config = EvalConfig.fromJson(<String, Object?>{
        'criteria': <String, Object?>{'final_response_exact_match': 1.0},
        'multi_run_config': <String, Object?>{
          'num_runs': 4,
          'cross_run_criteria': <Map<String, Object?>>[
            <String, Object?>{
              'method': 'pass_at_k',
              'k': 2,
              'threshold': 0.8,
            },
            <String, Object?>{
              'method': 'pass_hat_k',
              'k': 2,
              'threshold': 0.6,
            },
            <String, Object?>{
              'method': 'pass_at_k',
              'k': 3,
            },
          ],
        },
      });

      expect(
        config.multiRunConfig!.crossRunCriteria![0],
        isA<PassKMultiRunCriterion>(),
      );
      expect(
        config.multiRunConfig!.crossRunCriteria![2].threshold,
        isNull,
      );
      expect(hasPassCountRules(config.multiRunConfig), isTrue);

      expect(
        () => checkPassKCriteriaAgainstNumRuns(config.multiRunConfig, 1),
        throwsArgumentError,
      );
      checkPassKCriteriaAgainstNumRuns(config.multiRunConfig, 4);

      EvalCaseResult makeRun(int idx, EvalStatus status) {
        return EvalCaseResult(
          evalSetId: 'set1',
          evalId: 'case1',
          finalEvalStatus: status,
          evalMetricResultPerInvocation: const <EvalMetricResultPerInvocation>[],
          overallEvalMetricResults: <EvalMetricResultSpec>[
            EvalMetricResultSpec(
              metricName: 'final_response_exact_match',
              threshold: 1.0,
              score: status == EvalStatus.passed ? 1.0 : 0.0,
              evalStatus: status,
            ),
          ],
          sessionId: 'sess_$idx',
        );
      }

      final List<MultiRunCaseResult> aggregated = aggregateEvalCaseResults(
        <EvalCaseResult>[
          makeRun(1, EvalStatus.passed),
          makeRun(2, EvalStatus.failed),
          makeRun(3, EvalStatus.passed),
          makeRun(4, EvalStatus.passed),
        ],
        multiRunConfig: config.multiRunConfig,
      );
      expect(aggregated, hasLength(1));
      final MultiRunCaseResult caseResult = aggregated.first;
      expect(caseResult.crossRunResults, hasLength(3));
      expect(caseResult.crossRunResults[0].value, closeTo(1.0, 1e-9));
      expect(
        caseResult.crossRunResults[0].status,
        EvalStatus.passed,
      );
      // pass^2 = 0.5 < threshold 0.6 -> failed
      expect(
        caseResult.crossRunResults[1].value,
        closeTo(0.5, 1e-9),
      );
      expect(
        caseResult.crossRunResults[1].status,
        EvalStatus.failed,
      );
      // Report-only criterion has null threshold -> informational
      expect(
        caseResult.crossRunResults[2].status,
        EvalStatus.informational,
      );
      expect(caseResult.finalEvalStatus, EvalStatus.failed);
    });

    test('425576020: AgentDetails loads toolDeclarations back into ToolDeclaration and serializes cleanly', () {
      final AgentDetails details = AgentDetails.fromJson(<String, Object?>{
        'name': 'weather_agent',
        'instructions': 'Provide weather forecasts.',
        'tool_declarations': <Object?>[
          <String, Object?>{
            'function_declarations': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'get_weather',
                'description': 'Gets weather for a city',
                'parameters': <String, Object?>{
                  'type': 'OBJECT',
                  'properties': <String, Object?>{
                    'city': <String, Object?>{'type': 'STRING'},
                  },
                },
              },
            ],
          },
        ],
      });

      expect(details.toolDeclarations, hasLength(1));
      expect(details.toolDeclarations.first, isA<ToolDeclaration>());
      final ToolDeclaration toolDecl =
          details.toolDeclarations.first as ToolDeclaration;
      expect(toolDecl.functionDeclarations, hasLength(1));
      expect(toolDecl.functionDeclarations.first.name, 'get_weather');

      final AppDetails appDetails = AppDetails(
        agentDetails: <String, AgentDetails>{'weather_agent': details},
      );
      final String jsonStr = getToolDeclarationsAsJsonStr(appDetails);
      final Map<String, dynamic> decoded =
          jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['tool_declarations'], isA<Map<String, dynamic>>());
    });

    test('656696c4d: LlmAsJudge and PerTurnUserSimulatorQualityV1 honor parallelismLimit', () async {
      final _ConcurrencyTrackingInvoker invoker = _ConcurrencyTrackingInvoker(
        delay: const Duration(milliseconds: 25),
        responseBuilder: (String prompt, int callIndex) => 'PASS',
      );
      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: 'custom_judge',
        threshold: 0.5,
        criterion: LlmAsAJudgeCriterion(
          threshold: 0.5,
          judgeModelOptions: JudgeModelOptions(
            numSamples: 2,
            parallelismLimit: 2,
          ),
        ),
      );
      final _TestLlmAsJudge judge = _TestLlmAsJudge(
        evalMetric: metric,
        autoRaterInvoker: invoker.invoke,
      );

      final List<Invocation> invocations = List<Invocation>.generate(
        3,
        (int i) => Invocation(
          invocationId: 'inv_$i',
          userContent: <String, Object?>{
            'role': 'user',
            'parts': <Map<String, Object?>>[
              <String, Object?>{'text': 'question $i'},
            ],
          },
          finalResponse: <String, Object?>{
            'role': 'model',
            'parts': <Map<String, Object?>>[
              <String, Object?>{'text': 'answer $i'},
            ],
          },
        ),
      );

      final EvaluationResult res = await judge.evaluateInvocations(
        actualInvocations: invocations,
      );
      expect(res.overallEvalStatus, EvalStatus.passed);
      expect(invoker.totalCalls, 6);
      expect(invoker.maxObservedConcurrency, lessThanOrEqualTo(2));
      expect(invoker.maxObservedConcurrency, greaterThanOrEqualTo(2));

      // Verify PerTurnUserSimulatorQualityV1 bounds concurrency as well.
      final _ConcurrencyTrackingJudgeLlm simJudgeLlm =
          _ConcurrencyTrackingJudgeLlm(
            delay: const Duration(milliseconds: 25),
            responseBuilder: (LlmRequest request, int callIndex) =>
                '{"is_valid": "valid"}',
          );
      final PerTurnUserSimulatorQualityV1 simEval =
          PerTurnUserSimulatorQualityV1(
            EvalMetricSpec(
              metricName: 'per_turn_user_simulator_quality_v1',
              threshold: 0.5,
              criterion: LlmBackedUserSimulatorCriterion(
                threshold: 0.5,
                judgeModelOptions: JudgeModelOptions(
                  numSamples: 1,
                  parallelismLimit: 2,
                ),
              ),
            ),
            llmFactory: (_) => simJudgeLlm,
          );
      final EvaluationResult simRes = await simEval.evaluateInvocations(
        actualInvocations: invocations,
        conversationScenario: ConversationScenario(
          startingPrompt: 'question 0',
          conversationPlan: 'Ask 3 questions.',
        ),
      );
      expect(simRes.overallEvalStatus, EvalStatus.passed);
      expect(simJudgeLlm.maxObservedConcurrency, lessThanOrEqualTo(2));
    });

    test('d1f2add4f & e4f6c3a9c: RubricBasedEvaluator drops incomplete sample verdicts and scores invocation-specific rubrics', () async {
      final List<String> judgeOutputs = <String>[
        // Sample 1 for invocation 1: leaves rubric inv1_r without a verdict -> dropped!
        '''
ID: r1
Property: Answers greeting
Rationale: Did greet
Verdict: yes
''',
        // Sample 2 for invocation 1: answers both r1 and inv1_r -> kept!
        '''
ID: r1
Property: Answers greeting
Rationale: Did greet
Verdict: yes

ID: inv1_r
Property: Mentions Seattle
Rationale: Mentioned Seattle
Verdict: yes
''',
        // Sample 1 for invocation 2: answers r1 and inv2_r (no inv1_r!) -> kept!
        '''
ID: r1
Property: Answers greeting
Rationale: Did greet
Verdict: yes

ID: inv2_r
Property: Mentions Tokyo
Rationale: Did not mention Tokyo
Verdict: no
''',
        // Sample 2 for invocation 2: answers r1 and inv2_r -> kept!
        '''
ID: r1
Property: Answers greeting
Rationale: Did greet
Verdict: yes

ID: inv2_r
Property: Mentions Tokyo
Rationale: Did not mention Tokyo
Verdict: no
''',
      ];
      int callIdx = 0;

      final Rubric globalRubric = Rubric(
        rubricId: 'r1',
        rubricContent: RubricContent(textProperty: 'Answers greeting'),
      );
      final _TestRubricEvaluator evaluator = _TestRubricEvaluator(
        evalMetric: EvalMetricSpec(
          metricName: 'rubric_metric',
          threshold: 0.5,
          criterion: RubricsBasedCriterion(
            threshold: 0.5,
            judgeModelOptions: JudgeModelOptions(
              numSamples: 2,
              parallelismLimit: 1,
            ),
            rubrics: <Rubric>[globalRubric],
          ),
        ),
        autoRaterInvoker: ({
          required String prompt,
          required JudgeModelOptions judgeModelOptions,
        }) async {
          return LlmResponse(
            content: Content.modelText(judgeOutputs[callIdx++]),
          );
        },
      );

      final List<Invocation> actuals = <Invocation>[
        Invocation(
          invocationId: 'actual_1',
          userContent: <String, Object?>{'role': 'user'},
          rubrics: <Map<String, Object?>>[
            Rubric(
              rubricId: 'inv1_r',
              rubricContent: RubricContent(textProperty: 'Mentions Seattle'),
            ).toJson(),
          ],
        ),
        Invocation(
          invocationId: 'actual_2',
          userContent: <String, Object?>{'role': 'user'},
          rubrics: <Map<String, Object?>>[
            Rubric(
              rubricId: 'inv2_r',
              rubricContent: RubricContent(textProperty: 'Mentions Tokyo'),
            ).toJson(),
          ],
        ),
      ];
      final List<Invocation> expecteds = <Invocation>[
        Invocation(
          invocationId: 'exp_1',
          userContent: <String, Object?>{'role': 'user'},
        ),
        Invocation(
          invocationId: 'exp_2',
          userContent: <String, Object?>{'role': 'user'},
        ),
      ];

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: actuals,
        expectedInvocations: expecteds,
      );

      expect(result.perInvocationResults, hasLength(2));
      // Invocation 1: sample 1 was dropped because inv1_r had no verdict; sample 2 scored 1.0 on both r1 and inv1_r.
      expect(result.perInvocationResults[0].score, closeTo(1.0, 1e-9));
      // Invocation 2: scored against r1 (1.0) and inv2_r (0.0) -> 0.5.
      expect(result.perInvocationResults[1].score, closeTo(0.5, 1e-9));
    });
  });
}
