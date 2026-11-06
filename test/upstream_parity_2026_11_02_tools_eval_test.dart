import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/evaluation/agent_evaluator.dart';
import 'package:adk_dart/src/evaluation/eval_case.dart' as eval_case;
import 'package:adk_dart/src/evaluation/eval_config.dart';
import 'package:adk_dart/src/evaluation/eval_metrics.dart';
import 'package:adk_dart/src/evaluation/eval_set.dart';
import 'package:adk_dart/src/evaluation/evaluation_generator.dart';
import 'package:adk_dart/src/evaluation/metric_evaluator_registry.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/tools/_automatic_function_calling_util.dart';
import 'package:adk_dart/src/tools/_function_tool_declarations.dart';
import 'package:adk_dart/src/tools/_gemini_schema_util.dart';
import 'package:adk_dart/src/tools/agent_simulator/agent_simulator_engine.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/environment/base_environment.dart';
import 'package:adk_dart/src/tools/environment/environment_toolset.dart';
import 'package:adk_dart/src/tools/environment/local_environment.dart';
import 'package:adk_dart/src/tools/environment_simulation/environment_simulation_config.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/tools/load_mcp_resource_tool.dart';
import 'package:adk_dart/src/tools/mcp_tool/agent_to_mcp.dart';
import 'package:adk_dart/src/tools/mcp_tool/conversion_utils.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_session_manager.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_tool.dart';
import 'package:adk_dart/src/tools/mcp_tool/mcp_toolset.dart';
import 'package:adk_dart/src/tools/tool_confirmation.dart';
import 'package:adk_dart/src/tools/tool_context.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:test/test.dart';

enum _Priority { low, medium, high }

class _FakeSemanticLlm extends BaseLlm {
  _FakeSemanticLlm(this._handler) : super(model: 'fake-semantic-llm');

  final Future<LlmResponse> Function(LlmRequest request) _handler;
  int callCount = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount += 1;
    yield await _handler(request);
  }
}

class _DelayedAgent extends BaseAgent {
  _DelayedAgent({
    required super.name,
    required this.delayMs,
    required this.onEnter,
    required this.onExit,
  });

  final int delayMs;
  final void Function() onEnter;
  final void Function() onExit;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    onEnter();
    try {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      final String prompt =
          context.userContent?.parts.firstOrNull?.text ?? 'ok';
      yield Event(
        invocationId: context.invocationId,
        author: name,
        content: Content.modelText('echo:$prompt'),
      );
    } finally {
      onExit();
    }
  }
}

class _DummyTool extends BaseTool {
  _DummyTool({required super.name, super.title})
    : super(description: 'dummy tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'live': true, 'args': args};
  }
}

void main() {
  group('SemanticArgMatcher & ToolArgsMatcher', () {
    test('parses semantic JSON, fenced JSON, and bare verdict/score', () {
      final ArgMatchResult okResult = parseSemanticJudgement(
        '{"matched": true, "score": 0.9, "reason": "ok"}',
      );
      expect(okResult.matched, isTrue);
      expect(okResult.score, 0.9);
      expect(okResult.reason, 'ok');

      final ArgMatchResult fencedResult = parseSemanticJudgement(
        '```json\n{"matched": false, "score": 0.2, "reason": "bad"}\n```',
      );
      expect(fencedResult.matched, isFalse);
      expect(fencedResult.score, 0.2);
      expect(fencedResult.reason, 'bad');

      expect(parseSemanticVerdict('true'), isTrue);
      expect(parseSemanticVerdict('false'), isFalse);
      expect(() => parseSemanticVerdict('no'), throwsFormatException);
      expect(parseSemanticScore('0.75', matched: true), 0.75);
      expect(
        () => parseSemanticScore('1.5', matched: true),
        throwsFormatException,
      );
    });

    test('evaluates with LLM judge, caches deterministically, and deduplicates in-flight', () async {
      final Completer<LlmResponse> completer = Completer<LlmResponse>();
      final _FakeSemanticLlm fakeLlm = _FakeSemanticLlm((_) => completer.future);
      final SemanticArgMatcher matcher = SemanticArgMatcher(
        criteria: 'Same city meaning',
        llm: fakeLlm,
      );
      expect(matcher.isDeterministic, isFalse);
      expect(matcher.model, isNull);
      expect(
        matcher.withDefaultModel('gemini-2.5-pro').model,
        'gemini-2.5-pro',
      );

      final Future<ArgMatchResult> first = matcher.matchAsync(
        toolName: 'weather',
        argName: 'city',
        expected: 'NYC',
        actual: 'New York City',
      );
      final Future<ArgMatchResult> second = matcher.matchAsync(
        toolName: 'weather',
        argName: 'city',
        expected: 'NYC',
        actual: 'New York City',
      );

      completer.complete(
        LlmResponse(
          content: Content.modelText(
            '{"matched": true, "score": 0.95, "reason": "NYC is New York City"}',
          ),
        ),
      );

      final List<ArgMatchResult> results = await Future.wait(<Future<ArgMatchResult>>[
        first,
        second,
      ]);
      expect(fakeLlm.callCount, 1);
      expect(results[0].matched, isTrue);
      expect(results[0].score, closeTo(0.95, 1e-6));
      expect(results[1].matched, isTrue);

      // Cached hit does not invoke LLM again.
      final ArgMatchResult third = await matcher.matchAsync(
        toolName: 'weather',
        argName: 'city',
        expected: 'NYC',
        actual: 'New York City',
      );
      expect(fakeLlm.callCount, 1);
      expect(third.matched, isTrue);
    });

    test('ToolArgsMatcher runs deterministic matchers before semantic matchers and short-circuits', () async {
      int semanticCalls = 0;
      final SemanticArgMatcher semanticMatcher = SemanticArgMatcher(
        llm: _FakeSemanticLlm((_) async {
          semanticCalls += 1;
          return LlmResponse(
            content: Content.modelText(
              '{"matched": true, "score": 1.0, "reason": "ok"}',
            ),
          );
        }),
      );
      final ToolArgsMatcher matcher = ToolArgsMatcher(
        perArgMatchers: <String, BaseArgMatcher>{
          'id': const ExactArgMatcher(42),
          'query': semanticMatcher,
        },
      );

      final ToolArgsMatchResult failedFast = await matcher.matchAsync(
        toolName: 'search',
        expected: <String, Object?>{'id': 42, 'query': 'flights'},
        actual: <String, Object?>{'id': 99, 'query': 'airfare'},
        shortCircuit: true,
      );
      expect(failedFast.matched, isFalse);
      expect(semanticCalls, 0);

      final ToolArgsMatchResult fullEval = await matcher.matchAsync(
        toolName: 'search',
        expected: <String, Object?>{'id': 42, 'query': 'flights'},
        actual: <String, Object?>{'id': 42, 'query': 'airfare'},
      );
      expect(fullEval.matched, isTrue);
      expect(fullEval.score, 1.0);
      expect(fullEval.perArg.keys, containsAll(<String>['id', 'query']));
      expect(semanticCalls, 1);
    });
  });

  group('AgentSimulator argsMatcher & two-pass selection', () {
    test('InjectionConfig validates non-empty matchArgs when argsMatcher is set', () {
      expect(
        () => InjectionConfig(
          argsMatcher: ToolArgsMatcher(),
          injectedResponse: <String, Object?>{'ok': true},
        ),
        throwsArgumentError,
      );
      expect(EnvironmentSimulationConfig, isNotNull);
    });

    test('AgentSimulatorEngine evaluates exact before argsMatcher and respects probability per draw', () async {
      final SemanticArgMatcher semantic = SemanticArgMatcher(
        llm: _FakeSemanticLlm((_) async {
          return LlmResponse(
            content: Content.modelText(
              '{"matched": true, "score": 0.9, "reason": "synonym"}',
            ),
          );
        }),
      );
      final AgentSimulatorConfig config = AgentSimulatorConfig(
        simulationModel: 'gemini-2.5-pro',
        toolSimulationConfigs: <ToolSimulationConfig>[
          ToolSimulationConfig(
            toolName: 'lookup',
            injectionConfigs: <InjectionConfig>[
              InjectionConfig(
                injectionProbability: 0.0,
                matchArgs: <String, Object?>{'q': 'cats'},
                injectedResponse: <String, Object?>{'hit': 'exact_zero_prob'},
              ),
              InjectionConfig(
                injectionProbability: 1.0,
                matchArgs: <String, Object?>{'q': 'felines'},
                argsMatcher: ToolArgsMatcher(defaultMatcher: semantic),
                injectedResponse: <String, Object?>{'hit': 'semantic_fallback'},
              ),
            ],
          ),
        ],
      );
      final AgentSimulatorEngine engine = AgentSimulatorEngine(config);
      final Map<String, Object?>? result = await engine.simulate(
        _DummyTool(name: 'lookup'),
        <String, Object?>{'q': 'cats'},
        Object(),
      );
      expect(result, <String, Object?>{'hit': 'semantic_fallback'});
    });
  });

  group('Environment UTF-8 surrogateescape & streaming ReadFileTool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adk_env_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('hasLoneUtf16Surrogates and encodeWriteFileContent handle surrogateescape', () {
      expect(hasLoneUtf16Surrogates('hello \uDC80 world'), isTrue);
      expect(hasLoneUtf16Surrogates('hello 😊 world'), isFalse);
      final Uint8List raw = Uint8List.fromList(<int>[0x61, 0x80, 0xFE, 0x62]);
      const String surrogateString = 'a\uDC80\uDCFEb';
      expect(hasLoneUtf16Surrogates(surrogateString), isTrue);
      expect(
        () => encodeWriteFileContent(surrogateString),
        throwsFormatException,
      );
      expect(encodeWriteFileContent(raw), orderedEquals(raw));
      expect(
        encodeWriteFileContent('ab'),
        orderedEquals(<int>[0x61, 0x62]),
      );
    });

    test('ReadFileTool streams line ranges and rejects start_line > 1 on empty file', () async {
      final LocalEnvironment env = LocalEnvironment(workingDirectory: tempDir);
      await env.initialize();
      final File emptyFile = File('${tempDir.path}/empty.txt')
        ..writeAsStringSync('');
      final File multiFile = File('${tempDir.path}/lines.txt')
        ..writeAsStringSync('line1\nline2\nline3\nline4\n');

      final ReadFileTool readTool = ReadFileTool(env);
      final Map<String, Object?> emptyErr =
          await readTool.run(
                args: <String, dynamic>{
                  'path': emptyFile.path,
                  'start_line': 2,
                },
                toolContext: _UnavailableToolContext(),
              )
              as Map<String, Object?>;
      expect(emptyErr['status'], 'error');
      expect('${emptyErr['error']}', contains('exceeds file length (0 lines)'));

      final Map<String, Object?> sliceOk =
          await readTool.run(
                args: <String, dynamic>{
                  'path': multiFile.path,
                  'start_line': 2,
                  'end_line': 3,
                },
                toolContext: _UnavailableToolContext(),
              )
              as Map<String, Object?>;
      expect(sliceOk['status'], 'ok');
      expect('${sliceOk['content']}', contains('2\tline2'));
      expect('${sliceOk['content']}', contains('3\tline3'));
      expect('${sliceOk['content']}', isNot(contains('line1')));
      await env.close();
    });

    test('EditFileTool preserves non-UTF8 bytes and rejects lone surrogates or U+FFFD with hint', () async {
      final LocalEnvironment env = LocalEnvironment(workingDirectory: tempDir);
      await env.initialize();
      final File binTextFile = File('${tempDir.path}/latin.txt');
      // Header with 0xFF byte followed by ASCII lines.
      binTextFile.writeAsBytesSync(<int>[
        0x23,
        0xFF,
        0x0A,
        ...utf8.encode('old_value = 1\n'),
      ]);

      final EditFileTool editTool = EditFileTool(env);

      // Rejects lone surrogates in new_string when old_string matches
      final Map<String, Object?> surrogateErr =
          await editTool.run(
                args: <String, dynamic>{
                  'path': binTextFile.path,
                  'old_string': 'old_value = 1',
                  'new_string': 'new_\uDC80',
                },
                toolContext: _UnavailableToolContext(),
              )
              as Map<String, Object?>;
      expect(surrogateErr['status'], 'error');
      expect('${surrogateErr['error']}', contains('cannot be encoded'));

      // Hints when \uFFFD is passed and matches lossy UTF-8 decoding
      final Map<String, Object?> fffdErr =
          await editTool.run(
                args: <String, dynamic>{
                  'path': binTextFile.path,
                  'old_string': '#\uFFFD\n',
                  'new_string': '#\n',
                },
                toolContext: _UnavailableToolContext(),
              )
              as Map<String, Object?>;
      expect(fffdErr['status'], 'error');
      expect('${fffdErr['error']}', contains('not valid UTF-8'));

      // Edits ASCII portion while preserving 0xFF byte untouched
      final Map<String, Object?> editOk =
          await editTool.run(
                args: <String, dynamic>{
                  'path': binTextFile.path,
                  'old_string': 'old_value = 1',
                  'new_string': 'new_value = 2',
                },
                toolContext: _UnavailableToolContext(),
              )
              as Map<String, Object?>;
      expect(editOk['status'], 'ok');
      final List<int> updatedBytes = binTextFile.readAsBytesSync();
      expect(updatedBytes.sublist(0, 3), <int>[0x23, 0xFF, 0x0A]);
      expect(utf8.decode(updatedBytes.sublist(3)), 'new_value = 2\n');
      await env.close();
    });
  });

  group('Schema dereferencing, FunctionTool enum list coercion, ToolConfirmation, MCP', () {
    test('dereferenceSchema resolves local refs and strips definitions when no cyclic refs remain', () {
      final Map<String, dynamic> schema = <String, dynamic>{
        r'$defs': <String, dynamic>{
          'Item': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'name': <String, dynamic>{'type': 'string'},
            },
          },
        },
        'type': 'object',
        'properties': <String, dynamic>{
          'item': <String, dynamic>{
            r'$ref': r'#/$defs/Item',
            'description': 'Override description',
          },
        },
      };
      final Map<String, dynamic> resolved = dereferenceSchema(schema);
      expect(resolved.containsKey(r'$defs'), isFalse);
      final Map<String, dynamic> itemProp =
          resolved['properties']['item'] as Map<String, dynamic>;
      expect(itemProp['type'], 'object');
      expect(itemProp['description'], 'Override description');

      final FunctionDeclaration decl = buildFunctionDeclarationFromSpec(<String, Object?>{
        'name': 'create_item',
        'description': 'Creates item',
        'parametersJsonSchema': schema,
      });
      expect(decl.parameters.containsKey(r'$defs'), isFalse);

      final FunctionDeclaration afcDecl = buildFunctionDeclaration(
        <String, Object?>{
          'name': 'fn',
          'description': 'Fn',
          'parameters': schema,
        },
      );
      expect(afcDecl.parameters.containsKey(r'$defs'), isFalse);
    });

    test('FunctionTool coerces List<Enum> elements from strings', () async {
      List<Object?>? receivedList;
      final FunctionTool tool = FunctionTool(
        func: ({required List<Object?> priorities}) {
          receivedList = priorities;
          return priorities
              .map((Object? p) => p is _Priority ? p.name : '$p')
              .toList();
        },
        name: 'set_priorities',
        description: 'Sets priorities',
        declaration: FunctionDeclaration(
          name: 'set_priorities',
          description: 'Sets priorities',
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'priorities': <String, dynamic>{
                'type': 'array',
                'items': <String, dynamic>{
                  'type': 'string',
                  'enumValues': _Priority.values,
                },
              },
            },
          },
        ),
      );

      final Object? res = await tool.run(
        args: <String, dynamic>{
          'priorities': <Object?>['low', 'high'],
        },
        toolContext: _UnavailableToolContext(),
      );
      expect(res, <String>['low', 'high']);
      expect(receivedList, <_Priority>[_Priority.low, _Priority.high]);
    });

    test('ToolConfirmation defaults confirmed to false and supports JSON round-trip', () {
      final ToolConfirmation confirmation = ToolConfirmation();
      expect(confirmation.confirmed, isFalse);
      expect(confirmation.hint, '');
      final Map<String, Object?> json = ToolConfirmation(
        hint: 'Check param',
        confirmed: true,
        payload: <String, Object?>{'k': 'v'},
      ).toJson();
      final ToolConfirmation restored = ToolConfirmation.fromJson(json);
      expect(restored.confirmed, isTrue);
      expect(restored.hint, 'Check param');
      expect(restored.payload, <String, Object?>{'k': 'v'});
    });

    test('BaseTool displayTitle, McpTool title extraction, conversion_utils, agent_to_mcp, and McpToolset headers', () async {
      final _DummyTool untitled = _DummyTool(name: 'my_tool');
      expect(untitled.title, isNull);
      expect(untitled.displayTitle, isNull);

      final _DummyTool titled = _DummyTool(
        name: 'my_tool',
        title: 'My Friendly Tool',
      );
      expect(titled.displayTitle, 'My Friendly Tool');

      final McpBaseTool rawTool = McpBaseTool(
        name: 'mcp_search',
        description: 'Search',
        annotations: <String, Object?>{'title': 'Annotation Title'},
        inputSchema: <String, Object?>{'type': 'object'},
      );
      expect(extractMcpToolTitle(rawTool), 'Annotation Title');

      // conversion_utils: omits 'type' for TYPE_UNSPECIFIED and union schemas
      final Map<String, Object?> unionSchema = geminiToJsonSchema(<String, Object?>{
        'type': 'TYPE_UNSPECIFIED',
        'any_of': <Object?>[
          <String, Object?>{'type': 'STRING'},
          <String, Object?>{'type': 'INTEGER'},
        ],
      });
      expect(unionSchema.containsKey('type'), isFalse);
      expect(unionSchema['anyOf'], hasLength(2));

      // agent_to_mcp: skips thought parts
      expect(
        partToMcpContentBlock(Part.text('internal reasoning', thought: true)),
        isNull,
      );
      expect(
        partToMcpContentBlock(Part.text('visible text'))?.text,
        'visible text',
      );

      // McpToolset messageHandler + headerProvider on listResources/readResource
      final List<McpServerMessage> notifications = <McpServerMessage>[];
      final StdioConnectionParams connParams = StdioConnectionParams(
        command: 'echo',
      );
      McpSessionManager.instance.registerResources(
        connectionParams: connParams,
        resources: <String, List<McpResourceContent>>{
          'memo://greeting': <McpResourceContent>[
            McpResourceContent(text: 'Hello MCP'),
          ],
        },
      );

      final McpToolset toolset = McpToolset(
        connectionParams: connParams,
        headerProvider: (_) => <String, String>{'x-tenant': 'acme'},
        messageHandler: notifications.add,
      );
      McpSessionManager.dispatchServerMessage(
        McpServerMessage(
          url: connParams.resolvedConnectionId,
          method: 'notifications/tools/list_changed',
          params: const <String, Object?>{},
        ),
      );
      expect(notifications, hasLength(1));

      final List<String> uris = await toolset.listResources();
      expect(uris, contains('memo://greeting'));

      final LoadMcpResourceTool resourceTool = LoadMcpResourceTool(toolset);
      expect(resourceTool.name, 'load_mcp_resource');
    });
  });

  group('Evaluation parallelism, MetricEvaluatorRegistry.fork, and usage_metadata pairing', () {
    test('EvalConfig validates parallelism >= 1 and round-trips JSON', () {
      expect(() => EvalConfig(parallelism: 0), throwsArgumentError);
      final EvalConfig config = EvalConfig.fromJson(<String, Object?>{
        'criteria': <String, Object?>{'final_response_match_v2': 0.8},
        'parallelism': 6,
      });
      expect(config.parallelism, 6);
      expect(config.toJson()['parallelism'], 6);
      expect(config.copyWith(parallelism: 2).parallelism, 2);
    });

    test('MetricEvaluatorRegistry.fork isolates registrations from parent registry', () {
      final MetricEvaluatorRegistry forked =
          defaultMetricEvaluatorRegistry.fork();
      expect(
        forked.getRegisteredMetrics().map((MetricInfo m) => m.metricName),
        contains('tool_trajectory_avg_score'),
      );
      final int originalCount =
          defaultMetricEvaluatorRegistry.getRegisteredMetrics().length;
      forked.registerEvaluator(
        metricInfo: MetricInfo(
          metricName: 'custom_isolated_metric',
          description: 'Custom isolated metric',
        ),
        evaluatorFactory: (EvalMetricSpec metric) =>
            defaultMetricEvaluatorRegistry.getEvaluator(
              EvalMetricSpec(
                metricName: 'tool_trajectory_avg_score',
                threshold: 1.0,
              ),
            ),
      );
      expect(
        defaultMetricEvaluatorRegistry.getRegisteredMetrics().length,
        originalCount,
      );
    });

    test('EvaluationGenerator.generateResponses bounds concurrency to parallelism and preserves order', () async {
      int active = 0;
      int maxActive = 0;
      final _DelayedAgent agent = _DelayedAgent(
        name: 'delayed_agent',
        delayMs: 30,
        onEnter: () {
          active += 1;
          if (active > maxActive) {
            maxActive = active;
          }
        },
        onExit: () {
          active -= 1;
        },
      );

      final EvalSet evalSet = EvalSet(
        evalSetId: 'parallel_set',
        evalCases: List<eval_case.EvalCase>.generate(
          6,
          (int i) => eval_case.EvalCase(
            evalId: 'case_$i',
            conversation: <eval_case.Invocation>[
              eval_case.Invocation(
                userContent: <String, Object?>{
                  'role': 'user',
                  'parts': <Map<String, Object?>>[
                    <String, Object?>{'text': 'msg_$i'},
                  ],
                },
              ),
            ],
          ),
        ),
      );

      final List<EvalCaseResponses> responses =
          await EvaluationGenerator.generateResponses(
            evalSet: evalSet,
            rootAgent: agent,
            repeatNum: 1,
            parallelism: 2,
          );
      expect(maxActive, lessThanOrEqualTo(2));
      expect(maxActive, greaterThanOrEqualTo(2));
      expect(
        responses.map((EvalCaseResponses r) => r.evalCase.evalId).toList(),
        <String>['case_0', 'case_1', 'case_2', 'case_3', 'case_4', 'case_5'],
      );
    });

    test('convertEventsToEvalInvocations pairs standalone usage_metadata events and omits duplicate final text', () {
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'user',
          content: Content.userText('Hello'),
        ),
        // Standalone usage report emitted before content in live/streaming mode
        Event(
          invocationId: 'inv-1',
          author: 'assistant',
          liveSessionId: 'live-1',
          usageMetadata: <String, Object?>{'totalTokenCount': 42},
        ),
        Event(
          invocationId: 'inv-1',
          author: 'assistant',
          liveSessionId: 'live-1',
          modelVersion: 'gemini-2.5-flash',
          content: Content.modelText('Final answer'),
        ),
      ];

      final List<eval_case.Invocation> invocations =
          EvaluationGenerator.convertEventsToEvalInvocations(events);
      expect(invocations, hasLength(1));
      final eval_case.Invocation inv = invocations.single;
      final List<Object?> parts = inv.finalResponse!['parts']! as List<Object?>;
      expect((parts.single! as Map<String, Object?>)['text'], 'Final answer');
      final eval_case.InvocationEvents data =
          inv.intermediateData! as eval_case.InvocationEvents;
      // Standalone usage event was merged into the model event rather than creating a second event
      expect(data.invocationEvents, hasLength(1));
      final eval_case.InvocationEvent mergedEvent =
          data.invocationEvents.single;
      expect(mergedEvent.modelVersion, 'gemini-2.5-flash');
      expect(
        mergedEvent.usageMetadata,
        <String, Object?>{'totalTokenCount': 42},
      );
      // Final response text is omitted from InvocationEvent.content when there are no tool calls
      expect(mergedEvent.content, isNull);
    });

    test('AgentEvaluator validates parallelism >= 1', () async {
      expect(
        () => AgentEvaluator.evaluateEvalSet(
          agentModule: _DelayedAgent(
            name: 'a',
            delayMs: 1,
            onEnter: () {},
            onExit: () {},
          ),
          evalSet: EvalSet(
            evalSetId: 's',
            evalCases: <eval_case.EvalCase>[],
          ),
          criteria: <String, double>{},
          parallelism: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

class _StubInvocationContext implements InvocationContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnavailableToolContext implements ToolContext {
  final InvocationContext _invocationContext = _StubInvocationContext();

  @override
  InvocationContext get invocationContext => _invocationContext;

  @override
  String? get functionCallId => null;

  @override
  ToolConfirmation? get toolConfirmation => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
