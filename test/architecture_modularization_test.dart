import 'package:adk_dart/a2a.dart' as a2a;
import 'package:adk_dart/agents.dart' as agents;
import 'package:adk_dart/evaluation.dart' as evaluation;
import 'package:adk_dart/integrations.dart' as integrations;
import 'package:adk_dart/models.dart' as models;
import 'package:adk_dart/sessions.dart' as sessions;
import 'package:adk_dart/telemetry.dart' as telemetry;
import 'package:adk_dart/tools.dart' as tools;
import 'package:adk_dart/workflow.dart' as workflow;
import 'package:test/test.dart';

void main() {
  group('Domain Entrypoint Barrels', () {
    test('agents barrel exports agent runtime, flows, planners, and runners', () {
      final agents.LlmAgent agent = agents.LlmAgent(
        name: 'test_agent',
        model: 'gemini-2.5-flash',
        instruction: 'Hello',
      );
      expect(agent.name, 'test_agent');

      final agents.InMemoryRunner runner = agents.InMemoryRunner(agent: agent);
      expect(runner.agent, same(agent));

      final agents.Content content = agents.Content.userText('ping');
      expect(content.parts.single.text, 'ping');

      final agents.PlanReActPlanner planner = agents.PlanReActPlanner();
      expect(planner, isA<agents.BasePlanner>());
    });

    test('workflow barrel and modularized workflow parts work end-to-end', () async {
      final workflow.FunctionNode step1 = workflow.node(
        (workflow.WorkflowContext ctx, Object? input) => 'step1:$input',
        name: 'step_1',
      );
      final workflow.FunctionNode step2 = workflow.node(
        (workflow.WorkflowContext ctx, Object? input) => '$input->step2',
        name: 'step_2',
      );

      final workflow.Workflow wf = workflow.Workflow(
        name: 'test_workflow',
        nodes: <workflow.BaseNode>[step1, step2],
        edges: <workflow.Edge>[
          workflow.Edge(fromNode: workflow.START, toNode: step1),
          workflow.Edge(fromNode: step1, toNode: step2),
        ],
      );

      final workflow.WorkflowResult result = await wf.runWorkflow(input: 'init');
      expect(result.outputs['step_1'], 'step1:init');
      expect(result.outputs['step_2'], 'step1:init->step2');
      expect(
        result.nodeStates['step_2']?.status,
        workflow.NodeStatus.completed,
      );
    });

    test('evaluation barrel exports evaluation models and metrics', () {
      final evaluation.EvaluateConfig config = evaluation.EvaluateConfig(
        evalMetrics: <evaluation.EvalMetric>[
          evaluation.EvalMetric.finalResponseExactMatch,
        ],
        parallelism: 2,
      );
      expect(
        config.evalMetrics,
        contains(evaluation.EvalMetric.finalResponseExactMatch),
      );
      expect(config.parallelism, 2);

      final evaluation.InMemoryEvalSetsManager manager =
          evaluation.InMemoryEvalSetsManager();
      expect(manager, isA<evaluation.EvalSetsManager>());
    });

    test('tools barrel exports tools, skills, and code executors', () {
      final tools.FunctionTool tool = tools.FunctionTool(
        func: ({required String query}) => 'result: $query',
        name: 'search_tool',
        description: 'Searches items',
      );
      expect(tool.name, 'search_tool');

      final tools.BuiltInCodeExecutor executor = tools.BuiltInCodeExecutor();
      expect(executor, isA<tools.BaseCodeExecutor>());

      final tools.Frontmatter frontmatter = tools.Frontmatter(
        name: 'my-skill',
        description: 'A test skill',
      );
      expect(frontmatter.name, 'my-skill');
    });

    test('models barrel and modularized LiteLlm work end-to-end', () async {
      final models.LiteLlm llm = models.LiteLlm(
        model: 'openai/gpt-4o-mini',
        completionsInvoker: ({
          required Map<String, Object?> payload,
          required bool stream,
        }) async {
          return <Map<String, Object?>>[
            <String, Object?>{
              'choices': <Map<String, Object?>>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'role': 'assistant',
                    'content':
                        '<tool_call>{"name": "lookup", "arguments": {"id": 42}}</tool_call>',
                  },
                  'finish_reason': 'stop',
                },
              ],
            },
          ];
        },
      );

      final List<models.LlmResponse> responses = await llm
          .generateContent(
            models.LlmRequest(
              model: 'openai/gpt-4o-mini',
              contents: <agents.Content>[agents.Content.userText('Find 42')],
            ),
            stream: false,
          )
          .toList();

      expect(responses, hasLength(1));
      final agents.FunctionCall? fnCall =
          responses.single.content?.parts.firstWhere(
            (agents.Part part) => part.functionCall != null,
          ).functionCall;
      expect(fnCall, isNotNull);
      expect(fnCall!.name, 'lookup');
      expect(fnCall.args, <String, dynamic>{'id': 42});
    });

    test('sessions barrel exports session, artifact, and memory services', () async {
      final sessions.InMemorySessionService sessionService =
          sessions.InMemorySessionService();
      final sessions.Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user_1',
      );
      expect(session.appName, 'app');

      final sessions.InMemoryArtifactService artifactService =
          sessions.InMemoryArtifactService();
      expect(artifactService, isA<sessions.BaseArtifactService>());

      final sessions.InMemoryMemoryService memoryService =
          sessions.InMemoryMemoryService();
      expect(memoryService, isA<sessions.BaseMemoryService>());
    });

    test('integrations barrel exports cloud and third-party integrations', () {
      const integrations.ModelArmorSdpDeidentifyResult sdpResult =
          integrations.ModelArmorSdpDeidentifyResult(
            executionState: integrations.ModelArmorInvocationResult.success,
            matchState: integrations.ModelArmorFilterMatchState.noMatchFound,
          );
      expect(
        sdpResult.executionState,
        integrations.ModelArmorInvocationResult.success,
      );
    });

    test('a2a barrel exports A2A protocol and router utilities', () {
      final a2a.InMemoryA2ARouter router = a2a.InMemoryA2ARouter();
      expect(router, isNotNull);

      final a2a.A2AMessage msg = a2a.A2AMessage(
        fromAgent: 'agent_a',
        toAgent: 'agent_b',
        content: 'hello',
      );
      expect(msg.fromAgent, 'agent_a');
      expect(msg.toAgent, 'agent_b');
    });

    test('telemetry barrel and modularized BigQueryAgentAnalyticsPlugin work', () {
      final telemetry.InMemoryTelemetryService telemetryService =
          telemetry.InMemoryTelemetryService();
      expect(telemetryService, isA<telemetry.BaseTelemetryService>());

      final telemetry.InMemoryBigQueryEventSink sink =
          telemetry.InMemoryBigQueryEventSink();
      final telemetry.BigQueryAgentAnalyticsPlugin plugin =
          telemetry.BigQueryAgentAnalyticsPlugin(
            projectId: 'test-proj',
            datasetId: 'test_dataset',
            tableId: 'agent_events',
            sink: sink,
            useBigQueryInsertAllSink: false,
          );
      expect(plugin.projectId, 'test-proj');
      expect(plugin.datasetId, 'test_dataset');
      expect(plugin.tableId, 'agent_events');
    });
  });
}
