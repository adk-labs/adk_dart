# ADK Python Daily Change Report

- Date (UTC): 2026-10-19
- Source: `google/adk-python`
- Latest SHA: `ebbfb0ee5166424240156ab9056f2bf67f5af784`
- Previous SHA: `e2dbc0f55027372f3a701d41004ee006ee8f9f14`

## Summary

- New commits: 17

## Commits

- [ebbfb0ee](https://github.com/google/adk-python/commit/ebbfb0ee5166424240156ab9056f2bf67f5af784) perf: cut late /run_sse turns by 13-30% by loading their events once (George Weale, 2026-10-19)
- [2802834e](https://github.com/google/adk-python/commit/2802834eb2dc15855e82142b598b7d22a6843810) fix: source MCP destination ID from RuntimeReference.uri (chelsealong, 2026-10-19)
- [92bb67f9](https://github.com/google/adk-python/commit/92bb67f9b5e4204aba71e482aeabfab39bd87da9) docs(runner): fix voluntary early-termination guidance in abort unit guide (Shangjie Chen, 2026-10-19)
- [ef8be1f9](https://github.com/google/adk-python/commit/ef8be1f96aa52f88611d75ad6ba6f76f48f3825b) test: cover use_sub_branch parallel single_turn context isolation (er-s-an, 2026-10-19)
- [2d81d328](https://github.com/google/adk-python/commit/2d81d3289586bdfb1b9ec4264193dba01416f945) docs(sessions): update State iteration, nested write tracking, and session error docs (Shangjie Chen, 2026-10-19)
- [57e8bc67](https://github.com/google/adk-python/commit/57e8bc67f19aa964e928b6c6d3199a9ec7892de6) fix: do not resolve Bigtable view parameters from session state (prasanna8585, 2026-10-19)
- [772f1396](https://github.com/google/adk-python/commit/772f1396244ac7c3381ee7cfe22530899b428de2) perf: cut a string-model agent's turn from 20 ms to 2.5 ms (George Weale, 2026-10-19)
- [dd80f8f7](https://github.com/google/adk-python/commit/dd80f8f7500c9853d44a3682405c4742f2c40c37) fix: forward thinking_config to litellm reasoning params (chelsealong, 2026-10-19)
- [557743c4](https://github.com/google/adk-python/commit/557743c4484c7745f6c52b3bca07727011852e78) fix: keep a streamed thought signature sent without the call's name (Vetle Leinonen-Roeim, 2026-10-19)
- [5d408696](https://github.com/google/adk-python/commit/5d408696d2c5a1c8bb80cac6e4fb63263093bf82) fix: share event id across streamed A2A artifact chunks (Ferran Pons Serra, 2026-10-19)
- [8ff99419](https://github.com/google/adk-python/commit/8ff99419f3da8bc5921122699f125bf931905698) fix: keep client token usage when the last response has none (Somay-kousis, 2026-10-19)
- [ead208a4](https://github.com/google/adk-python/commit/ead208a47540e0004286302d6718330679278a1b) feat: record google_search grounding on LLM spans (Spandan Keche, 2026-10-19)
- [52cc2d82](https://github.com/google/adk-python/commit/52cc2d82a2959e9920db04c028be1450d7b4aaa0) fix: give each seeded environment-simulation injection its own generator (George Weale, 2026-10-19)
- [d3770b83](https://github.com/google/adk-python/commit/d3770b837ea186487e6a4f16d644e3b3a9f10208) test: resolve wrapped callable annotations in tool schemas (Chenghao Liu, 2026-10-18)
- [8f17ac4f](https://github.com/google/adk-python/commit/8f17ac4fa4c9a18efabc699ea3032bb861e25dcf) fix(tools): extract query text from all user content parts in ExampleTool (Yuhan Gao, 2026-10-18)
- [04b8b601](https://github.com/google/adk-python/commit/04b8b6011ed6335febeef77631f137613d471348) fix: preserve Annotated text and content schemas (Jeeho Lee, 2026-10-18)
- [ebe11595](https://github.com/google/adk-python/commit/ebe11595e7da50a1f158f64e266fb4e73f60bea1) test: cover FunctionTool with async tools behind sync decorators (techi101, 2026-10-18)

## Changed Files

- `M	docs/guides/examples/example/index.md`
- `M	docs/guides/models/llm_registry/index.md`
- `M	docs/guides/runners/runner/abort.md`
- `M	docs/guides/sessions/session/index.md`
- `M	docs/guides/sessions/state/index.md`
- `M	docs/guides/telemetry/telemetry_config/index.md`
- `M	src/google/adk/a2a/agent/_remote_a2a_agent.py`
- `M	src/google/adk/a2a/converters/to_adk_event.py`
- `M	src/google/adk/agents/llm_agent.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/examples/example_util.py`
- `M	src/google/adk/integrations/agent_registry/agent_registry.py`
- `M	src/google/adk/models/base_llm.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/telemetry/_adk_attributes.py`
- `M	src/google/adk/telemetry/_metrics.py`
- `M	src/google/adk/telemetry/context.py`
- `M	src/google/adk/telemetry/tracing.py`
- `M	src/google/adk/tools/bigtable/bigtable_toolset.py`
- `M	src/google/adk/tools/environment_simulation/environment_simulation_config.py`
- `M	src/google/adk/tools/environment_simulation/environment_simulation_engine.py`
- `M	src/google/adk/tools/example_tool.py`
- `M	src/google/adk/tools/preload_memory_tool.py`
- `M	src/google/adk/utils/_schema_utils.py`
- `M	src/google/adk/utils/content_utils.py`
- `M	tests/unittests/a2a/agent/test_remote_a2a_agent.py`
- `M	tests/unittests/a2a/converters/test_to_adk.py`
- `M	tests/unittests/agents/test_llm_agent_fields.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/integrations/agent_registry/test_agent_registry.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/telemetry/functional/_recording.py`
- `M	tests/unittests/telemetry/functional/scenarios/conversation.py`
- `M	tests/unittests/telemetry/functional/scenarios/inference.py`
- `M	tests/unittests/telemetry/functional_divergences.json`
- `A	tests/unittests/telemetry/functional_goldens/agent/grounding.json`
- `M	tests/unittests/telemetry/functional_test_cases.py`
- `M	tests/unittests/telemetry/regenerate.py`
- `M	tests/unittests/telemetry/test_functional.py`
- `M	tests/unittests/telemetry/test_metrics.py`
- `M	tests/unittests/telemetry/test_semconv_conformance.py`
- `M	tests/unittests/telemetry/test_spans.py`
- `M	tests/unittests/tools/bigtable/test_bigtable_toolset.py`
- `M	tests/unittests/tools/environment_simulation/test_environment_simulation_engine.py`
- `M	tests/unittests/tools/test_example_tool.py`
- `M	tests/unittests/tools/test_function_tool.py`
- `M	tests/unittests/tools/test_function_tool_with_import_annotations.py`
- `M	tests/unittests/utils/test_content_utils.py`
- `M	tests/unittests/utils/test_schema_utils.py`
- `M	tests/unittests/workflow/test_llm_agent_as_node.py`
