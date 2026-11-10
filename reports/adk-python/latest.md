# ADK Python Daily Change Report

- Date (UTC): 2026-11-10
- Source: `google/adk-python`
- Latest SHA: `61efa3003f896d715fd8ed07b570f73c01f81247`
- Previous SHA: `b989d684945f8d16baf3d7a64cb784cdc9b58bd4`

## Summary

- New commits: 14

## Commits

- [61efa300](https://github.com/google/adk-python/commit/61efa3003f896d715fd8ed07b570f73c01f81247) fix: initialize the environment from tool calls (Liang Wu, 2026-11-10)
- [dc7d7431](https://github.com/google/adk-python/commit/dc7d7431a6d325003068bc3d19af2aa1262adca6) fix: run a node once when a list of routes matches several edges to it (hyeonsang010716, 2026-11-10)
- [b4126cdd](https://github.com/google/adk-python/commit/b4126cddb2c982e6649dde36171cc6b82b704b2e) fix: pass a single_turn transfer target's reply downstream (Vishal Bulbule, 2026-11-10)
- [58390078](https://github.com/google/adk-python/commit/5839007855d3f795c822f07b230755a5bf18feaa) fix: report empty Claude responses as model errors (emme1t, 2026-11-10)
- [f0eb6139](https://github.com/google/adk-python/commit/f0eb6139c2cc072b768e6340dea43f093237a14e) fix: use agentidentitycredentials v1 client in /agent-identity/finalize (Google Team Member, 2026-11-10)
- [e41b46bc](https://github.com/google/adk-python/commit/e41b46bc3df0591810a89bd370470093eed0040b) docs: use the current Agent Runtime product name in README (Google Team Member, 2026-11-10)
- [c41bc42f](https://github.com/google/adk-python/commit/c41bc42fb8a7487d7e3cd3d62202005ea0d1375a) feat: list bundled resource paths in the load_skill response (Prajwal, 2026-11-10)
- [6e448cf5](https://github.com/google/adk-python/commit/6e448cf59faa0b04d47f974f93b2022990fb0d23) fix(eval): don't fail a no-argument tool call over None vs empty args (Yusef Syed, 2026-11-10)
- [cd8debd2](https://github.com/google/adk-python/commit/cd8debd2e7920512783217bc81f268824a81033e) fix(antigravity): pass cached token count in the turn usage event (Google Team Member, 2026-11-10)
- [b79c529b](https://github.com/google/adk-python/commit/b79c529b57d2e9477e86521a8cdf47bd1d9fa98f) docs: say tool_filter does not apply to load_mcp_resource (Iliass Ayaou, 2026-11-10)
- [fa647fcc](https://github.com/google/adk-python/commit/fa647fcc1ed93b171ae6f32580a51a649048910c) fix: run a task agent's after callbacks when finish_task succeeds (Arjun Prabhulal, 2026-11-10)
- [efc7717b](https://github.com/google/adk-python/commit/efc7717bf478f2e0edba052a41d36cacdd43eddf) fix(workflow): clear open interrupts sealed by error function responses (Thomas Zettl, 2026-11-10)
- [ab638443](https://github.com/google/adk-python/commit/ab638443816b425787dbb6b2fd835cdf03bbcbef) fix: fail on connector schema operation error and bound poll wait (Naveen Chatlapalli, 2026-11-09)
- [19737966](https://github.com/google/adk-python/commit/197379667ca9b65973949032feb841dcfcf4e3a7) docs: remove experimental and allowlist notes for deferred service tier (Google Team Member, 2026-11-09)

## Changed Files

- `M	README.md`
- `M	contributing/samples/environment_and_skills/skills/tests/current_humidity.json`
- `M	contributing/samples/environment_and_skills/skills/tests/current_weather.json`
- `M	contributing/samples/environment_and_skills/skills/tests/support_hours.json`
- `M	contributing/samples/environment_and_skills/skills/tests/wind_speed.json`
- `M	contributing/samples/multi_agent/task_sub_agent/tests/10_burgers.json`
- `M	contributing/samples/multi_agent/task_sub_agent/tests/3_burgers.json`
- `M	contributing/samples/workflows/agent_in_workflow/tests/go_approve.json`
- `M	contributing/samples/workflows/agent_in_workflow/tests/go_decline.json`
- `M	contributing/samples/workflows/agent_in_workflow/tests/jane_doe.json`
- `M	contributing/samples/workflows/agent_in_workflow/tests/jane_doe_and_phone_number.json`
- `M	contributing/samples/workflows/agent_in_workflow/tests/phone_number.json`
- `M	contributing/samples/workflows/agent_in_workflow/tests/wrong_name.json`
- `M	docs/guides/environment/base_environment/index.md`
- `M	docs/guides/models/service_tier/index.md`
- `M	docs/guides/tools/mcp_tool/mcp_toolset/index.md`
- `M	src/google/adk/agents/llm/task/_finish_task_tool.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/environment/_base_environment.py`
- `M	src/google/adk/evaluation/trajectory_evaluator.py`
- `M	src/google/adk/events/_abort_events.py`
- `M	src/google/adk/events/_interrupts.py`
- `M	src/google/adk/labs/antigravity/_antigravity_agent.py`
- `M	src/google/adk/models/anthropic_llm.py`
- `M	src/google/adk/tools/application_integration_tool/clients/connections_client.py`
- `M	src/google/adk/tools/environment/_constants.py`
- `M	src/google/adk/tools/environment/_edit_file_tool.py`
- `M	src/google/adk/tools/environment/_environment_toolset.py`
- `M	src/google/adk/tools/environment/_execute_tool.py`
- `M	src/google/adk/tools/environment/_read_file_tool.py`
- `M	src/google/adk/tools/environment/_utils.py`
- `M	src/google/adk/tools/environment/_write_file_tool.py`
- `M	src/google/adk/tools/mcp_tool/mcp_toolset.py`
- `M	src/google/adk/tools/skill_toolset.py`
- `M	src/google/adk/workflow/_graph.py`
- `M	src/google/adk/workflow/_llm_agent_wrapper.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	src/google/adk/workflow/utils/_replay_manager.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/evaluation/test_trajectory_evaluator.py`
- `M	tests/unittests/events/test_abort_events.py`
- `M	tests/unittests/events/test_interrupts.py`
- `M	tests/unittests/labs/antigravity/test_antigravity_agent.py`
- `M	tests/unittests/models/test_anthropic_llm.py`
- `M	tests/unittests/tools/application_integration_tool/clients/test_connections_client.py`
- `A	tests/unittests/tools/environment/test_environment_utils.py`
- `M	tests/unittests/tools/mcp_tool/test_mcp_toolset.py`
- `M	tests/unittests/tools/test_environment_toolset.py`
- `M	tests/unittests/tools/test_skill_toolset.py`
- `M	tests/unittests/workflow/test_graph.py`
- `M	tests/unittests/workflow/test_llm_agent_as_node.py`
- `M	tests/unittests/workflow/test_task_api_e2e.py`
- `M	tests/unittests/workflow/test_workflow_hitl.py`
- `M	tests/unittests/workflow/test_workflow_routes.py`
- `M	tests/unittests/workflow/utils/test_rehydration_utils.py`
- `M	tests/unittests/workflow/utils/test_replay_manager.py`
