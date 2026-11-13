# ADK Python Daily Change Report

- Date (UTC): 2026-11-13
- Source: `google/adk-python`
- Latest SHA: `12aab4aaaa1a72e3edcc65fa4f9d849896ea6c48`
- Previous SHA: `e5dd820da49433c73be1b1296c790f17ec3defa7`

## Summary

- New commits: 11

## Commits

- [12aab4aa](https://github.com/google/adk-python/commit/12aab4aaaa1a72e3edcc65fa4f9d849896ea6c48) fix: only create the agents file watcher when agent reload is enabled (Liang Wu, 2026-11-13)
- [1de97607](https://github.com/google/adk-python/commit/1de97607c86b18c0288bfe71257bad102ea74fb6) feat(telemetry): record the inference token metrics in every schema version (Google Team Member, 2026-11-13)
- [56b25c61](https://github.com/google/adk-python/commit/56b25c61953b382ac161f9fef3470d5fec52598e) fix(telemetry): use semconv units for invoke_agent call-count metrics (Google Team Member, 2026-11-13)
- [8d857f47](https://github.com/google/adk-python/commit/8d857f47d1da9b88398a4a6019115417b93a53f9) fix(telemetry): exclude tool runtime from model call duration without a recorded span (Google Team Member, 2026-11-13)
- [f67cc356](https://github.com/google/adk-python/commit/f67cc356cd31775a75f9a8e7aae30cc86b00bcf8) fix: do not promote a failed remote A2A task to workflow output (Ferran Pons Serra, 2026-11-13)
- [5112046c](https://github.com/google/adk-python/commit/5112046cba8add65900c2ca15337a57a689f68ec) fix: trace sub-agents by the model they inherit (Aditya Singh, 2026-11-13)
- [b6952874](https://github.com/google/adk-python/commit/b6952874ae58d5528bf758573a2f701eaae61643) fix: mask credential material in the telemetry serializer (Ido Gol, 2026-11-13)
- [5ce1d0c1](https://github.com/google/adk-python/commit/5ce1d0c15af9edef87692f43230bc5bc01103202) feat(plugins): isolate nested AgentTool state and add response_text_key (Haiyuan Cao, 2026-11-12)
- [1ae967e3](https://github.com/google/adk-python/commit/1ae967e33d077c2055e140f861f5280441d5d2f8) chore: merge release v2.14.1 to main (adk-bot, 2026-11-12)
- [1a0ddabf](https://github.com/google/adk-python/commit/1a0ddabf1b65d49bb814ac1c2b0c06af4a3a57a4) fix(live): yield finished tool responses when the live connection fails (Jason Zhang, 2026-11-12)
- [e237ec06](https://github.com/google/adk-python/commit/e237ec06c8bf2e54924af2fad35674bd726b82cc) test(live): cover long-running calls that return nothing (Jason Zhang, 2026-11-12)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	CHANGELOG.md`
- `M	docs/guides/plugins/bigquery_agent_analytics_eval_sql/index.md`
- `M	src/google/adk/a2a/agent/_remote_a2a_agent.py`
- `M	src/google/adk/agents/invocation_context.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/live/_live_llm_flow.py`
- `M	src/google/adk/plugins/auto_tracing_helpers.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_plugin.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_view_ctes_v1.sql`
- `M	src/google/adk/telemetry/_instrumentation.py`
- `M	src/google/adk/telemetry/_metrics.py`
- `M	src/google/adk/telemetry/_serialization.py`
- `M	src/google/adk/telemetry/_token_usage.py`
- `M	src/google/adk/telemetry/tracing.py`
- `M	src/google/adk/tools/agent_tool.py`
- `A	src/google/adk/utils/_credential_names.py`
- `M	src/google/adk/version.py`
- `M	tests/unittests/a2a/agent/test_remote_a2a_agent.py`
- `M	tests/unittests/agents/test_invocation_context.py`
- `M	tests/unittests/cli/test_adk_web_server_run_live.py`
- `M	tests/unittests/cli/test_cors_regex.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/flows/llm_flows/tools/test_live_caller.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_plugin.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_sql_sync.py`
- `M	tests/unittests/streaming/test_live_tool_shutdown.py`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-event-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-no-content-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-span-and-event-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-span-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-telemetry-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/grounding.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-resource-exhausted-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/stable-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/stable-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/no-experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/mcp/experimental-span-and-event.json`
- `M	tests/unittests/telemetry/functional_goldens/mcp/http-exchange.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/no-experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-event-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-no-content-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-span-and-event-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-span-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/stable-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/stable-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/invalid-skill-resource-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-resource-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-script-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-disabled-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-event-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-no-content-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-span-and-event-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-span-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/stable-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/stable-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/workflow_compaction/sliding-window-schema-v1.json`
- `M	tests/unittests/telemetry/test_instrumentation.py`
- `M	tests/unittests/telemetry/test_metrics.py`
- `M	tests/unittests/telemetry/test_serialization.py`
- `M	tests/unittests/telemetry/test_spans.py`
- `M	tests/unittests/tools/test_agent_tool.py`
