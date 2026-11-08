# Workflows (ADK 2.0 DAGs) & Multi-Agent Systems

## 1. ADK 2.0 Graph Workflows (`Workflow`, `BaseNode`, `JoinNode`)

`Workflow` orchestrates function nodes, `LlmAgent` nodes, sub-workflows, conditional branches, parallel fan-out/fan-in (`JoinNode`), and human-in-the-loop pauses (`RequestInput`):

```dart
import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final FunctionNode fetchA = FunctionNode(
    name: 'fetch_a',
    func: (WorkflowContext ctx) async => <String, Object?>{'a': 10},
  );

  final FunctionNode fetchB = FunctionNode(
    name: 'fetch_b',
    func: (WorkflowContext ctx) async => <String, Object?>{'b': 20},
  );

  final JoinNode join = JoinNode(name: 'join_ab');

  final FunctionNode combine = FunctionNode(
    name: 'combine',
    func: (WorkflowContext ctx, Map<String, Object?> nodeInput) async {
      return <String, Object?>{'sum': 30, 'inputs': nodeInput};
    },
  );

  final Workflow workflow = Workflow(
    name: 'parallel_pipeline',
    edges: <Object>[
      // Fan-out from START to fetch_a and fetch_b in parallel
      ('START', <BaseNode>[fetchA, fetchB]),
      // Fan-in both branches into JoinNode
      (<BaseNode>[fetchA, fetchB], join),
      // Continue to combine node
      (join, combine),
    ],
  );

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
      print('Workflow Output: ${event.content?.parts.first.text}');
    }
  }
}
```

### Conditional Routing & Dynamic Nodes (`ctx.runNode`)

- **Conditional Edges**: Pass a router callback `(START, myNode, (WorkflowContext ctx) => ctx.state['route'] == 'fast' ? fastNode : thoroughNode)` or route maps.
- **Dynamic Node Scheduling**: Inside a node function, call `await ctx.runNode(childNode, input: ...)` to dynamically spawn and await nodes at runtime.
- **Human-in-the-Loop (`RequestInput`)**: Yield or return a `RequestInput(prompt: 'Approve deployment?')` inside a node to pause the workflow and resume on the next `runner.runAsync(...)` call.
- **Workflow as a Tool (`NodeTool`)**: Wrap any `Workflow` or `BaseNode` in `NodeTool(node: myWorkflow)` so an `LlmAgent` can call the workflow as a tool.

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
