# ADK Python Daily Change Report

- Date (UTC): 2026-11-18
- Source: `google/adk-python`
- Latest SHA: `aa0f434a8b09de181db5812268e00e9e2f27e20f`
- Previous SHA: `889ddd3134df1dd1a626205ee78811950dec2a5c`

## Summary

- New commits: 13

## Commits

- [aa0f434a](https://github.com/google/adk-python/commit/aa0f434a8b09de181db5812268e00e9e2f27e20f) fix: keep the Gemini API on v1beta unless a version is configured (George Weale, 2026-11-18)
- [43e959ee](https://github.com/google/adk-python/commit/43e959ee4611a3cf9b6d084a7aeaf33f68b489ea) fix: stop retrying context cache creation on models that refuse it (George Weale, 2026-11-18)
- [36ac021e](https://github.com/google/adk-python/commit/36ac021eb6156a5fccf2af257b83c97eb8b84e1f) fix(eval): send Gemini 4 a thinking level instead of the default budget (George Weale, 2026-11-18)
- [8fa57e82](https://github.com/google/adk-python/commit/8fa57e82a7fef495fda510718d9912cccc0494b4) fix(tools): report the thinking level ModelConsultTool actually sent (George Weale, 2026-11-18)
- [fa7b2045](https://github.com/google/adk-python/commit/fa7b2045810a943d43ddfc4351a1b426b1511e69) fix: use a thinking level for SemanticArgMatcher on Gemini 4 (George Weale, 2026-11-18)
- [30cb66ec](https://github.com/google/adk-python/commit/30cb66ec17702b4ff6f0bbfe043dbcc86fdadd8e) fix: keep ManagedAgent Developer API clients on v1beta (George Weale, 2026-11-18)
- [fa9ae7e0](https://github.com/google/adk-python/commit/fa9ae7e0139ed7e6bb804e38ff5d8aa8f4873917) fix(vmaas): AgentEngineEnvironment can be pickled after use (Liang Wu, 2026-11-18)
- [15af24c1](https://github.com/google/adk-python/commit/15af24c15c11baaf9066fb3f8121badab41fce3d) fix: Support google-genai releases that move converters to _converters (Mark Daoust, 2026-11-18)
- [ec2ac7c5](https://github.com/google/adk-python/commit/ec2ac7c5ea8f007e6cdffd4db999df7dea9f329d) fix: support non-LLM root nodes in app-info and get_agents_dict (Google Team Member, 2026-11-18)
- [c74df83c](https://github.com/google/adk-python/commit/c74df83c0dae648459c6b485e29d531dda9aab29) fix: accept every SDK thinking level in ModelConsultTool (George Weale, 2026-11-17)
- [de1d3079](https://github.com/google/adk-python/commit/de1d3079e8968e5e970ec146e5963ecbe68a5b7a) fix: treat Gemini 4 and later as Gemini 3 or newer in LiteLlm (George Weale, 2026-11-17)
- [b916291f](https://github.com/google/adk-python/commit/b916291fccb1b830affe542240c2520f7a176b10) feat(artifacts): support artifact metadata on S3 in FsspecArtifactService (Google Team Member, 2026-11-17)
- [277553a0](https://github.com/google/adk-python/commit/277553a02ab8e91a93a380306221c66562651655) fix: skip the genai OTel instrumentor when dependencies conflict (George Weale, 2026-11-17)

## Changed Files

- `M	docs/guides/evaluation/eval_config/index.md`
- `M	docs/guides/optimization/agent_optimizer/index.md`
- `M	docs/guides/tools/model_consult/model_consult_tool/index.md`
- `M	docs/guides/tools/tool_args_matcher/tool_args_matcher/index.md`
- `M	src/google/adk/agents/_managed_agent.py`
- `M	src/google/adk/agents/context_cache_config.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/evaluation/simulation/_llm_audio_user_simulator.py`
- `M	src/google/adk/evaluation/simulation/llm_backed_user_simulator.py`
- `M	src/google/adk/integrations/fsspec/_backends.py`
- `M	src/google/adk/integrations/fsspec/_fsspec_artifact_service.py`
- `M	src/google/adk/integrations/vmaas/_agent_engine_environment.py`
- `M	src/google/adk/integrations/vmaas/_sandbox_manager.py`
- `M	src/google/adk/models/_generate_content_body.py`
- `M	src/google/adk/models/apigee_llm.py`
- `M	src/google/adk/models/gemini_context_cache_manager.py`
- `M	src/google/adk/models/google_llm.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/optimization/gepa_root_agent_prompt_optimizer.py`
- `M	src/google/adk/optimization/simple_prompt_optimizer.py`
- `M	src/google/adk/tools/computer_use/computer_use_toolset.py`
- `M	src/google/adk/tools/environment_simulation/environment_simulation_config.py`
- `M	src/google/adk/tools/environment_simulation/environment_simulation_engine.py`
- `M	src/google/adk/tools/model_consult/_advisor.py`
- `M	src/google/adk/tools/model_consult/_model_consult_tool.py`
- `M	src/google/adk/tools/tool_args_matcher/_semantic_arg_matcher.py`
- `M	src/google/adk/utils/agent_info.py`
- `M	src/google/adk/utils/model_name_utils.py`
- `M	tests/unittests/agents/test_gemini_context_cache_manager.py`
- `M	tests/unittests/agents/test_managed_agent.py`
- `M	tests/unittests/artifacts/test_artifact_service.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/evaluation/simulation/test_llm_backed_user_simulator.py`
- `M	tests/unittests/evaluation/simulation/test_user_simulator_provider.py`
- `M	tests/unittests/integrations/fsspec/test_fsspec_artifact_service.py`
- `M	tests/unittests/integrations/vmaas/test_agent_engine_environment.py`
- `M	tests/unittests/integrations/vmaas/test_sandbox_manager.py`
- `M	tests/unittests/models/test_apigee_llm.py`
- `M	tests/unittests/models/test_generate_content_body.py`
- `M	tests/unittests/models/test_google_llm.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/optimization/gepa_root_agent_prompt_optimizer_test.py`
- `M	tests/unittests/optimization/simple_prompt_optimizer_test.py`
- `M	tests/unittests/tools/environment_simulation/test_environment_simulation_engine.py`
- `M	tests/unittests/tools/model_consult/test_advisor.py`
- `M	tests/unittests/tools/model_consult/test_model_consult_tool.py`
- `M	tests/unittests/tools/tool_args_matcher/test_semantic_arg_matcher.py`
- `M	tests/unittests/utils/test_agent_info.py`
- `M	tests/unittests/utils/test_model_name_utils.py`
