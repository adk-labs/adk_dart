# ADK Python Daily Change Report

- Date (UTC): 2026-10-15
- Source: `google/adk-python`
- Latest SHA: `31398554885485f92bd918f35f90b9810f3ffed1`
- Previous SHA: `156f007ce1899bf0116eb990ce448be8ac1b3308`

## Summary

- New commits: 12

## Commits

- [31398554](https://github.com/google/adk-python/commit/31398554885485f92bd918f35f90b9810f3ffed1) fix(integrations): use the mTLS Model Armor endpoint when mTLS is enabled (Jason Zhang, 2026-10-15)
- [0491606e](https://github.com/google/adk-python/commit/0491606e42f56565aa6091f6aefa4cedd006476c) fix(features): fail fast when feature decorators are misused (Xuan Yang, 2026-10-15)
- [019387c6](https://github.com/google/adk-python/commit/019387c62d706375059376156c355f20e0c735c2) fix: record artifact_delta from before and after agent callbacks (Akshay Shah, 2026-10-15)
- [456d2cb9](https://github.com/google/adk-python/commit/456d2cb9ef1ac2c20842c60c97cf9079eb8adf33) fix(spanner): validate the database id used in the create statement (George Weale, 2026-10-15)
- [4211b238](https://github.com/google/adk-python/commit/4211b238aad18576bd87dc7d14b4f95092718d70) test: pin that a rerun_on_resume node reruns on its first answer (George Weale, 2026-10-15)
- [2416f660](https://github.com/google/adk-python/commit/2416f660b15fbb6b8e8d92c76eef76d6de69963e) fix: find stored words with a capital dotted I in sqlite memory (Somay-kousis, 2026-10-15)
- [74d0eff8](https://github.com/google/adk-python/commit/74d0eff89391746464997b6eb1ca5cb3d44ca670) fix: keep every tool call in a finish-bearing stream chunk (Aamir Ahmed, 2026-10-15)
- [b60b44ff](https://github.com/google/adk-python/commit/b60b44ff2a2ab843cabb4804bfc5492926953352) fix: serve dev UI behind prefix-stripping proxies (Nitish Reddy, 2026-10-15)
- [7d6637c5](https://github.com/google/adk-python/commit/7d6637c536f3e4343c904f64b4d8bd2c8331ce7a) fix: return 404 when adding a session to a missing eval set (Ankit Kumar, 2026-10-15)
- [3c8c63e4](https://github.com/google/adk-python/commit/3c8c63e41b3efca99e20b0b06804ed6b69b1dbf1) feat: seed adk web sessions from initial_state.json (Bicheng Wang, 2026-10-15)
- [23bc0bb7](https://github.com/google/adk-python/commit/23bc0bb79d2d9b5b8657562cee00a63afdbef38a) fix: send adk run queries as messages after a pause is answered (Jinzhengxu, 2026-10-15)
- [d01d5d84](https://github.com/google/adk-python/commit/d01d5d840832df35d536dcf154dc2575348ca5cc) feat(telemetry): count conversation compactions per workflow (Artur Gajowniczek, 2026-10-15)

## Changed Files

- `M	docs/guides/features/feature_registry/index.md`
- `M	docs/guides/workflow/base_node/index.md`
- `M	scripts/compliance_checks.py`
- `M	src/google/adk/agents/base_agent.py`
- `M	src/google/adk/apps/compaction.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/cli/cli.py`
- `M	src/google/adk/cli/dev_server.py`
- `M	src/google/adk/features/_feature_decorator.py`
- `M	src/google/adk/features/_feature_registry.py`
- `M	src/google/adk/integrations/model_armor/_plugin.py`
- `M	src/google/adk/memory/_sqlite_memory_service.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/runners.py`
- `M	src/google/adk/telemetry/_instrumentation.py`
- `M	src/google/adk/telemetry/_metrics.py`
- `M	src/google/adk/telemetry/_schema_version.py`
- `M	src/google/adk/telemetry/context.py`
- `M	src/google/adk/telemetry/node_tracing.py`
- `M	src/google/adk/tools/spanner/admin_tool.py`
- `M	src/google/adk/utils/feature_decorator.py`
- `M	src/google/adk/workflow/_base_node.py`
- `M	src/google/adk/workflow/_node_runner_utils.py`
- `M	tests/unittests/agents/test_base_agent.py`
- `M	tests/unittests/apps/test_compaction.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/cli/utils/test_cli_tools_click.py`
- `M	tests/unittests/features/test_feature_decorator.py`
- `M	tests/unittests/integrations/model_armor/test_model_armor_plugin.py`
- `M	tests/unittests/memory/test_sqlite_memory_service.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/scripts/test_compliance_checks.py`
- `M	tests/unittests/telemetry/functional/_digests.py`
- `M	tests/unittests/telemetry/functional/_recording.py`
- `M	tests/unittests/telemetry/functional/scenarios/__init__.py`
- `A	tests/unittests/telemetry/functional/scenarios/compaction.py`
- `M	tests/unittests/telemetry/functional/scenarios/telemetry_setup.py`
- `M	tests/unittests/telemetry/functional_divergences.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/experimental-telemetry-stable-no-capture-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/experimental-telemetry-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent_tool/experimental-telemetry-schema-v2.json`
- `A	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/no-experimental-telemetry-schema-v2.json`
- `A	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/sliding-window-schema-v2.json`
- `A	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/token-threshold-schema-v2.json`
- `A	tests/unittests/telemetry/functional_goldens/conversational_agent_compaction/untriggered-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/multi_agent/experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/nested_agents_in_workflow/experimental-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/invalid-skill-resource-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/invalid-skill-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-resource-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-script-telemetry-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/skill/skill-telemetry-schema-v2.json`
- `A	tests/unittests/telemetry/functional_goldens/workflow_compaction/sliding-window-schema-v1.json`
- `A	tests/unittests/telemetry/functional_goldens/workflow_compaction/sliding-window-schema-v2.json`
- `M	tests/unittests/telemetry/functional_test_cases.py`
- `M	tests/unittests/telemetry/test_instrumentation.py`
- `M	tests/unittests/telemetry/test_metrics.py`
- `M	tests/unittests/telemetry/test_semconv_conformance.py`
- `M	tests/unittests/tools/spanner/test_admin_tool.py`
- `M	tests/unittests/utils/test_feature_decorator.py`
- `M	tests/unittests/workflow/test_workflow_hitl.py`
