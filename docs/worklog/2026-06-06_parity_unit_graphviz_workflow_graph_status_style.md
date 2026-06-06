# Parity Unit: Graphviz Workflow Graph Status/Style Visualization

- Date: 2026-06-06
- Commit: `7138c61 feat: add status-aware graph dot output`
- Reference: `ref/adk-python/src/google/adk/cli/utils/graph_visualization.py`
- Scope:
  - `lib/src/cli/agent_graph.dart`
  - `lib/src/dev/web_server.dart`
  - `test/cli_agent_graph_test.dart`

## Background

Python's dev UI graph visualization produces Graphviz DOT/SVG with workflow-specific styling: status colors, conditional branch diamonds, missing-default warnings, tool dashed edges, highlighted edges, and terminal `END` nodes. Dart graph endpoints previously emitted only a minimal DOT graph with labels and edge labels.

## Implementation

- Added public `getAgentGraphDot(...)` on top of the existing `AgentGraph` model.
- Added dark/light DOT theme attributes for graph, node, and edge defaults.
- Added status fill colors for:
  - `completed`
  - `running`
  - `failed`
  - `inactive`
  - `waiting`
  - `cancelled`
- Supported status lookup by full graph node ID and short workflow node-state key.
- Added conditional branch diamond rendering.
- Added `[NO DEFAULT]` warning labels for routed nodes without a default edge.
- Added dashed tool node styling and dashed tool edges.
- Preserved event graph highlighted edge styling.
- Added workflow terminal `END` node generation.
- Rewired dev-server graph endpoints to call the shared DOT generator.
- Added parsing for `event.actions.agentState.nodes.*.status` so event graph snapshots can color nodes when status state is present.

## Tests

- Added CLI graph tests for:
  - Graphviz DOT theme attributes
  - workflow status colors
  - conditional diamond styling
  - missing-default warning labels
  - terminal `END` edge generation
  - dashed/highlighted tool edges
- Re-ran dev-server graph endpoint regression tests.

## Verification

- `dart analyze lib/src/cli/agent_graph.dart lib/src/dev/web_server.dart test/cli_agent_graph_test.dart`: PASS
- `dart test test/cli_agent_graph_test.dart`: PASS, 4 passed
- `dart test test/dev_web_server_test.dart --name "serves graph serialized app info for workflow roots"`: PASS
- `dart test test/dev_web_server_test.dart --name "serves debug trace and event graph after run"`: PASS
- `dart analyze lib test`: PASS with existing info-level lints
- `dart test`: PASS, 1326 passed, 3 skipped

## Remaining Gap

- This closed DOT-level graph visualization status/style parity.
- Live Graphviz SVG/PNG rendering parity remains separate because Dart currently returns DOT text rather than invoking Graphviz.
