# ADK Go Daily Change Report

- Date (UTC): 2026-11-09
- Source: `google/adk-go`
- Latest SHA: `1523862f9f50cd298cbce092b7e882709ae0405d`
- Previous SHA: `dba8afa2bc3a54e13731ac6d18592edcba4c7530`

## Summary

- New commits: 15

## Commits

- [1523862](https://github.com/google/adk-go/commit/1523862f9f50cd298cbce092b7e882709ae0405d) feat(auth): let tools ask the end user to sign in (#2231) (Sasha, 2026-11-09)
- [f2dc5d3](https://github.com/google/adk-go/commit/f2dc5d3adc6d9af714c5bec47f6e8bd4b3f7b99b) fix(llminternal): carry Live API usage metadata on live responses (#2215) (KVR Vishnu, 2026-11-10)
- [3b6fd84](https://github.com/google/adk-go/commit/3b6fd847a15d147b3c17921e2f48eb29f2cd9685) test(preloadmemorytool): cover empty text separator ordering (#2237) (ktsoator, 2026-11-10)
- [bec1602](https://github.com/google/adk-go/commit/bec16021456d633a75ef0c4af11073b03fbc3c20) fix(workflowinternal): reject a null finish_task result (#1741) (Gangavarapu Vivek, 2026-11-09)
- [1edb057](https://github.com/google/adk-go/commit/1edb0572264d71b3ba3ab4e9bd24a979e267a96e) docs(agentanalytics): add package godoc documenting Go design and parity behavior (#2176) (Haiyuan Cao, 2026-11-09)
- [3193128](https://github.com/google/adk-go/commit/3193128beaaeafdda22fe4aa0de3c38f76e5dc3c) fix(adkrest): drop nil parts when serializing events and scanning the event graph  (#2192) (PratikDhanave, 2026-11-09)
- [2278f8f](https://github.com/google/adk-go/commit/2278f8f5bdc54510a26ccc7642ed448fa96b77ff) fix(adkrest): treat MaxConcurrentRuns<=0 as unlimited in the Eventarc trigger (#2191) (PratikDhanave, 2026-11-09)
- [46ff99b](https://github.com/google/adk-go/commit/46ff99b8092edf3f33b5ab383e91d3cecfbd27c2) fix(llminternal): drop nil parts in the streaming aggregator (#2190) (PratikDhanave, 2026-11-09)
- [75ae920](https://github.com/google/adk-go/commit/75ae9208b8313bb1488c7394343d3d9f02d3716a) fix(session): skip nil parts in IsFinalResponse classification (#2189) (PratikDhanave, 2026-11-09)
- [ff9e77c](https://github.com/google/adk-go/commit/ff9e77c562f466175907eafa22107b59c17e6cce) fix(preloadmemorytool): read all text parts from the query (#2220) (Zuhaib Ahmed, 2026-11-09)
- [59e7902](https://github.com/google/adk-go/commit/59e7902094252af2c44cffc0b11a41511b40c1b6) test(preloadmemorytool): cover thought positions in memory text (#2214) (ktsoator, 2026-11-09)
- [e261429](https://github.com/google/adk-go/commit/e2614290704ab16cda45d1fe0499e9e99f1002ff) fix(workflow): honor UUID provider for input requests (#1915) (Francesc Campoy, 2026-11-09)
- [ab42390](https://github.com/google/adk-go/commit/ab42390cf3fb5c733d1dbeca19cde79f8b4ad069) chore(deps): bump the go-minor-patch group with 7 updates (#2208) (dependabot[bot], 2026-11-09)
- [e98671f](https://github.com/google/adk-go/commit/e98671f209a48424a0739cc3c3abec0fb0e880ec) feat(tool/bigquerytoolset): add the job tool (#2206) (Gangavarapu Vivek, 2026-11-09)
- [be529e7](https://github.com/google/adk-go/commit/be529e7ba8437855ea17f379a3e8fefb728c625a) fix(workflow): pass a typed node's output schema to the model (#2194) (Jyotiraditya, 2026-11-09)

## Changed Files

- `M	agent/llmagent/llm_agent_wrapper_test.go`
- `M	examples/workflow/hitl_simple/main.go`
- `A	exp/authflow/authflow.go`
- `A	exp/authflow/authflow_test.go`
- `M	exp/doc.go`
- `M	go.mod`
- `M	go.sum`
- `A	internal/llminternal/auth_preprocessor.go`
- `M	internal/llminternal/base_flow.go`
- `M	internal/llminternal/base_flow_live_test.go`
- `M	internal/llminternal/base_flow_test.go`
- `M	internal/llminternal/basic_processor.go`
- `M	internal/llminternal/functions.go`
- `M	internal/llminternal/functions_test.go`
- `M	internal/llminternal/googlellm/live_connection.go`
- `M	internal/llminternal/googlellm/live_connection_test.go`
- `M	internal/llminternal/other_processors.go`
- `A	internal/llminternal/output_schema_binding.go`
- `A	internal/llminternal/output_schema_binding_test.go`
- `M	internal/llminternal/outputschema_processor.go`
- `M	internal/llminternal/stream_aggregator.go`
- `M	internal/llminternal/stream_aggregator_test.go`
- `M	internal/utils/schema_test.go`
- `M	internal/workflowinternal/finish_task_tool.go`
- `M	internal/workflowinternal/finish_task_tool_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `A	plugin/agentanalytics/doc.go`
- `A	plugin/agentanalytics/doc_test.go`
- `M	plugin/agentanalytics/trace_manager_test.go`
- `M	server/adkrest/controllers/debug.go`
- `M	server/adkrest/controllers/debug_test.go`
- `M	server/adkrest/controllers/sessions.go`
- `M	server/adkrest/controllers/sessions_test.go`
- `M	server/adkrest/controllers/triggers/config.go`
- `M	server/adkrest/controllers/triggers/eventarc.go`
- `M	server/adkrest/controllers/triggers/eventarc_test.go`
- `M	server/adkrest/internal/models/event.go`
- `M	server/adkrest/internal/models/event_test.go`
- `M	server/adkrest/internal/models/redact.go`
- `M	server/adkrest/internal/models/session.go`
- `M	server/adkrest/internal/models/session_test.go`
- `M	session/event_test.go`
- `M	session/session.go`
- `M	tool/bigquerytoolset/config.go`
- `A	tool/bigquerytoolset/descriptions/get_job_info.txt`
- `M	tool/bigquerytoolset/doc.go`
- `M	tool/bigquerytoolset/metadata.go`
- `M	tool/bigquerytoolset/toolset.go`
- `M	tool/bigquerytoolset/toolset_test.go`
- `M	tool/preloadmemorytool/tool.go`
- `M	tool/preloadmemorytool/tool_test.go`
- `M	workflow/agent_node.go`
- `A	workflow/agent_node_output_schema_test.go`
- `M	workflow/hitl_test.go`
- `A	workflow/model_output_schema.go`
- `A	workflow/model_output_schema_test.go`
- `M	workflow/request_input.go`
