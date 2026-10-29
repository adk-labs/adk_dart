# ADK Python Daily Change Report

- Date (UTC): 2026-10-29
- Source: `google/adk-python`
- Latest SHA: `29956a8e69366c58f95b54eface6497b2294629d`
- Previous SHA: `82fe029b8490479229dbfc33815468fe17a427ab`

## Summary

- New commits: 18

## Commits

- [29956a8e](https://github.com/google/adk-python/commit/29956a8e69366c58f95b54eface6497b2294629d) feat(tools): preserve tool display titles on BaseTool, McpTool, and events (Google Team Member, 2026-10-29)
- [d45df6a4](https://github.com/google/adk-python/commit/d45df6a44e1fd1261997b2f1e7e6f74314e0bf9f) feat(classifiers): add RefusalAnswer for questions a model declines (Yuhan Gao, 2026-10-29)
- [75fb7886](https://github.com/google/adk-python/commit/75fb78863b96f0381e2117dba28f8442fa45ba68) chore(deps): raise e2b floor to 2.29.5 (Kathy Wu, 2026-10-29)
- [58332a28](https://github.com/google/adk-python/commit/58332a284b73435eb5c54dac73f6740258b7a741) fix: convert list[Enum] tool arguments to the declared members (Somay-kousis, 2026-10-29)
- [e3d0ec92](https://github.com/google/adk-python/commit/e3d0ec9263f8a22bc857535baea0ce8456d689b6) feat(cli): pip install wheels and installable packages passed to --extra_packages (Yang Song, 2026-10-29)
- [b6600be7](https://github.com/google/adk-python/commit/b6600be7b40e1b561418ecaf395240948881d9c0) fix(workflow): keep JoinNode in a loop firing after the first iteration (Thomas Zettl, 2026-10-29)
- [08c289bb](https://github.com/google/adk-python/commit/08c289bb48e9fda73ed06d03dc7d8879c73fd2db) feat(tools): add semantic argument matching to Environment Simulation injections (Google Team Member, 2026-10-29)
- [3640e7d0](https://github.com/google/adk-python/commit/3640e7d0c74bb2d377a58271ac6290d2e51ee60d) feat: add get_active_events helper function (ecantn, 2026-10-28)
- [ba456715](https://github.com/google/adk-python/commit/ba456715ce8a25c99218db992d4b96ab30f2d5c5) fix(telemetry): give every gen_ai duration and token histogram bucket bounds (Google Team Member, 2026-10-28)
- [0fe80f19](https://github.com/google/adk-python/commit/0fe80f19c2495895d8f432a6af7e6515d3a0426e) fix: split CJK sentences in ElevenLabsTTS (Kayvan Zahiri, 2026-10-28)
- [665945db](https://github.com/google/adk-python/commit/665945db17579b68d0586f482b5d715c3e5f62c5) feat(bigquery): make built-in BigQuery skills loadable and discoverable via get_bigquery_skill (Google Team Member, 2026-10-28)
- [ba8905a3](https://github.com/google/adk-python/commit/ba8905a36ddcdae459d431ca648bc39cb219a9f7) perf: handle workflow node paths and branches as plain strings (George Weale, 2026-10-28)
- [effd6410](https://github.com/google/adk-python/commit/effd64101112643cf96ce6bdef6ece26080f6d49) feat: support input and output files in ContainerCodeExecutor (Hamdi Sakly, 2026-10-28)
- [27dda3e1](https://github.com/google/adk-python/commit/27dda3e11eefef25fd75ba4b3ea43ded989f6e56) fix: handle non-UTF-8 avatar configuration files (xili-ytl, 2026-10-28)
- [1e63423e](https://github.com/google/adk-python/commit/1e63423e5198a8d9dd04214add6bd67cb7d561bf) fix: stamp the model response event when finalizing it (Mihir Inamdar, 2026-10-28)
- [ff66b1f1](https://github.com/google/adk-python/commit/ff66b1f178c02bc0ef5d97b4303cb2c446f045cc) feat: store eval files outside a read-only agents_dir (Anusha, 2026-10-28)
- [930ec4de](https://github.com/google/adk-python/commit/930ec4de0ef4c5f2bfc2f13227a3fea9fb2e6d84) test: cover the tool call that carries no arguments (yasumorishima, 2026-10-28)
- [adc2433b](https://github.com/google/adk-python/commit/adc2433bf467cf3ba778189e3b0ddf17bde5f0fb) fix: exclude replayed nodes from workflow max_concurrency count (Mihir Inamdar, 2026-10-28)

## Changed Files

- `M	.agents/skills/adk-architecture/references/interface-workflow.md`
- `M	contributing/samples/live/cascade/README_elevenlabs.md`
- `M	docs/guides/integrations/bigquery/bigquery_toolset/index.md`
- `M	docs/guides/labs/classifiers/classifier_node/index.md`
- `M	docs/guides/tools/tool_args_matcher/tool_args_matcher/index.md`
- `M	docs/guides/workflow/join_node/index.md`
- `M	pyproject.toml`
- `M	src/google/adk/agents/context.py`
- `M	src/google/adk/cli/cli_deploy.py`
- `M	src/google/adk/cli/cli_eval.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/cli/fast_api.py`
- `A	src/google/adk/cli/utils/_eval_storage.py`
- `M	src/google/adk/code_executors/container_code_executor.py`
- `M	src/google/adk/events/__init__.py`
- `M	src/google/adk/events/_branch_path.py`
- `M	src/google/adk/events/_node_path_builder.py`
- `M	src/google/adk/events/_rewind_events.py`
- `M	src/google/adk/events/event.py`
- `M	src/google/adk/flows/llm_flows/base_llm_flow.py`
- `M	src/google/adk/flows/llm_flows/context/_contents.py`
- `M	src/google/adk/flows/llm_flows/core/_finalizer.py`
- `M	src/google/adk/integrations/bigquery/_bigquery_skill.py`
- `M	src/google/adk/integrations/bigquery/bigquery_toolset.py`
- `M	src/google/adk/integrations/eleven_labs/README.md`
- `M	src/google/adk/integrations/eleven_labs/_tts.py`
- `M	src/google/adk/labs/classifiers/__init__.py`
- `M	src/google/adk/labs/classifiers/_base_classifier.py`
- `M	src/google/adk/labs/classifiers/_classifier_node.py`
- `M	src/google/adk/labs/classifiers/_types.py`
- `M	src/google/adk/telemetry/_metrics.py`
- `M	src/google/adk/tools/base_tool.py`
- `M	src/google/adk/tools/environment_simulation/environment_simulation_config.py`
- `M	src/google/adk/tools/environment_simulation/environment_simulation_engine.py`
- `M	src/google/adk/tools/mcp_tool/mcp_tool.py`
- `M	src/google/adk/tools/tool_args_matcher/__init__.py`
- `A	src/google/adk/tools/tool_args_matcher/_semantic_arg_matcher.py`
- `M	src/google/adk/utils/_schema_utils.py`
- `M	src/google/adk/workflow/_dynamic_node_scheduler.py`
- `M	src/google/adk/workflow/_join_node.py`
- `M	src/google/adk/workflow/_workflow.py`
- `M	src/google/adk/workflow/utils/_replay_manager.py`
- `A	tests/integration/test_environment_simulation_semantic_matching.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/cli/utils/test_cli_deploy.py`
- `M	tests/unittests/cli/utils/test_cli_eval.py`
- `M	tests/unittests/cli/utils/test_cli_tools_click.py`
- `M	tests/unittests/cli/utils/test_evals.py`
- `M	tests/unittests/code_executors/test_container_code_executor.py`
- `M	tests/unittests/events/test_branch_path.py`
- `M	tests/unittests/events/test_node_path_builder.py`
- `A	tests/unittests/events/test_rewind_events.py`
- `M	tests/unittests/flows/llm_flows/context/test_contents_branch.py`
- `M	tests/unittests/flows/llm_flows/core/test_finalizer.py`
- `M	tests/unittests/flows/llm_flows/test_base_llm_flow.py`
- `M	tests/unittests/integrations/bigquery/test_bigquery_skill.py`
- `M	tests/unittests/integrations/eleven_labs/test_tts.py`
- `M	tests/unittests/labs/classifiers/test_classifier_node.py`
- `M	tests/unittests/labs/classifiers/test_types.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/tools/environment_simulation/test_environment_simulation_config.py`
- `M	tests/unittests/tools/environment_simulation/test_environment_simulation_engine.py`
- `M	tests/unittests/tools/mcp_tool/test_mcp_tool.py`
- `M	tests/unittests/tools/test_function_tool.py`
- `A	tests/unittests/tools/tool_args_matcher/test_semantic_arg_matcher.py`
- `M	tests/unittests/workflow/test_join_node.py`
- `M	tests/unittests/workflow/test_workflow_concurrency.py`
- `M	tests/unittests/workflow/utils/test_replay_manager.py`
