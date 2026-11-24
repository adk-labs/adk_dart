# ADK Python Daily Change Report

- Date (UTC): 2026-11-24
- Source: `google/adk-python`
- Latest SHA: `825a44c5dfb72cd14d5d037a8f42a27c7bf62292`
- Previous SHA: `84cb0742bcd5921efc585dff7c1ae86063702f81`

## Summary

- New commits: 6

## Commits

- [825a44c5](https://github.com/google/adk-python/commit/825a44c5dfb72cd14d5d037a8f42a27c7bf62292) perf(telemetry): skip serializing request history when content capture is off (Afonso Ribeiro, 2026-11-24)
- [50961696](https://github.com/google/adk-python/commit/50961696a49750c1bff354c9406c455778c2a166) fix(a2a): propagate CancelledError raised inside runner.run_async (Google Team Member, 2026-11-24)
- [1c384506](https://github.com/google/adk-python/commit/1c384506e08bb808f3eab2d82f6c26f2d65b773e) fix(models): handle Claude sampling settings on anthropic 1.x and 2.x (George Weale, 2026-11-24)
- [8d064dc9](https://github.com/google/adk-python/commit/8d064dc91612805805fd8e2e281c8b86f503e37f) feat(telemetry): record gen_ai.client.inference.duration (Google Team Member, 2026-11-24)
- [e3dbdc17](https://github.com/google/adk-python/commit/e3dbdc1726bed0bfc3d2e3f335fc7c0dcdf6b9c5) fix(plugins): keep secret_key and passwd args out of tracing spans (John B Joseph, 2026-11-24)
- [54fc37e5](https://github.com/google/adk-python/commit/54fc37e5fab77f2cfc02fd02f8e6019d288d3920) chore(features): reject new imports of google.adk.a2a.experimental (Xuan Yang, 2026-11-23)

## Changed Files

- `M	docs/guides/features/feature_registry/index.md`
- `M	scripts/compliance_checks.py`
- `M	src/google/adk/a2a/executor/utils.py`
- `M	src/google/adk/models/anthropic_llm.py`
- `M	src/google/adk/telemetry/_experimental_semconv.py`
- `M	src/google/adk/telemetry/_instrumentation.py`
- `M	src/google/adk/telemetry/_metrics.py`
- `M	src/google/adk/telemetry/tracing.py`
- `M	src/google/adk/utils/_credential_names.py`
- `M	tests/unittests/a2a/executor/test_a2a_agent_executor.py`
- `M	tests/unittests/a2a/executor/test_a2a_agent_executor_impl.py`
- `M	tests/unittests/models/test_anthropic_llm.py`
- `M	tests/unittests/plugins/test_auto_tracing_plugin.py`
- `M	tests/unittests/scripts/test_compliance_checks.py`
- `M	tests/unittests/telemetry/functional/scenarios/telemetry_setup.py`
- `M	tests/unittests/telemetry/functional_divergences.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-event-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-event-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-no-content-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-no-content-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-span-and-event-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-span-and-event-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-span-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-span-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-telemetry-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-telemetry-no-capture-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/grounding.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-resource-exhausted-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-resource-exhausted-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-valueerror-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-valueerror-span-and-event-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/stable-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/stable-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/tool-error-valueerror-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/tool-error-valueerror-span-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/no-experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/no-experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/no-experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/sliding-window-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/token-threshold-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/untriggered-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/mcp/experimental-span-and-event.json`
- `M	tests/unittests/telemetry/functional_goldens/mcp/http-exchange.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/no-experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/no-experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/nested_agents_in_workflow/experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/nested_agents_in_workflow/no-experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-event-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-event-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-no-content-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-no-content-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-span-and-event-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-span-and-event-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-span-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/experimental-span-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/node/stable-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/node/stable-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/invalid-skill-resource-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/invalid-skill-resource-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/invalid-skill-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-resource-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-resource-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-script-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-script-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-disabled-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-disabled-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-event-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-event-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-no-content-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-no-content-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-span-and-event-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-span-and-event-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-span-only-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/experimental-span-only-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/stable-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/streaming/stable-no-capture-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/workflow_compaction/sliding-window-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/workflow_compaction/sliding-window-schema-v2.json`
- `M	tests/unittests/telemetry/test_experimental_semconv.py`
- `M	tests/unittests/telemetry/test_semconv_conformance.py`
- `M	tests/unittests/telemetry/test_serialization.py`
