# Workflows (ADK 2.0 DAGs) & Multi-Agent Systems

## 1. ADK 2.0 Graph Workflows (`Workflow`, `BaseNode`, `JoinNode`)

`Workflow` orchestrates `FunctionNode`s, `AgentNode`s (or `LlmAgent`s wrapped in a workflow), sub-workflows, conditional branches, parallel fan-out/fan-in (`JoinNode`), and human-in-the-loop pauses (`RequestInput`):

```dart
import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final FunctionNode fetchA = FunctionNode(
    name: 'fetch_a',
    function: (WorkflowContext ctx, Object? nodeInput) async =>
        <String, Object?>{'a': 10},
  );

  final FunctionNode fetchB = FunctionNode(
    name: 'fetch_b',
    function: (WorkflowContext ctx, Object? nodeInput) async =>
        <String, Object?>{'b': 20},
  );

  final JoinNode join = JoinNode(name: 'join_ab');

  final FunctionNode combine = FunctionNode(
    name: 'combine',
    function: (WorkflowContext ctx, Object? nodeInput) async {
      final Map<String, Object?> inputs =
          (nodeInput as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
      return <String, Object?>{'sum': 30, 'inputs': inputs};
    },
  );

  // Build using the fluent EdgesBuilder API (or pass edges: <Edge>[...]):
  final Workflow workflow = Workflow.build(
    name: 'parallel_pipeline',
    nodes: <BaseNode>[fetchA, fetchB, join, combine],
    buildEdges: (EdgesBuilder g) {
      g
          .fromStart()
          .thenGroup(<Object>[fetchA, fetchB])
          .joinTo(join)
          .then(combine);
    },
  );

  // Option A: Run directly and inspect WorkflowResult
  final WorkflowResult result = await workflow.runWorkflow(input: 'start');
  print('Workflow Outputs: ${result.outputs}');

  // Option B: Run as a BaseAgent inside InMemoryRunner / Runner
  final InMemoryRunner runner = InMemoryRunner(agent: workflow);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'u1',
    sessionId: 's1',
  );

  await for (final Event event in runner.runAsync(
    userId: 'u1',
    sessionId: session.id,
    newMessage: Content.userText('run'),
  )) {
    if (event.isFinalResponse()) {
      print('Workflow Event Output: ${event.content?.parts.first.text}');
    }
  }
}
```

### Conditional Routing, Dynamic Nodes (`ctx.runNode`), HITL & Tool Wrappers

- **Conditional Edges**: Set `ctx.route = 'fast'` inside a node and connect routes via `EdgesBuilder`:
  ```dart
  g.from(classifyNode).route((RouteMap r) {
    r.on('fast').then(fastNode);
    r.otherwise(thoroughNode);
  });
  ```
- **Dynamic Node Scheduling**: Inside a node function, call `await ctx.runNode(childNode, input: ...)` to dynamically spawn and await nodes at runtime. **Rule**: Any node that calls `ctx.runNode(...)` **must** be constructed with `rerunOnResume: true`.
- **Human-in-the-Loop (`RequestInput`)**: Place `RequestInput(name: 'ask_approval', message: 'Approve deployment?')` in the graph (or run it dynamically via `await ctx.runNode(RequestInput(name: 'ask', message: 'Approve?'))` inside a node with `rerunOnResume: true`) to pause the workflow and resume on the next run.
- **Workflow or Node as a Tool (`WorkflowTool` & `NodeTool`)**:
  - Wrap a multi-node `Workflow` in `WorkflowTool(workflow: myWorkflow)` so an `LlmAgent` can call the entire workflow as a tool.
  - Wrap a single `BaseNode` (`FunctionNode`, `AgentNode`) in `NodeTool(node: myNode)`.

---

## 2. Classic Multi-Agent Shells (`SequentialAgent`, `ParallelAgent`, `LoopAgent`)

```dart
final SequentialAgent pipeline = SequentialAgent(
  name: 'research_and_write',
  subAgents: <BaseAgent>[
    researchAgent, // Sets outputKey: 'research_notes'
    writerAgent,   // Reads {research_notes} in its instruction
  ],
);

final ParallelAgent concurrentGather = ParallelAgent(
  name: 'parallel_gather',
  subAgents: <BaseAgent>[newsAgent, marketAgent],
);

final LoopAgent iterativeRefiner = LoopAgent(
  name: 'refiner_loop',
  maxIterations: 3,
  subAgents: <BaseAgent>[draftAgent, criticAgent], // Use ExitLoopTool to exit early
);
```

---

## 3. Autonomous Sub-Agent Transfer (`subAgents`)

Give an `LlmAgent` a `subAgents` list and clear `description` strings on each child agent. The runtime automatically injects the `transfer_to_agent` tool:

```dart
final Agent billingAgent = Agent(
  name: 'billing_agent',
  model: 'gemini-2.5-flash',
  description: 'Handles invoices, refunds, and subscription billing questions.',
  instruction: 'Resolve billing issues.',
);

final Agent supportAgent = Agent(
  name: 'tech_support_agent',
  model: 'gemini-2.5-flash',
  description: 'Troubleshoots technical bugs and API errors.',
  instruction: 'Resolve technical issues.',
);

final Agent coordinator = Agent(
  name: 'coordinator',
  model: 'gemini-2.5-flash',
  instruction: 'Route the user to billing_agent or tech_support_agent.',
  subAgents: <BaseAgent>[billingAgent, supportAgent],
);
```

> **Rule**: An agent instance can only have **one parent**. Never pass the same `Agent` instance into two different `subAgents` lists; construct a separate instance instead.

---

## 4. Bounded Task Delegation (`mode: 'task'`) & Remote A2A (`RemoteA2aAgent`)

- **Task Mode (`mode: 'task'` or `mode: 'single_turn'`)**: Setting `mode: 'task'` on an `LlmAgent` automatically registers `FinishTaskTool` (`finish_task`) and exposes the child agent as a callable task tool on its parent coordinator:
  ```dart
  final Agent auditorTask = Agent(
    name: 'security_auditor',
    model: 'gemini-2.5-flash',
    description: 'Audits a code snippet and returns structured findings.',
    instruction: 'Audit the input and call finish_task when done.',
    mode: 'task',
    parallelWorker: true,
    maxParallelWorkers: 4,
  );
  ```
- **Remote A2A Agent (`RemoteA2aAgent`)**: Connects a remote Agent-to-Agent (A2A) server as a sub-agent via an `AgentCard` or `.well-known/agent.json` URL:
  ```dart
  final RemoteA2aAgent remoteSpecialist = RemoteA2aAgent(
    name: 'remote_specialist',
    description: 'Delegates specialized queries to a remote A2A agent.',
    agentCard: 'https://example.com/.well-known/agent.json',
  );
  ```
