import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/agents/readonly_context.dart';
import 'package:adk_dart/src/evaluation/base_eval_service.dart';
import 'package:adk_dart/src/evaluation/eval_case.dart';
import 'package:adk_dart/src/evaluation/eval_metric.dart';
import 'package:adk_dart/src/evaluation/eval_metrics.dart';
import 'package:adk_dart/src/evaluation/eval_result.dart';
import 'package:adk_dart/src/evaluation/evaluation_generator.dart';
import 'package:adk_dart/src/evaluation/evaluator.dart';
import 'package:adk_dart/src/evaluation/hallucinations_v1.dart';
import 'package:adk_dart/src/evaluation/local_eval_service.dart';
import 'package:adk_dart/src/evaluation/metric_evaluator_registry.dart';
import 'package:adk_dart/src/evaluation/metric_info_providers.dart';
import 'package:adk_dart/src/evaluation/tool_parameter_match_evaluator.dart';
import 'package:adk_dart/src/evaluation/trajectory_evaluator.dart';
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/skills/skill_runtime.dart';
import 'package:adk_dart/src/tools/_automatic_function_calling_util.dart';
import 'package:adk_dart/src/tools/application_integration_tool/clients/connections_client.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/base_toolset.dart';
import 'package:adk_dart/src/tools/computer_use/base_computer.dart';
import 'package:adk_dart/src/tools/computer_use/computer_use_toolset.dart';
import 'package:adk_dart/src/tools/environment/base_environment.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_session_manager.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_toolset.dart';
import 'package:adk_dart/src/tools/openapi_tool/common/common.dart';
import 'package:adk_dart/src/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.dart';
import 'package:adk_dart/src/tools/openapi_tool/openapi_spec_parser/rest_api_tool.dart';
import 'package:adk_dart/src/tools/skill_toolset.dart';
import 'package:adk_dart/src/tools/tool_args_matcher/tool_args_matcher.dart';
import 'package:adk_dart/src/tools/toolsearch/tool_search_toolset.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'package:test/test.dart';

class _QueuedLlm extends BaseLlm {
  _QueuedLlm(this.responses) : super(model: 'fake-llm');

  final List<LlmResponse> responses;
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (_index < responses.length) {
      yield responses[_index++];
    }
  }
}

class _AsyncTestMatcher extends BaseArgMatcher {
  _AsyncTestMatcher(this._fn);

  final Future<bool> Function(Object? expected, Object? actual) _fn;

  @override
  String get type => 'custom_async';

  @override
  ArgMatchResult match(Object? actual) =>
      ArgMatchResult(matched: true, actual: actual, matcherType: type);

  @override
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    final bool ok = await _fn(expected, actual);
    return ArgMatchResult(
      matched: ok,
      expected: expected,
      actual: actual,
      matcherType: type,
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': type};
}

class _CountingToolset extends BaseToolset {
  _CountingToolset({
    super.toolNamePrefix,
    super.disableInvocationCache,
  });

  int getToolsCallCount = 0;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    getToolsCallCount += 1;
    return <BaseTool>[
      FunctionTool(
        name: 'tool_$getToolsCallCount',
        func: () => 'ok',
      ),
    ];
  }
}

class _FakeEnvironment extends BaseEnvironment {
  _FakeEnvironment({super.workingDirectory});

  int initializeCount = 0;
  int closeCount = 0;
  final Map<String, List<int>> writtenFiles = <String, List<int>>{};
  final List<String> executedCommands = <String>[];

  @override
  Future<void> initialize({Context? ctx}) async {
    initializeCount += 1;
    isInitialized = true;
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    isInitialized = false;
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async {
    executedCommands.add(command);
    return const EnvironmentExecutionResult(
      exitCode: 0,
      stdout: 'ran ok\n',
    );
  }

  @override
  Future<List<int>> readFile(Object path, {Context? ctx}) async {
    return writtenFiles['$path'] ?? const <int>[];
  }

  @override
  Future<void> writeFile(
    Object path,
    Object content, {
    Context? ctx,
  }) async {
    writtenFiles['$path'] = encodeWriteFileContent(content);
  }
}

class _FakeComputer extends BaseComputer {
  @override
  Future<(int, int)> screenSize() async => (1024, 768);

  @override
  Future<ComputerEnvironment> environment() async =>
      ComputerEnvironment.environmentBrowser;

  @override
  Future<ComputerState> currentState() async =>
      ComputerState(url: 'https://example.com');

  @override
  Future<ComputerState> openWebBrowser() => currentState();

  @override
  Future<ComputerState> clickAt(int x, int y) => currentState();

  @override
  Future<ComputerState> hoverAt(int x, int y) => currentState();

  @override
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) => currentState();

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
  Future<ComputerState> keyCombination(List<String> keys) => currentState();

  @override
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) => currentState();
}

Context _makeContext({String invocationId = 'inv_1'}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: LlmAgent(
      name: 'agent',
      model: _QueuedLlm(const <LlmResponse>[]),
    ),
    session: Session(
      id: 'sess_1',
      appName: 'app',
      userId: 'user_1',
      state: <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

Invocation _toolInvocation({
  required List<EvalJsonMap> toolUses,
  List<EvalJsonMap>? toolResponses,
  String userText = 'run tools',
  String finalText = 'done',
}) {
  return Invocation(
    userContent: <String, Object?>{
      'role': 'user',
      'parts': <Object?>[
        <String, Object?>{'text': userText},
      ],
    },
    finalResponse: <String, Object?>{
      'role': 'model',
      'parts': <Object?>[
        <String, Object?>{'text': finalText},
      ],
    },
    intermediateData: IntermediateData(
      toolUses: toolUses,
      toolResponses: toolResponses,
    ),
  );
}

void main() {
  group('1. Tools Parity (67b217d00..df9f9d045)', () {
    test('ca42dcd18: removeAnyOf selects first non-null union member', () {
      final Map<String, Object?> leadingNullSchema = <String, Object?>{
        'properties': <String, Object?>{
          'field': <String, Object?>{
            'anyOf': <Object?>[
              <String, Object?>{'type': 'null'},
              <String, Object?>{'type': 'string', 'description': 'primary'},
              <String, Object?>{'type': 'integer'},
            ],
            'title': 'UnionField',
          },
        },
      };
      removeAnyOf(leadingNullSchema);
      final Map<String, Object?> leadingNullProp =
          ((leadingNullSchema['properties'] as Map)['field'] as Map)
              .cast<String, Object?>();
      expect(leadingNullProp.containsKey('anyOf'), isFalse);
      expect(leadingNullProp['type'], 'string');
      expect(leadingNullProp['description'], 'primary');
      expect(leadingNullProp['title'], 'UnionField');

      final Map<String, Object?> multiNonNullSchema = <String, Object?>{
        'properties': <String, Object?>{
          'field': <String, Object?>{
            'anyOf': <Object?>[
              <String, Object?>{'type': 'string'},
              <String, Object?>{'type': 'number'},
            ],
          },
        },
      };
      removeAnyOf(multiNonNullSchema);
      final Map<String, Object?> multiNonNullProp =
          ((multiNonNullSchema['properties'] as Map)['field'] as Map)
              .cast<String, Object?>();
      expect(multiNonNullProp['type'], 'string');

      final Map<String, Object?> fullSchema = <String, Object?>{
        'title': 'Payload',
        'type': 'object',
        'properties': <String, Object?>{
          'id': <String, Object?>{
            'title': 'Id',
            'default': 'abc',
            'anyOf': <Object?>[
              <String, Object?>{'type': 'null'},
              <String, Object?>{'type': 'string'},
              <String, Object?>{'type': 'integer'},
            ],
          },
          'count': <String, Object?>{
            'type': 'integer',
          },
        },
      };
      final Map<String, Object?> processedNonVertex = processPydanticSchema(
        false,
        fullSchema,
      );
      final Map<String, Object?> props =
          (processedNonVertex['properties'] as Map).cast<String, Object?>();
      final Map<String, Object?> idProp =
          (props['id'] as Map).cast<String, Object?>();
      expect(idProp.containsKey('title'), isFalse);
      expect(idProp['type'], 'string');
      expect(idProp.containsKey('nullable'), isFalse);
      expect(idProp.containsKey('default'), isFalse);
      expect(processedNonVertex['required'], equals(<String>['count']));

      final Map<String, Object?> processedVertex = processPydanticSchema(
        true,
        fullSchema,
      );
      final Map<String, Object?> vertexIdProp =
          ((processedVertex['properties'] as Map)['id'] as Map)
              .cast<String, Object?>();
      expect(vertexIdProp['nullable'], isTrue);
    });

    test('ab6384438: ConnectionsClient fails on operation error and bounds poll wait', () async {
      final ConnectionsClient errorClient = ConnectionsClient(
        project: 'proj',
        location: 'us-central1',
        connection: 'conn1',
        accessTokenProvider: ({String? serviceAccountJson}) async => 'tok',
        sleeper: (_) async {},
        requestExecutor: ({
          required Uri uri,
          required String method,
          required Map<String, String> headers,
          String? body,
        }) async {
          if (uri.path.contains(':fetchAuthSchema') ||
              uri.path.contains('connectionSchemaMetadata')) {
            return ApplicationIntegrationHttpResponse(
              statusCode: 200,
              body: jsonEncode(<String, Object?>{'name': 'operations/op-err'}),
            );
          }
          return ApplicationIntegrationHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'name': 'operations/op-err',
              'done': true,
              'error': <String, Object?>{
                'code': 13,
                'message': 'Connector backend crashed',
              },
            }),
          );
        },
      );

      await expectLater(
        () => errorClient.getEntitySchemaAndOperations('Account'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(
              contains('operations/op-err'),
              contains('Connector backend crashed'),
            ),
          ),
        ),
      );

      Duration now = Duration.zero;
      final ConnectionsClient timeoutClient = ConnectionsClient(
        project: 'proj',
        location: 'us-central1',
        connection: 'conn1',
        operationTimeout: const Duration(seconds: 5),
        monotonicClock: () => now,
        sleeper: (Duration d) async {
          now += const Duration(seconds: 3);
        },
        accessTokenProvider: ({String? serviceAccountJson}) async => 'tok',
        requestExecutor: ({
          required Uri uri,
          required String method,
          required Map<String, String> headers,
          String? body,
        }) async {
          if (uri.path.contains('operations/op-slow')) {
            return ApplicationIntegrationHttpResponse(
              statusCode: 200,
              body: jsonEncode(<String, Object?>{
                'name': 'operations/op-slow',
                'done': false,
              }),
            );
          }
          return ApplicationIntegrationHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{'name': 'operations/op-slow'}),
          );
        },
      );

      await expectLater(
        () => timeoutClient.getEntitySchemaAndOperations('Account'),
        throwsA(
          isA<TimeoutException>().having(
            (TimeoutException e) => e.message,
            'message',
            contains('operations/op-slow'),
          ),
        ),
      );
    });

    test('b979abe57 & b79c529b5: BaseToolset invocation caching, opt-out, and load_mcp_resource', () async {
      final Context ctx1 = _makeContext(invocationId: 'inv_a');
      final Context ctx2 = _makeContext(invocationId: 'inv_b');

      final _CountingToolset cached = _CountingToolset(toolNamePrefix: 'p');
      expect(cached.useInvocationCache, isTrue);
      final List<BaseTool> first = await cached.getToolsWithPrefix(
        readonlyContext: ctx1,
      );
      final List<BaseTool> secondSameInvocation =
          await cached.getToolsWithPrefix(readonlyContext: ctx1);
      final List<BaseTool> otherInvocation = await cached.getToolsWithPrefix(
        readonlyContext: ctx2,
      );
      expect(cached.getToolsCallCount, 2);
      expect(first.single.name, 'p_tool_1');
      expect(secondSameInvocation.single.name, 'p_tool_1');
      expect(otherInvocation.single.name, 'p_tool_2');

      final _CountingToolset uncached = _CountingToolset(
        toolNamePrefix: 'p',
        disableInvocationCache: true,
      );
      expect(uncached.useInvocationCache, isFalse);
      await uncached.getToolsWithPrefix(readonlyContext: ctx1);
      await uncached.getToolsWithPrefix(readonlyContext: ctx1);
      expect(uncached.getToolsCallCount, 2);

      // ToolSearchToolset and SkillToolset disable invocation cache by default.
      final ToolSearchToolset toolSearch = ToolSearchToolset(
        tools: <Object>[FunctionTool(name: 'alpha', func: () => 1)],
      );
      expect(toolSearch.useInvocationCache, isFalse);

      final SkillToolset skillToolset = SkillToolset(skills: const <Skill>[]);
      expect(skillToolset.useInvocationCache, isFalse);

      final ComputerUseToolset computerToolset = ComputerUseToolset(
        computer: _FakeComputer(),
        disableInvocationCache: true,
      );
      expect(computerToolset.useInvocationCache, isFalse);

      // McpToolset appends load_mcp_resource even when toolFilter excludes it.
      final StreamableHTTPConnectionParams mcpParams =
          StreamableHTTPConnectionParams(
            url: 'http://localhost:39991/mcp-nov12-test',
          );
      McpSessionManager.instance.registerTools(
        connectionParams: mcpParams,
        tools: <BaseTool>[
          FunctionTool(
            name: 'allowed_tool',
            description: 'Allowed remote tool',
            func: () => 'ok',
          ),
          FunctionTool(
            name: 'blocked_tool',
            description: 'Blocked remote tool',
            func: () => 'ok',
          ),
        ],
      );
      addTearDown(McpSessionManager.instance.clear);
      final McpToolset mcpToolset = McpToolset(
        connectionParams: mcpParams,
        toolFilter: const <String>['allowed_tool'],
        useMcpResources: true,
        disableInvocationCache: true,
      );
      expect(mcpToolset.useInvocationCache, isFalse);
      final List<BaseTool> mcpTools = await mcpToolset.getTools();
      expect(
        mcpTools.map((BaseTool t) => t.name).toList(),
        equals(<String>['allowed_tool', 'load_mcp_resource']),
      );
    });

    test('e5ffe9c9d: ApiParameter and RestApiTool preserve required flag across serialization', () {
      final ApiParameter requiredParam = ApiParameter(
        originalName: 'userId',
        paramLocation: 'query',
        paramSchema: <String, Object?>{'type': 'string'},
        description: 'Required user id',
        required: true,
      );
      final ApiParameter optionalParam = ApiParameter(
        originalName: 'filter',
        paramLocation: 'query',
        paramSchema: <String, Object?>{'type': 'string'},
        description: 'Optional filter',
        required: false,
      );

      expect(requiredParam.toJson()['required'], isTrue);
      expect(optionalParam.toJson()['required'], isFalse);

      final ApiParameter restoredRequired = ApiParameter.fromJson(
        requiredParam.toJson(),
      );
      final ApiParameter restoredOptional = ApiParameter.fromJson(
        optionalParam.toJson(),
      );
      expect(restoredRequired.required, isTrue);
      expect(restoredOptional.required, isFalse);

      final ParsedOperation parsedOp = ParsedOperation(
        name: 'list_items',
        description: 'Lists items',
        endpoint: OperationEndpoint(
          baseUrl: 'https://api.example.com',
          path: '/items',
          method: 'get',
        ),
        operation: <String, Object?>{'operationId': 'list_items'},
        parameters: <ApiParameter>[requiredParam, optionalParam],
        returnValue: ApiParameter(
          originalName: '',
          paramLocation: '',
          paramSchema: <String, Object?>{'type': 'object'},
        ),
      );
      final RestApiTool roundTripped = RestApiTool.fromParsedOperationStr(
        jsonEncode(parsedOp.toJson()),
      );
      final FunctionDeclaration decl = roundTripped.getDeclaration()!;
      final List<Object?> requiredFields =
          (decl.parameters['required'] as List?)?.cast<Object?>() ??
          const <Object?>[];
      expect(requiredFields, contains('user_id'));
      expect(requiredFields, isNot(contains('filter')));
    });

    test('c41bc42fb: SkillToolset lists bundled resources in load_skill and materializes environment lazily', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'skill_lazy_env_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeEnvironment env = _FakeEnvironment(workingDirectory: tempDir);
      final Skill richSkill = Skill(
        frontmatter: Frontmatter(
          name: 'data-skill',
          description: 'Has bundled resources',
        ),
        instructions: 'Use bundled files.',
        resources: Resources(
          references: <String, String>{'ref1.md': 'Ref 1'},
          assets: <String, String>{'asset1.json': '{}'},
          scripts: <String, Script>{'run.sh': Script(src: 'echo hi')},
        ),
      );
      final Skill plainSkill = Skill(
        frontmatter: Frontmatter(
          name: 'plain-skill',
          description: 'No bundled resources',
        ),
        instructions: 'Plain instructions.',
      );

      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[richSkill, plainSkill],
        environment: env,
      );
      final Context ctx = _makeContext();

      // Before environment initialization, default skillsFolder is NOT advertised in system instructions.
      final LlmRequest beforeInitReq = LlmRequest();
      await toolset.processLlmRequest(
        toolContext: ctx,
        llmRequest: beforeInitReq,
      );
      final String beforeSysInstruction =
          beforeInitReq.config.systemInstruction ?? '';
      expect(beforeSysInstruction, isNot(contains('Skills location:')));
      expect(env.initializeCount, 0);

      final List<BaseTool> tools = await toolset.getTools(readonlyContext: ctx);
      final BaseTool loadTool = tools.firstWhere(
        (BaseTool t) => t.name == loadSkillToolName,
      );

      // load_skill returns ordered resources (references -> assets -> scripts) without initializing env.
      final Map<String, Object?> richLoaded =
          (await loadTool.run(
                args: <String, dynamic>{'name': 'data-skill'},
                toolContext: ctx,
              ) as Map)
              .cast<String, Object?>();
      expect(
        richLoaded['resources'],
        equals(<String>[
          'references/ref1.md',
          'assets/asset1.json',
          'scripts/run.sh',
        ]),
      );
      expect(env.initializeCount, 0);

      // load_skill omits resources key when skill has no resources.
      final Map<String, Object?> plainLoaded =
          (await loadTool.run(
                args: <String, dynamic>{'name': 'plain-skill'},
                toolContext: ctx,
              ) as Map)
              .cast<String, Object?>();
      expect(plainLoaded.containsKey('resources'), isFalse);

      // close() does not close an uninitialized environment.
      await toolset.close();
      expect(env.closeCount, 0);

      // run_skill_script lazily initializes and stages skill files, and close() then closes env.
      final BaseTool runScriptTool = tools.firstWhere(
        (BaseTool t) => t.name == runSkillScriptToolName,
      );
      final Map<String, Object?> execResult =
          (await runScriptTool.run(
                args: <String, dynamic>{
                  'skill_name': 'data-skill',
                  'file_path': 'scripts/run.sh',
                },
                toolContext: ctx,
              ) as Map)
              .cast<String, Object?>();
      expect(execResult['status'], 'success');
      expect(env.initializeCount, 1);
      expect(
        env.writtenFiles.keys,
        contains('/skills/data-skill/scripts/run.sh'),
      );

      final LlmRequest afterInitReq = LlmRequest();
      await toolset.processLlmRequest(
        toolContext: ctx,
        llmRequest: afterInitReq,
      );
      expect(afterInitReq.config.systemInstruction, contains('skills'));

      await toolset.close();
      expect(env.closeCount, 1);
    });
  });

  group('2. Evaluation Parity (67b217d00..df9f9d045)', () {
    setUp(() {
      overrideFeatureEnabled(FeatureName.toolArgsMatcher, true);
    });

    tearDown(resetFeatureRegistryForTest);

    test('04ba41209: ToolParameterMatchCriterion validation, PrebuiltMetrics, registry, and info provider', () {
      expect(PrebuiltMetricNames.toolParameterMatch, 'tool_parameter_match');
      expect(PrebuiltMetrics.toolParameterMatch.value, 'tool_parameter_match');

      final MetricInfo info =
          ToolParameterMatchEvaluatorMetricInfoProvider().getMetricInfo();
      expect(info.metricName, 'tool_parameter_match');
      expect(info.metricValueInfo.interval?.minValue, 0.0);
      expect(info.metricValueInfo.interval?.maxValue, 1.0);

      final Evaluator registered = getDefaultMetricEvaluatorRegistry()
          .getEvaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.toolParameterMatch,
              threshold: 0.9,
            ),
          );
      expect(registered, isA<ToolParameterMatchEvaluator>());

      // Strict criterion validation rejects unknown keys and non-MatchType values.
      expect(
        () => ToolParameterMatchCriterion.fromJson(<String, Object?>{
          'threshold': 0.8,
          'unexpected_field': true,
        }),
        throwsArgumentError,
      );
      expect(
        () => ToolParameterMatchCriterion.fromJson(<String, Object?>{
          'match_type': 'BOGUS_MODE',
        }),
        throwsArgumentError,
      );
      expect(
        () => ToolParameterMatchCriterion.fromJson(<String, Object?>{
          'args_matcher': 'not_a_map',
        }),
        throwsArgumentError,
      );

      final ToolParameterMatchCriterion roundTrip =
          ToolParameterMatchCriterion.fromJson(<String, Object?>{
            'threshold': 0.75,
            'match_type': 'ANY_ORDER',
            'args_matcher': <String, Object?>{
              'default_matcher': <String, Object?>{'type': 'ignore'},
            },
          });
      expect(roundTrip.threshold, 0.75);
      expect(roundTrip.hasExplicitThreshold, isTrue);
      expect(roundTrip.matchType, MatchType.anyOrder);
      expect(roundTrip.toJson()['match_type'], 'ANY_ORDER');
    });

    test('04ba41209: ToolParameterMatchEvaluator feature gate, threshold precedence, EXACT / IN_ORDER / ANY_ORDER, and concurrency cap', () async {
      // Feature gate disabled -> FeatureDisabledError.
      overrideFeatureEnabled(FeatureName.toolArgsMatcher, false);
      expect(
        () => ToolParameterMatchEvaluator(
          EvalMetricSpec(
            metricName: PrebuiltMetricNames.toolParameterMatch,
            threshold: 0.8,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      overrideFeatureEnabled(FeatureName.toolArgsMatcher, true);

      // Missing threshold on both metric and criterion -> ArgumentError.
      expect(
        () => ToolParameterMatchEvaluator(
          EvalMetricSpec(metricName: PrebuiltMetricNames.toolParameterMatch),
        ),
        throwsArgumentError,
      );

      // Empty expected tool calls -> NOT_EVALUATED.
      final ToolParameterMatchEvaluator defaultEval =
          ToolParameterMatchEvaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.toolParameterMatch,
              threshold: 0.8,
            ),
          );
      final EvaluationResult emptyExpected = await defaultEval
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              _toolInvocation(
                toolUses: <EvalJsonMap>[
                  <String, Object?>{'name': 'search', 'args': <String, Object?>{'q': 'dart'}},
                ],
              ),
            ],
            expectedInvocations: <Invocation>[
              _toolInvocation(toolUses: const <EvalJsonMap>[]),
            ],
          );
      expect(emptyExpected.overallEvalStatus, EvalStatus.notEvaluated);
      expect(emptyExpected.overallScore, isNull);
      expect(
        emptyExpected.perInvocationResults.single.evalStatus,
        EvalStatus.notEvaluated,
      );

      // EXACT mode fails when extra tool calls exist; IN_ORDER succeeds.
      final List<Invocation> actualWithExtra = <Invocation>[
        _toolInvocation(
          toolUses: <EvalJsonMap>[
            <String, Object?>{'name': 'log', 'args': const <String, Object?>{}},
            <String, Object?>{
              'name': 'book',
              'args': <String, Object?>{'city': 'Seoul', 'nights': 3},
            },
          ],
        ),
      ];
      final List<Invocation> expectedSingle = <Invocation>[
        _toolInvocation(
          toolUses: <EvalJsonMap>[
            <String, Object?>{
              'name': 'book',
              'args': <String, Object?>{'city': 'Seoul', 'nights': 2},
            },
          ],
        ),
      ];

      final ToolParameterMatchEvaluator exactEval = ToolParameterMatchEvaluator(
        EvalMetricSpec(
          metricName: PrebuiltMetricNames.toolParameterMatch,
          threshold: 0.8,
          criterion: ToolParameterMatchCriterion(matchType: MatchType.exact),
        ),
      );
      final EvaluationResult exactRes = await exactEval.evaluateInvocations(
        actualInvocations: actualWithExtra,
        expectedInvocations: expectedSingle,
      );
      expect(exactRes.overallScore, 0.0);
      expect(exactRes.overallEvalStatus, EvalStatus.failed);

      // Threshold precedence: metric.threshold (0.4) overrides criterion.threshold (0.9).
      final ToolParameterMatchEvaluator inOrderEval =
          ToolParameterMatchEvaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.toolParameterMatch,
              threshold: 0.4,
              criterion: ToolParameterMatchCriterion(
                threshold: 0.9,
                matchType: MatchType.inOrder,
              ),
            ),
          );
      final EvaluationResult inOrderRes = await inOrderEval.evaluateInvocations(
        actualInvocations: actualWithExtra,
        expectedInvocations: expectedSingle,
      );
      expect(inOrderRes.overallScore, closeTo(0.5, 1e-9));
      expect(inOrderRes.overallEvalStatus, EvalStatus.passed);

      // ANY_ORDER Hungarian assignment maximizes global sum of scores across same-name calls
      // and bounds concurrent scoring to maxConcurrentCallScores (8).
      int active = 0;
      int maxActive = 0;
      final BaseArgMatcher trackingMatcher = _AsyncTestMatcher((
        Object? expected,
        Object? actual,
      ) async {
        active += 1;
        if (active > maxActive) {
          maxActive = active;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active -= 1;
        return expected == actual;
      });

      final List<EvalJsonMap> fiveExpected = List<EvalJsonMap>.generate(
        5,
        (int i) => <String, Object?>{
          'name': 'worker',
          'args': <String, Object?>{'slot': i, 'tag': 'ok'},
        },
      );
      final List<EvalJsonMap> fiveActualReversed = fiveExpected.reversed
          .toList();

      final ToolParameterMatchEvaluator anyOrderEval =
          ToolParameterMatchEvaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.toolParameterMatch,
              threshold: 0.9,
              criterion: ToolParameterMatchCriterion(
                matchType: MatchType.anyOrder,
                argsMatcher: ToolArgsMatcher(defaultMatcher: trackingMatcher),
              ),
            ),
          );
      final EvaluationResult anyOrderRes = await anyOrderEval
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              _toolInvocation(toolUses: fiveActualReversed),
            ],
            expectedInvocations: <Invocation>[
              _toolInvocation(toolUses: fiveExpected),
            ],
          );
      expect(anyOrderRes.overallScore, closeTo(1.0, 1e-9));
      expect(anyOrderRes.overallEvalStatus, EvalStatus.passed);
      expect(maxActive, lessThanOrEqualTo(maxConcurrentCallScores));
      expect(maxActive, greaterThan(1));

      // Fast error propagation notifies currentCallScoreCancellationToken.
      bool siblingCancelled = false;
      final BaseArgMatcher failingConcurrentMatcher = _AsyncTestMatcher((
        Object? expected,
        Object? actual,
      ) async {
        if (expected == 'boom') {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          throw StateError('judge failure');
        }
        final Completer<void> waitCancel = Completer<void>();
        currentCallScoreCancellationToken?.onCancel(() {
          siblingCancelled = true;
          if (!waitCancel.isCompleted) {
            waitCancel.complete();
          }
        });
        await waitCancel.future.timeout(const Duration(seconds: 2));
        return true;
      });

      final ToolParameterMatchEvaluator failingEval =
          ToolParameterMatchEvaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.toolParameterMatch,
              threshold: 0.9,
              criterion: ToolParameterMatchCriterion(
                matchType: MatchType.anyOrder,
                argsMatcher: ToolArgsMatcher(
                  defaultMatcher: failingConcurrentMatcher,
                ),
              ),
            ),
          );
      await expectLater(
        () => failingEval.evaluateInvocations(
          actualInvocations: <Invocation>[
            _toolInvocation(
              toolUses: <EvalJsonMap>[
                <String, Object?>{'name': 't', 'args': <String, Object?>{'x': 'a'}},
                <String, Object?>{'name': 't', 'args': <String, Object?>{'x': 'b'}},
              ],
            ),
          ],
          expectedInvocations: <Invocation>[
            _toolInvocation(
              toolUses: <EvalJsonMap>[
                <String, Object?>{'name': 't', 'args': <String, Object?>{'x': 'slow'}},
                <String, Object?>{'name': 't', 'args': <String, Object?>{'x': 'boom'}},
              ],
            ),
          ],
        ),
        throwsStateError,
      );
      expect(siblingCancelled, isTrue);
    });

    test('825a3747e: getAllToolCalls and getAllToolResponses exclude ADK client function calls', () {
      final InvocationEvents events = InvocationEvents(
        invocationEvents: <InvocationEvent>[
          InvocationEvent(
            author: 'agent',
            content: <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'id': '1',
                    'name': 'cancel_order',
                    'args': const <String, Object?>{},
                  },
                },
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'id': '2',
                    'name': 'adk_request_confirmation',
                    'args': const <String, Object?>{},
                  },
                },
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'id': '3',
                    'name': 'adk_request_credential',
                    'args': const <String, Object?>{},
                  },
                },
                <String, Object?>{
                  'function_call': <String, Object?>{
                    'id': '4',
                    'name': 'adk_request_input',
                    'args': const <String, Object?>{},
                  },
                },
              ],
            },
          ),
          InvocationEvent(
            author: 'user',
            content: <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{
                  'function_response': <String, Object?>{
                    'id': '1',
                    'name': 'cancel_order',
                    'response': const <String, Object?>{},
                  },
                },
                <String, Object?>{
                  'function_response': <String, Object?>{
                    'id': '2',
                    'name': 'adk_request_confirmation',
                    'response': const <String, Object?>{},
                  },
                },
                <String, Object?>{
                  'function_response': <String, Object?>{
                    'id': '3',
                    'name': 'adk_request_credential',
                    'response': const <String, Object?>{},
                  },
                },
                <String, Object?>{
                  'function_response': <String, Object?>{
                    'id': '4',
                    'name': 'adk_request_input',
                    'response': const <String, Object?>{},
                  },
                },
              ],
            },
          ),
        ],
      );

      expect(
        getAllToolCalls(events).map((EvalJsonMap c) => c['name']).toList(),
        equals(<String>['cancel_order', 'adk_request_input']),
      );
      expect(
        getAllToolResponses(events).map((EvalJsonMap r) => r['name']).toList(),
        equals(<String>['cancel_order', 'adk_request_input']),
      );

      final IntermediateData intermediateData = IntermediateData(
        toolUses: <EvalJsonMap>[
          <String, Object?>{'id': '1', 'name': 'cancel_order', 'args': const <String, Object?>{}},
          <String, Object?>{'id': '2', 'name': 'adk_request_confirmation', 'args': const <String, Object?>{}},
          <String, Object?>{'id': '3', 'name': 'adk_request_credential', 'args': const <String, Object?>{}},
          <String, Object?>{'id': '4', 'name': 'adk_request_input', 'args': const <String, Object?>{}},
        ],
        toolResponses: <EvalJsonMap>[
          <String, Object?>{'id': '1', 'name': 'cancel_order', 'response': const <String, Object?>{}},
          <String, Object?>{'id': '2', 'name': 'adk_request_confirmation', 'response': const <String, Object?>{}},
          <String, Object?>{'id': '3', 'name': 'adk_request_credential', 'response': const <String, Object?>{}},
          <String, Object?>{'id': '4', 'name': 'adk_request_input', 'response': const <String, Object?>{}},
        ],
      );
      expect(
        getAllToolCalls(intermediateData).map((EvalJsonMap c) => c['name']).toList(),
        equals(<String>['cancel_order', 'adk_request_input']),
      );
      expect(
        getAllToolResponses(intermediateData).map((EvalJsonMap r) => r['name']).toList(),
        equals(<String>['cancel_order', 'adk_request_input']),
      );
    });

    test('59b0dd63c: HallucinationsV1Evaluator does not score responses with unlabelled sentences unless best-case fails', () async {
      // Case 1: Single invocation with unlabelled sentence -> NOT_EVALUATED (null score).
      final HallucinationsV1Evaluator unlabelledEvaluator =
          HallucinationsV1Evaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.hallucinationsV1,
              threshold: 0.8,
              criterion: HallucinationsCriterion(threshold: 0.8),
            ),
            llmFactory: (_) => _QueuedLlm(<LlmResponse>[
              LlmResponse(
                content: Content.modelText(
                  '<sentence>Sky is blue.</sentence>\n<sentence>Grass is green.</sentence>',
                ),
              ),
              // Missing second sentence in validator output -> unlabelled!
              LlmResponse(
                content: Content.modelText(
                  'sentence: Sky is blue.\nlabel: `supported`\nrationale: ok\nsupporting_excerpt: sky\ncontradicting_excerpt: null',
                ),
              ),
            ]),
          );

      final EvaluationResult singleUnscored = await unlabelledEvaluator
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              _toolInvocation(
                toolUses: const <EvalJsonMap>[],
                userText: 'Sky is blue and grass is green.',
                finalText: 'Sky is blue. Grass is green.',
              ),
            ],
          );
      expect(singleUnscored.overallScore, isNull);
      expect(singleUnscored.overallEvalStatus, EvalStatus.notEvaluated);

      // Case 2: Two invocations: first scores 0.0 (unsupported), second is unlabelled -> best-case (0 + 1)/2 = 0.5 < 0.8 -> FAILED with 0.5!
      final HallucinationsV1Evaluator bestCaseFailEvaluator =
          HallucinationsV1Evaluator(
            EvalMetricSpec(
              metricName: PrebuiltMetricNames.hallucinationsV1,
              threshold: 0.8,
              criterion: HallucinationsCriterion(threshold: 0.8),
            ),
            llmFactory: (_) => _QueuedLlm(<LlmResponse>[
              LlmResponse(
                content: Content.modelText('<sentence>Moon is cheese.</sentence>'),
              ),
              LlmResponse(
                content: Content.modelText(
                  'sentence: "Moon is cheese."\nlabel: unsupported\nrationale: false\nsupporting_excerpt: null\ncontradicting_excerpt: null',
                ),
              ),
              LlmResponse(
                content: Content.modelText('<sentence>Sun is hot.</sentence>'),
              ),
              LlmResponse(
                content: Content.modelText(
                  'sentence: Sun is hot.\nlabel: invalid_unknown_label\nrationale: bad',
                ),
              ),
            ]),
          );

      final EvaluationResult bestCaseFailed = await bestCaseFailEvaluator
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              _toolInvocation(
                toolUses: const <EvalJsonMap>[],
                finalText: 'Moon is cheese.',
              ),
              _toolInvocation(
                toolUses: const <EvalJsonMap>[],
                finalText: 'Sun is hot.',
              ),
            ],
          );
      expect(bestCaseFailed.overallEvalStatus, EvalStatus.failed);
      expect(bestCaseFailed.overallScore, closeTo(0.5, 1e-9));
      expect(
        bestCaseFailed.perInvocationResults[0].evalStatus,
        EvalStatus.failed,
      );
      expect(
        bestCaseFailed.perInvocationResults[1].evalStatus,
        EvalStatus.notEvaluated,
      );
    });

    test('f1b1f9d96 & f0086e3f4: LocalEvalService keeps sessionDetails per eval case and supports standalone BaseNode', () async {
      final BaseNode standaloneNode = node(
        ( WorkflowContext ctx, Object? input) => 'Echo from node: $input',
        name: 'echo_node',
        description: 'Standalone function node',
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final LocalEvalService evalService = LocalEvalService(
        rootAgent: standaloneNode,
        sessionService: sessionService,
      );

      expect(
        getEvalSessionAppNameAndUserId(null),
        equals((defaultEvalAppName, defaultEvalUserId)),
      );

      final EvalCase caseWithSessionInput = EvalCase(
        evalId: 'case_custom_session',
        sessionInput: SessionInput(
          appName: 'custom_eval_app',
          userId: 'alice',
          state: <String, Object?>{'tier': 'gold'},
        ),
        conversation: <Invocation>[
          Invocation(
            userContent: <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': 'hello'},
              ],
            },
            finalResponse: <String, Object?>{
              'role': 'model',
              'parts': <Object?>[
                <String, Object?>{'text': 'Echo from node: hello'},
              ],
            },
          ),
        ],
      );

      final List<InferenceResult> inferences = await evalService
          .performInference(
            InferenceRequest(
              appName: 'fallback_app',
              evalCases: <EvalCase>[caseWithSessionInput],
            ),
          )
          .toList();
      expect(inferences, hasLength(1));
      expect(inferences.single.status, InferenceStatus.success);
      expect(inferences.single.responseText, contains('Echo from node'));

      final List<EvalCaseResult> evalResults = await evalService
          .evaluate(
            EvaluateRequest(
              inferenceResults: inferences,
              evalCasesById: <String, EvalCase>{
                caseWithSessionInput.evalId: caseWithSessionInput,
              },
              evaluateConfig: EvaluateConfig(
                evalMetricSpecs: <EvalMetricSpec>[
                  EvalMetricSpec(
                    metricName: PrebuiltMetricNames.responseMatchScore,
                    threshold: 0.5,
                  ),
                ],
              ),
            ),
          )
          .toList();
      expect(evalResults, hasLength(1));
      final EvalCaseResult result = evalResults.single;
      expect(result.sessionDetails, isNotNull);
      expect(result.sessionDetails!.appName, 'custom_eval_app');
      expect(result.sessionDetails!.userId, 'alice');
      expect(result.sessionDetails!.state['tier'], 'gold');
      expect(result.sessionDetails!.events, isNotEmpty);
      expect(result.userId, 'alice');
    });

    test('6e448cf59: TrajectoryEvaluator treats null args and empty map args as equal for no-arg tool calls', () async {
      final TrajectoryEvaluator evaluator = TrajectoryEvaluator(
        evalMetric: EvalMetricSpec(
          metricName: PrebuiltMetricNames.toolTrajectoryAvgScore,
          threshold: 1.0,
          criterion: ToolTrajectoryCriterion(
            threshold: 1.0,
            matchType: MatchType.exact,
          ),
        ),
      );

      final EvaluationResult nullVsEmpty = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[
          _toolInvocation(
            toolUses: <EvalJsonMap>[
              <String, Object?>{'name': 'ping', 'args': null},
            ],
          ),
        ],
        expectedInvocations: <Invocation>[
          _toolInvocation(
            toolUses: <EvalJsonMap>[
              <String, Object?>{'name': 'ping', 'args': const <String, Object?>{}},
            ],
          ),
        ],
      );
      expect(nullVsEmpty.overallScore, 1.0);
      expect(nullVsEmpty.overallEvalStatus, EvalStatus.passed);

      final EvaluationResult emptyVsNonEmpty = await evaluator
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              _toolInvocation(
                toolUses: <EvalJsonMap>[
                  <String, Object?>{'name': 'ping', 'args': null},
                ],
              ),
            ],
            expectedInvocations: <Invocation>[
              _toolInvocation(
                toolUses: <EvalJsonMap>[
                  <String, Object?>{
                    'name': 'ping',
                    'args': <String, Object?>{'verbose': true},
                  },
                ],
              ),
            ],
          );
      expect(emptyVsNonEmpty.overallScore, 0.0);
      expect(emptyVsNonEmpty.overallEvalStatus, EvalStatus.failed);
    });
  });
}
