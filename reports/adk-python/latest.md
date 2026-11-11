# ADK Python Daily Change Report

- Date (UTC): 2026-11-11
- Source: `google/adk-python`
- Latest SHA: `59b0dd63c32cc5dbf8475f1e0e555770aabaa6f0`
- Previous SHA: `61efa3003f896d715fd8ed07b570f73c01f81247`

## Summary

- New commits: 13

## Commits

- [59b0dd63](https://github.com/google/adk-python/commit/59b0dd63c32cc5dbf8475f1e0e555770aabaa6f0) fix: do not score hallucinations_v1 responses with unlabelled sentences (shwetangsinha0509, 2026-11-11)
- [9687bae1](https://github.com/google/adk-python/commit/9687bae1c91e0b3572529c955c81850c5a642409) fix: run code without an artifact service when it writes no files (gjija, 2026-11-11)
- [098eefa2](https://github.com/google/adk-python/commit/098eefa2466d923cf5fec10b297057e012069d89) chore: migrate PyPI publishing workflow to OSS Exit Gate (Arturo Zarazua, 2026-11-11)
- [e5ffe9c9](https://github.com/google/adk-python/commit/e5ffe9c9daed15b952e83d5d778fe89c251f1d48) fix: preserve required flag in RestApiTool serialization (TejasLamba2006, 2026-11-11)
- [c0bcdaa4](https://github.com/google/adk-python/commit/c0bcdaa480a7547587fffd783f54bc408ae814a0) fix: clean up empty maps after deleting sessions (DisturbedCrow, 2026-11-10)
- [ef812bd6](https://github.com/google/adk-python/commit/ef812bd6c40df54e35f38c4b3d2ac582e3b6e856) docs(samples): add an OpenAI Responses API sample with a reasoning model (Haran Rajkumar, 2026-11-10)
- [353a771d](https://github.com/google/adk-python/commit/353a771d7603834432592abee15bea2b2e208852) fix: keep streamed OCI parallel tool calls separate and in order (gjija, 2026-11-10)
- [ca42dcd1](https://github.com/google/adk-python/commit/ca42dcd186d2fab30eb0b57eac99712707921627) fix: take the first non-null union member in _remove_any_of (Pratik Dhanave, 2026-11-10)
- [07958613](https://github.com/google/adk-python/commit/079586136e74221e0c2b795f531be8db935a44d7) fix: read LangGraphAgent reply text from content blocks (gjija, 2026-11-10)
- [9e549adf](https://github.com/google/adk-python/commit/9e549adf7ed48fa2040f4a062a9a48680cc7ab6f) fix: flush debug logging trace and clear state on unhandled run errors (George Weale, 2026-11-10)
- [825a3747](https://github.com/google/adk-python/commit/825a3747e9a9aea7b92eb5a6bb0d926304ded696) fix: exclude ADK client function calls from evaluated tool calls (Anoshor, 2026-11-10)
- [3bb410c9](https://github.com/google/adk-python/commit/3bb410c90bb8c32bdf3229c00247476ae8c126cb) fix: stop emitting `required: true` inside optimization field schemas (Akash Kokare, 2026-11-10)
- [61a4dc64](https://github.com/google/adk-python/commit/61a4dc642019345199702eeddfac03626fe8e50b) fix: give a cloned LlmAgent tools for its own sub-agents (Shangjie Chen, 2026-11-10)

## Changed Files

- `M	.github/workflows/release-publish.yml`
- `M	contributing/samples/models/hello_world_openai/README.md`
- `A	contributing/samples/models/openai_responses_reasoning/README.md`
- `A	contributing/samples/models/openai_responses_reasoning/__init__.py`
- `A	contributing/samples/models/openai_responses_reasoning/agent.py`
- `A	contributing/samples/models/openai_responses_reasoning/run.py`
- `M	docs/guides/optimization/agent_optimizer/index.md`
- `M	src/google/adk/agents/langgraph_agent.py`
- `M	src/google/adk/agents/llm_agent.py`
- `M	src/google/adk/evaluation/eval_case.py`
- `M	src/google/adk/evaluation/hallucinations_v1.py`
- `M	src/google/adk/flows/llm_flows/extensions/_code_execution.py`
- `M	src/google/adk/integrations/oci/_oci_genai_llm.py`
- `M	src/google/adk/optimization/data_types.py`
- `M	src/google/adk/optimization/local_eval_sampler.py`
- `M	src/google/adk/plugins/debug_logging_plugin.py`
- `M	src/google/adk/sessions/in_memory_session_service.py`
- `M	src/google/adk/tools/_automatic_function_calling_util.py`
- `M	src/google/adk/tools/openapi_tool/common/common.py`
- `M	tests/unittests/agents/test_agent_clone.py`
- `M	tests/unittests/agents/test_langgraph_agent.py`
- `M	tests/unittests/evaluation/test_eval_case.py`
- `M	tests/unittests/evaluation/test_hallucinations_v1.py`
- `M	tests/unittests/flows/llm_flows/extensions/test_code_execution.py`
- `M	tests/unittests/integrations/oci/test_oci_genai_llm.py`
- `A	tests/unittests/optimization/data_types_test.py`
- `M	tests/unittests/plugins/test_debug_logging_plugin.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `M	tests/unittests/tools/openapi_tool/common/test_common.py`
- `M	tests/unittests/tools/openapi_tool/openapi_spec_parser/test_rest_api_tool.py`
- `M	tests/unittests/tools/test_build_function_declaration.py`
