# ADK Python Daily Change Report

- Date (UTC): 2026-10-31
- Source: `google/adk-python`
- Latest SHA: `8cd3b12c8a5d658c5e0d3ea0731d8be34a092a4a`
- Previous SHA: `968cd869ff79be622eb921c5e314bd19efd889d2`

## Summary

- New commits: 23

## Commits

- [8cd3b12c](https://github.com/google/adk-python/commit/8cd3b12c8a5d658c5e0d3ea0731d8be34a092a4a) fix(eval): preserve live usage without extra inference calls (JasonH, 2026-10-30)
- [af371b72](https://github.com/google/adk-python/commit/af371b7236c87bad36957e5f691b350c513e6bb2) fix: keep thought parts out of FirestoreMemoryService (Aditya Singh, 2026-10-30)
- [e9e8f615](https://github.com/google/adk-python/commit/e9e8f6156fb73cdfe799af0a0a57786e807732df) feat: support configuring eval case parallelism in eval config and CLI (Rafael Ladeira, 2026-10-30)
- [db604322](https://github.com/google/adk-python/commit/db60432275b8db9e41e0935d87d1b40b4c623675) fix(scripts): accept a shared guide page documenting a module's exports (Yuhan Gao, 2026-10-30)
- [81c3fe64](https://github.com/google/adk-python/commit/81c3fe649232f79b03f5663da90d4434ddeb8073) fix: decode base64 bytes in rehydrated workflow node outputs (ninglinLiu, 2026-10-30)
- [cddc57f6](https://github.com/google/adk-python/commit/cddc57f63db9aa8e8048184b647c62f9800063f3) refactor(workflow): unify static node loop bookkeeping onto DynamicNodeRun (Shangjie Chen, 2026-10-30)
- [3a6b7a51](https://github.com/google/adk-python/commit/3a6b7a51da72cdffa9d0611dced7446fc49240dd) fix: keep partial events out of Agent Engine storage (Aditya Singh, 2026-10-30)
- [28d49753](https://github.com/google/adk-python/commit/28d49753845ad0ed0d024cdeb7f738b6ff1446e0) fix: send the request's headers when loading MCP resources (Aditya Singh, 2026-10-30)
- [72205cd3](https://github.com/google/adk-python/commit/72205cd3ee52ed4ab49359cc951f2283e3d35191) fix: mark failed MCP tool results as errors on the interactions API (Aditya Singh, 2026-10-30)
- [3a5bbd2f](https://github.com/google/adk-python/commit/3a5bbd2f593c3785eff9b9855054744df0b64db8) fix: normalize array-tail schema types (Jeeho Lee, 2026-10-30)
- [611b8e7c](https://github.com/google/adk-python/commit/611b8e7cc22008146c9e23587a81580424410477) fix: prevent file truncation on invalid write_file content (Arjun Ganesh, 2026-10-30)
- [e5b7dc8c](https://github.com/google/adk-python/commit/e5b7dc8c68c64a093363cc195ce27304a8efe904) fix: read Workflow.graph when drawing the dev UI graph (Md Khairul Islam, 2026-10-30)
- [50ab3b5e](https://github.com/google/adk-python/commit/50ab3b5e9708900e2153d448647dc69b6164285f) fix(live): drop saved audio from history replayed to the CascadeLive reasoner (Liang Wu, 2026-10-30)
- [ce4e0c40](https://github.com/google/adk-python/commit/ce4e0c40772e8d460d6b727c3bdf56efe7ac779b) fix: preserve union arguments when exporting MCP tool schemas (Ytq1115, 2026-10-30)
- [73b6790b](https://github.com/google/adk-python/commit/73b6790b2688c27330eecd18b590157c0704ee58) fix: use set_model_response for output_schema agents that can transfer (Somay-kousis, 2026-10-30)
- [e3d1594d](https://github.com/google/adk-python/commit/e3d1594d04f8ae88921fadae4bc8f16bcb698d0b) fix: preserve non-UTF-8 bytes in EditFileTool (1wos, 2026-10-30)
- [0af1cdce](https://github.com/google/adk-python/commit/0af1cdce3b1a92d0067c66f43fb9a4fd217ec73a) fix: preserve split Unicode surrogate pairs (BichengWang, 2026-10-30)
- [e4a824f2](https://github.com/google/adk-python/commit/e4a824f24b5fd25b929419a6dfe3f871cafd61c6) fix(live): make CascadeLive reply to history that ends with a user turn (Liang Wu, 2026-10-30)
- [875e2aef](https://github.com/google/adk-python/commit/875e2aef7e800ca307fcff85b68e54d6101ba63c) feat: add a2a agent card generation with the CLI (guillaume blaquiere, 2026-10-30)
- [da98d4d6](https://github.com/google/adk-python/commit/da98d4d641b673369ef96ee94424459083dd7703) fix: report unreadable SKILL.md files to on_error (Mihir Inamdar, 2026-10-30)
- [f6325bc2](https://github.com/google/adk-python/commit/f6325bc2251302db26f3e5aa6dd8e4d439ea5d75) fix: send a JSON-safe state_delta from VertexAiSessionService (Aditya Singh, 2026-10-30)
- [a9cabe72](https://github.com/google/adk-python/commit/a9cabe7269b9d63feb812b3051d2a6eda89ce85f) fix: keep the streamed thought signature on its own part (Atul Joshi, 2026-10-30)
- [2a0bffa1](https://github.com/google/adk-python/commit/2a0bffa1258dd3b806acb6368acc8f5d29868474) fix: allow whole-file reads of empty files in ReadFileTool (Mu-ty831, 2026-10-30)

## Changed Files

- `M	.agents/skills/adk-architecture/references/interface-workflow.md`
- `M	.agents/skills/adk-unit-guide/SKILL.md`
- `M	docs/guides/evaluation/agent_evaluator/index.md`
- `M	docs/guides/evaluation/eval_config/index.md`
- `M	scripts/check_new_py_files.py`
- `A	src/google/adk/cli/_cli_generate_agent_card.py`
- `M	src/google/adk/cli/agent_graph.py`
- `M	src/google/adk/cli/cli_eval.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/environment/_local_environment.py`
- `M	src/google/adk/evaluation/agent_evaluator.py`
- `M	src/google/adk/evaluation/eval_config.py`
- `M	src/google/adk/evaluation/evaluation_generator.py`
- `M	src/google/adk/flows/llm_flows/basic.py`
- `M	src/google/adk/flows/llm_flows/prompt/_schema.py`
- `M	src/google/adk/integrations/firestore/firestore_memory_service.py`
- `M	src/google/adk/live/_cascade_live_connection.py`
- `M	src/google/adk/live/_runner_utils.py`
- `M	src/google/adk/models/gemini_llm_connection.py`
- `M	src/google/adk/models/interactions_utils.py`
- `M	src/google/adk/sessions/vertex_ai_session_service.py`
- `M	src/google/adk/skills/_utils.py`
- `M	src/google/adk/tools/environment/_edit_file_tool.py`
- `M	src/google/adk/tools/environment/_read_file_tool.py`
- `M	src/google/adk/tools/load_mcp_resource_tool.py`
- `M	src/google/adk/tools/mcp_tool/conversion_utils.py`
- `M	src/google/adk/utils/_schema_utils.py`
- `M	src/google/adk/utils/content_utils.py`
- `M	src/google/adk/utils/streaming_utils.py`
- `M	src/google/adk/workflow/_dynamic_node_scheduler.py`
- `M	src/google/adk/workflow/_node_runner_utils.py`
- `M	src/google/adk/workflow/_workflow.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	tests/unittests/cli/test_agent_graph.py`
- `A	tests/unittests/cli/test_cli_generate_agent_card.py`
- `M	tests/unittests/cli/utils/test_cli_tools_click.py`
- `M	tests/unittests/environment/test_local_environment.py`
- `M	tests/unittests/evaluation/test_agent_evaluator.py`
- `M	tests/unittests/evaluation/test_eval_config.py`
- `M	tests/unittests/evaluation/test_evaluation_generator.py`
- `M	tests/unittests/flows/llm_flows/prompt/test_schema.py`
- `M	tests/unittests/integrations/firestore/test_firestore_memory_service.py`
- `M	tests/unittests/live/test_cascade_live_connection.py`
- `A	tests/unittests/live/test_cascade_live_workflow.py`
- `M	tests/unittests/models/test_anthropic_llm.py`
- `M	tests/unittests/models/test_interactions_utils.py`
- `M	tests/unittests/scripts/test_check_new_py_files.py`
- `M	tests/unittests/sessions/test_vertex_ai_session_service.py`
- `M	tests/unittests/skills/test__utils.py`
- `M	tests/unittests/tools/environment/test_edit_file_tool.py`
- `M	tests/unittests/tools/environment/test_read_file_tool.py`
- `M	tests/unittests/tools/mcp_tool/test_conversion_utils.py`
- `M	tests/unittests/tools/test_load_mcp_resource_tool.py`
- `M	tests/unittests/utils/test_content_utils.py`
- `M	tests/unittests/utils/test_streaming_utils.py`
- `M	tests/unittests/workflow/test_workflow.py`
- `M	tests/unittests/workflow/test_workflow_bytes.py`
- `M	tests/unittests/workflow/test_workflow_failures.py`
