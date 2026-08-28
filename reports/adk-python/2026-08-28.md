# ADK Python Daily Change Report

- Date (UTC): 2026-08-28
- Source: `google/adk-python`
- Latest SHA: `35570c25b3e3d32150aa2fff1a95e3bf53bd4d5a`
- Previous SHA: `181d52e402d8c0d921a0e3dd80d5c743a5b40589`

## Summary

- New commits: 16

## Commits

- [35570c25](https://github.com/google/adk-python/commit/35570c25b3e3d32150aa2fff1a95e3bf53bd4d5a) refactor(runners): extract node runner async loop into workflow/_node_runner_utils (Shangjie Chen, 2026-08-28)
- [fbfaea7e](https://github.com/google/adk-python/commit/fbfaea7e3889d1b0af4b718f430f4e35cb835dd5) refactor: reach the MCP SDK through the dependencies seam (Kathy Wu, 2026-08-28)
- [fa321f1b](https://github.com/google/adk-python/commit/fa321f1b49f7bd961b58ad19fd8b8e6fa285b918) fix(environment): terminate the whole process tree when a local command times out (Kathy Wu, 2026-08-28)
- [2a9461b1](https://github.com/google/adk-python/commit/2a9461b1da1c3f7bf732cb37ac43a865f907c6a4) feat: load ADK 2.0 graph workflows from YAML configuration (Shangjie Chen, 2026-08-28)
- [f0bee2cd](https://github.com/google/adk-python/commit/f0bee2cd1b1befe91659a6b7c13e2d9e94299812) refactor(live): adopt google.adk.live across internals, samples, and tests (Shangjie Chen, 2026-08-28)
- [024c4fc9](https://github.com/google/adk-python/commit/024c4fc9273a177df71c750b09f034f0d5fdff4c) refactor: map YAML agent configs onto agent classes by reflection (Shangjie Chen, 2026-08-28)
- [10ac52b5](https://github.com/google/adk-python/commit/10ac52b5f05c5a3e7f9c6b6bbbc867cc962c657b) feat: add get_authenticated_url and get_signed_url to GcsArtifactService (Prajwal, 2026-08-28)
- [8db82ba2](https://github.com/google/adk-python/commit/8db82ba298af92256f9566a766bbe55a4912d873) fix: match a branch's run ids exactly when resolving HITL interrupts (Shangjie Chen, 2026-08-28)
- [e51aadcf](https://github.com/google/adk-python/commit/e51aadcfa27cdb2443dfe2deb716788043abeec3) fix: point misplaced generation kwargs at generate_content_config (Aarav Mittal, 2026-08-28)
- [66315dae](https://github.com/google/adk-python/commit/66315daea81f1ea181ae7b89d33cfa4ed8204359) fix: stop offering run_skill_script when no code executor is configured (Kathy Wu, 2026-08-28)
- [7c36523b](https://github.com/google/adk-python/commit/7c36523baaac14799560e6da45482553e469f651) chore: merge release v2.8.0 to main (adk-bot, 2026-08-28)
- [4295bd02](https://github.com/google/adk-python/commit/4295bd0238f1b1244ac8325cc4a0c14fac56a739) perf: stop rescanning the session for every user response event (Shangjie Chen, 2026-08-28)
- [f8fdfed2](https://github.com/google/adk-python/commit/f8fdfed281186489dc915e767e7f9f4a18081ae2) perf: extend the workflow replay index instead of rebuilding it per event (Shangjie Chen, 2026-08-28)
- [afbcaff7](https://github.com/google/adk-python/commit/afbcaff7b8744edbd2992c5ea6bf03ecb5e78787) fix: treat a max_iterations of zero as zero loop passes (George Weale, 2026-08-28)
- [73d9fe05](https://github.com/google/adk-python/commit/73d9fe053f99188e01ad186df5dcc401c48e79d7) fix: add optional OIDC verification for Pub/Sub and Eventarc triggers (Herdiyan Adam Putra, 2026-08-28)
- [2c9c00da](https://github.com/google/adk-python/commit/2c9c00da2b43b5defea0be3ecbe4303e91d05162) ci: update pre-commit hooks to latest stable versions (Syed Jafri, 2026-08-28)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	.github/release-please-config.json`
- `M	.pre-commit-config.yaml`
- `M	CHANGELOG.md`
- `M	contributing/samples/live/live_bidi_streaming_tools_agent/agent.py`
- `M	contributing/samples/workflows/loop_config/README.md`
- `M	contributing/samples/workflows/loop_config/root_agent.yaml`
- `A	contributing/samples/workflows/loop_config/tests/computer.json`
- `A	contributing/samples/workflows/loop_config/tests/flower.json`
- `M	docs/guides/README.md`
- `A	docs/guides/agents/config/index.md`
- `M	src/google/adk/a2a/utils/agent_card_builder.py`
- `M	src/google/adk/agents/active_streaming_tool.py`
- `M	src/google/adk/agents/base_agent.py`
- `M	src/google/adk/agents/config_agent_utils.py`
- `M	src/google/adk/agents/invocation_context.py`
- `M	src/google/adk/agents/llm_agent.py`
- `M	src/google/adk/agents/loop_agent.py`
- `M	src/google/adk/agents/mcp_instruction_provider.py`
- `M	src/google/adk/artifacts/gcs_artifact_service.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/cli/browser/assets/config/runtime-config.json`
- `M	src/google/adk/cli/cli_deploy.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/cli/fast_api.py`
- `M	src/google/adk/cli/trigger_routes.py`
- `A	src/google/adk/dependencies/_mcp.py`
- `A	src/google/adk/dependencies/_mcp_name.py`
- `M	src/google/adk/environment/_local_environment.py`
- `M	src/google/adk/evaluation/evaluation_generator.py`
- `M	src/google/adk/flows/llm_flows/base_llm_flow.py`
- `M	src/google/adk/flows/llm_flows/functions.py`
- `M	src/google/adk/integrations/agent_registry/agent_registry.py`
- `M	src/google/adk/runners.py`
- `M	src/google/adk/telemetry/_experimental_semconv.py`
- `M	src/google/adk/tools/mcp_tool/_agent_to_mcp.py`
- `M	src/google/adk/tools/mcp_tool/conversion_utils.py`
- `M	src/google/adk/tools/mcp_tool/mcp_session_manager.py`
- `M	src/google/adk/tools/mcp_tool/mcp_tool.py`
- `M	src/google/adk/tools/mcp_tool/mcp_toolset.py`
- `M	src/google/adk/tools/mcp_tool/session_context.py`
- `M	src/google/adk/tools/skill_toolset.py`
- `M	src/google/adk/version.py`
- `M	src/google/adk/workflow/_llm_agent_wrapper.py`
- `A	src/google/adk/workflow/_node_runner_utils.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	src/google/adk/workflow/utils/_replay_manager.py`
- `M	tests/unittests/a2a/utils/test_agent_card_builder.py`
- `M	tests/unittests/agents/test_agent_config.py`
- `M	tests/unittests/agents/test_invocation_context.py`
- `M	tests/unittests/agents/test_llm_agent_error_messages.py`
- `M	tests/unittests/agents/test_loop_agent.py`
- `M	tests/unittests/agents/test_output_key_visibility.py`
- `M	tests/unittests/artifacts/test_artifact_service.py`
- `M	tests/unittests/cli/test_trigger_routes.py`
- `M	tests/unittests/cli/utils/test_agent_loader.py`
- `M	tests/unittests/cli/utils/test_cli_deploy.py`
- `M	tests/unittests/cli/utils/test_cli_tools_click.py`
- `M	tests/unittests/environment/test_local_environment.py`
- `M	tests/unittests/flows/llm_flows/test_base_llm_flow.py`
- `M	tests/unittests/flows/llm_flows/test_base_llm_flow_realtime.py`
- `M	tests/unittests/flows/llm_flows/test_functions_simple.py`
- `M	tests/unittests/flows/llm_flows/test_live_model_callbacks.py`
- `M	tests/unittests/streaming/test_live_streaming_configs.py`
- `M	tests/unittests/streaming/test_live_tool_shutdown.py`
- `M	tests/unittests/streaming/test_multi_agent_streaming.py`
- `M	tests/unittests/streaming/test_streaming.py`
- `M	tests/unittests/streaming/test_streaming_tool_events.py`
- `M	tests/unittests/telemetry/test_experimental_semconv.py`
- `M	tests/unittests/test_runners.py`
- `M	tests/unittests/testing_utils.py`
- `A	tests/unittests/tools/mcp_tool/test_dependencies_mcp.py`
- `M	tests/unittests/tools/test_skill_toolset.py`
- `A	tests/unittests/workflow/test_node_runner_utils.py`
- `M	tests/unittests/workflow/test_workflow_live.py`
- `M	tests/unittests/workflow/testing_utils.py`
- `M	tests/unittests/workflow/utils/test_rehydration_utils.py`
- `M	tests/unittests/workflow/utils/test_replay_manager.py`
