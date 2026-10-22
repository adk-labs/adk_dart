# ADK Python Daily Change Report

- Date (UTC): 2026-10-22
- Source: `google/adk-python`
- Latest SHA: `471341f28d23a57c6f15d74c83cd3fc3300fdc3d`
- Previous SHA: `59dc13457c2001094086b972022b485a56bcff9c`

## Summary

- New commits: 17

## Commits

- [471341f2](https://github.com/google/adk-python/commit/471341f28d23a57c6f15d74c83cd3fc3300fdc3d) fix(runner): close isolated runs that end on a terminal node outcome (Shangjie Chen, 2026-10-22)
- [facd7dda](https://github.com/google/adk-python/commit/facd7ddafe0e23715e079e50971ad27b251e2e98) fix: close inner async generators across node `_run_impl` and skip compaction on early close (Google Team Member, 2026-10-22)
- [92dfe41e](https://github.com/google/adk-python/commit/92dfe41e8db5ce248d7141498662787990f8e508) fix: stub ADC in modules that imported google.auth.default by name (Google Team Member, 2026-10-22)
- [636a8e3d](https://github.com/google/adk-python/commit/636a8e3d7d44f7c6f26f42dc2ffaa6d54964e503) test(workflow): cover what a node retry replays (Thomas Zettl, 2026-10-22)
- [b84e0a0a](https://github.com/google/adk-python/commit/b84e0a0a394fea73144408eb649efb06df74791f) fix: require authlib 1.9.1 or newer for CVE fixes (Google Team Member, 2026-10-22)
- [bd385358](https://github.com/google/adk-python/commit/bd38535817a9639408a5f863c0f044aaa65d74cb) fix: classify stream-level non-retryable BigQuery write errors as non_retryable (Google Team Member, 2026-10-21)
- [8d7445d9](https://github.com/google/adk-python/commit/8d7445d99d9404f68805a7cb72b848a795c30bc1) fix(runner): key finished isolation scopes by invocation id (Shangjie Chen, 2026-10-21)
- [d3247446](https://github.com/google/adk-python/commit/d324744645ee372db8ecce4c0209e9c70ce18e0b) fix(auth): support raw token strings in HTTP and API key auth resume (Yuhan Gao, 2026-10-21)
- [b01c5fff](https://github.com/google/adk-python/commit/b01c5fff5378fed116b6978cb9293909e3c4a5e0) feat: expose session rewind as a REST endpoint (chelsealong, 2026-10-21)
- [55a6fe5f](https://github.com/google/adk-python/commit/55a6fe5f3d40734bab219d5a5032e19c3d0f5326) fix: cap litellm below 1.106.3 END_PUBLIC Installing google-adk[extensions] while the compromised litellm 1.107.0 was on PyPI pulled in its credential stealer, because the extras accepted any litellm release from 1.84 up, and LiteLLM has not yet ruled out further access to its release accounts. This bounds litellm below 1.106.3 in the all, extensions and test extras, which today keeps users on 1.106.2, the release LiteLLM tells users to pin to. (George Weale, 2026-10-21)
- [caf828df](https://github.com/google/adk-python/commit/caf828df5ef9e6322826ad4fe0dd0d2dce552a64) feat(integrations): keep MongoDB credentials out of Agent Engine packages (Venkatesh Shanbhag, 2026-10-21)
- [c8d0aa51](https://github.com/google/adk-python/commit/c8d0aa51ccba8e8e22a5bc3d525b06c06179b7a2) refactor: remove the Gemini._merge_tracking_headers wrapper (Liang Wu, 2026-10-21)
- [17fb8afc](https://github.com/google/adk-python/commit/17fb8afc15a7cd8f33d82328d65b8e0e47436739) fix: reap ADK sessions of dead MCP connections in to_mcp_server (harshal-96, 2026-10-21)
- [47e613d8](https://github.com/google/adk-python/commit/47e613d84769d2e4f84bf5f4be7ecb81fe1996a7) fix: point litellm install hints at google-adk[extensions] (George Weale, 2026-10-21)
- [5762ef81](https://github.com/google/adk-python/commit/5762ef81f2f7a11bce064491e86d6f5e3cf3ea88) feat(plugins): support conversation_only eval view mode and session prompt fallback (Haiyuan Cao, 2026-10-21)
- [ed76f945](https://github.com/google/adk-python/commit/ed76f94501f0e4dad9346e064980c1059bded1a7) feat(tools): add extensible tool argument matcher (Yi Liu, 2026-10-21)
- [d2ae9016](https://github.com/google/adk-python/commit/d2ae9016a6a63e073dea129e647553c04cf09864) fix: present the mTLS client certificate from RemoteA2aAgent's default client (Kathy Wu, 2026-10-21)

## Changed Files

- `M	.agents/skills/adk-architecture/references/architecture-node-runner.md`
- `M	constraints-3.11.txt`
- `M	constraints-3.12.txt`
- `M	constraints-3.13.txt`
- `M	constraints-3.14.txt`
- `M	constraints-3.15.txt`
- `M	contributing/samples/integrations/gepa/README.md`
- `M	contributing/samples/integrations/gepa/gepa_tau_bench.ipynb`
- `M	contributing/samples/integrations/gepa/voter_agent/gepa.ipynb`
- `M	contributing/samples/mcp/mcp_server_side_sampling/README.md`
- `M	contributing/samples/models/hello_world_nvidia/README.md`
- `M	docs/guides/README.md`
- `M	docs/guides/integrations/mongodb/mongodb_toolset/index.md`
- `A	docs/guides/tools/tool_args_matcher/tool_args_matcher/index.md`
- `M	docs/guides/workflow/retry_config/index.md`
- `M	pyproject.toml`
- `M	src/google/adk/a2a/agent/_remote_a2a_agent.py`
- `M	src/google/adk/agents/_managed_agent.py`
- `M	src/google/adk/agents/base_agent.py`
- `M	src/google/adk/auth/_auth_resume.py`
- `M	src/google/adk/auth/auth_handler.py`
- `M	src/google/adk/cli/api_server.py`
- `A	src/google/adk/events/_isolation_scope.py`
- `M	src/google/adk/features/_feature_registry.py`
- `M	src/google/adk/integrations/mongodb/README.md`
- `M	src/google/adk/integrations/mongodb/_client.py`
- `M	src/google/adk/integrations/mongodb/_mongodb_toolset.py`
- `M	src/google/adk/labs/antigravity/_antigravity_agent.py`
- `M	src/google/adk/models/apigee_llm.py`
- `M	src/google/adk/models/google_llm.py`
- `M	src/google/adk/models/registry.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_plugin.py`
- `M	src/google/adk/runners.py`
- `M	src/google/adk/tools/mcp_tool/_agent_to_mcp.py`
- `M	src/google/adk/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.py`
- `A	src/google/adk/tools/tool_args_matcher/__init__.py`
- `A	src/google/adk/tools/tool_args_matcher/_tool_args_matcher.py`
- `M	src/google/adk/workflow/_base_node.py`
- `M	src/google/adk/workflow/_node.py`
- `M	src/google/adk/workflow/_node_runner_utils.py`
- `M	src/google/adk/workflow/utils/_workflow_hitl_utils.py`
- `M	tests/unittests/a2a/agent/test_remote_a2a_agent.py`
- `M	tests/unittests/agents/test_base_agent.py`
- `M	tests/unittests/agents/test_managed_agent.py`
- `M	tests/unittests/auth/test_auth_handler.py`
- `M	tests/unittests/auth/test_auth_resume.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/integrations/mongodb/test_mongodb_toolset.py`
- `M	tests/unittests/labs/antigravity/test_antigravity_agent.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_plugin.py`
- `M	tests/unittests/test_runners.py`
- `M	tests/unittests/test_samples.py`
- `M	tests/unittests/tools/mcp_tool/test_agent_to_mcp.py`
- `M	tests/unittests/tools/openapi_tool/openapi_spec_parser/test_tool_auth_handler.py`
- `A	tests/unittests/tools/tool_args_matcher/__init__.py`
- `A	tests/unittests/tools/tool_args_matcher/test_tool_args_matcher.py`
- `M	tests/unittests/workflow/test_node_runner_failure.py`
- `M	tests/unittests/workflow/test_node_runner_utils.py`
- `M	tests/unittests/workflow/test_tool_node.py`
- `M	tests/unittests/workflow/test_workflow_dynamic_nodes.py`
- `M	tests/unittests/workflow/test_workflow_node.py`
- `M	tests/unittests/workflow/test_workflow_routes.py`
- `M	tests/unittests/workflow/utils/test_rehydration_utils.py`
- `M	tests/unittests/workflow/utils/test_workflow_hitl_utils.py`
