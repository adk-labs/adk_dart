# ADK JS Daily Change Report

- Date (UTC): 2026-11-10
- Source: `google/adk-js`
- Latest SHA: `c9ff7b71359f27f0004e1bca60a2bad527826e18`
- Previous SHA: `f41747828fcb02276d18281a88cee5ab5128e2ff`

## Summary

- New commits: 6

## Commits

- [c9ff7b7](https://github.com/google/adk-js/commit/c9ff7b71359f27f0004e1bca60a2bad527826e18) feat(core): add agent and run error hooks and finalize aborted runs (#1156) (Zaid Lattouf, 2026-11-10)
- [d98ee13](https://github.com/google/adk-js/commit/d98ee13004c97949211daba1a643f9a72bc7caa6) fix(agents): treat Object.prototype names as missing state keys in instructions (#1252) (G, 2026-11-10)
- [86a2492](https://github.com/google/adk-js/commit/86a249271e995a25e3936a720fd5606ed20cb5c9) fix(skills): run a skill script named without the scripts/ prefix (#1254) (G, 2026-11-10)
- [5f1a8f3](https://github.com/google/adk-js/commit/5f1a8f30792f40d7ddebd4e2c429d49eb589af27) chore(deps): bump the npm_and_yarn group across 1 directory with 5 updates (#1245) (dependabot[bot], 2026-11-10)
- [53f5861](https://github.com/google/adk-js/commit/53f5861cd568d8d1d22a1f5c411d51dbaa6cf602) fix(agents): keep parallel tool responses when another call asks for confirmation (#1244) (coder-abu, 2026-11-11)
- [8dad457](https://github.com/google/adk-js/commit/8dad4578fef657fa70f666f21fe1768b72fbdf69) test(integration): use placeholder GCP identifiers in agent_tool_vertexai_test (#1072) (adk-foundry-bot, 2026-11-09)

## Changed Files

- `M	core/src/agents/base_agent.ts`
- `M	core/src/agents/instructions.ts`
- `M	core/src/agents/llm_agent.ts`
- `M	core/src/plugins/base_plugin.ts`
- `M	core/src/plugins/plugin_manager.ts`
- `M	core/src/runner/runner.ts`
- `M	core/src/sessions/base_session_service.ts`
- `M	core/src/sessions/vertex_ai_session_service.ts`
- `M	core/src/tools/skill/run_skill_script_tool.ts`
- `M	core/src/utils/error_utils.ts`
- `M	core/test/agents/instructions_test.ts`
- `M	core/test/plugins/base_plugin_test.ts`
- `M	core/test/plugins/plugin_manager_test.ts`
- `M	core/test/runner/run_live_test.ts`
- `M	core/test/runner/runner_abort_test.ts`
- `A	core/test/runner/runner_plugin_lifecycle_test.ts`
- `M	core/test/sessions/in_memory_session_service_test.ts`
- `M	core/test/sessions/vertex_ai_session_service_test.ts`
- `M	core/test/tools/function_tool_confirmation_test.ts`
- `M	core/test/tools/skills/run_skill_script_tool_test.ts`
- `M	core/test/utils/error_utils_test.ts`
- `M	docs/guides/runners/index.md`
- `M	package-lock.json`
- `M	tests/integration/tools/agent_tool_vertexai_test.ts`
