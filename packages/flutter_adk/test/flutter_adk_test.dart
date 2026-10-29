import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_adk/flutter_adk_platform_interface.dart';
import 'package:flutter_adk/flutter_adk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _EchoModel extends BaseLlm {
  _EchoModel() : super(model: 'echo-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('echo'));
  }
}

class MockFlutterAdkPlatform
    with MockPlatformInterfaceMixin
    implements FlutterAdkPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterAdkPlatform initialPlatform = FlutterAdkPlatform.instance;

  test('$MethodChannelFlutterAdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAdk>());
  });

  test('getPlatformVersion', () async {
    FlutterAdk flutterAdkPlugin = FlutterAdk();
    MockFlutterAdkPlatform fakePlatform = MockFlutterAdkPlatform();
    FlutterAdkPlatform.instance = fakePlatform;

    expect(await flutterAdkPlugin.getPlatformVersion(), '42');
  });

  test('exports adk_core symbols', () {
    final Session session = Session(
      id: 'session_1',
      appName: 'app',
      userId: 'u',
    );
    final InMemorySessionService sessions = InMemorySessionService();
    expect(session.id, 'session_1');
    expect(sessions.runtimeType, InMemorySessionService);
  });

  test('exports Agent and Runner symbols', () async {
    final Agent agent = Agent(
      name: 'capital_agent',
      model: _EchoModel(),
      instruction: 'Answer capital questions.',
      tools: <Object>[
        FunctionTool(
          name: 'get_capital_city',
          description: 'Returns a capital city.',
          func: ({required String country}) => <String, Object?>{
            'capital': country.toUpperCase(),
          },
        ),
      ],
    );

    final InMemoryRunner runner = InMemoryRunner(
      agent: agent,
      appName: 'flutter_app',
    );
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'u1',
      sessionId: 's1',
    );
    final List<Event> events = await runner
        .runAsync(
          userId: 'u1',
          sessionId: session.id,
          newMessage: Content.userText('hello'),
        )
        .toList();

    expect(events.last.content?.parts.first.text, 'echo');
    await runner.close();
  });

  test('exports AgentTool symbol', () {
    final Agent agent = Agent(
      name: 'child_agent',
      model: _EchoModel(),
      instruction: 'Echo',
    );
    final AgentTool tool = AgentTool(agent: agent);

    expect(tool.name, 'child_agent');
  });

  test('exports Gemini model symbol', () {
    final Gemini gemini = Gemini(
      model: 'gemini-2.5-flash',
      environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
    );
    expect(gemini.model, 'gemini-2.5-flash');
  });

  test('exports workflow agent symbols', () {
    final Agent leafForSequential = Agent(
      name: 'leaf_seq',
      model: _EchoModel(),
      instruction: 'Echo',
    );
    final Agent leafForParallel = Agent(
      name: 'leaf_par',
      model: _EchoModel(),
      instruction: 'Echo',
    );
    final Agent leafForLoop = Agent(
      name: 'leaf_loop',
      model: _EchoModel(),
      instruction: 'Echo',
    );
    final SequentialAgent sequential = SequentialAgent(
      name: 'seq',
      subAgents: <BaseAgent>[leafForSequential],
    );
    final ParallelAgent parallel = ParallelAgent(
      name: 'par',
      subAgents: <BaseAgent>[leafForParallel],
    );
    final LoopAgent loop = LoopAgent(
      name: 'loop',
      maxIterations: 1,
      subAgents: <BaseAgent>[leafForLoop],
    );
    expect(sequential.subAgents.length, 1);
    expect(parallel.subAgents.length, 1);
    expect(loop.subAgents.length, 1);
  });

  test('exports mcp and skill symbols', () {
    final StreamableHTTPConnectionParams connection =
        StreamableHTTPConnectionParams(url: 'https://example.com/mcp');
    final McpToolset mcpToolset = McpToolset(connectionParams: connection);

    final Skill skill = Skill(
      name: 'hello-skill',
      description: 'simple skill',
      instructions: 'say hello',
      resources: Resources(
        references: <String, String>{'hello.md': 'hello'},
        scripts: <String, Script>{},
      ),
    );
    final SkillToolset skillToolset = SkillToolset(skills: <Skill>[skill]);

    expect(mcpToolset.runtimeType, McpToolset);
    expect(skillToolset.runtimeType, SkillToolset);
  });

  test('exports built-in retrieval tool symbols', () {
    final UrlContextTool urlTool = UrlContextTool();
    final VertexAiSearchTool searchTool = VertexAiSearchTool(
      dataStoreId:
          'projects/p/locations/global/collections/default_collection/dataStores/ds',
    );
    final VertexRagRetrievalTool ragTool = VertexRagRetrievalTool(
      ragCorpora: <String>['projects/p/locations/us-central1/ragCorpora/c'],
    );

    expect(urlTool.name, 'url_context');
    expect(urlContext.name, 'url_context');
    expect(searchTool.name, 'vertex_ai_search');
    expect(ragTool.name, 'vertex_rag_retrieval');
  });

  test('exports new parity symbols (capabilities, choice tool, session errors, reflect plugin)', () {
    expect(const LlmCapabilities().outputSchemaAndTools, isFalse);
    expect(getUserChoice.name, equals('get_user_choice'));
    expect(SessionNotFoundError('missing').message, equals('missing'));
    expect(StaleSessionError('stale').message, equals('stale'));
    expect(ReflectAndRetryModelPlugin(maxRetries: 2).maxRetries, equals(2));
  });

  testWidgets('AdkMessageBubble renders AdkCodeExecutionCard and AdkGroundingSourcesBar', (
    WidgetTester tester,
  ) async {
    AdkGroundingSource? tappedSource;
    final AdkChatMessage msg = AdkChatMessage.model(
      id: 'm1',
      text: 'The result is 42.',
      codeExecution: const AdkCodeExecution(
        language: 'PYTHON',
        code: 'print(6 * 7)',
        output: '42\n',
        outcome: 'OUTCOME_OK',
      ),
      grounding: const AdkGroundingInfo(
        searchQueries: <String>['meaning of life'],
        sources: <AdkGroundingSource>[
          AdkGroundingSource(
            title: 'ADK Docs',
            uri: 'https://google.github.io/adk-docs/',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdkMessageBubble(
            message: msg,
            onGroundingSourceTap: (AdkGroundingSource src) {
              tappedSource = src;
            },
          ),
        ),
      ),
    );

    expect(find.byType(AdkCodeExecutionCard), findsOneWidget);
    expect(find.text('PYTHON'), findsOneWidget);
    expect(find.text('print(6 * 7)'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.byType(AdkGroundingSourcesBar), findsOneWidget);
    expect(find.text('meaning of life'), findsOneWidget);
    expect(find.text('ADK Docs'), findsOneWidget);

    await tester.tap(find.text('ADK Docs'));
    expect(tappedSource?.uri, 'https://google.github.io/adk-docs/');
  });

  test('AdkTokenUsage operator +, cacheHitRatio, and estimateCostUsd work accurately', () {
    const AdkTokenUsage turn1 = AdkTokenUsage(
      promptTokens: 1000,
      completionTokens: 200,
      thoughtTokens: 50,
      cachedTokens: 400,
      totalTokens: 1250,
      latencyMs: 320,
    );
    const AdkTokenUsage turn2 = AdkTokenUsage(
      promptTokens: 500,
      completionTokens: 100,
      cachedTokens: 100,
      totalTokens: 600,
      latencyMs: 180,
    );
    final AdkTokenUsage sum = turn1 + turn2;
    expect(sum.promptTokens, 1500);
    expect(sum.completionTokens, 300);
    expect(sum.thoughtTokens, 50);
    expect(sum.cachedTokens, 500);
    expect(sum.totalTokens, 1850);
    expect(sum.latencyMs, 500);
    expect(turn1.cacheHitRatio, closeTo(0.4, 1e-6));
    expect(sum.estimateCostUsd(), greaterThan(0));
  });

  testWidgets('AdkUsageMonitorCard and AdkContextWindowMeter render usage metrics', (
    WidgetTester tester,
  ) async {
    const AdkTokenUsage usage = AdkTokenUsage(
      promptTokens: 2400,
      completionTokens: 600,
      thoughtTokens: 200,
      cachedTokens: 800,
      totalTokens: 3200,
      latencyMs: 450,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                AdkUsageMonitorCard(
                  usage: usage,
                  modelName: 'gemini-2.5-flash',
                  turnCount: 3,
                ),
                AdkContextWindowMeter(
                  usedTokens: 64000,
                  maxContextTokens: 128000,
                  compactionThresholdTokens: 96000,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Token Usage & Cost'), findsOneWidget);
    expect(find.text('gemini-2.5-flash'), findsOneWidget);
    expect(find.text('3.2k'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('Context Window'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
  });

  testWidgets('AdkMessageBubble routes built-in tools to specialized cards and renders compaction & token badges', (
    WidgetTester tester,
  ) async {
    final List<AdkChatMessage> messages = <AdkChatMessage>[
      AdkChatMessage.tool(
        id: 't_skill',
        toolName: 'list_skills',
        toolResult:
            '<available_skills><skill><name>weather</name><description>Get forecast</description></skill></available_skills>',
      ),
      AdkChatMessage.tool(
        id: 't_edit',
        toolName: 'EditFile',
        toolArgs: const <String, dynamic>{
          'path': 'lib/main.dart',
          'old_string': 'print("old");',
          'new_string': 'print("new");\nprint("done");',
        },
      ),
      AdkChatMessage.tool(
        id: 't_shell',
        toolName: 'execute_bash',
        toolArgs: const <String, dynamic>{'command': 'dart test'},
        toolResult: const <String, dynamic>{
          'stdout': '\x1B[32mAll tests passed!\x1B[0m',
          'exit_code': 0,
        },
      ),
      AdkChatMessage.tool(
        id: 't_web',
        toolName: 'load_web_page',
        toolArgs: const <String, dynamic>{'url': 'https://dart.dev/guides'},
        toolResult: 'Dart documentation content',
      ),
      AdkChatMessage.tool(
        id: 't_comp',
        toolName: 'click_at',
        toolArgs: const <String, dynamic>{'x': 120, 'y': 340},
      ),
      AdkChatMessage.system(
        id: 's_compact',
        text: 'Session compacted: Earlier turns summarized.',
        isCompaction: true,
      ),
      AdkChatMessage.model(
        id: 'm_usage',
        text: 'Completed tasks.',
        tokenUsage: const AdkTokenUsage(
          promptTokens: 500,
          completionTokens: 120,
          totalTokens: 620,
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: messages
                .map((AdkChatMessage m) => AdkMessageBubble(message: m))
                .toList(),
          ),
        ),
      ),
    );

    expect(find.byType(AdkSkillToolCard), findsOneWidget);
    expect(find.text('Available Skills (1)'), findsOneWidget);
    expect(find.byType(AdkFileEditCard), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.byType(AdkShellCommandCard), findsOneWidget);
    expect(find.text('All tests passed!'), findsOneWidget);
    expect(find.byType(AdkWebPageCard), findsOneWidget);
    expect(find.text('dart.dev'), findsOneWidget);
    expect(find.byType(AdkComputerActionCard), findsOneWidget);
    expect(find.text('(120, 340)'), findsOneWidget);
    expect(find.byType(AdkCompactionSummaryCard), findsOneWidget);
    expect(find.byType(AdkTokenUsageBadge), findsOneWidget);
    expect(find.text('620 tokens'), findsOneWidget);
  });

  testWidgets('AdkReflectRetryBanner and AdkMultiRunEvalCard render accurately', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              AdkReflectRetryBanner(
                attempt: 2,
                maxRetries: 3,
                targetName: 'search_api',
                errorSummary: 'Invalid JSON argument',
              ),
              AdkMultiRunEvalCard(
                caseSummaries: <AdkMultiRunCaseSummary>[
                  AdkMultiRunCaseSummary(
                    evalId: 'case_weather_1',
                    totalRuns: 5,
                    passedRuns: 4,
                    passed: true,
                    metrics: <AdkMultiRunMetricSummary>[
                      AdkMultiRunMetricSummary(
                        metricName: 'tool_trajectory_avg_score',
                        methodName: 'mean_of_runs',
                        value: 0.92,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Attempt 2/3'), findsOneWidget);
    expect(find.textContaining('search_api'), findsOneWidget);
    expect(find.text('case_weather_1'), findsOneWidget);
    expect(find.text('4/5 runs passed'), findsOneWidget);
  });

  testWidgets('Custom AdkCardStyle, slot widgets, and custom builders override default UI', (
    WidgetTester tester,
  ) async {
    const AdkCardStyle customStyle = AdkCardStyle(
      backgroundColor: Colors.amber,
      borderColor: Colors.deepOrange,
      accentColor: Colors.purple,
      textColor: Colors.black87,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              AdkSkillToolCard(
                toolName: 'list_skills',
                toolResult:
                    '<available_skills><skill><name>alpha</name><description>desc</description></skill></available_skills>',
                initiallyExpanded: true,
                style: customStyle,
                leadingIcon: const Icon(Icons.star, key: Key('custom_skill_icon')),
                skillItemBuilder: (BuildContext context, AdkSkillSummary skill) =>
                    Text('CUSTOM_SKILL:${skill.name}'),
              ),
              AdkFileEditCard(
                toolName: 'EditFile',
                toolArgs: const <String, dynamic>{
                  'path': 'main.dart',
                  'old_string': 'a',
                  'new_string': 'b',
                },
                style: customStyle,
                diffLineBuilder: (BuildContext context, AdkDiffLine line) =>
                    Text('CUSTOM_DIFF:${line.content}'),
              ),
              AdkMessageBubble(
                message: AdkChatMessage.model(
                  id: 'm_custom',
                  text: 'Custom bubble',
                  tokenUsage: const AdkTokenUsage(
                    promptTokens: 10,
                    completionTokens: 20,
                    totalTokens: 30,
                  ),
                ),
                tokenUsageBuilder: (
                  BuildContext context,
                  AdkTokenUsage usage,
                  AdkChatMessage msg,
                ) =>
                    Text('CUSTOM_TOKENS:${usage.effectiveTotalTokens}'),
              ),
              AdkMessageBubble(
                message: AdkChatMessage.tool(
                  id: 't_custom',
                  toolName: 'my_custom_tool',
                ),
                toolCardBuilder: (BuildContext context, AdkChatMessage msg) =>
                    Text('CUSTOM_TOOL_CARD:${msg.toolName}'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('custom_skill_icon')), findsOneWidget);
    expect(find.text('CUSTOM_SKILL:alpha'), findsOneWidget);
    expect(find.text('CUSTOM_DIFF:a'), findsOneWidget);
    expect(find.text('CUSTOM_DIFF:b'), findsOneWidget);
    expect(find.text('CUSTOM_TOKENS:30'), findsOneWidget);
    expect(find.text('CUSTOM_TOOL_CARD:my_custom_tool'), findsOneWidget);
  });
}
