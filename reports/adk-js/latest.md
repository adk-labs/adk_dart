# ADK JS Daily Change Report

- Date (UTC): 2026-10-20
- Source: `google/adk-js`
- Latest SHA: `9da07da369665125c7545a1500b3bb3cc53bce72`
- Previous SHA: `adc9b6174d07f32d1291d13901aeec06dbe136de`

## Summary

- New commits: 9

## Commits

- [9da07da](https://github.com/google/adk-js/commit/9da07da369665125c7545a1500b3bb3cc53bce72) fix(skills): report a missing or non-directory path in validateSkillDir (#1086) (adk-foundry-bot, 2026-10-19)
- [1976731](https://github.com/google/adk-js/commit/1976731f3c252a3408e50838600aba478551f13e) test(core): add unit tests for auth, instructions, tool callbacks, live runs, and usage metadata (#1105) (Scott Mansfield, 2026-10-19)
- [b04c64c](https://github.com/google/adk-js/commit/b04c64cb941426fa8fc75e90b610250a9e647d05) test(integration): build real InvocationContexts in skill-script fixtures (#1085) (adk-foundry-bot, 2026-10-19)
- [78a81bd](https://github.com/google/adk-js/commit/78a81bd8bb3eb74e5e957a5c2b62c8f92a784444) test(core): spread the real module in three vi.mock factories (#1095) (adk-foundry-bot, 2026-10-19)
- [0525ffc](https://github.com/google/adk-js/commit/0525ffc11a44c5a9642d3fdf3aecdbfca066dbcf) test(integration): let server-start hooks outlast the start watchdog (#1073) (adk-foundry-bot, 2026-10-19)
- [fa62265](https://github.com/google/adk-js/commit/fa622652b46bc7bab4eed3eaccf16be4595fd303) fix: resolve the exit_loop built-in tool in YAML agent configs (#572) (Amaad Martin, 2026-10-19)
- [be51de9](https://github.com/google/adk-js/commit/be51de92cb075c386c5584da0697a735b51b4e3e) fix(deploy): stop echoing the rejected value in the Dockerfile newline error (#1096) (adk-foundry-bot, 2026-10-19)
- [0b905df](https://github.com/google/adk-js/commit/0b905df63d0f4a00da81110036e62f0448d05916) feat(agents): port adk-python v0.5.0 changes to agents (#1104) (Scott Mansfield, 2026-10-19)
- [593c451](https://github.com/google/adk-js/commit/593c4516634a8e68f9da68cb06a1e80991572f48) feat: port adk-python v0.5.0 changes to artifacts, auth, events (+7 more) (#1102) (Scott Mansfield, 2026-10-19)

## Changed Files

- `M	core/src/agents/base_agent.ts`
- `M	core/src/skills/loader.ts`
- `M	core/src/tools/openapi_tool/openapi_spec_parser/operation_parser.ts`
- `M	core/test/a2a/event_processor_utils_test.ts`
- `M	core/test/agents/base_agent_test.ts`
- `M	core/test/agents/functions_test.ts`
- `M	core/test/agents/llm_agent_test.ts`
- `M	core/test/agents/processors/instructions_llm_request_processor_test.ts`
- `M	core/test/agents/run_config_test.ts`
- `M	core/test/agents/sequential_agent_test.ts`
- `M	core/test/auth/auth_preprocessor_test.ts`
- `M	core/test/models/base_llm_test.ts`
- `M	core/test/models/google_llm_test.ts`
- `M	core/test/sessions/in_memory_session_service_test.ts`
- `M	core/test/skills/loader_test.ts`
- `M	core/test/tools/openapi_tool/operation_parser_test.ts`
- `M	core/test/tools/skills/run_skill_inline_script_tool_test.ts`
- `M	core/test/tools/skills/run_skill_script_tool_test.ts`
- `M	dev/src/cli/deploy/deploy_utils.ts`
- `M	dev/src/integration/agent_registry.ts`
- `M	dev/src/integration/replay_plugin.ts`
- `M	dev/src/integration/test_runner.ts`
- `M	dev/test/cli/cli_deploy_cloud_run_test.ts`
- `M	dev/test/integration/agent_registry_test.ts`
- `A	dev/test/integration/replay_plugin_test.ts`
- `A	dev/test/integration/test_runner_test.ts`
- `M	tests/integration/a2a/basic/a2a_agent_test.ts`
- `M	tests/integration/a2a/input_required/input_required_test.ts`
- `M	tests/integration/a2a/stream/stream_test.ts`
- `M	tests/integration/adk_web/webui_test.ts`
- `M	tests/integration/test_api_server.ts`
- `M	tests/integration/tools/run_skill_inline_script_tool_test.ts`
- `M	tests/integration/tools/run_skill_script_tool_test.ts`
