# ADK Python Daily Change Report

- Date (UTC): 2026-11-24
- Source: `google/adk-python`
- Latest SHA: `84cb0742bcd5921efc585dff7c1ae86063702f81`
- Previous SHA: `2b90353cd2f1ee0a8a52262a7843333b6f7d2c8d`

## Summary

- New commits: 11

## Commits

- [84cb0742](https://github.com/google/adk-python/commit/84cb0742bcd5921efc585dff7c1ae86063702f81) feat(cli): warn on duplicate Agent Engine display name and add --update_if_exists (Google Team Member, 2026-11-23)
- [b4ae4fb8](https://github.com/google/adk-python/commit/b4ae4fb8dde4fb45644b0a02a455a9ab94b14df0) feat(classifiers): add GeminiDecisionsClassifier for the Gemini Decisions API (Kathy Wu, 2026-11-23)
- [9c22a89f](https://github.com/google/adk-python/commit/9c22a89fe2d212a0672ea0bdfcc155ac8d361b5e) fix: track transient instructions and gate dynamic instruction routing (George Weale, 2026-11-23)
- [8c0d2f88](https://github.com/google/adk-python/commit/8c0d2f88064dc4f4661a02accb01fe4fb6c25efa) fix(telemetry): Record a Gemini inference once when the google-genai instrumentor is installed (Max Ind, 2026-11-23)
- [d2a60a21](https://github.com/google/adk-python/commit/d2a60a21d4786791665dab728d26334b409ceea6) refactor(a2a): use X | None, X | Y, and builtin generics in type hints (Yuhan Gao, 2026-11-23)
- [17c4a10a](https://github.com/google/adk-python/commit/17c4a10afb604e11f92ca04c99d1cab6a90cd6cb) fix: copy the request config and tools when screening live user input (Jason Zhang, 2026-11-23)
- [163bfc06](https://github.com/google/adk-python/commit/163bfc0681fde974bb58d4f1d5274697d574bb34) fix: allow google-genai 3 (George Weale, 2026-11-23)
- [6686413c](https://github.com/google/adk-python/commit/6686413c26490e67c7200d4908e6cea6ff995aad) feat(skills): add load_skill_from_markdown to build a skill from SKILL.md text (George Weale, 2026-11-23)
- [7ed9cb5d](https://github.com/google/adk-python/commit/7ed9cb5d774979b4f9ea13994631b5ea66d2f6a5) ci: remove the PR triage GitHub workflow (George Weale, 2026-11-23)
- [4d9e2c75](https://github.com/google/adk-python/commit/4d9e2c75f92305b335f8e66f8b4a8ea99f13017f) fix(artifacts): tighten S3 metadata checks in FsspecArtifactService (Google Team Member, 2026-11-22)
- [481e1b2f](https://github.com/google/adk-python/commit/481e1b2f15440743a61ccf36bcbcdba12d5949be) feat(artifacts): support artifact metadata on Azure in FsspecArtifactService (Google Team Member, 2026-11-22)

## Changed Files

- `M	.github/workflows/continuous-integration.yml`
- `D	.github/workflows/pr-triage.yml`
- `M	contributing/samples/adk_team/adk_pr_triaging_agent/README.md`
- `M	docs/guides/README.md`
- `M	docs/guides/flows/llm_flows/base_llm_flow/live_model_callbacks.md`
- `A	docs/guides/labs/classifiers/gemini_decisions_classifier/index.md`
- `M	docs/guides/skills/skill/index.md`
- `M	pyproject.toml`
- `M	src/google/adk/a2a/_compat.py`
- `M	src/google/adk/a2a/agent/_remote_a2a_agent.py`
- `M	src/google/adk/a2a/agent/interceptors/new_integration_extension.py`
- `M	src/google/adk/a2a/agent/utils.py`
- `M	src/google/adk/a2a/converters/event_converter.py`
- `M	src/google/adk/a2a/converters/from_adk_event.py`
- `M	src/google/adk/a2a/converters/part_converter.py`
- `M	src/google/adk/a2a/converters/request_converter.py`
- `M	src/google/adk/a2a/converters/to_adk_event.py`
- `M	src/google/adk/a2a/executor/config.py`
- `M	src/google/adk/a2a/executor/interceptors/include_artifacts_in_a2a_event.py`
- `M	src/google/adk/a2a/executor/utils.py`
- `M	src/google/adk/a2a/utils/agent_card_builder.py`
- `M	src/google/adk/cli/cli_deploy.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/flows/llm_flows/basic.py`
- `M	src/google/adk/flows/llm_flows/core/_utils.py`
- `M	src/google/adk/flows/llm_flows/prompt/_dynamic_instructions.py`
- `M	src/google/adk/integrations/fsspec/_backends.py`
- `M	src/google/adk/integrations/fsspec/_fsspec_artifact_service.py`
- `M	src/google/adk/integrations/model_armor/_plugin.py`
- `M	src/google/adk/labs/classifiers/__init__.py`
- `A	src/google/adk/labs/classifiers/_gemini_decisions_classifier.py`
- `M	src/google/adk/live/_cascade_live.py`
- `M	src/google/adk/live/_live_llm_flow.py`
- `M	src/google/adk/models/_fallback_model.py`
- `M	src/google/adk/models/anthropic_llm.py`
- `M	src/google/adk/models/base_llm.py`
- `M	src/google/adk/models/google_llm.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/models/llm_request.py`
- `M	src/google/adk/plugins/context_filter_plugin.py`
- `M	src/google/adk/plugins/multimodal_tool_results_plugin.py`
- `M	src/google/adk/skills/__init__.py`
- `M	src/google/adk/skills/_utils.py`
- `M	src/google/adk/telemetry/_genai_instrumentor.py`
- `M	src/google/adk/telemetry/tracing.py`
- `M	tests/unittests/a2a/converters/test_event_round_trip.py`
- `M	tests/unittests/a2a/integration/client.py`
- `M	tests/unittests/artifacts/test_artifact_service.py`
- `M	tests/unittests/cli/utils/test_cli_deploy.py`
- `M	tests/unittests/flows/llm_flows/test_base_llm_flow.py`
- `M	tests/unittests/integrations/fsspec/test_fsspec_artifact_service.py`
- `M	tests/unittests/integrations/model_armor/test_model_armor_plugin.py`
- `A	tests/unittests/labs/classifiers/test_gemini_decisions_classifier.py`
- `M	tests/unittests/live/test_cascade_live.py`
- `M	tests/unittests/live/test_live_llm_flow.py`
- `M	tests/unittests/models/test_anthropic_llm.py`
- `M	tests/unittests/models/test_fallback_model.py`
- `M	tests/unittests/models/test_google_llm.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/models/test_llm_request.py`
- `M	tests/unittests/plugins/test_context_filtering_plugin.py`
- `M	tests/unittests/plugins/test_multimodal_tool_results_plugin.py`
- `M	tests/unittests/skills/test__utils.py`
- `M	tests/unittests/telemetry/test_functional.py`
- `M	tests/unittests/telemetry/test_genai_instrumentor_bypass.py`
- `M	tests/unittests/telemetry/test_smoke.py`
- `M	tests/unittests/tools/model_consult/test_advisor.py`
