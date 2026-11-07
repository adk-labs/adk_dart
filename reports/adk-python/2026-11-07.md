# ADK Python Daily Change Report

- Date (UTC): 2026-11-07
- Source: `google/adk-python`
- Latest SHA: `dd7161f7a2b88cd7ae482cc2acd8423675ac027c`
- Previous SHA: `10711d0532373f526a4438c8c0bcb93c4e81419c`

## Summary

- New commits: 10

## Commits

- [dd7161f7](https://github.com/google/adk-python/commit/dd7161f7a2b88cd7ae482cc2acd8423675ac027c) fix(eval): stop judge and Vertex metrics from scoring model thoughts (Yi Liu, 2026-11-07)
- [9be86308](https://github.com/google/adk-python/commit/9be86308a1a1af769541165c9ff57d0ec095c68c) feat(models): add LlmRequest.to_generate_content_body() (Ayush Pandey, 2026-11-06)
- [5c4fa928](https://github.com/google/adk-python/commit/5c4fa928548b5969bd61d2d8a1c1c7c813c49b33) chore: merge release v2.14.0 to main (adk-bot, 2026-11-06)
- [d0f227af](https://github.com/google/adk-python/commit/d0f227afc3c7187de875dda2e11ff4b47fe285cd) fix: refcount toolsets on Runner so close() waits for last holder (Google Team Member, 2026-11-06)
- [f8ba96a2](https://github.com/google/adk-python/commit/f8ba96a2503d9dbdc7e4384006a545d68e309d66) fix: run OAuth2 auth response token exchange off the event loop (George Weale, 2026-11-06)
- [bd438976](https://github.com/google/adk-python/commit/bd4389766cb19d0afefd6168916ba4121629ecbe) fix: type the API server eval managers as optional (George Weale, 2026-11-06)
- [669f55bb](https://github.com/google/adk-python/commit/669f55bbaa75f49e59a2273c2ecbb534749c85b0) fix: pass raw argument values to a callable require_confirmation (Haran Rajkumar, 2026-11-06)
- [b5b6e58d](https://github.com/google/adk-python/commit/b5b6e58d6b095283e438fd3fa110841b0d39be67) fix: refcount toolsets on Runner so close() waits for last holder (Google Team Member, 2026-11-06)
- [ba142cf8](https://github.com/google/adk-python/commit/ba142cf8e91b045aa0b435f71dbd7c3e686efa45) fix: stop rerunning a waiting wait_for_output node on resume (Akshay Shah, 2026-11-06)
- [c44adfd6](https://github.com/google/adk-python/commit/c44adfd681cf4e143e4ccbeea1ec2ab22c1e4203) test(eval): lock in that report-only pass@k / pass^k criteria are INFORMATIONAL (Google Team Member, 2026-11-06)

## Changed Files

- `M	.agents/skills/adk-architecture/references/interface-workflow.md`
- `M	.github/.release-please-manifest.json`
- `M	.github/release-please-config.json`
- `M	CHANGELOG.md`
- `M	docs/guides/workflow/base_node/index.md`
- `M	src/google/adk/auth/auth_handler.py`
- `M	src/google/adk/auth/credential_manager.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/cli/dev_server.py`
- `M	src/google/adk/evaluation/hallucinations_v1.py`
- `M	src/google/adk/evaluation/llm_as_judge_utils.py`
- `M	src/google/adk/evaluation/rubric_based_multi_turn_trajectory_evaluator.py`
- `M	src/google/adk/evaluation/vertex_ai_eval_facade.py`
- `A	src/google/adk/models/_generate_content_body.py`
- `M	src/google/adk/models/llm_request.py`
- `M	src/google/adk/tools/function_tool.py`
- `M	src/google/adk/version.py`
- `M	src/google/adk/workflow/utils/_replay_interceptor.py`
- `M	tests/unittests/auth/test_auth_handler.py`
- `M	tests/unittests/auth/test_credential_manager.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/evaluation/test_eval_case_result_multi_run_aggregator.py`
- `M	tests/unittests/evaluation/test_final_response_match_v2.py`
- `M	tests/unittests/evaluation/test_hallucinations_v1.py`
- `M	tests/unittests/evaluation/test_llm_as_judge_utils.py`
- `M	tests/unittests/evaluation/test_rubric_based_multi_turn_trajectory_evaluator.py`
- `M	tests/unittests/evaluation/test_vertex_ai_eval_facade.py`
- `A	tests/unittests/models/test_generate_content_body.py`
- `M	tests/unittests/tools/test_function_tool.py`
- `M	tests/unittests/workflow/test_workflow_hitl.py`
- `M	tests/unittests/workflow/utils/test_replay_interceptor.py`
