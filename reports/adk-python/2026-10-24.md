# ADK Python Daily Change Report

- Date (UTC): 2026-10-24
- Source: `google/adk-python`
- Latest SHA: `12c7bed7661ccf942f0f6d3b62bed22a23ea0a85`
- Previous SHA: `f08f9d677f16f36980be56d34bb1b4a444b2d934`

## Summary

- New commits: 6

## Commits

- [12c7bed7](https://github.com/google/adk-python/commit/12c7bed7661ccf942f0f6d3b62bed22a23ea0a85) fix: pass the caller's temp: state to an AgentTool's wrapped agent (Somay-kousis, 2026-10-24)
- [25d19171](https://github.com/google/adk-python/commit/25d191710985371dfb93a131f2fa797734850952) fix: mark failed A2A tasks as error events (sakiko-toyokawa, 2026-10-23)
- [b9812500](https://github.com/google/adk-python/commit/b98125006644d8fee70606dab71d350ab674daf0) fix: stop list_sessions(user_id="") from listing every user in Firestore (Akshay Shah, 2026-10-23)
- [6c204445](https://github.com/google/adk-python/commit/6c2044453982af250c54d8f668fc47bb82643e16) docs(guides): add LlmClassifier unit guide (Kathy Wu, 2026-10-23)
- [ceb0627f](https://github.com/google/adk-python/commit/ceb0627f12dabb186ae9efbd58b87b455da92737) chore: merge release v2.13.0 to main (Wei Sun (Jack), 2026-10-23)
- [6b00a389](https://github.com/google/adk-python/commit/6b00a38901e7181801f645e5890da54aa322b6dc) fix: stop LiteLlm from running tool calls quoted in answer text (donggyun112, 2026-10-23)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	.github/release-please-config.json`
- `M	CHANGELOG.md`
- `M	docs/guides/README.md`
- `A	docs/guides/labs/classifiers/llm_classifier/index.md`
- `M	docs/guides/tools/agent_tool/index.md`
- `M	src/google/adk/a2a/_compat.py`
- `M	src/google/adk/a2a/agent/_remote_a2a_agent.py`
- `M	src/google/adk/a2a/converters/event_converter.py`
- `M	src/google/adk/a2a/converters/to_adk_event.py`
- `M	src/google/adk/a2a/converters/utils.py`
- `M	src/google/adk/integrations/firestore/firestore_session_service.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/tools/agent_tool.py`
- `M	src/google/adk/version.py`
- `M	tests/unittests/a2a/agent/test_remote_a2a_agent.py`
- `M	tests/unittests/a2a/converters/test_event_converter.py`
- `M	tests/unittests/a2a/converters/test_to_adk.py`
- `M	tests/unittests/a2a/test_compat.py`
- `M	tests/unittests/integrations/firestore/test_firestore_session_service.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/tools/test_agent_tool.py`
