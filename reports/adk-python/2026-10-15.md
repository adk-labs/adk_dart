# ADK Python Daily Change Report

- Date (UTC): 2026-10-15
- Source: `google/adk-python`
- Latest SHA: `156f007ce1899bf0116eb990ce448be8ac1b3308`
- Previous SHA: `fb447108ab4dd1d4c1ed7e1ffde60ea3b4dd55f2`

## Summary

- New commits: 17

## Commits

- [156f007ce](https://github.com/google/adk-python/commit/156f007ce1899bf0116eb990ce448be8ac1b3308) refactor(workflow): deduplicate callable invocation, parameter resolution, and HITL helpers (Shangjie Chen, 2026-10-15)
- [9a5510e09](https://github.com/google/adk-python/commit/9a5510e09b788d114cedfb07119a0c9cd4cc527b) fix: surface HITL pauses in AgentTool instead of returning "" (chelsealong, 2026-10-14)
- [2f6c6664a](https://github.com/google/adk-python/commit/2f6c6664a8d3cdf9151ac585bcfe6cb2c0f78d52) feat: make MongoDbToolset picklable for Agent Engine (Venkatesh Shanbhag, 2026-10-14)
- [377306e43](https://github.com/google/adk-python/commit/377306e43c5914de3f64f72526173b0732b0c7d8) fix: merge tracking headers regardless of casing (Jeeho Lee, 2026-10-14)
- [eff016d23](https://github.com/google/adk-python/commit/eff016d235e4b19407868e5278c579e5414c2675) fix: use McpTool inside McpToolset (Sankalp Gilda, 2026-10-14)
- [d0c8454ed](https://github.com/google/adk-python/commit/d0c8454ed762981a9bd6be8aa843ce80e18a5327) fix(tools): return validation error dict when Workflow entry node rejects tool args in NodeTool (Shangjie Chen, 2026-10-14)
- [cb48b9198](https://github.com/google/adk-python/commit/cb48b91981c7306b3110435019e19047b712a7eb) feat: support BaseLlm instances in evaluation and user simulation (Google Team Member, 2026-10-14)
- [e8c4bacdf](https://github.com/google/adk-python/commit/e8c4bacdfe675ceb5adcaf24ea005af94d271c68) feat(classifiers): add ClassifierNode for workflow routing (Kathy Wu, 2026-10-14)
- [e4165d0a4](https://github.com/google/adk-python/commit/e4165d0a43947ba7e1a0b2544e9e6e65f86ad1a8) fix(plugins): match credential key names that use hyphens (George Weale, 2026-10-14)
- [cac5fbbbd](https://github.com/google/adk-python/commit/cac5fbbbd121cccc07fcd91b68c95b8bc360b02f) test: verify generateContent preserves function call IDs (gioboa, 2026-10-14)
- [7d3658ef1](https://github.com/google/adk-python/commit/7d3658ef1a1f61c4c18cc4781f6892460add960c) fix: keep finished parallel tool results when a sibling raises (Thuongvu Ho, 2026-10-14)
- [773418f34](https://github.com/google/adk-python/commit/773418f34f93edd7c379edb5703744066b9cc28a) feat(classifiers): add BaseClassifier and typed question/answer types (Kathy Wu, 2026-10-14)
- [1360dda52](https://github.com/google/adk-python/commit/1360dda520dbff1b8f41c9f6265226c92a7021f2) fix(flows): isolate parallel single-turn node events across branches and node_paths (Shangjie Chen, 2026-10-14)
- [9b0ceecd9](https://github.com/google/adk-python/commit/9b0ceecd9e5d0df86261d8f93ab41833f2470892) test: scope atexit cleanup assertions to their client (Sankalp Gilda, 2026-10-14)
- [c2dcb75af](https://github.com/google/adk-python/commit/c2dcb75af5c7a6786c68d8d2e6ed26506a830c75) fix: return 404 when an eval result or session is missing (George Weale, 2026-10-14)
- [e342a14ec](https://github.com/google/adk-python/commit/e342a14eca15e4e5a0a103a06f8307543633e904) fix: finish runner cleanup when close is cancelled (George Weale, 2026-10-14)
- [29bb0532c](https://github.com/google/adk-python/commit/29bb0532c48abad0314cecea5a30b3cdaf6d7898) fix(evaluation): reject drive-qualified app and eval set ids (George Weale, 2026-10-14)

## Changed Files

- `M	docs/guides/README.md`
- `A	docs/guides/labs/classifiers/classifier_node/index.md`
- `M	src/google/adk/agents/invocation_context.py`
- `M	src/google/adk/cli/dev_server.py`
- `M	src/google/adk/evaluation/_path_validation.py`
- `M	src/google/adk/evaluation/eval_metrics.py`
- `M	src/google/adk/evaluation/hallucinations_v1.py`
- `M	src/google/adk/evaluation/llm_as_judge.py`
- `M	src/google/adk/evaluation/llm_as_judge_utils.py`
- `M	src/google/adk/evaluation/simulation/llm_backed_user_simulator.py`
- `M	src/google/adk/evaluation/simulation/per_turn_user_simulator_quality_v1.py`
- `M	src/google/adk/evaluation/simulation/user_simulator.py`
- `M	src/google/adk/features/_feature_registry.py`
- `M	src/google/adk/flows/llm_flows/context/_contents.py`
- `M	src/google/adk/flows/llm_flows/core/_function_call_postprocessor.py`
- `M	src/google/adk/flows/llm_flows/tools/_batch_executor.py`
- `M	src/google/adk/integrations/mongodb/_client.py`
- `M	src/google/adk/integrations/mongodb/_mongodb_toolset.py`
- `A	src/google/adk/labs/classifiers/__init__.py`
- `A	src/google/adk/labs/classifiers/_base_classifier.py`
- `A	src/google/adk/labs/classifiers/_classifier_node.py`
- `A	src/google/adk/labs/classifiers/_types.py`
- `M	src/google/adk/plugins/auto_tracing_helpers.py`
- `M	src/google/adk/runners.py`
- `M	src/google/adk/tools/_node_tool.py`
- `M	src/google/adk/tools/agent_tool.py`
- `M	src/google/adk/tools/function_tool.py`
- `M	src/google/adk/tools/mcp_tool/mcp_session_manager.py`
- `M	src/google/adk/tools/mcp_tool/mcp_tool.py`
- `M	src/google/adk/tools/mcp_tool/mcp_toolset.py`
- `M	src/google/adk/utils/_google_client_headers.py`
- `M	src/google/adk/utils/_sync_runner.py`
- `M	src/google/adk/workflow/_base_node.py`
- `M	src/google/adk/workflow/_function_node.py`
- `M	src/google/adk/workflow/_tool_node.py`
- `M	src/google/adk/workflow/utils/_graph_validation.py`
- `M	src/google/adk/workflow/utils/_workflow_hitl_utils.py`
- `M	tests/unittests/agents/test_invocation_context.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/evaluation/simulation/test_llm_audio_user_simulator.py`
- `M	tests/unittests/evaluation/simulation/test_llm_backed_user_simulator.py`
- `M	tests/unittests/evaluation/simulation/test_per_turn_user_simulation_quality_v1.py`
- `tests/unittests/evaluation/simulation/test_user_simulator_provider.py`
- `M	tests/unittests/evaluation/test__path_validation.py`
- `M	tests/unittests/evaluation/test_custom_metric_evaluator.py`
- `M	tests/unittests/evaluation/test_hallucinations_v1.py`
- `M	tests/unittests/evaluation/test_llm_as_judge.py`
- `M	tests/unittests/evaluation/test_llm_as_judge_utils.py`
- `M	tests/unittests/flows/llm_flows/tools/test_batch_executor.py`
- `M	tests/unittests/integrations/mongodb/test_mongodb_toolset.py`
- `A	tests/unittests/labs/classifiers/__init__.py`
- `A	tests/unittests/labs/classifiers/test_base_classifier.py`
- `A	tests/unittests/labs/classifiers/test_classifier_node.py`
- `A	tests/unittests/labs/classifiers/test_types.py`
- `M	tests/unittests/models/test_completions_http_client.py`
- `M	tests/unittests/models/test_google_llm.py`
- `M	tests/unittests/plugins/test_auto_tracing_plugin.py`
- `M	tests/unittests/telemetry/functional_goldens/mcp/experimental-span-and-event.json`
- `M	tests/unittests/telemetry/functional_goldens/mcp/http-exchange.json`
- `M	tests/unittests/test_runners.py`
- `M	tests/unittests/tools/mcp_tool/test_mcp_session_manager.py`
- `M	tests/unittests/tools/mcp_tool/test_mcp_toolset.py`
- `M	tests/unittests/tools/test_agent_tool.py`
- `M	tests/unittests/tools/test_function_tool.py`
- `M	tests/unittests/utils/test_google_client_headers.py`
- `A	tests/unittests/utils/test_sync_runner.py`
- `M	tests/unittests/workflow/test_function_node.py`
- `M	tests/unittests/workflow/test_llm_agent_as_node.py`
- `M	tests/unittests/workflow/test_node_tool.py`
- `M	tests/unittests/workflow/utils/test_graph_validation.py`
- `M	tests/unittests/workflow/utils/test_workflow_hitl_utils.py`
