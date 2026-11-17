# ADK Python Daily Change Report

- Date (UTC): 2026-11-17
- Source: `google/adk-python`
- Latest SHA: `889ddd3134df1dd1a626205ee78811950dec2a5c`
- Previous SHA: `11d088b5597c258b3e787ce705e88828be40854d`

## Summary

- New commits: 15

## Commits

- [889ddd31](https://github.com/google/adk-python/commit/889ddd3134df1dd1a626205ee78811950dec2a5c) fix!: stop MCP servers from reading session state through prompt arguments (George Weale, 2026-11-17)
- [13b6ae89](https://github.com/google/adk-python/commit/13b6ae89cc2d8a55388bc638b97c8ec03bd80401) fix: repair the model samples that fail on their first turn (George Weale, 2026-11-17)
- [94952c52](https://github.com/google/adk-python/commit/94952c524fd4dd2a70f7ef843f3ed7badbbece35) test: catch resume bugs that in-memory sessions hide (George Weale, 2026-11-17)
- [c16dac70](https://github.com/google/adk-python/commit/c16dac705b9dcd38acca627458b22858484efd26) fix: only pip install extra_packages folders that declare a project (George Weale, 2026-11-17)
- [5f2f2279](https://github.com/google/adk-python/commit/5f2f2279c9a29c473efb4dec151ba4b53e841cd9) fix(skills): stop writing skills into the environment while a request is built (Liang Wu, 2026-11-17)
- [6959bac7](https://github.com/google/adk-python/commit/6959bac7bf254b35e35e13bc4809350c87f732ea) fix: accept content lists in Interactions code execution results (George Weale, 2026-11-17)
- [d94b5e21](https://github.com/google/adk-python/commit/d94b5e214c435a0d05ca090e9c83c7462761cb87) fix(skills): refresh a stale skill copy in the environment when its script runs (Liang Wu, 2026-11-17)
- [ba774bcc](https://github.com/google/adk-python/commit/ba774bcc3341a0573a4dd84ad379aaabffecd135) fix(cli): log the redacted payload /run returns (George Weale, 2026-11-17)
- [1ade0ba6](https://github.com/google/adk-python/commit/1ade0ba68cffb497d03de6b103f861f72d41798d) fix: pass each adk deploy --allow_origins as its own server argument (George Weale, 2026-11-17)
- [4da8071f](https://github.com/google/adk-python/commit/4da8071faca2bad8e9a1355bbf815d493f4476f7) fix: keep daytona on the 0.x SDK DaytonaEnvironment uses (Mislav Ivanda, 2026-11-17)
- [3256db08](https://github.com/google/adk-python/commit/3256db08ca547fb928326108b9e8df89ea196585) feat: attach agent cached_content seed on initial turn (Hugues Lys, 2026-11-17)
- [761538ab](https://github.com/google/adk-python/commit/761538ab2b8111688995a8108059c4606e4e13f7) fix(live): send tracking headers on live sessions through caller-supplied clients (Google Team Member, 2026-11-17)
- [90c3a294](https://github.com/google/adk-python/commit/90c3a29412d33e4221fa998600d763173eee6349) refactor(artifacts): move FsspecArtifactService backend-specific I/O into per-backend adapters (Google Team Member, 2026-11-16)
- [abcc0205](https://github.com/google/adk-python/commit/abcc0205bcacc13c6163952903e2b0b20300ed09) feat: add CheckGroundingClient for grounding verification (Google Team Member, 2026-11-16)
- [3e6c5868](https://github.com/google/adk-python/commit/3e6c5868f53bd483a50bc3337af282a3652640f7) fix(cli): require a local client for the telemetry consent write (George Weale, 2026-11-16)

## Changed Files

- `M	constraints-3.11.txt`
- `M	constraints-3.12.txt`
- `M	constraints-3.13.txt`
- `M	constraints-3.14.txt`
- `M	constraints-3.15.txt`
- `M	contributing/samples/models/hello_world_apigeellm/main.py`
- `M	contributing/samples/models/hello_world_gemma/agent.py`
- `M	contributing/samples/models/hello_world_litellm/agent.py`
- `M	contributing/samples/models/hello_world_litellm_add_function_to_prompt/agent.py`
- `M	contributing/samples/models/interactions_api/README.md`
- `M	contributing/samples/models/interactions_api/main.py`
- `M	contributing/samples/models/litellm_inline_tool_call/agent.py`
- `M	contributing/samples/models/litellm_structured_output/agent.py`
- `M	contributing/samples/models/litellm_with_fallback_models/agent.py`
- `M	pyproject.toml`
- `M	src/google/adk/agents/context_cache_config.py`
- `M	src/google/adk/agents/llm_agent.py`
- `M	src/google/adk/agents/mcp_instruction_provider.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/cli/cli_deploy.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/cli/deployers/_dockerfile_template.py`
- `M	src/google/adk/cli/dev_server.py`
- `M	src/google/adk/features/_feature_registry.py`
- `A	src/google/adk/integrations/discovery_engine/__init__.py`
- `A	src/google/adk/integrations/discovery_engine/_check_grounding_client.py`
- `A	src/google/adk/integrations/discovery_engine/_types.py`
- `A	src/google/adk/integrations/fsspec/_backends.py`
- `M	src/google/adk/integrations/fsspec/_fsspec_artifact_service.py`
- `M	src/google/adk/models/cache_metadata.py`
- `M	src/google/adk/models/gemini_context_cache_manager.py`
- `M	src/google/adk/models/google_llm.py`
- `M	src/google/adk/models/interactions_utils.py`
- `M	src/google/adk/tools/skill_toolset.py`
- `M	tests/unittests/agents/test_gemini_context_cache_manager.py`
- `M	tests/unittests/agents/test_mcp_instruction_provider.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/cli/utils/test_cli_deploy.py`
- `M	tests/unittests/cli/utils/test_cli_deploy_to_cloud_run.py`
- `A	tests/unittests/integrations/discovery_engine/test_check_grounding_client.py`
- `M	tests/unittests/integrations/fsspec/test_fsspec_artifact_service.py`
- `M	tests/unittests/models/test_google_llm.py`
- `M	tests/unittests/models/test_interactions_utils.py`
- `M	tests/unittests/sessions/_conformance.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `A	tests/unittests/sessions/test_session_service_resume.py`
- `M	tests/unittests/tools/test_skill_toolset.py`
