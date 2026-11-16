# ADK Python Daily Change Report

- Date (UTC): 2026-11-16
- Source: `google/adk-python`
- Latest SHA: `11d088b5597c258b3e787ce705e88828be40854d`
- Previous SHA: `d05e482038bdbb226c3a1179550cf83bd8fcbefb`

## Summary

- New commits: 14

## Commits

- [11d088b5](https://github.com/google/adk-python/commit/11d088b5597c258b3e787ce705e88828be40854d) docs(cli): document multimodal Content dict inputs for Agent Engine queries (Google Team Member, 2026-11-16)
- [f4fab788](https://github.com/google/adk-python/commit/f4fab78850d900009e27ae9b0e03ef664775fd77) feat(sessions): add BaseSessionService.append_events and batch buffered writes with it (Ayush Agrawal, 2026-11-16)
- [dbae28d3](https://github.com/google/adk-python/commit/dbae28d3ccd0958d202a85e2c39cdf249ae2c7f2) fix(a2a): persist streamed RemoteA2aAgent output without last_chunk (Ayush Pandey, 2026-11-16)
- [b64b540c](https://github.com/google/adk-python/commit/b64b540c18318ec25062cc32c582d9dea406e870) feat(eval): report each cross-run criterion's mean over the eval set (Google Team Member, 2026-11-16)
- [01b4b5a7](https://github.com/google/adk-python/commit/01b4b5a76eebddea389f319981853d81b1eb7c1e) fix(workflow): ignore a resume response schema of an unsupported shape (George Weale, 2026-11-16)
- [2b7e3209](https://github.com/google/adk-python/commit/2b7e3209890c85b0908cfff81080e9be49650581) fix: stop the multimodal plugin resending inline media in session mode (George Weale, 2026-11-16)
- [b7c9c40f](https://github.com/google/adk-python/commit/b7c9c40f855a91943297b63a2a45fad9a160d0d7) fix: stop get_session dropping events appended out of timestamp order (George Weale, 2026-11-16)
- [5e91ab0a](https://github.com/google/adk-python/commit/5e91ab0a5dcd0d2dc872c9cb8581a7a2afb18055) fix(cli): keep extra_packages before requirements and reinstall after (Google Team Member, 2026-11-16)
- [691ecbee](https://github.com/google/adk-python/commit/691ecbeedcb3da44690c773876ec662f27dc17e6) feat(environment): add `EnvironmentScope` and lock `initialize` per scope (Liang Wu, 2026-11-16)
- [e1deb17f](https://github.com/google/adk-python/commit/e1deb17f5274f49595caa703e41d9439563b8015) feat(sessions): add BufferedSessionService to write session events in the background (Ayush Agrawal, 2026-11-16)
- [f390bd99](https://github.com/google/adk-python/commit/f390bd99b0fb643f1a98bb4e491a765023677f66) fix(build): Set uv exclude-newer to 7 days in ADK pyproject.toml (Google Team Member, 2026-11-16)
- [dd14fa21](https://github.com/google/adk-python/commit/dd14fa21342be6c18b1d556ed6c3f41bc41bc3f2) docs: correct agent skill claims the code no longer supports (George Weale, 2026-11-16)
- [8ec642c1](https://github.com/google/adk-python/commit/8ec642c1298f498e36ea622a1f7aa584a9eaf53e) fix: drop parent_agent from BaseAgent's repr (Google Team Member, 2026-11-16)
- [c6586f19](https://github.com/google/adk-python/commit/c6586f19ab8a2bb8b53e70041633b10858d9902e) feat(features): enable DYNAMIC_INSTRUCTION_ROUTING by default (Yi Liu, 2026-11-15)

## Changed Files

- `M	.agents/skills/adk-agent-builder/SKILL.md`
- `M	.agents/skills/adk-agent-builder/references/advanced-patterns.md`
- `M	.agents/skills/adk-agent-builder/references/best-practices.md`
- `M	.agents/skills/adk-agent-builder/references/callbacks-and-plugins.md`
- `M	.agents/skills/adk-agent-builder/references/function-nodes.md`
- `M	.agents/skills/adk-agent-builder/references/getting-started.md`
- `M	.agents/skills/adk-agent-builder/references/human-in-the-loop.md`
- `M	.agents/skills/adk-agent-builder/references/import-paths.md`
- `M	.agents/skills/adk-agent-builder/references/llm-agent-nodes.md`
- `M	.agents/skills/adk-agent-builder/references/parallel-and-fanout.md`
- `M	.agents/skills/adk-agent-builder/references/routing-and-conditions.md`
- `M	.agents/skills/adk-agent-builder/references/session-and-state.md`
- `M	.agents/skills/adk-agent-builder/references/state-and-events.md`
- `M	.agents/skills/adk-agent-builder/references/task-mode.md`
- `M	.agents/skills/adk-agent-builder/references/testing.md`
- `M	.agents/skills/adk-architecture/SKILL.md`
- `M	.agents/skills/adk-architecture/references/architecture-checkpoint-resume.md`
- `M	.agents/skills/adk-architecture/references/architecture-context.md`
- `M	.agents/skills/adk-architecture/references/architecture-llm-context-orchestration.md`
- `M	.agents/skills/adk-architecture/references/architecture-observability.md`
- `M	.agents/skills/adk-architecture/references/architecture-runner-roles.md`
- `M	.agents/skills/adk-architecture/references/architecture-workflow-resumability.md`
- `M	.agents/skills/adk-architecture/references/interface-agent.md`
- `M	.agents/skills/adk-architecture/references/interface-base-agent.md`
- `M	.agents/skills/adk-architecture/references/interface-base-node.md`
- `M	.agents/skills/adk-architecture/references/interface-event.md`
- `M	.agents/skills/adk-debug/SKILL.md`
- `M	.agents/skills/adk-debug/references/cli-run.md`
- `M	.agents/skills/adk-debug/references/event-flow.md`
- `M	.agents/skills/adk-debug/references/logs-and-traces.md`
- `M	.agents/skills/adk-debug/references/web-api.md`
- `M	.agents/skills/adk-sample-creator/SKILL.md`
- `M	.agents/skills/adk-unit-guide/SKILL.md`
- `M	.agents/skills/adk-unit-guide/references/guide-template.md`
- `M	.agents/skills/adk-verify-snippets/SKILL.md`
- `M	.github/workflows/continuous-integration.yml`
- `M	.github/workflows/release-artifact-check.yml`
- `M	.github/workflows/release-publish.yml`
- `M	docs/guides/README.md`
- `M	docs/guides/environment/base_environment/index.md`
- `M	docs/guides/errors/index.md`
- `M	docs/guides/evaluation/eval_config/index.md`
- `A	docs/guides/sessions/buffered_session_service/index.md`
- `M	pyproject.toml`
- `M	src/google/adk/a2a/agent/_remote_a2a_agent.py`
- `M	src/google/adk/agents/base_agent.py`
- `M	src/google/adk/cli/cli_deploy.py`
- `M	src/google/adk/cli/cli_eval.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/cli/deployers/_dockerfile_template.py`
- `M	src/google/adk/environment/__init__.py`
- `M	src/google/adk/environment/_base_environment.py`
- `A	src/google/adk/environment/_environment_scope.py`
- `M	src/google/adk/errors/__init__.py`
- `A	src/google/adk/errors/_session_persistence_error.py`
- `M	src/google/adk/evaluation/_eval_case_result_multi_run_aggregator.py`
- `M	src/google/adk/features/_feature_registry.py`
- `M	src/google/adk/integrations/redis/_redis_session_service.py`
- `M	src/google/adk/plugins/multimodal_tool_results_plugin.py`
- `M	src/google/adk/sessions/__init__.py`
- `A	src/google/adk/sessions/_buffered_session_service.py`
- `A	src/google/adk/sessions/_session_write_buffer.py`
- `M	src/google/adk/sessions/base_session_service.py`
- `M	src/google/adk/sessions/in_memory_session_service.py`
- `M	src/google/adk/tools/environment/_utils.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	tests/unittests/a2a/agent/test_remote_a2a_agent.py`
- `M	tests/unittests/agents/test_base_agent.py`
- `M	tests/unittests/cli/utils/test_cli_deploy.py`
- `M	tests/unittests/cli/utils/test_cli_eval_pretty_print.py`
- `M	tests/unittests/cli/utils/test_cli_tools_click.py`
- `M	tests/unittests/environment/test_base_environment.py`
- `M	tests/unittests/evaluation/test_eval_case_result_multi_run_aggregator.py`
- `M	tests/unittests/plugins/test_multimodal_tool_results_plugin.py`
- `M	tests/unittests/sessions/_conformance.py`
- `A	tests/unittests/sessions/test_buffered_session_service.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `M	tests/unittests/tools/environment/test_environment_utils.py`
- `M	tests/unittests/tools/test_environment_toolset.py`
- `M	tests/unittests/workflow/utils/test_rehydration_utils.py`
