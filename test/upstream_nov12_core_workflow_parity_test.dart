import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/callback_context.dart';
import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/langgraph_agent.dart';
import 'package:adk_dart/src/agents/llm/task/finish_task_tool.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/artifacts/in_memory_artifact_service.dart';
import 'package:adk_dart/src/auth/auth_credential.dart';
import 'package:adk_dart/src/auth/auth_tool.dart';
import 'package:adk_dart/src/auth/credential_manager.dart';
import 'package:adk_dart/src/auth/exchanger/base_credential_exchanger.dart';
import 'package:adk_dart/src/auth/exchanger/credential_exchanger_registry.dart';
import 'package:adk_dart/src/code_executors/base_code_executor.dart';
import 'package:adk_dart/src/code_executors/code_execution_utils.dart';
import 'package:adk_dart/src/events/abort_events.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/event_actions.dart';
import 'package:adk_dart/src/events/interrupts.dart';
import 'package:adk_dart/src/events/request_input.dart';
import 'package:adk_dart/src/flows/llm_flows/code_execution.dart';
import 'package:adk_dart/src/flows/llm_flows/functions.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/plugins/base_plugin.dart';
import 'package:adk_dart/src/plugins/debug_logging_plugin.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/tools/agent_tool.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/tools/long_running_tool.dart';
import 'package:adk_dart/src/tools/openapi_tool/auth/credential_exchangers/base_credential_exchanger.dart';
import 'package:adk_dart/src/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/workflow/edges_builder.dart';
import 'package:adk_dart/src/workflow/replay_manager.dart';
import 'package:adk_dart/src/workflow/workflow.dart';
import 'package:test/test.dart';

class _QueuedMockLlm extends BaseLlm {
  _QueuedMockLlm(this.responses) : super(model: 'queued-mock-llm');

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    if (_index >= responses.length) {
      yield LlmResponse(content: Content.modelText('default-eof'));
      return;
    }
    yield responses[_index++];
  }
}

class _AfterAgentRecorderPlugin extends BasePlugin {
  _AfterAgentRecorderPlugin(this.calls) : super(name: 'after_agent_recorder');

  final List<String> calls;

  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    calls.add('plugin:${agent.name}');
    return null;
  }
}

class _SyncWorkServiceAccountExchanger extends BaseCredentialExchanger {
  _SyncWorkServiceAccountExchanger(this.events);

  final List<String> events;

  @override
  Future<ExchangeResult> exchange({
    required AuthCredential authCredential,
    String? authScheme,
  }) async {
    events.add('exchanger:run');
    return ExchangeResult(
      credential: AuthCredential(
        authType: AuthCredentialType.serviceAccount,
        serviceAccount: authCredential.serviceAccount?.copyWith(),
        http: HttpAuth(
          scheme: 'bearer',
          credentials: HttpCredentials(token: 'exchanged-sa-token'),
        ),
      ),
      wasExchanged: true,
    );
  }
}

class _SyncOpenApiExchanger extends BaseAuthCredentialExchanger {
  _SyncOpenApiExchanger(this.events);

  final List<String> events;

  @override
  Future<AuthCredential?> exchangeCredential(
    Object authScheme, [
    AuthCredential? authCredential,
  ]) async {
    events.add('openapi_exchanger:run');
    return AuthCredential(
      authType: AuthCredentialType.serviceAccount,
      http: HttpAuth(
        scheme: 'bearer',
        credentials: HttpCredentials(token: 'openapi-sa-token'),
      ),
    );
  }
}

class _FakeCodeExecutor extends BaseCodeExecutor {
  _FakeCodeExecutor(this.nextResult);

  final CodeExecutionResult nextResult;
  int calls = 0;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    calls += 1;
    return nextResult;
  }
}

class _ThrowingAgent extends BaseAgent {
  _ThrowingAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    context.session.state['before_crash'] = 'recorded';
    throw StateError('unhandled boom');
  }
}

InvocationContext _buildContext({
  BaseAgent? agent,
  InMemorySessionService? sessionService,
  Session? session,
  String invocationId = 'inv-1',
  bool isResumable = false,
}) {
  final InMemorySessionService resolvedService =
      sessionService ?? InMemorySessionService();
  final BaseAgent resolvedAgent =
      agent ?? LlmAgent(name: 'root', model: _QueuedMockLlm(<LlmResponse>[]));
  final Session resolvedSession =
      session ?? Session(id: 'sess-1', appName: 'app', userId: 'user-1');
  return InvocationContext(
    sessionService: resolvedService,
    invocationId: invocationId,
    agent: resolvedAgent,
    session: resolvedSession,
    resumabilityConfig: ResumabilityConfig(isResumable: isResumable),
  );
}

LlmResponse _fcResponse(List<Part> parts) {
  return LlmResponse(content: Content(role: 'model', parts: parts));
}

Part _fcPart(String name, Map<String, dynamic> args, {String? id}) {
  return Part.fromFunctionCall(name: name, args: args, id: id);
}

void main() {
  group('1. LangGraphAgent content blocks (079586136)', () {
    test('extracts concatenated text from content block lists and ignores reasoning blocks', () async {
      final LangGraphAgent blockAgent = LangGraphAgent(
        name: 'lg_blocks',
        invokeGraph: ({required List<LangGraphMessage> messages, required String threadId}) {
          return <String, Object?>{
            'messages': <Object?>[
              ...messages,
              <String, Object?>{
                'role': 'assistant',
                'content': <Object?>[
                  <String, Object?>{'type': 'reasoning', 'summary': 'thinking...'},
                  <String, Object?>{'type': 'text', 'text': 'Hello '},
                  <String, Object?>{'type': 'text', 'text': 'world!'},
                ],
              },
            ],
          };
        },
      );

      final InvocationContext ctx = _buildContext(agent: blockAgent)
        ..userContent = Content.userText('hi');
      final List<Event> events = await blockAgent.runAsync(ctx).toList();
      expect(events, hasLength(1));
      expect(events.single.content?.parts.single.text, 'Hello world!');
    });

    test('returns empty string when content blocks contain only non-text entries', () async {
      final LangGraphAgent reasoningOnlyAgent = LangGraphAgent(
        name: 'lg_reasoning_only',
        invokeGraph: ({required List<LangGraphMessage> messages, required String threadId}) {
          return <Object?>[
            <String, Object?>{'type': 'reasoning', 'summary': 'internal'},
            <String, Object?>{'type': 'tool_use', 'name': 'noop'},
          ];
        },
      );

      final InvocationContext ctx = _buildContext(agent: reasoningOnlyAgent)
        ..userContent = Content.userText('hi');
      final List<Event> events = await reasoningOnlyAgent.runAsync(ctx).toList();
      expect(events, hasLength(1));
      expect(events.single.content?.parts.single.text, '');
      expect(
        LangGraphMessage.assistantBlocks(<Object?>[
          <String, Object?>{'type': 'reasoning', 'text': 'ignored'},
          <String, Object?>{'type': 'text', 'text': 'kept'},
        ]).text,
        'kept',
      );
      expect(extractLangGraphMessageText('plain reply'), 'plain reply');
    });
  });

  group('2a. finish_task after callbacks & abort sealing (fa647fcc1)', () {
    test('FinishTaskTool sets skipSummarization and runs agent & plugin afterAgentCallbacks', () async {
      final List<String> calls = <String>[];
      final LlmAgent taskAgent = LlmAgent(
        name: 'task_worker',
        mode: 'task',
        model: _QueuedMockLlm(<LlmResponse>[
          _fcResponse(<Part>[
            _fcPart(finishTaskToolName, <String, dynamic>{'result': 'done'}, id: 'ft-1'),
          ]),
          LlmResponse(content: Content.modelText('unexpected extra model turn')),
        ]),
        afterAgentCallback: (CallbackContext ctx) {
          calls.add('agent:${ctx.agentName}');
          return null;
        },
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        app: App(
          name: 'app',
          rootAgent: taskAgent,
          plugins: <BasePlugin>[_AfterAgentRecorderPlugin(calls)],
        ),
        sessionService: sessionService,
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('run task'),
          )
          .toList();

      expect(calls, containsAllInOrder(<String>['plugin:task_worker', 'agent:task_worker']));
      final Event finishFrEvent = events.firstWhere(isFinishTaskTerminalFr);
      expect(finishFrEvent.actions.skipSummarization, isTrue);
      expect(
        events.any((Event e) => e.content?.parts.any((Part p) => p.text == 'unexpected extra model turn') ?? false),
        isFalse,
      );
    });

    test('task-mode Workflow node runs plugin and agent afterAgentCallback when finish_task succeeds', () async {
      final List<String> calls = <String>[];
      final LlmAgent taskNode = LlmAgent(
        name: 'task_node',
        mode: 'task',
        model: _QueuedMockLlm(<LlmResponse>[
          _fcResponse(<Part>[
            _fcPart(finishTaskToolName, <String, dynamic>{'result': 'workflow_done'}, id: 'ft-wf'),
          ]),
        ]),
        afterAgentCallback: (CallbackContext ctx) {
          calls.add('agent:${ctx.agentName}');
          return null;
        },
      );
      final Workflow wf = Workflow(
        name: 'wf_task_after',
        nodes: <BaseNode>[buildNode(taskNode)],
        edges: <Edge>[Edge(fromNode: START, toNode: taskNode)],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        app: App(
          name: 'app',
          rootAgent: wf,
          plugins: <BasePlugin>[_AfterAgentRecorderPlugin(calls)],
        ),
        sessionService: sessionService,
      );

      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('hi'),
          )
          .toList();

      expect(calls, contains('plugin:task_node'));
      expect(calls, contains('agent:task_node'));
      expect(
        events.any(
          (Event e) => e.content?.parts.any((Part p) => p.text == 'workflow_done') ?? false,
        ),
        isTrue,
      );
    });

    test('isPausedTaskReply returns false when finish_task already completed in the same isolationScope', () {
      final List<Event> invocationEvents = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'root',
          content: Content(
            role: 'model',
            parts: <Part>[_fcPart('child_task', <String, dynamic>{'request': 'go'}, id: 'call-parent')],
          ),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'child_task',
          isolationScope: 'call-parent',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                id: 'ft-1',
                name: finishTaskToolName,
                response: <String, dynamic>{'result': finishTaskSuccessResult},
              ),
            ],
          ),
          actions: EventActions(skipSummarization: true),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'child_task',
          isolationScope: 'call-parent',
          content: Content.modelText('after-agent callback note'),
        ),
      ];

      expect(
        isPausedTaskReply(invocationEvents.last, invocationEvents: invocationEvents),
        isFalse,
      );
      final List<Event> aborts = buildAbortEvents(
        invocationEvents,
        invocationId: 'inv-1',
        rootAgentName: 'root',
      );
      expect(aborts, hasLength(1));
      expect(aborts.single.getFunctionResponses().single.id, 'call-parent');
    });
  });

  group('2b. single_turn transfer target reply in Workflow (b4126cddb)', () {
    for (final bool isResumable in <bool>[false, true]) {
      test('passes transfer target reply downstream and runs target once (isResumable=$isResumable)', () async {
        final _QueuedMockLlm translateModel = _QueuedMockLlm(<LlmResponse>[
          LlmResponse(content: Content.modelText('Hello!')),
          LlmResponse(content: Content.modelText('unused')),
        ]);
        final _QueuedMockLlm summarizeModel = _QueuedMockLlm(<LlmResponse>[
          LlmResponse(content: Content.modelText('Short.')),
          LlmResponse(content: Content.modelText('unused')),
        ]);
        final LlmAgent lead = LlmAgent(
          name: 'lead',
          model: _QueuedMockLlm(<LlmResponse>[
            _fcResponse(<Part>[
              _fcPart('transfer_to_agent', <String, dynamic>{'agent_name': 'translate'}, id: 'tr-1'),
            ]),
            _fcResponse(<Part>[
              _fcPart('transfer_to_agent', <String, dynamic>{'agent_name': 'summarize'}, id: 'tr-2'),
            ]),
          ]),
          instruction: 'Route.',
          subAgents: <BaseAgent>[
            LlmAgent(name: 'translate', model: translateModel, instruction: 'Translate.'),
            LlmAgent(name: 'summarize', model: summarizeModel, instruction: 'Summarize.'),
          ],
        );
        final List<Object?> capturedInputs = <Object?>[];
        final FunctionNode capture = node((WorkflowContext ctx, Object? input) {
          capturedInputs.add(input);
          return input;
        }, name: 'capture');

        final Workflow wf = Workflow.build(
          name: 'wf_transfer',
          nodes: <BaseNode>[buildNode(lead), capture],
          buildEdges: (EdgesBuilder g) {
            g.fromStart().then(lead).then(capture);
          },
        );

        final InMemorySessionService sessionService = InMemorySessionService();
        final Session session = await sessionService.createSession(
          appName: 'app',
          userId: 'u1',
        );
        final Runner runner = Runner(
          app: App(
            name: 'app',
            rootAgent: wf,
            resumabilityConfig: ResumabilityConfig(isResumable: isResumable),
          ),
          sessionService: sessionService,
        );

        await runner
            .runAsync(
              userId: 'u1',
              sessionId: session.id,
              newMessage: Content.userText('Hola'),
            )
            .toList();
        await runner
            .runAsync(
              userId: 'u1',
              sessionId: session.id,
              newMessage: Content.userText('Too long'),
            )
            .toList();

        expect(capturedInputs, <Object?>['Hello!', 'Short.']);
        expect(translateModel.requests, hasLength(1));
        expect(summarizeModel.requests, hasLength(1));
      });
    }

    test('resuming a downstream LRO node does not rerun transfer target', () async {
      final _QueuedMockLlm translateModel = _QueuedMockLlm(<LlmResponse>[
        LlmResponse(content: Content.modelText('Hello!')),
        LlmResponse(content: Content.modelText('unused')),
      ]);
      final LlmAgent lead = LlmAgent(
        name: 'lead',
        model: _QueuedMockLlm(<LlmResponse>[
          _fcResponse(<Part>[
            _fcPart('transfer_to_agent', <String, dynamic>{'agent_name': 'translate'}, id: 'tr-1'),
          ]),
        ]),
        subAgents: <BaseAgent>[
          LlmAgent(name: 'translate', model: translateModel),
        ],
      );
      final LongRunningFunctionTool approveTool = LongRunningFunctionTool(
        func: ({required String request}) => null,
      );
      final LlmAgent approver = LlmAgent(
        name: 'approver',
        model: _QueuedMockLlm(<LlmResponse>[
          _fcResponse(<Part>[
            _fcPart(approveTool.name, <String, dynamic>{'request': 'deploy'}, id: 'lro-approve'),
          ]),
          LlmResponse(content: Content.modelText('Approved.')),
        ]),
        tools: <Object>[approveTool],
      );

      final Workflow wf = Workflow.build(
        name: 'wf_resume_transfer',
        nodes: <BaseNode>[buildNode(lead), buildNode(approver)],
        buildEdges: (EdgesBuilder g) {
          g.fromStart().then(lead).then(approver);
        },
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        app: App(
          name: 'app',
          rootAgent: wf,
          resumabilityConfig: ResumabilityConfig(isResumable: true),
        ),
        sessionService: sessionService,
      );

      final List<Event> events1 = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('Hola'),
          )
          .toList();
      final Event interruptEvent = events1.firstWhere(
        (Event e) => e.longRunningToolIds?.isNotEmpty == true,
      );
      final String fcId = interruptEvent.longRunningToolIds!.first;
      final String invId = events1.first.invocationId;
      expect(translateModel.requests, hasLength(1));

      final List<Event> events2 = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            invocationId: invId,
            newMessage: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  id: fcId,
                  name: approveTool.name,
                  response: <String, dynamic>{'status': 'approved'},
                ),
              ],
            ),
          )
          .toList();

      expect(translateModel.requests, hasLength(1));
      expect(
        events2.any(
          (Event e) => e.content?.parts.any((Part p) => p.text == 'Approved.') ?? false,
        ),
        isTrue,
      );
    });
  });

  group('2c. LlmAgent.clone mode-built tools for sub-agents (61a4dc642)', () {
    test('rebuilds SingleTurnAgentTool, TaskAgentTool, and FinishTaskTool onto cloned instances', () {
      final LlmAgent stChild = LlmAgent(name: 'st_child', mode: 'single_turn');
      final LlmAgent taskChild = LlmAgent(
        name: 'task_child',
        mode: 'task',
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{'answer': <String, Object?>{'type': 'string'}},
        },
      );
      final LlmAgent root = LlmAgent(
        name: 'root',
        mode: 'task',
        subAgents: <BaseAgent>[stChild, taskChild],
      );

      final LlmAgent cloned = root.clone().clone();
      final SingleTurnAgentTool clonedStTool = cloned.tools
          .whereType<SingleTurnAgentTool>()
          .single;
      final TaskAgentTool clonedTaskTool = cloned.tools
          .whereType<TaskAgentTool>()
          .single;
      final List<FinishTaskTool> clonedFinishTools = cloned.tools
          .whereType<FinishTaskTool>()
          .toList();

      expect(clonedFinishTools, hasLength(1));
      expect(identical(clonedStTool.agent, cloned.subAgents[0]), isTrue);
      expect(identical(clonedStTool.agent, stChild), isFalse);
      expect(identical(clonedTaskTool.agent, cloned.subAgents[1]), isTrue);
      expect(identical(clonedTaskTool.agent, taskChild), isFalse);

      final FinishTaskTool childFinishTool = (cloned.subAgents[1] as LlmAgent)
          .tools
          .whereType<FinishTaskTool>()
          .single;
      expect(
        identical(
          childFinishTool,
          taskChild.tools.whereType<FinishTaskTool>().single,
        ),
        isFalse,
      );
    });

    test('handles subAgents/tools/mode/outputSchema updates, custom swapped tools, and removed mode tools', () {
      final LlmAgent childA = LlmAgent(name: 'child_a', mode: 'task');
      final LlmAgent childB = LlmAgent(name: 'child_b', mode: 'single_turn');
      final BaseTool customToolForA = FunctionTool(
        func: () => 'custom',
        name: 'child_a',
      );

      final LlmAgent parent = LlmAgent(
        name: 'parent',
        mode: 'task',
        subAgents: <BaseAgent>[childA, childB],
      );
      // Swap child_a's auto-built tool with a custom tool and remove child_b's tool.
      parent.tools.removeWhere((Object t) => t is TaskAgentTool && t.name == 'child_a');
      parent.tools.add(customToolForA);
      parent.tools.removeWhere((Object t) => t is SingleTurnAgentTool && t.name == 'child_b');

      final LlmAgent clonedSame = parent.clone();
      expect(clonedSame.tools, contains(same(customToolForA)));
      expect(
        clonedSame.tools.where((Object t) => t is SingleTurnAgentTool && t.name == 'child_b'),
        isEmpty,
      );

      // Caller-supplied tools list is not mutated when mode tools are rebuilt.
      final BaseTool helperTool = FunctionTool(func: () => 'ok', name: 'helper');
      final List<Object> callerTools = <Object>[helperTool];
      final LlmAgent newSub = LlmAgent(name: 'new_sub', mode: 'single_turn');
      final LlmAgent updatedClone = parent.clone(
        update: <String, Object?>{
          'tools': callerTools,
          'sub_agents': <BaseAgent>[newSub],
          'mode': 'chat',
        },
      );
      expect(callerTools, <Object>[helperTool]);
      expect(updatedClone.tools.whereType<FinishTaskTool>(), isEmpty);
      expect(
        updatedClone.tools.whereType<SingleTurnAgentTool>().single.agent,
        same(newSub),
      );

      // Sub-agent switched to chat drops delegated mode tool on clone.
      final LlmAgent switchSub = LlmAgent(name: 'switch_sub', mode: 'single_turn');
      final LlmAgent switchParent = LlmAgent(
        name: 'switch_parent',
        subAgents: <BaseAgent>[switchSub],
      );
      expect(switchParent.tools.whereType<SingleTurnAgentTool>(), hasLength(1));
      switchSub.mode = 'chat';
      final LlmAgent switchedClone = switchParent.clone();
      expect(switchedClone.tools.whereType<SingleTurnAgentTool>(), isEmpty);
    });
  });

  group('3. Async off-turn service-account credential exchange (9651df04d)', () {
    test('CredentialManager and ToolAuthHandler yield synchronous turn before exchanging credentials', () async {
      final List<String> events = <String>[];
      final CredentialExchangerRegistry registry = CredentialExchangerRegistry()
        ..register(
          AuthCredentialType.serviceAccount,
          _SyncWorkServiceAccountExchanger(events),
        );
      final AuthConfig authConfig = AuthConfig(
        authScheme: 'oauth2',
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.serviceAccount,
          serviceAccount: ServiceAccountAuth(
            useDefaultCredential: true,
            scopes: <String>['https://www.googleapis.com/auth/cloud-platform'],
          ),
        ),
      );
      final CredentialManager manager = CredentialManager(
        authConfig: authConfig,
        exchangerRegistry: registry,
      );
      final Context ctx = Context(_buildContext());

      final Future<AuthCredential?> credFuture = manager.getAuthCredential(ctx);
      events.add('caller:after_start_manager');
      final AuthCredential? exchanged = await credFuture;
      expect(exchanged?.http?.credentials.token, 'exchanged-sa-token');
      expect(
        events.indexOf('caller:after_start_manager'),
        lessThan(events.indexOf('exchanger:run')),
      );

      events.clear();
      final ToolAuthHandler handler = ToolAuthHandler(
        ctx,
        <String, Object?>{'type': 'http', 'scheme': 'bearer'},
        AuthCredential(
          authType: AuthCredentialType.serviceAccount,
          serviceAccount: ServiceAccountAuth(
            useDefaultCredential: true,
            scopes: <String>['scope:read'],
          ),
        ),
        credentialExchanger: _SyncOpenApiExchanger(events),
      );
      final Future<AuthPreparationResult> prepFuture =
          handler.prepareAuthCredentials();
      events.add('caller:after_start_openapi');
      final AuthPreparationResult prepResult = await prepFuture;
      expect(prepResult.authCredential?.http?.credentials.token, 'openapi-sa-token');
      expect(
        events.indexOf('caller:after_start_openapi'),
        lessThan(events.indexOf('openapi_exchanger:run')),
      );
    });
  });

  group('4a. Leave paused long-running calls open on task cancellation (e1e231cb3)', () {
    test('external stream cancel leaves LRO call unsealed while sealing ordinary dangling sibling call', () async {
      final Completer<void> normalToolEntered = Completer<void>();
      final Completer<String> normalToolBlocker = Completer<String>();
      final LongRunningFunctionTool lroTool = LongRunningFunctionTool(
        func: ({required String ticket}) => null,
      );
      final FunctionTool slowSiblingTool = FunctionTool(
        name: 'slow_sibling',
        func: () async {
          normalToolEntered.complete();
          return normalToolBlocker.future;
        },
      );
      final LlmAgent agent = LlmAgent(
        name: 'lro_cancel_agent',
        model: _QueuedMockLlm(<LlmResponse>[
          _fcResponse(<Part>[
            _fcPart(lroTool.name, <String, dynamic>{'ticket': 'T-1'}, id: 'call-lro'),
            _fcPart('slow_sibling', <String, dynamic>{}, id: 'call-sibling'),
          ]),
          LlmResponse(content: Content.modelText('Resumed after cancel!')),
        ]),
        tools: <Object>[lroTool, slowSiblingTool],
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        app: App(
          name: 'app',
          rootAgent: agent,
          resumabilityConfig: ResumabilityConfig(isResumable: true),
        ),
        sessionService: sessionService,
      );

      final List<Event> seen = <Event>[];
      late StreamSubscription<Event> sub;
      sub = runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('start'),
          )
          .listen(seen.add);

      await normalToolEntered.future;
      await sub.cancel();

      final Session stored = (await sessionService.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      ))!;
      expect(indexOpenInterrupts(stored.events).keys, <String>{'call-lro'});
      final List<FunctionResponse> abortResponses = stored.events
          .where((Event e) => e.errorCode == 'INVOCATION_ABORTED')
          .expand((Event e) => e.getFunctionResponses())
          .toList();
      expect(abortResponses.map((FunctionResponse r) => r.id), <String?>['call-sibling']);

      // Resuming the paused LRO call succeeds cleanly.
      final String invId = seen.first.invocationId;
      final List<Event> resumedEvents = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            invocationId: invId,
            newMessage: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  id: 'call-lro',
                  name: lroTool.name,
                  response: <String, dynamic>{'status': 'done'},
                ),
              ],
            ),
          )
          .toList();
      expect(
        resumedEvents.any(
          (Event e) => e.content?.parts.any((Part p) => p.text == 'Resumed after cancel!') ?? false,
        ),
        isTrue,
      );
    });

    test('guardedCallIds protects confirmation, credential, and sub-agent branch calls; explicit abortSignal seals all', () async {
      final InvocationContext ctx = _buildContext(invocationId: 'inv-guard');
      ctx.session.events.addAll(<Event>[
        Event(
          invocationId: 'inv-guard',
          author: 'root',
          content: Content(
            role: 'model',
            parts: <Part>[
              _fcPart('sub_agent', <String, dynamic>{'request': 'go'}, id: 'parent-branch-call'),
              _fcPart('danger_op', <String, dynamic>{}, id: 'orig-confirm-call'),
              _fcPart('authed_op', <String, dynamic>{}, id: 'orig-cred-call'),
              _fcPart('plain_dangling', <String, dynamic>{}, id: 'plain-call'),
            ],
          ),
        ),
        Event(
          invocationId: 'inv-guard',
          author: 'sub_agent',
          branch: 'sub_agent@parent-branch-call',
          longRunningToolIds: <String>{'sub-lro-id'},
          content: Content(
            role: 'model',
            parts: <Part>[_fcPart('wait_user', <String, dynamic>{}, id: 'sub-lro-id')],
          ),
        ),
        Event(
          invocationId: 'inv-guard',
          author: 'root',
          longRunningToolIds: <String>{'confirm-fc-id', 'cred-fc-id'},
          actions: EventActions(
            requestedToolConfirmations: <String, Object>{'orig-confirm-call': true},
          ),
          content: Content(
            role: 'model',
            parts: <Part>[
              _fcPart(
                'adk_request_confirmation',
                <String, dynamic>{
                  'originalFunctionCall': <String, dynamic>{'id': 'orig-confirm-call', 'name': 'danger_op'},
                },
                id: 'confirm-fc-id',
              ),
              _fcPart(
                'adk_request_credential',
                <String, dynamic>{'functionCallId': 'orig-cred-call'},
                id: 'cred-fc-id',
              ),
            ],
          ),
        ),
      ]);

      final Set<String> guarded = guardedCallIds(ctx);
      expect(
        guarded,
        containsAll(<String>{
          'parent-branch-call',
          'sub-lro-id',
          'confirm-fc-id',
          'orig-confirm-call',
          'cred-fc-id',
          'orig-cred-call',
        }),
      );
      expect(guarded, isNot(contains('plain-call')));

      final List<Event> cancelAborts = buildAbortEvents(
        ctx.session.events,
        invocationId: 'inv-guard',
        rootAgentName: 'root',
        keepOpen: guarded,
      );
      expect(
        cancelAborts.expand((Event e) => e.getFunctionResponses()).map((FunctionResponse r) => r.id),
        <String?>['plain-call'],
      );

      // Explicit abortSignal (keepOpen empty) seals ALL dangling calls including LROs.
      final List<Event> explicitAborts = buildAbortEvents(
        ctx.session.events,
        invocationId: 'inv-guard',
        rootAgentName: 'root',
      );
      expect(
        explicitAborts.expand((Event e) => e.getFunctionResponses()).map((FunctionResponse r) => r.id),
        containsAll(<String?>['parent-branch-call', 'sub-lro-id', 'confirm-fc-id', 'cred-fc-id', 'plain-call']),
      );
    });
  });

  group('4b. Keep text answers as text when RequestInput schema expects string (b989d6849)', () {
    for (final String rawInput in <String>['94103', 'true', '{"a":1}', '[1,2]', 'null']) {
      test('string and nullable-string schemas preserve "$rawInput" as String on resume', () async {
        final FunctionNode askText = node(
          (WorkflowContext ctx, Object? _) {
            if (ctx.resumeInputs.containsKey('zip_q')) {
              return ctx.resumeInputs['zip_q'];
            }
            return RequestInput(
              interruptId: 'zip_q',
              message: 'Enter text:',
              responseSchema: <String, Object?>{
                'anyOf': <Object?>[
                  <String, Object?>{'type': 'string'},
                  <String, Object?>{'type': 'null'},
                ],
              },
            );
          },
          name: 'ask_text',
          rerunOnResume: true,
        );
        final Workflow wf = Workflow(
          name: 'wf_text_schema',
          nodes: <BaseNode>[askText],
          edges: <Edge>[Edge(fromNode: START, toNode: askText)],
        );

        final Event reqEvent = createRequestInputEvent(
          RequestInput(
            interruptId: 'zip_q',
            message: 'Enter text:',
            responseSchema: <String, Object?>{
              'anyOf': <Object?>[
                <String, Object?>{'type': 'string'},
                <String, Object?>{'type': 'null'},
              ],
            },
          ),
          invocationId: 'inv-str',
          author: 'ask_text',
        ).copyWith(nodeInfo: NodeInfo(path: 'wf_text_schema@1/ask_text@1'));

        final Event userReply = Event(
          invocationId: 'inv-str',
          author: 'user',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                id: 'zip_q',
                name: requestInputFunctionCallName,
                response: <String, dynamic>{'result': rawInput},
              ),
            ],
          ),
        );

        final WorkflowResult rehydrated = wf.rehydrateResultFromEvents(
          <Event>[reqEvent, userReply],
          invocationId: 'inv-str',
        );
        expect(rehydrated.nodeStates['ask_text']?.resumeInputs['zip_q'], isA<String>());
        expect(rehydrated.nodeStates['ask_text']?.resumeInputs['zip_q'], rawInput);

        final WorkflowResult resumed = await wf.runWorkflow(previousResult: rehydrated);
        expect(resumed.outputs['ask_text'], isA<String>());
        expect(resumed.outputs['ask_text'], rawInput);
      });
    }

    test('integer schema still JSON-parses numeric string answers', () {
      final FunctionNode askCount = node(
        (WorkflowContext ctx, Object? _) => ctx.resumeInputs['count_q'],
        name: 'ask_count',
        rerunOnResume: true,
      );
      final Workflow wf = Workflow(
        name: 'wf_int_schema',
        nodes: <BaseNode>[askCount],
        edges: <Edge>[Edge(fromNode: START, toNode: askCount)],
      );
      final Event reqEvent = createRequestInputEvent(
        RequestInput(
          interruptId: 'count_q',
          message: 'How many?',
          responseSchema: <String, Object?>{'type': 'integer'},
        ),
        invocationId: 'inv-int',
        author: 'ask_count',
      ).copyWith(nodeInfo: NodeInfo(path: 'wf_int_schema@1/ask_count@1'));
      final Event userReply = Event(
        invocationId: 'inv-int',
        author: 'user',
        content: Content(
          role: 'user',
          parts: <Part>[
            Part.fromFunctionResponse(
              id: 'count_q',
              name: requestInputFunctionCallName,
              response: <String, dynamic>{'result': '42'},
            ),
          ],
        ),
      );

      final WorkflowResult rehydrated = wf.rehydrateResultFromEvents(
        <Event>[reqEvent, userReply],
        invocationId: 'inv-int',
      );
      expect(rehydrated.nodeStates['ask_count']?.resumeInputs['count_q'], 42);
    });
  });

  group('5. Clear open interrupts sealed by error FunctionResponses (efc7717bf)', () {
    test('indexOpenInterrupts closes error-sealed call IDs without closing enclosing branch interrupts', () {
      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-1',
          author: 'parent',
          longRunningToolIds: <String>{'parent-lro'},
          content: Content(
            role: 'model',
            parts: <Part>[_fcPart('outer_wait', <String, dynamic>{}, id: 'parent-lro')],
          ),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'child',
          branch: 'parent@parent-lro.child@1',
          longRunningToolIds: <String>{'child-lro'},
          content: Content(
            role: 'model',
            parts: <Part>[_fcPart('inner_wait', <String, dynamic>{}, id: 'child-lro')],
          ),
        ),
        Event(
          invocationId: 'inv-1',
          author: 'child',
          branch: 'parent@parent-lro.child@1',
          errorCode: 'INVOCATION_ABORTED',
          errorMessage: 'Sub-branch aborted',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                id: 'child-lro',
                name: 'inner_wait',
                response: <String, dynamic>{'error': 'Sub-branch aborted'},
              ),
            ],
          ),
        ),
      ];

      // Sub-branch error seal closes child-lro while keeping ancestor parent-lro open.
      expect(indexOpenInterrupts(events).keys, <String>{'parent-lro'});
    });

    test('rehydrateResultFromEvents and ReplayManager drop pathless abort-sealed interrupts and rerun node on resume', () async {
      int aRuns = 0;
      int bRuns = 0;
      final FunctionNode nodeA = node(
        (WorkflowContext ctx, Object? _) {
          aRuns += 1;
          if (ctx.resumeInputs.containsKey('ask')) {
            return 'approved:${ctx.resumeInputs['ask']}';
          }
          return RequestInput(interruptId: 'ask', message: 'approve?');
        },
        name: 'node_a',
        rerunOnResume: true,
        waitForOutput: true,
      );
      final FunctionNode nodeB = node((WorkflowContext ctx, Object? _) {
        bRuns += 1;
        return 'from_b';
      }, name: 'node_b');
      final JoinNode join = JoinNode(name: 'join');
      final FunctionNode collect = node((WorkflowContext ctx, Object? input) {
        final Map<Object?, Object?> m = input as Map<Object?, Object?>;
        return '${m['node_a']}|${m['node_b']}';
      }, name: 'collect');

      final Workflow wf = Workflow.build(
        name: 'wf_abort_resume',
        nodes: <BaseNode>[nodeA, nodeB, join, collect],
        buildEdges: (EdgesBuilder g) {
          g.fromStart().thenGroup(<Object>[nodeA, nodeB]).joinTo(join).then(collect);
        },
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        app: App(
          name: 'app',
          rootAgent: wf,
          resumabilityConfig: ResumabilityConfig(isResumable: true),
        ),
        sessionService: sessionService,
      );

      // Run 1: pauses at node_a while node_b completes.
      final List<Event> events1 = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            newMessage: Content.userText('start'),
          )
          .toList();
      expect(aRuns, 1);
      expect(bRuns, 1);
      final String invId = events1.first.invocationId;

      // Simulate pathless INVOCATION_ABORTED sealing 'ask' in session history.
      final Session stored = (await sessionService.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      ))!;
      final List<Event> abortSeals = buildAbortEvents(
        stored.events,
        invocationId: invId,
        rootAgentName: wf.name,
      );
      expect(abortSeals, isNotEmpty);
      for (final Event seal in abortSeals) {
        await sessionService.appendEvent(session: stored, event: seal);
      }

      // ReplayManager routes pathless seal and drops aborted node_a@1 from barrier sequence.
      final InvocationContext inspectCtx = _buildContext(
        agent: wf,
        sessionService: sessionService,
        session: stored,
        invocationId: invId,
        isResumable: true,
      );
      final ReplayManager replayManager = ReplayManager();
      final ReplaySequenceBarrier barrier = replayManager
          .prepareParentSequenceBarrier(Context(inspectCtx), 'wf_abort_resume@1');
      expect(barrier.pending, isNot(contains('node_a@1')));

      // Run 2: resume same invocation; node_b is NOT rerun, node_a reruns and re-emits 'ask'.
      final List<Event> events2 = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            invocationId: invId,
          )
          .toList();
      expect(aRuns, 2);
      expect(bRuns, 1);
      expect(events2.expand(extractEventInterruptIds), contains('ask'));

      // Run 3: supply user answer for fresh 'ask' interrupt; workflow finishes.
      final List<Event> events3 = await runner
          .runAsync(
            userId: 'u1',
            sessionId: session.id,
            invocationId: invId,
            newMessage: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  id: 'ask',
                  name: requestInputFunctionCallName,
                  response: <String, dynamic>{'result': 'yes'},
                ),
              ],
            ),
          )
          .toList();
      expect(bRuns, 1);
      expect(
        events3.any(
          (Event e) => e.content?.parts.any((Part p) => p.text == 'approved:yes|from_b') ?? false,
        ),
        isTrue,
      );
    });

    test('nested sub-branch error seal preserves surviving parent output', () {
      final FunctionNode worker = node(
        (WorkflowContext ctx, Object? _) => 'parent_ok',
        name: 'worker',
        rerunOnResume: true,
      );
      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[worker],
        edges: <Edge>[Edge(fromNode: START, toNode: worker)],
      );

      final List<Event> events = <Event>[
        Event(
          invocationId: 'inv-sub',
          author: 'sub_0',
          nodeInfo: NodeInfo(path: 'wf@1/worker@1/sub_0@1'),
          longRunningToolIds: <String>{'sub-0'},
          content: Content(
            role: 'model',
            parts: <Part>[_fcPart(requestInputFunctionCallName, <String, dynamic>{}, id: 'sub-0')],
          ),
        ),
        Event(
          invocationId: 'inv-sub',
          author: 'worker',
          nodeInfo: NodeInfo(path: 'wf@1/worker@1'),
          output: 'parent_ok',
        ),
        Event(
          invocationId: 'inv-sub',
          author: 'sub_0',
          nodeInfo: NodeInfo(path: 'wf@1/worker@1/sub_0@1'),
          errorCode: 'RuntimeError',
          errorMessage: 'sub_0 crashed',
          content: Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                id: 'sub-0',
                name: requestInputFunctionCallName,
                response: <String, dynamic>{'error': 'sub_0 crashed'},
              ),
            ],
          ),
        ),
      ];

      final WorkflowResult result = wf.rehydrateResultFromEvents(
        events,
        invocationId: 'inv-sub',
      );
      expect(result.nodeStates['worker']?.interrupts, isEmpty);
      expect(result.nodeStates['worker']?.resumeInputs, isEmpty);
      expect(result.nodeStates['worker']?.status, NodeStatus.completed);
      expect(result.outputs['worker'], 'parent_ok');
    });
  });

  group('6. Code execution without artifact service when no files written (9687bae1c)', () {
    test('runs code without artifactService when outputFiles is empty and throws when files are produced', () async {
      final _FakeCodeExecutor noFileExecutor = _FakeCodeExecutor(
        CodeExecutionResult(stdout: '42\n'),
      );
      final LlmAgent agent = LlmAgent(
        name: 'coder',
        codeExecutor: noFileExecutor,
        model: _QueuedMockLlm(<LlmResponse>[]),
      );
      final InvocationContext ctxNoArtifact = _buildContext(agent: agent);
      expect(ctxNoArtifact.artifactService, isNull);

      final CodeExecutionResponseProcessor processor =
          CodeExecutionResponseProcessor();
      LlmResponse freshCodeResp() => LlmResponse(
        content: Content.modelText('```python\nprint(6 * 7)\n```'),
      );

      final List<Event> events = await processor
          .runAsync(ctxNoArtifact, freshCodeResp())
          .toList();
      expect(noFileExecutor.calls, 1);
      expect(events, hasLength(2));
      expect(events.last.actions.artifactDelta, isEmpty);

      // When outputFiles is non-empty and artifactService is null, throws StateError.
      final _FakeCodeExecutor fileExecutor = _FakeCodeExecutor(
        CodeExecutionResult(
          stdout: 'wrote png\n',
          outputFiles: <CodeExecutionFile>[
            CodeExecutionFile(
              name: 'chart.png',
              content: <int>[0x89, 0x50, 0x4E, 0x47, 0xFF],
              mimeType: 'image/png',
            ),
          ],
        ),
      );
      final LlmAgent fileAgent = LlmAgent(
        name: 'file_coder',
        codeExecutor: fileExecutor,
        model: _QueuedMockLlm(<LlmResponse>[]),
      );
      final InvocationContext ctxMissingService = _buildContext(agent: fileAgent);
      await expectLater(
        processor.runAsync(ctxMissingService, freshCodeResp()).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'Artifact service is not initialized.',
          ),
        ),
      );

      // With artifactService configured, binary bytes are saved intact without base64 corruption.
      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      final InvocationContext ctxWithArtifact = InvocationContext(
        sessionService: InMemorySessionService(),
        artifactService: artifactService,
        invocationId: 'inv-art',
        agent: fileAgent,
        session: Session(id: 's-art', appName: 'app', userId: 'u-art'),
      );
      final List<Event> savedEvents = await processor
          .runAsync(ctxWithArtifact, freshCodeResp())
          .toList();
      expect(savedEvents.last.actions.artifactDelta, <String, int>{'chart.png': 0});
      final Part? loaded = await artifactService.loadArtifact(
        appName: 'app',
        userId: 'u-art',
        sessionId: 's-art',
        filename: 'chart.png',
      );
      expect(loaded?.inlineData?.data, <int>[0x89, 0x50, 0x4E, 0x47, 0xFF]);
    });
  });

  group('7. DebugLoggingPlugin flushes trace & clears state on unhandled run errors (9e549adf7)', () {
    test('Runner unhandled exception triggers onRunErrorCallback, writes invocation_error, and clears state', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'adk-debug-err-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final File outputFile = File('${tempDir.path}/debug_trace.yaml');

      final DebugLoggingPlugin plugin = DebugLoggingPlugin(
        outputPath: outputFile.path,
        includeSessionState: true,
      );
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
      );
      final Runner runner = Runner(
        app: App(
          name: 'app',
          rootAgent: _ThrowingAgent(name: 'crasher'),
          plugins: <BasePlugin>[plugin],
        ),
        sessionService: sessionService,
      );

      await expectLater(
        runner
            .runAsync(
              userId: 'u1',
              sessionId: session.id,
              newMessage: Content.userText('boom'),
            )
            .toList(),
        throwsA(isA<StateError>()),
      );

      expect(outputFile.existsSync(), isTrue);
      final String raw = outputFile.readAsStringSync();
      final List<String> docs = raw
          .split('---\n')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      expect(docs, hasLength(1));

      final Map<String, Object?> doc =
          (jsonDecode(docs.single) as Map<Object?, Object?>).cast<String, Object?>();
      final List<Object?> entries = doc['entries'] as List<Object?>;
      final List<String?> entryTypes = entries
          .map((Object? e) => (e as Map<Object?, Object?>)['entry_type'] as String?)
          .toList();
      expect(entryTypes, contains('session_state_snapshot'));
      expect(entryTypes.last, 'invocation_error');
      final Map<Object?, Object?> errData =
          (entries.last as Map<Object?, Object?>)['data'] as Map<Object?, Object?>;
      expect(errData['error_type'], 'StateError');
      expect('${errData['error_message']}', contains('unhandled boom'));

      // Calling afterRunCallback for the same invocationId writes no duplicate document
      // because _invocationStates was cleared on error.
      final InvocationContext dummySameInv = InvocationContext(
        sessionService: sessionService,
        invocationId: '${doc['invocation_id']}',
        agent: _ThrowingAgent(name: 'crasher'),
        session: session,
      );
      await plugin.afterRunCallback(invocationContext: dummySameInv);
      final List<String> docsAfter = outputFile
          .readAsStringSync()
          .split('---\n')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      expect(docsAfter, hasLength(1));
    });
  });

  group('8. InMemorySessionService prunes empty maps on deleteSession (c0bcdaa48)', () {
    test('prunes empty userId and appName maps while preserving sibling sessions and app/user state', () async {
      final InMemorySessionService service = InMemorySessionService();
      final Session s1 = await service.createSession(
        appName: 'app_one',
        userId: 'alice',
        sessionId: 's1',
        state: <String, Object?>{'app:shared': 'v1', 'user:pref': 'dark', 'local': 1},
      );
      final Session s2 = await service.createSession(
        appName: 'app_one',
        userId: 'alice',
        sessionId: 's2',
      );
      final Session sBob = await service.createSession(
        appName: 'app_one',
        userId: 'bob',
        sessionId: 'sb',
      );

      await service.deleteSession(
        appName: 'app_one',
        userId: 'alice',
        sessionId: s1.id,
      );
      expect(service.sessions['app_one']?.containsKey('alice'), isTrue);
      expect(service.sessions['app_one']?['alice']?.keys, <String>[s2.id]);

      await service.deleteSession(
        appName: 'app_one',
        userId: 'alice',
        sessionId: s2.id,
      );
      expect(service.sessions['app_one']?.containsKey('alice'), isFalse);
      expect(service.sessions['app_one']?.containsKey('bob'), isTrue);

      await service.deleteSession(
        appName: 'app_one',
        userId: 'bob',
        sessionId: sBob.id,
      );
      expect(service.sessions.containsKey('app_one'), isFalse);
      // App and user state outlive deleted sessions.
      expect(service.appState['app_one'], <String, Object?>{'shared': 'v1'});
      expect(service.userState['app_one']?['alice'], <String, Object?>{'pref': 'dark'});
    });
  });

  group('9. Workflow route deduplication (dc7d7431a) & rerunOnResume error message (ba43b4f0a)', () {
    test('resolveNextPendingNodes and RouteMap run target node and JoinNode once when multiple routes match', () async {
      final FunctionNode nodeA = node((WorkflowContext ctx, Object? _) {
        ctx.route = <String>['route_x', 'route_y'];
        return 'A';
      }, name: 'NodeA');
      int bRuns = 0;
      final FunctionNode nodeB = node((WorkflowContext ctx, Object? _) {
        bRuns += 1;
        return 'B';
      }, name: 'NodeB');
      final FunctionNode nodeC = node((WorkflowContext ctx, Object? _) => 'C', name: 'NodeC');

      // Direct Graph/Edge helper parity with test_get_next_pending_nodes_returns_each_target_once.
      final List<String> pending = Workflow.resolveNextPendingNodes(
        <Edge>[
          Edge(fromNode: START, toNode: nodeA),
          Edge(fromNode: nodeA, toNode: nodeB, route: 'route1'),
          Edge(fromNode: nodeA, toNode: nodeC, route: 'route2'),
          Edge(fromNode: nodeA, toNode: nodeB, route: 'route3'),
        ],
        'NodeA',
        routesToMatch: <String>['route1', 'route2', 'route3'],
      );
      expect(pending, <String>['NodeB', 'NodeC']);

      // End-to-end Workflow.build with multiple route entries to the same node.
      final Workflow wfNode = Workflow.build(
        name: 'test_routes_to_one_node',
        nodes: <BaseNode>[nodeA, nodeB],
        buildEdges: (EdgesBuilder g) {
          g.fromStart().then(nodeA).route((RouteMap r) {
            r.on('route_x').then(nodeB);
            r.on('route_y').then(nodeB);
          });
        },
      );
      final WorkflowResult resNode = await wfNode.runWorkflow(input: 'start');
      expect(bRuns, 1);
      expect(resNode.outputs['NodeB'], 'B');

      // End-to-end Workflow.build with multiple route entries to a JoinNode.
      int afterGateRuns = 0;
      final JoinNode gate = JoinNode(name: 'Gate');
      final FunctionNode afterGate = node((WorkflowContext ctx, Object? _) {
        afterGateRuns += 1;
        return 'B';
      }, name: 'AfterGate');
      final Workflow wfJoin = Workflow.build(
        name: 'test_routes_to_one_join',
        nodes: <BaseNode>[nodeA, gate, afterGate],
        buildEdges: (EdgesBuilder g) {
          g.fromStart().then(nodeA).route((RouteMap r) {
            r.on('route_x').then(gate);
            r.on('route_y').then(gate);
          });
          g.from(gate).then(afterGate);
        },
      );
      final WorkflowResult resJoin = await wfJoin.runWorkflow(input: 'start');
      expect(afterGateRuns, 1);
      expect(resJoin.outputs['Gate'], <String, Object?>{'NodeA': 'A'});
      expect(resJoin.outputs['AfterGate'], 'B');
    });

    test('context.runNode without rerunOnResume names the calling node in StateError', () async {
      final FunctionNode child = node(
        (WorkflowContext ctx, Object? _) => 'done',
        name: 'child',
      );
      final FunctionNode orchestrator = node(
        (WorkflowContext ctx, Object? input) => ctx.runNode(child, input: input),
        name: 'orchestrator',
      );
      final Workflow wf = Workflow(
        name: 'root',
        nodes: <BaseNode>[orchestrator],
        edges: <Edge>[Edge(fromNode: START, toNode: orchestrator)],
      );

      await expectLater(
        wf.runWorkflow(input: 'start'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              startsWith("Node 'orchestrator' calls context.runNode but has rerunOnResume: false;"),
              contains('set rerunOnResume: true on it'),
            ),
          ),
        ),
      );
    });
  });
}
