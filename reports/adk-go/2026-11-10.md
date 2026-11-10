# ADK Go Daily Change Report

- Date (UTC): 2026-11-10
- Source: `google/adk-go`
- Latest SHA: `c232ad8381ab7de2ac562ba41e70a98b7bc64a9a`
- Previous SHA: `1523862f9f50cd298cbce092b7e882709ae0405d`

## Summary

- New commits: 5

## Commits

- [c232ad8](https://github.com/google/adk-go/commit/c232ad8381ab7de2ac562ba41e70a98b7bc64a9a) feat(plugin): add OnAgentErrorCallback (#2229) (Zuhaib Ahmed, 2026-11-10)
- [00313e5](https://github.com/google/adk-go/commit/00313e5fa344f46c09d984bfe5f4643fa4a220a5) fix(llminternal): keep the resumption handle out of the caller's LiveRunConfig (#2244) (Harshit Wandhare, 2026-11-10)
- [b5cec67](https://github.com/google/adk-go/commit/b5cec673ecb2b8bbaa94b99acaf1e1c02ef0bc86) fix(llminternal): send LiveRunConfig realtime input, affective dialog and proactivity (#2216) (KVR Vishnu, 2026-11-10)
- [db14273](https://github.com/google/adk-go/commit/db1427393f4ef75da71c27869adead96c785a3f7) ci: cap release-please at minor bumps for the core module (#2258) (Jan Wojtas, 2026-11-10)
- [7fd9f83](https://github.com/google/adk-go/commit/7fd9f83fc1a84c8a0d771e27c583581a7fbbea8c) fix(configurable): apply config_path containment to workflow node refs (#1299) (Anton Dziatkovskii, 2026-11-10)

## Changed Files

- `M	.github/release-please-config.json`
- `M	agent/agent.go`
- `A	agent/agent_on_error_test.go`
- `M	internal/configurable/configurable.go`
- `M	internal/configurable/configurable_utils.go`
- `M	internal/configurable/configurable_utils_test.go`
- `A	internal/configurable/configurable_utils_windows_test.go`
- `M	internal/configurable/configurable_workflow.go`
- `A	internal/configurable/configurable_workflow_ref_test.go`
- `M	internal/llminternal/base_flow.go`
- `A	internal/llminternal/base_flow_live_config_test.go`
- `M	internal/llminternal/base_flow_live_test.go`
- `M	internal/llminternal/googlellm/live_connection.go`
- `M	internal/llminternal/googlellm/variant.go`
- `M	internal/llminternal/googlellm/variant_test.go`
- `M	internal/plugininternal/plugin_manager.go`
- `A	internal/utils/fs.go`
- `A	internal/utils/fs_disk_test.go`
- `A	internal/utils/fs_test.go`
- `M	plugin/plugin.go`
