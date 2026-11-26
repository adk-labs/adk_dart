import 'dart:async';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/agents/config_agent_utils.dart'
    as config_agent_utils;
import 'package:adk_dart/src/tools/bash_tool.dart' as bash_tool;
import 'package:test/test.dart';

class _RecordingAnthropicTransport implements AnthropicRestTransport {
  Map<String, Object?>? lastRequest;

  @override
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async {
    lastRequest = Map<String, Object?>.from(request);
    return <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'ok'},
      ],
      'usage': <String, Object?>{'input_tokens': 2, 'output_tokens': 3},
      'stop_reason': 'end_turn',
    };
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

class _SequenceFakeLlm extends BaseLlm {
  _SequenceFakeLlm(this.responses) : super(model: 'seq-fake');

  final List<LlmResponse> responses;
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (_index < responses.length) {
      yield responses[_index++];
    } else {
      yield LlmResponse(content: Content.modelText('done'));
    }
  }
}

class _ThrowingLlm extends BaseLlm {
  _ThrowingLlm() : super(model: 'throwing-fake');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    throw Exception('boom');
  }
}

class _CustomTool extends BaseTool {
  _CustomTool({
    required super.name,
    super.description = 'custom tool',
    super.title,
    super.customMetadata,
  });

  @override
  FunctionDeclaration? getDeclaration() => FunctionDeclaration(name: name);

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

class _PrefixableToolset extends BaseToolset {
  _PrefixableToolset(this._tools, {super.toolNamePrefix});

  final List<BaseTool> _tools;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return _tools;
  }
}

class _ScopeCheckPlugin extends BasePlugin {
  _ScopeCheckPlugin() : super(name: 'scope_check');

  final List<(CallbackInfo?, CallbackInfo?)> observations =
      <(CallbackInfo?, CallbackInfo?)>[];

  void _record(Context ctx) {
    final Context unrelated = Context(ctx.invocationContext);
    observations.add((ctx.callbackInfo, unrelated.callbackInfo));
  }

  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    _record(callbackContext);
    return null;
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    _record(callbackContext);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    _record(toolContext);
    return null;
  }
}

void main() {
  group('1. AnthropicLlm adaptive/disabled thinking with ANY tool_choice (da786ed22)', () {
    LlmRequest buildRequestWithThinking(Map<String, Object?> thinkingConfig) {
      return LlmRequest(
        model: 'claude-sonnet-4-20250514',
        contents: <Content>[Content.userText('call tool')],
        config: GenerateContentConfig(
          thinkingConfig: thinkingConfig,
          tools: <ToolDeclaration>[
            ToolDeclaration(
              functionDeclarations: <FunctionDeclaration>[
                FunctionDeclaration(name: 'search', description: 'Search'),
                FunctionDeclaration(name: 'lookup', description: 'Lookup'),
              ],
            ),
          ],
          toolConfig: LlmToolConfig(
            functionCallingConfig: FunctionCallingConfig(
              mode: FunctionCallingConfigMode.any,
            ),
          ),
        ),
      );
    }

    test('adaptive thinking preserves forced ANY tool_choice', () async {
      final _RecordingAnthropicTransport transport =
          _RecordingAnthropicTransport();
      final AnthropicLlm llm = AnthropicLlm(
        model: 'claude-sonnet-4-20250514',
        restTransport: transport,
        environment: <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
      );

      await llm
          .generateContent(
            buildRequestWithThinking(<String, Object?>{'type': 'adaptive'}),
          )
          .toList();

      expect(transport.lastRequest!['thinking'], <String, Object?>{
        'type': 'adaptive',
      });
      expect(transport.lastRequest!['tool_choice'], <String, Object?>{
        'type': 'any',
      });
    });

    test('disabled thinking preserves forced ANY tool_choice', () async {
      final _RecordingAnthropicTransport transport =
          _RecordingAnthropicTransport();
      final AnthropicLlm llm = AnthropicLlm(
        model: 'claude-sonnet-4-20250514',
        restTransport: transport,
        environment: <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
      );

      await llm
          .generateContent(
            buildRequestWithThinking(<String, Object?>{'type': 'disabled'}),
          )
          .toList();

      expect(transport.lastRequest!['thinking'], <String, Object?>{
        'type': 'disabled',
      });
      expect(transport.lastRequest!['tool_choice'], <String, Object?>{
        'type': 'any',
      });
    });

    test('enabled manual thinking falls back ANY tool_choice to auto', () async {
      final _RecordingAnthropicTransport transport =
          _RecordingAnthropicTransport();
      final AnthropicLlm llm = AnthropicLlm(
        model: 'claude-sonnet-4-20250514',
        restTransport: transport,
        environment: <String, String>{'ANTHROPIC_API_KEY': 'test-key'},
      );

      await llm
          .generateContent(
            buildRequestWithThinking(<String, Object?>{'thinkingBudget': 1024}),
          )
          .toList();

      expect(transport.lastRequest!['thinking'], <String, Object?>{
        'type': 'enabled',
        'budget_tokens': 1024,
      });
      expect(transport.lastRequest!['tool_choice'], <String, Object?>{
        'type': 'auto',
      });
    });
  });

  group('2. CallbackType values and per-Context CallbackInfo scoping (2084efbe1)', () {
    test('CallbackType values match upstream and fromValue accepts both forms', () {
      const Map<CallbackType, String> expected = <CallbackType, String>{
        CallbackType.beforeAgent: 'before_agent',
        CallbackType.afterAgent: 'after_agent',
        CallbackType.beforeModel: 'before_model',
        CallbackType.afterModel: 'after_model',
        CallbackType.beforeTool: 'before_tool',
        CallbackType.afterTool: 'after_tool',
        CallbackType.onModelError: 'on_model_error',
        CallbackType.onToolError: 'on_tool_error',
        CallbackType.onAgentError: 'on_agent_error',
        CallbackType.beforeRun: 'before_run',
        CallbackType.afterRun: 'after_run',
        CallbackType.onUserMessage: 'on_user_message',
        CallbackType.onEvent: 'on_event',
        CallbackType.onRunError: 'on_run_error',
      };

      for (final MapEntry<CallbackType, String> entry in expected.entries) {
        expect(entry.key.value, entry.value);
        expect(CallbackType.fromValue(entry.value), entry.key);
        expect(CallbackType.fromValue('${entry.value}_callback'), entry.key);
      }
      expect(CallbackType.fromValue('unknown_hook'), isNull);
    });

    test('Context.callbackInfo is scoped strictly per Context instance and restored on exit/throw', () async {
      final InvocationContext invCtx = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv-scope',
        agent: LlmAgent(name: 'root', instruction: 'hi'),
        session: Session(id: 's1', appName: 'app', userId: 'u1'),
      );
      final Context targetCtx = Context(invCtx);
      final Context unrelatedCtx = Context(invCtx);

      expect(targetCtx.callbackInfo, isNull);
      expect(unrelatedCtx.callbackInfo, isNull);

      const CallbackInfo outerInfo = CallbackInfo(
        type: CallbackType.beforeAgent,
        name: 'outer',
      );
      const CallbackInfo innerInfo = CallbackInfo(
        type: CallbackType.beforeModel,
        name: 'inner',
      );

      await runWithCallbackScope<void>(
        outerInfo,
        () async {
          expect(targetCtx.callbackInfo, outerInfo);
          expect(unrelatedCtx.callbackInfo, isNull);
          expect(Context(invCtx).callbackInfo, isNull);

          await expectLater(
            runWithCallbackScope<void>(
              innerInfo,
              () async {
                expect(targetCtx.callbackInfo, innerInfo);
                expect(unrelatedCtx.callbackInfo, isNull);
                throw StateError('inner error');
              },
              callbackContext: targetCtx,
            ),
            throwsStateError,
          );

          expect(targetCtx.callbackInfo, outerInfo);
        },
        callbackContext: targetCtx,
      );

      expect(targetCtx.callbackInfo, isNull);
      expect(unrelatedCtx.callbackInfo, isNull);
    });

    test('unrelated Context inside agent and plugin callbacks sees null callbackInfo', () async {
      final _ScopeCheckPlugin plugin = _ScopeCheckPlugin();
      final List<(CallbackInfo?, CallbackInfo?)> agentChecks =
          <(CallbackInfo?, CallbackInfo?)>[];
      CallbackContext? capturedCtx;

      final FunctionTool tool = FunctionTool(
        name: 'ping',
        description: 'ping',
        func: () => <String, Object?>{'pong': true},
      );

      final LlmAgent agent = LlmAgent(
        name: 'cb_scope_agent',
        model: _SequenceFakeLlm(<LlmResponse>[
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(name: 'ping', id: 'c1', args: const {}),
              ],
            ),
          ),
          LlmResponse(content: Content.modelText('all done')),
        ]),
        tools: <Object>[tool],
        beforeAgentCallback: (CallbackContext ctx) {
          capturedCtx = ctx;
          agentChecks.add((
            ctx.callbackInfo,
            Context(ctx.invocationContext).callbackInfo,
          ));
          return null;
        },
        beforeModelCallback: (CallbackContext ctx, LlmRequest req) {
          agentChecks.add((
            ctx.callbackInfo,
            Context(ctx.invocationContext).callbackInfo,
          ));
          return null;
        },
        beforeToolCallback: (BaseTool t, Map<String, dynamic> a, ToolContext ctx) {
          agentChecks.add((
            ctx.callbackInfo,
            Context(ctx.invocationContext).callbackInfo,
          ));
          return null;
        },
      );

      final InMemoryRunner runner = InMemoryRunner(
        agent: agent,
        plugins: <BasePlugin>[plugin],
      );
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('go'),
          )
          .toList();

      expect(agentChecks, isNotEmpty);
      for (final (CallbackInfo? own, CallbackInfo? unrelated) in agentChecks) {
        expect(own, isNotNull);
        expect(own!.isFromPlugin, isFalse);
        expect(unrelated, isNull);
      }
      expect(plugin.observations, isNotEmpty);
      for (final (CallbackInfo? own, CallbackInfo? unrelated)
          in plugin.observations) {
        expect(own, isNotNull);
        expect(own!.isFromPlugin, isTrue);
        expect(unrelated, isNull);
      }
      expect(capturedCtx?.callbackInfo, isNull);
    });

    test('onModelErrorCallback scopes CallbackInfo on CallbackContext only', () async {
      CallbackInfo? onErrorOwn;
      CallbackInfo? onErrorUnrelated;

      final LlmAgent agent = LlmAgent(
        name: 'err_scope_agent',
        model: _ThrowingLlm(),
        onModelErrorCallback: (
          CallbackContext ctx,
          LlmRequest req,
          Exception err,
        ) {
          onErrorOwn = ctx.callbackInfo;
          onErrorUnrelated = Context(ctx.invocationContext).callbackInfo;
          return LlmResponse(content: Content.modelText('recovered'));
        },
      );

      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );
      await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('fail'),
          )
          .toList();

      expect(onErrorOwn?.type, CallbackType.onModelError);
      expect(onErrorUnrelated, isNull);
    });
  });

  group('3. config_agent_utils blocked modules and prefixes (1c7e8f76b)', () {
    test('blocks newly added gadget modules and CLI/internal prefixes', () {
      final AgentConfigResolvers resolvers = AgentConfigResolvers(
        symbols: <String, Object?>{'my_pkg.safe_tool': () => 'ok'},
      );

      const List<String> blockedRefs = <String>[
        'anyio',
        'anyio.run',
        'click',
        'click.command',
        'dotenv',
        'dotenv.load_dotenv',
        'graphviz',
        'graphviz.Digraph',
        'uvicorn',
        'uvicorn.run',
        'watchdog',
        'watchdog.observers',
        'ruamel',
        'ruamel.yaml',
        'yaml',
        'yaml.unsafe_load',
        'google.adk.cli',
        'google.adk.cli.fast_api',
        'pydantic._internal',
        'pydantic._internal.model_construction',
        'pydantic.v1',
        'pydantic.v1.BaseModel',
        'adk_dart.cli',
        'adk_dart.cli.server',
        'package:adk_dart/cli',
        'package:adk_dart/cli.dart',
        'package:adk_dart/cli/server.dart',
      ];

      for (final String ref in blockedRefs) {
        expect(
          () => config_agent_utils.resolveFullyQualifiedName(
            ref,
            resolvers: resolvers,
          ),
          throwsArgumentError,
          reason: 'Expected $ref to be blocked',
        );
      }

      expect(
        config_agent_utils.resolveFullyQualifiedName(
          'my_pkg.safe_tool',
          resolvers: resolvers,
        ),
        isA<Function>(),
      );
    });
  });

  group('4. Tool display names preference, trimming, merging, and _PrefixedTool.title (29956a8e6)', () {
    test('_PrefixedTool forwards delegate.title', () async {
      final _CustomTool base = _CustomTool(
        name: 'weather',
        title: 'Weather Tool',
      );
      final _PrefixableToolset toolset = _PrefixableToolset(
        <BaseTool>[base],
        toolNamePrefix: 'ext',
      );

      final List<BaseTool> prefixed = await toolset.getToolsWithPrefix();
      expect(prefixed, hasLength(1));
      expect(prefixed.single.name, 'ext_weather');
      expect(prefixed.single.title, 'Weather Tool');
      expect(prefixed.single.displayTitle, 'Weather Tool');
    });

    test('_populateToolDisplayNames prefers trimmed tool.title, ignores whitespace, falls back to metadata, and merges existing map', () async {
      final _CustomTool directTitleWins = _CustomTool(
        name: 'tool_direct',
        title: '  Direct Title  ',
        customMetadata: <String, dynamic>{'title': 'Metadata Title'},
      );
      final _CustomTool blankTitleFallback = _CustomTool(
        name: 'tool_fallback',
        title: '   \t ',
        customMetadata: <String, dynamic>{'title': '  Meta Fallback  '},
      );
      final _CustomTool whitespaceBoth = _CustomTool(
        name: 'tool_blank',
        title: '   ',
        customMetadata: <String, dynamic>{'title': '  '},
      );
      final _PrefixableToolset prefixedToolset = _PrefixableToolset(
        <BaseTool>[_CustomTool(name: 'search', title: 'Prefixed Search')],
        toolNamePrefix: 'mcp',
      );

      final _SequenceFakeLlm llm = _SequenceFakeLlm(<LlmResponse>[
        LlmResponse(
          customMetadata: <String, dynamic>{
            'other_key': 'keep_me',
            toolDisplayNamesMetadataKey: <String, Object?>{
              'preexisting_tool': 'Preexisting Display Name',
            },
          },
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'tool_direct',
                id: 'c1',
                args: const <String, dynamic>{},
              ),
              Part.fromFunctionCall(
                name: 'tool_fallback',
                id: 'c2',
                args: const <String, dynamic>{},
              ),
              Part.fromFunctionCall(
                name: 'tool_blank',
                id: 'c3',
                args: const <String, dynamic>{},
              ),
              Part.fromFunctionCall(
                name: 'mcp_search',
                id: 'c4',
                args: const <String, dynamic>{},
              ),
            ],
          ),
        ),
        LlmResponse(content: Content.modelText('done')),
      ]);

      final LlmAgent agent = LlmAgent(
        name: 'display_agent',
        model: llm,
        tools: <Object>[
          directTitleWins,
          blankTitleFallback,
          whitespaceBoth,
          prefixedToolset,
        ],
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('run tools'),
          )
          .toList();

      final Event fcEvent = events.firstWhere(
        (Event e) => e.getFunctionCalls().isNotEmpty,
      );
      expect(fcEvent.customMetadata?['other_key'], 'keep_me');
      expect(
        fcEvent.customMetadata?[toolDisplayNamesMetadataKey],
        equals(<String, Object?>{
          'preexisting_tool': 'Preexisting Display Name',
          'tool_direct': 'Direct Title',
          'tool_fallback': 'Meta Fallback',
          'mcp_search': 'Prefixed Search',
        }),
      );
    });
  });

  group('5. BashToolPolicy zero resource limits on ulimit shell prefix (a702e3c08)', () {
    test('buildUlimitPrefix enforces 0 for maxMemoryBytes, maxFileSizeBytes, and maxChildProcesses', () {
      if (Platform.isWindows) {
        return;
      }

      final String zeroPrefix = bash_tool.buildUlimitPrefix(
        BashToolPolicy(
          maxMemoryBytes: 0,
          maxFileSizeBytes: 0,
          maxChildProcesses: 0,
        ),
      );
      expect(zeroPrefix, contains('ulimit -S -H -f 0'));
      expect(zeroPrefix, contains('ulimit -v 0'));
      expect(zeroPrefix, contains('ulimit -u 0'));

      final String unsetPrefix = bash_tool.buildUlimitPrefix(BashToolPolicy());
      expect(unsetPrefix, isNot(contains('ulimit -S -H -f')));
      expect(unsetPrefix, isNot(contains('ulimit -v')));
      expect(unsetPrefix, isNot(contains('ulimit -u')));
    });

    test('setResourceLimits and ExecuteBashTool honor zero limits', () async {
      if (Platform.isWindows) {
        return;
      }

      final List<(String, (int, int))> recorded = <(String, (int, int))>[];
      final ExecuteBashTool tool = ExecuteBashTool(
        policy: BashToolPolicy(
          maxMemoryBytes: 0,
          maxFileSizeBytes: 0,
          maxChildProcesses: 0,
        ),
        setrlimit: (String resource, (int, int) limits) {
          recorded.add((resource, limits));
        },
      );

      final InvocationContext invCtx = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv-bash-zero',
        agent: LlmAgent(name: 'root', instruction: 'root'),
        session: Session(id: 's1', appName: 'app', userId: 'u1'),
      );
      final Context ctx = Context(
        invCtx,
        functionCallId: 'fc1',
        toolConfirmation: ToolConfirmation(confirmed: true),
      );

      await tool.run(
        args: <String, dynamic>{'command': 'true'},
        toolContext: ctx,
      );

      expect(
        recorded,
        containsAll(<(String, (int, int))>[
          (ResourceLimit.rlimitAs, (0, 0)),
          (ResourceLimit.rlimitFsize, (0, 0)),
          (ResourceLimit.rlimitNproc, (0, 0)),
        ]),
      );
    });
  });

  group('6. agent_info traverses NodeTool and BaseNode in LlmAgent.tools, isolates AgentTool (ec2ac7c5e)', () {
    test('discovers LlmAgents inside NodeTool and BaseNode tool entries without adding to subAgents or traversing AgentTool', () async {
      final LlmAgent helperInWorkflow = LlmAgent(
        name: 'workflow_helper',
        description: 'Workflow helper',
        instruction: 'Help via workflow',
      );
      final LlmAgent helperViaBaseNode = LlmAgent(
        name: 'direct_node_helper',
        description: 'Direct node helper',
        instruction: 'Help via BaseNode',
      );
      final LlmAgent wrappedAgentTool = LlmAgent(
        name: 'wrapped_agent_tool',
        description: 'Isolated agent tool',
        instruction: 'Do not traverse',
      );

      final Workflow nodeToolWorkflow = Workflow(
        name: 'tool_wf',
        nodes: <BaseNode>[AgentNode(agent: helperInWorkflow)],
        edges: <Edge>[Edge(fromNode: START, toNode: 'workflow_helper')],
      );

      final LlmAgent root = LlmAgent(
        name: 'root_agent',
        instruction: 'Coordinate',
        tools: <Object>[
          NodeTool(
            node: AgentNode(name: 'wf_node', agent: nodeToolWorkflow),
            name: 'run_workflow_helper',
          ),
          AgentNode(name: 'direct_node', agent: helperViaBaseNode),
          AgentTool(agent: wrappedAgentTool),
        ],
      );

      final Map<String, AgentInfo> agents = await getAgentsDict(root);

      expect(
        agents.keys,
        unorderedEquals(<String>[
          'root_agent',
          'workflow_helper',
          'direct_node_helper',
        ]),
      );
      expect(agents.containsKey('wrapped_agent_tool'), isFalse);
      expect(agents['root_agent']!.subAgents, isEmpty);
      expect(
        agents['root_agent']!.tools
            .expand((ToolDeclaration t) => t.functionDeclarations)
            .map((FunctionDeclaration d) => d.name),
        containsAll(<String>[
          'run_workflow_helper',
          'direct_node',
          'wrapped_agent_tool',
        ]),
      );
    });
  });
}
