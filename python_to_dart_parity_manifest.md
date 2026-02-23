# Python to Dart Parity Manifest

Generated: 2026-02-23

Summary:
- done: 250
- partial: 28
- missing: 208

| python_file | dart_file | status | parity_notes |
| --- | --- | --- | --- |
| `ref/adk-python/src/google/adk/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/a2a/__init__.py` | `lib/src/a2a/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/a2a/converters/__init__.py` | `lib/src/a2a/converters/(package)` | `done` | Added converter package surfaces and parity tests. |
| `ref/adk-python/src/google/adk/a2a/converters/event_converter.py` | `lib/src/a2a/converters/event_converter.dart` | `done` | Added A2A↔ADK event conversion, long-running tool metadata mapping, and state conversion tests. |
| `ref/adk-python/src/google/adk/a2a/converters/part_converter.py` | `lib/src/a2a/converters/part_converter.dart` | `done` | Added A2A↔GenAI part conversion including function/data/file mappings and tagged inline payload support. |
| `ref/adk-python/src/google/adk/a2a/converters/request_converter.py` | `lib/src/a2a/converters/request_converter.dart` | `done` | Added request-to-runner payload conversion with metadata propagation and user/session derivation. |
| `ref/adk-python/src/google/adk/a2a/converters/utils.py` | `lib/src/a2a/converters/utils.dart` | `done` | Added ADK metadata key and context-id conversion helpers with validation parity. |
| `ref/adk-python/src/google/adk/a2a/executor/__init__.py` | `lib/src/a2a/executor/(package)` | `done` | Added executor package surfaces and parity tests. |
| `ref/adk-python/src/google/adk/a2a/executor/a2a_agent_executor.py` | `lib/src/a2a/executor/a2a_agent_executor.dart` | `done` | Added A2A executor pipeline, session preparation, event queue publishing, and final artifact/status handling. |
| `ref/adk-python/src/google/adk/a2a/executor/task_result_aggregator.py` | `lib/src/a2a/executor/task_result_aggregator.dart` | `done` | Added task-state priority aggregation with in-flight status normalization parity. |
| `ref/adk-python/src/google/adk/a2a/experimental.py` | `lib/src/a2a/experimental.dart` | `done` | Added experimental marker/message surface for A2A module parity. |
| `ref/adk-python/src/google/adk/a2a/logs/__init__.py` | `lib/src/a2a/logs/(package)` | `done` | Added logs package surface for A2A structured logging parity. |
| `ref/adk-python/src/google/adk/a2a/logs/log_utils.py` | `lib/src/a2a/logs/log_utils.dart` | `done` | Added structured A2A request/response/message-part log formatting utilities. |
| `ref/adk-python/src/google/adk/a2a/utils/__init__.py` | `lib/src/a2a/utils/(package)` | `done` | Added A2A utility package surfaces and integration wiring. |
| `ref/adk-python/src/google/adk/a2a/utils/agent_card_builder.py` | `lib/src/a2a/utils/agent_card_builder.dart` | `done` | Added agent-card generation including tool/planner/code-execution/sub-agent skill extraction. |
| `ref/adk-python/src/google/adk/a2a/utils/agent_to_a2a.py` | `lib/src/a2a/utils/agent_to_a2a.dart` | `done` | Added agent-to-A2A application wiring with runner bootstrap and card loading/building. |
| `ref/adk-python/src/google/adk/agents/__init__.py` | `lib/src/agents/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/active_streaming_tool.py` | `lib/src/agents/active_streaming_tool.dart` | `done` | Added active streaming tool holder with task + live stream handles for invocation-time streaming parity. |
| `ref/adk-python/src/google/adk/agents/agent_config.py` | `lib/src/agents/agent_config.dart` | `done` | Added discriminated union parsing with built-in class dispatch and unknown-class fallback parity. |
| `ref/adk-python/src/google/adk/agents/base_agent.py` | `lib/src/agents/base_agent.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/base_agent_config.py` | `lib/src/agents/base_agent_config.dart` | `done` | Added base config model with extra-field capture/validation and callback/sub-agent decoding parity. |
| `ref/adk-python/src/google/adk/agents/callback_context.py` | `lib/src/agents/callback_context.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/common_configs.py` | `lib/src/agents/common_configs.dart` | `done` | Added `ArgumentConfig`/`CodeConfig`/`AgentRefConfig` contracts with one-of validation and argument normalization parity. |
| `ref/adk-python/src/google/adk/agents/config_agent_utils.py` | `lib/src/agents/config_agent_utils.dart` | `done` | Added config loading, YAML parsing, code/callback/agent reference resolution, and built-in/custom agent instantiation parity path. |
| `ref/adk-python/src/google/adk/agents/config_schemas/AgentConfig.json` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/agents/context.py` | `lib/src/agents/context.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/context_cache_config.py` | `lib/src/agents/context_cache_config.dart` | `done` | Added cache interval/ttl/min-token config with range validation, ttl string helper, and string representation parity. |
| `ref/adk-python/src/google/adk/agents/invocation_context.py` | `lib/src/agents/invocation_context.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/langgraph_agent.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/agents/live_request_queue.py` | `lib/src/agents/live_request_queue.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/llm_agent.py` | `lib/src/agents/llm_agent.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/llm_agent_config.py` | `lib/src/agents/llm_agent_config.dart` | `done` | Added full LLM agent config surface including legacy model-map normalization, source exclusivity checks, tools/callback parsing, and include-contents validation. |
| `ref/adk-python/src/google/adk/agents/loop_agent.py` | `lib/src/agents/loop_agent.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/loop_agent_config.py` | `lib/src/agents/loop_agent_config.dart` | `done` | Added loop config with strict field validation and max-iterations parsing parity. |
| `ref/adk-python/src/google/adk/agents/mcp_instruction_provider.py` | `lib/src/agents/mcp_instruction_provider.dart` | `done` | Added MCP-backed instruction provider that loads prompt resources and applies context-state argument interpolation. |
| `ref/adk-python/src/google/adk/agents/parallel_agent.py` | `lib/src/agents/parallel_agent.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/parallel_agent_config.py` | `lib/src/agents/parallel_agent_config.dart` | `done` | Added parallel config with strict extra-field rejection parity. |
| `ref/adk-python/src/google/adk/agents/readonly_context.py` | `lib/src/agents/readonly_context.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/remote_a2a_agent.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/agents/run_config.py` | `lib/src/agents/run_config.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/sequential_agent.py` | `lib/src/agents/sequential_agent.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/agents/sequential_agent_config.py` | `lib/src/agents/sequential_agent_config.dart` | `done` | Added sequential config with strict extra-field rejection parity. |
| `ref/adk-python/src/google/adk/agents/transcription_entry.py` | `lib/src/agents/transcription_entry.dart` | `done` | Added transcription entry model with role/data contract parity (Content or inline binary payload). |
| `ref/adk-python/src/google/adk/apps/__init__.py` | `lib/src/apps/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/apps/app.py` | `lib/src/apps/app.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/apps/base_events_summarizer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/apps/compaction.py` | `lib/src/apps/compaction.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/apps/llm_event_summarizer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/artifacts/__init__.py` | `lib/src/artifacts/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/artifacts/artifact_util.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/artifacts/base_artifact_service.py` | `lib/src/artifacts/base_artifact_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/artifacts/file_artifact_service.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/artifacts/gcs_artifact_service.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/artifacts/in_memory_artifact_service.py` | `lib/src/artifacts/in_memory_artifact_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/__init__.py` | `lib/src/auth/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/auth_credential.py` | `lib/src/auth/auth_credential.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/auth_handler.py` | `lib/src/auth/auth_handler.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/auth_preprocessor.py` | `lib/src/auth/auth_preprocessor.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/auth_schemes.py` | `lib/src/auth/auth_schemes.dart` | `done` | Added OpenAPI-compatible auth scheme models (`AuthSchemeType`, `OpenIdConnectWithConfig`, `ExtendedOAuth2`) and OAuth flow→grant-type mapping parity tests. |
| `ref/adk-python/src/google/adk/auth/auth_tool.py` | `lib/src/auth/auth_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/credential_manager.py` | `lib/src/auth/credential_manager.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/credential_service/__init__.py` | `lib/src/auth/credential_service/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/credential_service/base_credential_service.py` | `lib/src/auth/credential_service/base_credential_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/credential_service/in_memory_credential_service.py` | `lib/src/auth/credential_service/in_memory_credential_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/credential_service/session_state_credential_service.py` | `lib/src/auth/credential_service/session_state_credential_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/exchanger/__init__.py` | `lib/src/auth/exchanger/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/exchanger/base_credential_exchanger.py` | `lib/src/auth/exchanger/base_credential_exchanger.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/exchanger/credential_exchanger_registry.py` | `lib/src/auth/exchanger/credential_exchanger_registry.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/exchanger/oauth2_credential_exchanger.py` | `lib/src/auth/exchanger/oauth2_credential_exchanger.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/oauth2_credential_util.py` | `lib/src/auth/oauth2_credential_util.dart` | `done` | Added OAuth2/OpenID session-construction helper and token-to-credential update utility with parity tests. |
| `ref/adk-python/src/google/adk/auth/oauth2_discovery.py` | `lib/src/auth/oauth2_discovery.dart` | `done` | Added RFC-style OAuth2 discovery manager (auth-server and protected-resource metadata) with endpoint-order and validation tests. |
| `ref/adk-python/src/google/adk/auth/refresher/__init__.py` | `lib/src/auth/refresher/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/refresher/base_credential_refresher.py` | `lib/src/auth/refresher/base_credential_refresher.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/refresher/credential_refresher_registry.py` | `lib/src/auth/refresher/credential_refresher_registry.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/auth/refresher/oauth2_credential_refresher.py` | `lib/src/auth/refresher/oauth2_credential_refresher.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/cli/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/__main__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/adk_web_server.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/agent_graph.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/adk_favicon.svg` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/assets/ADK-512-color.svg` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/assets/audio-processor.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/assets/config/runtime-config.json` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-4MSGFQCD.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-7MR4QDTO.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-A6XEKK5I.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-AK5ESGDJ.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-BWFUMX67.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-BX7YU7E6.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-CHLIPOEM.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-GLGRLUIJ.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-HAQR6HJ6.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-HYLIZOX5.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-IXLBQLFI.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-M3M3P5CP.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-RLBEOMT4.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-RUWE7IJV.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-UATSMTT5.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-VPVAD56Y.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-W7GRJBO5.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/chunk-XB75PFJS.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/index.html` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/main-QQBY56NS.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/polyfills-5CFQRCPP.js` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/browser/styles-SI5RXIFC.css` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/README.md` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/adk_agent_builder_assistant.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/agent.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/instruction_embedded.template` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/sub_agents/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/sub_agents/google_search_agent.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/sub_agents/url_context_agent.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/cleanup_unused_files.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/delete_files.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/explore_project.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/query_schema.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/read_config_files.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/read_files.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/search_adk_knowledge.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/search_adk_source.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/write_config_files.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/tools/write_files.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/utils/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/utils/adk_source_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/utils/path_normalizer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/built_in_agents/utils/resolve_root_directory.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/cli.py` | `lib/src/dev/cli.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/cli/cli_create.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/cli_deploy.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/cli_eval.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/cli_tools_click.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/_generate_markdown_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/_generated_file_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/_replay_validators.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/adk_web_server_client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/cli_record.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/cli_test.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/conformance/test_case.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/fast_api.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/plugins/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/plugins/recordings_plugin.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/plugins/recordings_schema.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/plugins/replay_plugin.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/service_registry.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/agent_change_handler.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/agent_loader.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/base_agent_loader.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/cleanup.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/common.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/dot_adk_folder.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/envs.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/evals.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/local_storage.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/logs.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/service_factory.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/shared_value.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/cli/utils/state.py` | `lib/src/sessions/state.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/code_executors/__init__.py` | `lib/src/code_executors/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/code_executors/agent_engine_sandbox_code_executor.py` | `lib/src/code_executors/agent_engine_sandbox_code_executor.dart` | `partial` | Added resource-name validation and functional local-fallback execution path; full Vertex Agent Engine API integration remains. |
| `ref/adk-python/src/google/adk/code_executors/base_code_executor.py` | `lib/src/code_executors/base_code_executor.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/code_executors/built_in_code_executor.py` | `lib/src/code_executors/built_in_code_executor.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/code_executors/code_execution_utils.py` | `lib/src/code_executors/code_execution_utils.dart` | `done` | Added code/file/result data structures and utility helpers for extraction, conversion, and execution-result parts with parity tests. |
| `ref/adk-python/src/google/adk/code_executors/code_executor_context.py` | `lib/src/code_executors/code_executor_context.dart` | `done` | Added persistent context state helpers for execution-id/files/error counters/result history with parity tests. |
| `ref/adk-python/src/google/adk/code_executors/container_code_executor.py` | `lib/src/code_executors/container_code_executor.dart` | `partial` | Added container executor contract and docker invocation baseline; full docker client lifecycle parity remains. |
| `ref/adk-python/src/google/adk/code_executors/gke_code_executor.py` | `lib/src/code_executors/gke_code_executor.dart` | `partial` | Added hardened job-manifest/configmap/owner-reference builders and functional local-fallback execution; full Kubernetes API watch/log integration remains. |
| `ref/adk-python/src/google/adk/code_executors/unsafe_local_code_executor.py` | `lib/src/code_executors/unsafe_local_code_executor.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/code_executors/vertex_ai_code_executor.py` | `lib/src/code_executors/vertex_ai_code_executor.dart` | `partial` | Added code-with-imports path, file handling, and output artifact mapping with functional local-fallback execution; full Vertex Extension API integration remains. |
| `ref/adk-python/src/google/adk/dependencies/__init__.py` | `lib/src/dependencies/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/dependencies/rouge_scorer.py` | `lib/src/dependencies/rouge_scorer.dart` | `done` | Added ROUGE-1 scorer dependency module with precision/recall/f-measure API and parity tests. |
| `ref/adk-python/src/google/adk/dependencies/vertexai.py` | `lib/src/dependencies/vertexai.dart` | `done` | Added Vertex AI dependency module facade (`client`, `types`, `preview`) with deterministic local eval backend and parity tests. |
| `ref/adk-python/src/google/adk/errors/__init__.py` | `lib/src/errors/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/errors/already_exists_error.py` | `lib/src/errors/already_exists_error.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/errors/input_validation_error.py` | `lib/src/errors/input_validation_error.dart` | `done` | Added `InputValidationError` with default/custom message behavior and parity tests for string formatting. |
| `ref/adk-python/src/google/adk/errors/not_found_error.py` | `lib/src/errors/not_found_error.dart` | `done` | Added `NotFoundError` counterpart and wired into eval managers. |
| `ref/adk-python/src/google/adk/evaluation/__init__.py` | `lib/src/evaluation/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/evaluation/_eval_set_results_manager_utils.py` | `lib/src/evaluation/eval_set_results_manager_utils.dart` | `done` | Added create/parse helpers including legacy double-encoded JSON parsing. |
| `ref/adk-python/src/google/adk/evaluation/_eval_sets_manager_utils.py` | `lib/src/evaluation/eval_sets_manager_utils.dart` | `done` | Added CRUD helper utilities with not-found behavior parity. |
| `ref/adk-python/src/google/adk/evaluation/_retry_options_utils.py` | `lib/src/evaluation/_retry_options_utils.dart` | `done` | Added default HTTP retry option injection helper and plugin hook parity. |
| `ref/adk-python/src/google/adk/evaluation/agent_evaluator.py` | `lib/src/evaluation/agent_evaluator.dart` | `partial` | Added eval-set orchestration over generated runs and metric registry; Python module-loading and full legacy dataset migration helpers remain pending. |
| `ref/adk-python/src/google/adk/evaluation/app_details.py` | `lib/src/evaluation/app_details.dart` | `done` | Added app/agent projection model with instruction and tool lookup helpers. |
| `ref/adk-python/src/google/adk/evaluation/base_eval_service.py` | `lib/src/evaluation/base_eval_service.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/evaluation/common.py` | `lib/src/evaluation/common.dart` | `done` | Added shared JSON conversion helpers used across evaluation modules. |
| `ref/adk-python/src/google/adk/evaluation/constants.py` | `lib/src/evaluation/constants.dart` | `done` | Added eval dependency message constant parity. |
| `ref/adk-python/src/google/adk/evaluation/conversation_scenarios.py` | `lib/src/evaluation/conversation_scenarios.dart` | `done` | Added scenario container and persona-id to persona resolution parity. |
| `ref/adk-python/src/google/adk/evaluation/custom_metric_evaluator.py` | `lib/src/evaluation/custom_metric_evaluator.dart` | `done` | Added custom metric function registry and evaluator execution path. |
| `ref/adk-python/src/google/adk/evaluation/eval_case.py` | `lib/src/evaluation/eval_case.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/evaluation/eval_config.py` | `lib/src/evaluation/eval_config.dart` | `done` | Added EvalConfig loader/defaulting, custom metric validation, and metric mapping tests. |
| `ref/adk-python/src/google/adk/evaluation/eval_metrics.py` | `lib/src/evaluation/eval_metrics.dart` | `done` | Added criterion/metric info models and result spec types for parity APIs. |
| `ref/adk-python/src/google/adk/evaluation/eval_result.py` | `lib/src/evaluation/eval_result.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/evaluation/eval_rubrics.py` | `lib/src/evaluation/eval_rubrics.dart` | `done` | Added rubric content, rubric, and rubric score data models with JSON parity. |
| `ref/adk-python/src/google/adk/evaluation/eval_set.py` | `lib/src/evaluation/eval_set.dart` | `done` | Added EvalSet model with JSON serialization and manager tests. |
| `ref/adk-python/src/google/adk/evaluation/eval_set_results_manager.py` | `lib/src/evaluation/eval_set_results_manager.dart` | `done` | Added eval set result manager contract and local persistence implementation. |
| `ref/adk-python/src/google/adk/evaluation/eval_sets_manager.py` | `lib/src/evaluation/eval_sets_manager.dart` | `done` | Added eval sets manager contract with in-memory/local implementations. |
| `ref/adk-python/src/google/adk/evaluation/evaluation_constants.py` | `lib/src/evaluation/evaluation_constants.dart` | `done` | Added evaluation file key constants parity. |
| `ref/adk-python/src/google/adk/evaluation/evaluation_generator.py` | `lib/src/evaluation/evaluation_generator.dart` | `partial` | Added runner-based response generation and event-to-invocation conversion; full user-simulator provider integration is still incomplete. |
| `ref/adk-python/src/google/adk/evaluation/evaluator.py` | `lib/src/evaluation/evaluator.dart` | `done` | Added evaluator interface with per-invocation and overall evaluation result models. |
| `ref/adk-python/src/google/adk/evaluation/final_response_match_v1.py` | `lib/src/evaluation/final_response_match_v1.dart` | `done` | Added Rouge-style unigram overlap evaluator and per-invocation aggregation. |
| `ref/adk-python/src/google/adk/evaluation/final_response_match_v2.py` | `lib/src/evaluation/final_response_match_v2.dart` | `partial` | Added deterministic judge-compatible parser and binary match scoring; full LLM sampling path not yet ported. |
| `ref/adk-python/src/google/adk/evaluation/gcs_eval_set_results_manager.py` | `lib/src/evaluation/gcs_eval_set_results_manager.dart` | `done` | Added bucket-backed eval-set-results manager with pluggable GCS store adapter and parity CRUD tests. |
| `ref/adk-python/src/google/adk/evaluation/gcs_eval_sets_manager.py` | `lib/src/evaluation/gcs_eval_sets_manager.dart` | `done` | Added bucket-backed eval-set manager with id validation, eval-case CRUD helpers, and parity manager tests. |
| `ref/adk-python/src/google/adk/evaluation/hallucinations_v1.py` | `lib/src/evaluation/hallucinations_v1.dart` | `partial` | Added criterion parsing and grounding scorer; full two-stage prompt+judge workflow remains to be aligned. |
| `ref/adk-python/src/google/adk/evaluation/in_memory_eval_sets_manager.py` | `lib/src/evaluation/in_memory_eval_sets_manager.dart` | `done` | Added in-memory CRUD manager and parity tests. |
| `ref/adk-python/src/google/adk/evaluation/llm_as_judge.py` | `lib/src/evaluation/llm_as_judge.dart` | `partial` | Added judge base class with multi-sample aggregation and pluggable auto-rater invoker; direct model-registry-backed judge calls are pending. |
| `ref/adk-python/src/google/adk/evaluation/llm_as_judge_utils.py` | `lib/src/evaluation/llm_as_judge_utils.dart` | `done` | Added text/status/rubric/tool serialization helpers for judge-style evaluators. |
| `ref/adk-python/src/google/adk/evaluation/local_eval_service.py` | `lib/src/evaluation/local_eval_service.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/evaluation/local_eval_set_results_manager.py` | `lib/src/evaluation/local_eval_set_results_manager.dart` | `done` | Added disk-backed eval result persistence with list/get/save tests. |
| `ref/adk-python/src/google/adk/evaluation/local_eval_sets_manager.py` | `lib/src/evaluation/local_eval_sets_manager.dart` | `done` | Added disk-backed eval set manager including legacy format conversion support. |
| `ref/adk-python/src/google/adk/evaluation/metric_evaluator_registry.py` | `lib/src/evaluation/metric_evaluator_registry.dart` | `done` | Added registry with evaluator factory bindings and default prebuilt metric registrations. |
| `ref/adk-python/src/google/adk/evaluation/metric_info_providers.py` | `lib/src/evaluation/metric_info_providers.dart` | `done` | Added metric info providers and value range metadata parity. |
| `ref/adk-python/src/google/adk/evaluation/request_intercepter_plugin.py` | `lib/src/evaluation/request_intercepter_plugin.dart` | `done` | Added request-response interception plugin with request-id cache and lookup helper. |
| `ref/adk-python/src/google/adk/evaluation/response_evaluator.py` | `lib/src/evaluation/response_evaluator.dart` | `done` | Added response coherence and response-match evaluation entrypoint with metric dispatch. |
| `ref/adk-python/src/google/adk/evaluation/rubric_based_evaluator.py` | `lib/src/evaluation/rubric_based_evaluator.dart` | `done` | Added rubric-based evaluator base class with rubric filtering and aggregate scoring. |
| `ref/adk-python/src/google/adk/evaluation/rubric_based_final_response_quality_v1.py` | `lib/src/evaluation/rubric_based_final_response_quality_v1.dart` | `done` | Added rubric-based final-response-quality evaluator built on rubric base contract. |
| `ref/adk-python/src/google/adk/evaluation/rubric_based_tool_use_quality_v1.py` | `lib/src/evaluation/rubric_based_tool_use_quality_v1.dart` | `done` | Added rubric-based tool-use-quality evaluator with tool-call transcript scoring. |
| `ref/adk-python/src/google/adk/evaluation/safety_evaluator.py` | `lib/src/evaluation/safety_evaluator.dart` | `done` | Added safety evaluator counterpart with per-invocation and overall thresholding. |
| `ref/adk-python/src/google/adk/evaluation/simulation/__init__.py` | `lib/src/evaluation/simulation/(package)` | `done` | Added full simulation package surface exports and parity tests for provider/static/LLM-backed simulator flows. |
| `ref/adk-python/src/google/adk/evaluation/simulation/llm_backed_user_simulator.py` | `lib/src/evaluation/simulation/llm_backed_user_simulator.dart` | `done` | Added LLM-backed simulator config, conversation summarization, stop/turn-limit handling, and simulation evaluator wiring. |
| `ref/adk-python/src/google/adk/evaluation/simulation/llm_backed_user_simulator_prompts.py` | `lib/src/evaluation/simulation/llm_backed_user_simulator_prompts.dart` | `done` | Added simulator prompt templates, placeholder validation, persona rendering, and prompt formatting helpers. |
| `ref/adk-python/src/google/adk/evaluation/simulation/per_turn_user_simulator_quality_prompts.py` | `lib/src/evaluation/simulation/per_turn_user_simulator_quality_prompts.dart` | `done` | Added per-turn evaluator prompt templates and persona criteria rendering helpers for quality-judge inputs. |
| `ref/adk-python/src/google/adk/evaluation/simulation/per_turn_user_simulator_quality_v1.py` | `lib/src/evaluation/simulation/per_turn_user_simulator_quality_v1.dart` | `partial` | Added per-turn quality evaluator with scenario alignment scoring; full prompt-driven LLM rater is pending. |
| `ref/adk-python/src/google/adk/evaluation/simulation/pre_built_personas.py` | `lib/src/evaluation/simulation/pre_built_personas.dart` | `partial` | Added default persona registry scaffold; full prebuilt persona catalog remains to be ported. |
| `ref/adk-python/src/google/adk/evaluation/simulation/static_user_simulator.py` | `lib/src/evaluation/simulation/static_user_simulator.dart` | `done` | Added static conversation simulator that streams predefined user invocations and terminates with stop-signal status. |
| `ref/adk-python/src/google/adk/evaluation/simulation/user_simulator.py` | `lib/src/evaluation/simulation/user_simulator.dart` | `done` | Added base simulator config/status/message contracts and validated success-only user-message invariant. |
| `ref/adk-python/src/google/adk/evaluation/simulation/user_simulator_personas.py` | `lib/src/evaluation/simulation/user_simulator_personas.dart` | `done` | Added user behavior/persona models plus registry and lookup semantics. |
| `ref/adk-python/src/google/adk/evaluation/simulation/user_simulator_provider.py` | `lib/src/evaluation/simulation/user_simulator_provider.dart` | `done` | Added provider that selects static vs LLM-backed simulators and enforces conversation xor conversation-scenario contract. |
| `ref/adk-python/src/google/adk/evaluation/trajectory_evaluator.py` | `lib/src/evaluation/trajectory_evaluator.dart` | `done` | Added exact/in-order/any-order trajectory matching evaluator with thresholded status. |
| `ref/adk-python/src/google/adk/evaluation/vertex_ai_eval_facade.py` | `lib/src/evaluation/vertex_ai_eval_facade.dart` | `done` | Added Vertex AI eval facade with injected evaluator hook, credential precondition checks, and per-invocation aggregation parity tests. |
| `ref/adk-python/src/google/adk/events/__init__.py` | `lib/src/events/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/events/event.py` | `lib/src/events/event.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/events/event_actions.py` | `lib/src/events/event_actions.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/examples/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/examples/base_example_provider.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/examples/example.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/examples/example_util.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/examples/vertex_ai_example_store.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/features/__init__.py` | `lib/src/features/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/features/_feature_decorator.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/features/_feature_registry.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/flows/__init__.py` | `lib/src/flows/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/__init__.py` | `lib/src/flows/llm_flows/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/_base_llm_processor.py` | `lib/src/flows/llm_flows/base_llm_flow.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/_code_execution.py` | `lib/src/flows/llm_flows/code_execution.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/_nl_planning.py` | `lib/src/flows/llm_flows/nl_planning.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/_output_schema_processor.py` | `lib/src/flows/llm_flows/output_schema_processor.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/agent_transfer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/flows/llm_flows/audio_cache_manager.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/flows/llm_flows/audio_transcriber.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/flows/llm_flows/auto_flow.py` | `lib/src/flows/llm_flows/auto_flow.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/base_llm_flow.py` | `lib/src/flows/llm_flows/base_llm_flow.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/basic.py` | `lib/src/flows/llm_flows/basic.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/compaction.py` | `lib/src/flows/llm_flows/compaction.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/contents.py` | `lib/src/flows/llm_flows/contents.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/context_cache_processor.py` | `lib/src/flows/llm_flows/context_cache_processor.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/functions.py` | `lib/src/flows/llm_flows/functions.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/identity.py` | `lib/src/flows/llm_flows/identity.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/instructions.py` | `lib/src/flows/llm_flows/instructions.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/interactions_processor.py` | `lib/src/flows/llm_flows/interactions_processor.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/request_confirmation.py` | `lib/src/flows/llm_flows/request_confirmation.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/single_flow.py` | `lib/src/flows/llm_flows/single_flow.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/flows/llm_flows/transcription_manager.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/memory/__init__.py` | `lib/src/memory/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/memory/_utils.py` | `lib/src/memory/_utils.dart` | `done` | Added `formatTimestamp` helper with parity-focused timestamp formatting tests. |
| `ref/adk-python/src/google/adk/memory/base_memory_service.py` | `lib/src/memory/base_memory_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/memory/in_memory_memory_service.py` | `lib/src/memory/in_memory_memory_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/memory/memory_entry.py` | `lib/src/memory/memory_entry.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/memory/vertex_ai_memory_bank_service.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/memory/vertex_ai_rag_memory_service.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/__init__.py` | `lib/src/models/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/models/anthropic_llm.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/apigee_llm.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/base_llm.py` | `lib/src/models/base_llm.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/models/base_llm_connection.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/cache_metadata.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/gemini_context_cache_manager.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/gemini_llm_connection.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/gemma_llm.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/google_llm.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/interactions_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/lite_llm.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/models/llm_request.py` | `lib/src/models/llm_request.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/models/llm_response.py` | `lib/src/models/llm_response.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/models/registry.py` | `lib/src/models/registry.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/optimization/__init__.py` | `lib/src/optimization/(package)` | `done` | Added optimization module surfaces with parity-focused optimizer/data/sampler tests. |
| `ref/adk-python/src/google/adk/optimization/agent_optimizer.py` | `lib/src/optimization/agent_optimizer.dart` | `done` | Added generic optimizer base contract aligned with Python signature. |
| `ref/adk-python/src/google/adk/optimization/data_types.py` | `lib/src/optimization/data_types.dart` | `done` | Added sampling/agent-score/optimizer-result model types with parity tests. |
| `ref/adk-python/src/google/adk/optimization/sampler.py` | `lib/src/optimization/sampler.dart` | `done` | Added sampler interface and example-set semantics for train/validation evaluation. |
| `ref/adk-python/src/google/adk/optimization/simple_prompt_optimizer.py` | `lib/src/optimization/simple_prompt_optimizer.dart` | `done` | Added iterative prompt optimizer flow with candidate generation, batch scoring, and final validation tests. |
| `ref/adk-python/src/google/adk/planners/__init__.py` | `lib/src/planners/(package)` | `done` | Exports match baseline planner package and parity behavior is covered in planners parity tests. |
| `ref/adk-python/src/google/adk/planners/base_planner.py` | `lib/src/planners/base_planner.dart` | `done` | Abstract planner contract matches Python and is exercised by planner flow tests. |
| `ref/adk-python/src/google/adk/planners/built_in_planner.py` | `lib/src/planners/built_in_planner.dart` | `done` | Thinking-config overwrite semantics and no-op planner callbacks are covered in parity tests. |
| `ref/adk-python/src/google/adk/planners/plan_re_act_planner.py` | `lib/src/planners/plan_re_act_planner.dart` | `done` | NL planning prompt/tagging and response partitioning behavior is validated in planners parity tests. |
| `ref/adk-python/src/google/adk/platform/__init__.py` | `lib/src/platform/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/platform/thread.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/plugins/__init__.py` | `lib/src/plugins/(package)` | `done` | Plugin package now exports core baseline plugins (`Base`, `DebugLogging`, `Logging`, `PluginManager`, `ReflectRetry`) with tests. |
| `ref/adk-python/src/google/adk/plugins/base_plugin.py` | `lib/src/plugins/base_plugin.dart` | `done` | Callback surface matches Python base plugin and is covered by plugin manager callback tests. |
| `ref/adk-python/src/google/adk/plugins/bigquery_agent_analytics_plugin.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/plugins/context_filter_plugin.py` | `lib/src/plugins/context_filter_plugin.dart` | `done` | Added invocation window filtering with orphaned function-call/response preservation and tests. |
| `ref/adk-python/src/google/adk/plugins/debug_logging_plugin.py` | `lib/src/plugins/debug_logging_plugin.dart` | `done` | Added file-backed debug logging plugin with lifecycle/model/tool event capture and output tests. |
| `ref/adk-python/src/google/adk/plugins/global_instruction_plugin.py` | `lib/src/plugins/global_instruction_plugin.dart` | `done` | Added global instruction injection plugin with string/provider handling and tests. |
| `ref/adk-python/src/google/adk/plugins/logging_plugin.py` | `lib/src/plugins/logging_plugin.dart` | `done` | Added callback-level logging plugin matching baseline logging lifecycle hooks. |
| `ref/adk-python/src/google/adk/plugins/multimodal_tool_results_plugin.py` | `lib/src/plugins/multimodal_tool_results_plugin.dart` | `done` | Added multimodal tool part stash/restore behavior and parity tests for state wiring. |
| `ref/adk-python/src/google/adk/plugins/plugin_manager.py` | `lib/src/plugins/plugin_manager.dart` | `done` | Added callback error wrapping and parity-focused plugin manager early-exit/close tests. |
| `ref/adk-python/src/google/adk/plugins/reflect_retry_tool_plugin.py` | `lib/src/plugins/reflect_retry_tool_plugin.dart` | `done` | Added scoped retry guidance plugin with reset/exceed logic and parity behavior tests. |
| `ref/adk-python/src/google/adk/plugins/save_files_as_artifacts_plugin.py` | `lib/src/plugins/save_files_as_artifacts_plugin.dart` | `done` | Added inline-file upload to artifact persistence plugin with placeholder insertion and model-accessible URI tests. |
| `ref/adk-python/src/google/adk/py.typed` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/runners.py` | `lib/src/runners/runner.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/__init__.py` | `lib/src/sessions/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/_session_util.py` | `lib/src/sessions/session_util.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/base_session_service.py` | `lib/src/sessions/base_session_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/database_session_service.py` | `lib/src/sessions/database_session_service.dart` | `done` | Added database session facade with sqlite/in-memory routing and tests. |
| `ref/adk-python/src/google/adk/sessions/in_memory_session_service.py` | `lib/src/sessions/in_memory_session_service.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/migration/README.md` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/migration/_schema_check_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/migration/migrate_from_sqlalchemy_pickle.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/migration/migrate_from_sqlalchemy_sqlite.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/migration/migration_runner.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/schemas/shared.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/schemas/v0.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/schemas/v1.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/sessions/session.py` | `lib/src/sessions/session.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/sqlite_session_service.py` | `lib/src/sessions/sqlite_session_service.dart` | `done` | Added persistent local session service with state merge and append parity behavior tests. |
| `ref/adk-python/src/google/adk/sessions/state.py` | `lib/src/sessions/state.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/sessions/vertex_ai_session_service.py` | `lib/src/sessions/vertex_ai_session_service.dart` | `done` | Added Vertex-compatible session facade with app-name validation and lifecycle delegation tests. |
| `ref/adk-python/src/google/adk/skills/README.md` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/skills/__init__.py` | `lib/src/skills/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/skills/_utils.py` | `lib/src/skills/_utils.dart` | `done` | Added dedicated utility module export; behavior is implemented and tested via `skill.dart`. |
| `ref/adk-python/src/google/adk/skills/models.py` | `lib/src/skills/models.dart` | `done` | Added dedicated models module export; frontmatter/resources/skill model tests already cover parity. |
| `ref/adk-python/src/google/adk/skills/prompt.py` | `lib/src/skills/prompt.dart` | `done` | Added prompt formatting module export with XML formatting parity tests. |
| `ref/adk-python/src/google/adk/telemetry/__init__.py` | `lib/src/telemetry/(package)` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/telemetry/google_cloud.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/telemetry/setup.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/telemetry/sqlite_span_exporter.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/telemetry/tracing.py` | `lib/src/telemetry/tracing.dart` | `partial` | Counterpart exists but parity-focused tests were not detected. |
| `ref/adk-python/src/google/adk/tools/__init__.py` | `lib/src/tools/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/_automatic_function_calling_util.py` | `lib/src/tools/_automatic_function_calling_util.dart` | `done` | Added declaration builder helpers with ignore-param filtering and schema passthrough support. |
| `ref/adk-python/src/google/adk/tools/_forwarding_artifact_service.py` | `lib/src/tools/_forwarding_artifact_service.dart` | `done` | Added forwarding artifact service that delegates save/load/list/delete/version calls to tool context. |
| `ref/adk-python/src/google/adk/tools/_function_parameter_parse_util.py` | `lib/src/tools/_function_parameter_parse_util.dart` | `done` | Added schema/default compatibility helpers and tuple-schema normalization utilities. |
| `ref/adk-python/src/google/adk/tools/_function_tool_declarations.py` | `lib/src/tools/_function_tool_declarations.dart` | `done` | Added function declaration builders for JSON schema specs with ignored-parameter pruning. |
| `ref/adk-python/src/google/adk/tools/_gemini_schema_util.py` | `lib/src/tools/_gemini_schema_util.dart` | `done` | Added OpenAPI-to-Gemini schema sanitization utilities (snake_case, dereference, anyOf/type normalization). |
| `ref/adk-python/src/google/adk/tools/_google_credentials.py` | `lib/src/tools/_google_credentials.dart` | `done` | Added Google credentials config/manager parity with external-token lookup, OAuth request flow bridging, and cached-token handling. |
| `ref/adk-python/src/google/adk/tools/_memory_entry_utils.py` | `lib/src/tools/_memory_entry_utils.dart` | `done` | Added memory text extraction helper that joins textual parts only. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/agent_simulator_config.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/agent_simulator_engine.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/agent_simulator_factory.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/agent_simulator_plugin.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/strategies/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/strategies/base.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/strategies/tool_spec_mock_strategy.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/tool_connection_analyzer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_simulator/tool_connection_map.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/agent_tool.py` | `lib/src/tools/agent_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/api_registry.py` | `lib/src/tools/api_registry.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/apihub_tool/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/apihub_tool/apihub_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/apihub_tool/clients/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/apihub_tool/clients/apihub_client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/apihub_tool/clients/secret_client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/application_integration_tool/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/application_integration_tool/application_integration_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/application_integration_tool/clients/connections_client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/application_integration_tool/clients/integration_client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/application_integration_tool/integration_connector_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/authenticated_function_tool.py` | `lib/src/tools/authenticated_function_tool.dart` | `done` | Added authenticated function tool with credential injection and auth-request fallback behavior. |
| `ref/adk-python/src/google/adk/tools/base_authenticated_tool.py` | `lib/src/tools/base_authenticated_tool.dart` | `done` | Added base authenticated tool that routes through CredentialManager before executing implementation logic. |
| `ref/adk-python/src/google/adk/tools/base_tool.py` | `lib/src/tools/base_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/base_toolset.py` | `lib/src/tools/base_toolset.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/bigquery/__init__.py` | `lib/src/tools/bigquery/(package)` | `done` | Added BigQuery credential package surface under tools namespace. |
| `ref/adk-python/src/google/adk/tools/bigquery/bigquery_credentials.py` | `lib/src/tools/bigquery/bigquery_credentials.dart` | `done` | Added BigQuery credential config with default scope and token-cache-key parity behavior. |
| `ref/adk-python/src/google/adk/tools/bigquery/bigquery_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigquery/client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigquery/config.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigquery/data_insights_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigquery/metadata_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigquery/query_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigtable/__init__.py` | `lib/src/tools/bigtable/(package)` | `done` | Added Bigtable credential package surface under tools namespace. |
| `ref/adk-python/src/google/adk/tools/bigtable/bigtable_credentials.py` | `lib/src/tools/bigtable/bigtable_credentials.dart` | `done` | Added Bigtable credential config with default scope list and token-cache-key parity behavior. |
| `ref/adk-python/src/google/adk/tools/bigtable/bigtable_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigtable/client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigtable/metadata_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigtable/query_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/bigtable/settings.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/computer_use/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/computer_use/base_computer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/computer_use/computer_use_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/computer_use/computer_use_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/crewai_tool.py` | `lib/src/tools/crewai_tool.dart` | `done` | Added CrewAI-style wrapper tool with mandatory-argument guard, schema-aware declaration override, and config-driven runner resolution hooks. |
| `ref/adk-python/src/google/adk/tools/data_agent/__init__.py` | `lib/src/tools/data_agent/(package)` | `done` | Added Data Agent credential package surface under tools namespace. |
| `ref/adk-python/src/google/adk/tools/data_agent/config.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/data_agent/credentials.py` | `lib/src/tools/data_agent/credentials.dart` | `done` | Added Data Agent credential config with default BigQuery scope and token-cache-key parity behavior. |
| `ref/adk-python/src/google/adk/tools/data_agent/data_agent_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/data_agent/data_agent_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/discovery_engine_search_tool.py` | `lib/src/tools/discovery_engine_search_tool.dart` | `done` | Added Discovery Engine search tool contract with query validation, serving-config derivation, and injectable request handler for deterministic parity testing. |
| `ref/adk-python/src/google/adk/tools/enterprise_search_tool.py` | `lib/src/tools/enterprise_search_tool.dart` | `done` | Added enterprise web search built-in tool request processor with Gemini model gating and Gemini 1.x multi-tool guard parity. |
| `ref/adk-python/src/google/adk/tools/example_tool.py` | `lib/src/tools/example_tool.dart` | `done` | Added example injection tool/config with provider/list support and llm instruction composition. |
| `ref/adk-python/src/google/adk/tools/exit_loop_tool.py` | `lib/src/tools/exit_loop_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/function_tool.py` | `lib/src/tools/function_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/get_user_choice_tool.py` | `lib/src/tools/get_user_choice_tool.dart` | `done` | Added long-running get_user_choice tool helper that marks response as skip-summarization. |
| `ref/adk-python/src/google/adk/tools/google_api_tool/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/google_api_tool/google_api_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/google_api_tool/google_api_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/google_api_tool/google_api_toolsets.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/google_api_tool/googleapi_to_openapi_converter.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/google_maps_grounding_tool.py` | `lib/src/tools/google_maps_grounding_tool.dart` | `done` | Added Google Maps grounding built-in tool request processor with Gemini model compatibility checks and label tagging parity. |
| `ref/adk-python/src/google/adk/tools/google_search_agent_tool.py` | `lib/src/tools/google_search_agent_tool.dart` | `done` | Added Google search sub-agent factory and agent-tool wrapper parity surface. |
| `ref/adk-python/src/google/adk/tools/google_search_tool.py` | `lib/src/tools/google_search_tool.dart` | `done` | Added built-in google_search tool request processor with Gemini model guards and model-override behavior. |
| `ref/adk-python/src/google/adk/tools/google_tool.py` | `lib/src/tools/google_tool.dart` | `done` | Added Google tool wrapper that resolves credentials and injects credential/settings arguments with fallback invocation behavior. |
| `ref/adk-python/src/google/adk/tools/langchain_tool.py` | `lib/src/tools/langchain_tool.dart` | `done` | Added LangChain-style wrapper tool with `run_manager` filtering, schema-aware declaration override, and config-driven runner resolution hooks. |
| `ref/adk-python/src/google/adk/tools/load_artifacts_tool.py` | `lib/src/tools/load_artifacts_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/load_mcp_resource_tool.py` | `lib/src/tools/load_mcp_resource_tool.dart` | `done` | Added MCP resource loader tool with resource-list instruction injection and resource-content attachment. |
| `ref/adk-python/src/google/adk/tools/load_memory_tool.py` | `lib/src/tools/load_memory_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/load_web_page.py` | `lib/src/tools/load_web_page.dart` | `done` | Added web-page loader with redirect-disabled fetch and text extraction/filtering behavior. |
| `ref/adk-python/src/google/adk/tools/long_running_tool.py` | `lib/src/tools/long_running_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/mcp_tool/__init__.py` | `lib/src/tools/mcp_tool/(package)` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/mcp_tool/conversion_utils.py` | `lib/src/tools/mcp_tool/conversion_utils.dart` | `done` | Added ADK-to-MCP tool schema conversion helpers and schema normalization utilities. |
| `ref/adk-python/src/google/adk/tools/mcp_tool/mcp_session_manager.py` | `lib/src/tools/mcp_tool/mcp_session_manager.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/mcp_tool/mcp_tool.py` | `lib/src/tools/mcp_tool/mcp_tool.dart` | `done` | Added MCP tool wrapper with confirmation gating, auth-header derivation, and session-manager-backed tool invocation. |
| `ref/adk-python/src/google/adk/tools/mcp_tool/mcp_toolset.py` | `lib/src/tools/mcp_tool/mcp_toolset.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/mcp_tool/session_context.py` | `lib/src/tools/mcp_tool/session_context.dart` | `done` | Added async session lifecycle context with start/close semantics and timeout handling. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/auth_helpers.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/credential_exchangers/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/credential_exchangers/auto_auth_credential_exchanger.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/credential_exchangers/base_credential_exchanger.py` | `lib/src/auth/exchanger/base_credential_exchanger.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/credential_exchangers/oauth2_exchanger.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/auth/credential_exchangers/service_account_exchanger.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/common/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/common/common.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/openapi_spec_parser/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/openapi_spec_parser/openapi_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/openapi_spec_parser/operation_parser.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/openapi_spec_parser/rest_api_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/preload_memory_tool.py` | `lib/src/tools/preload_memory_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/pubsub/__init__.py` | `lib/src/tools/pubsub/(package)` | `done` | Added Pub/Sub credential package surface under tools namespace. |
| `ref/adk-python/src/google/adk/tools/pubsub/client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/pubsub/config.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/pubsub/message_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/pubsub/pubsub_credentials.py` | `lib/src/tools/pubsub/pubsub_credentials.dart` | `done` | Added Pub/Sub credential config with default scope and token-cache-key parity behavior. |
| `ref/adk-python/src/google/adk/tools/pubsub/pubsub_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/retrieval/__init__.py` | `lib/src/tools/retrieval/(package)` | `done` | Added retrieval tool package surface under tools namespace. |
| `ref/adk-python/src/google/adk/tools/retrieval/base_retrieval_tool.py` | `lib/src/tools/retrieval/base_retrieval_tool.dart` | `done` | Added base retrieval declaration contract exposing a query parameter schema. |
| `ref/adk-python/src/google/adk/tools/retrieval/files_retrieval.py` | `lib/src/tools/retrieval/files_retrieval.dart` | `done` | Added local file retrieval tool using an in-memory file index retriever fallback. |
| `ref/adk-python/src/google/adk/tools/retrieval/llama_index_retrieval.py` | `lib/src/tools/retrieval/llama_index_retrieval.dart` | `done` | Added generic retriever adapter contract and first-result text return behavior for retrieval tools. |
| `ref/adk-python/src/google/adk/tools/retrieval/vertex_ai_rag_retrieval.py` | `lib/src/tools/retrieval/vertex_ai_rag_retrieval.dart` | `done` | Added Vertex AI RAG retrieval tool with Gemini 2+ built-in label injection and callable fallback query handling. |
| `ref/adk-python/src/google/adk/tools/set_model_response_tool.py` | `lib/src/tools/set_model_response_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/skill_toolset.py` | `lib/src/tools/skill_toolset.dart` | `done` | Added skill toolset with list/load/load-resource tools, duplicate-name guard, and request-time system instruction + skills XML injection parity. |
| `ref/adk-python/src/google/adk/tools/spanner/__init__.py` | `lib/src/tools/spanner/(package)` | `done` | Added Spanner credential package surface under tools namespace. |
| `ref/adk-python/src/google/adk/tools/spanner/client.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/spanner/metadata_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/spanner/query_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/spanner/search_tool.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/spanner/settings.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/spanner/spanner_credentials.py` | `lib/src/tools/spanner/spanner_credentials.dart` | `done` | Added Spanner credential config with admin/data scopes and token-cache-key parity behavior. |
| `ref/adk-python/src/google/adk/tools/spanner/spanner_toolset.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/spanner/utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/tools/tool_configs.py` | `lib/src/tools/tool_configs.dart` | `done` | Added tool config datatypes (`BaseToolConfig`, `ToolArgsConfig`, `ToolConfig`) with JSON mapping helpers. |
| `ref/adk-python/src/google/adk/tools/tool_confirmation.py` | `lib/src/tools/tool_confirmation.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/tool_context.py` | `lib/src/tools/tool_context.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/toolbox_toolset.py` | `lib/src/tools/toolbox_toolset.dart` | `done` | Added toolbox toolset wrapper with delegate-backed tool loading/close lifecycle and explicit missing-SDK error path. |
| `ref/adk-python/src/google/adk/tools/transfer_to_agent_tool.py` | `lib/src/tools/transfer_to_agent_tool.dart` | `done` | Counterpart exists and tests reference module/package terms. |
| `ref/adk-python/src/google/adk/tools/url_context_tool.py` | `lib/src/tools/url_context_tool.dart` | `done` | Added URL context tool model compatibility checks and built-in declaration injection behavior. |
| `ref/adk-python/src/google/adk/tools/vertex_ai_search_tool.py` | `lib/src/tools/vertex_ai_search_tool.dart` | `done` | Added Vertex AI Search built-in tool with data-store/engine exclusivity validation, dynamic config builder, and Gemini model guard parity. |
| `ref/adk-python/src/google/adk/utils/__init__.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/_client_labels_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/_debug_output.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/_google_client_headers.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/cache_performance_analyzer.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/content_utils.py` | `lib/src/utils/content_utils.dart` | `done` | Added audio-part detection and content audio-filtering helpers with role/part preservation parity. |
| `ref/adk-python/src/google/adk/utils/context_utils.py` | `lib/src/utils/context_utils.dart` | `done` | Added async-closing helpers (`Aclosing`, `withAclosing`) for deterministic async resource cleanup parity. |
| `ref/adk-python/src/google/adk/utils/env_utils.py` | `lib/src/utils/env_utils.dart` | `done` | Added environment-flag utility with Python-equivalent true/1 enable semantics and default fallback behavior. |
| `ref/adk-python/src/google/adk/utils/feature_decorator.py` | `lib/src/utils/feature_decorator.dart` | `done` | Added feature-gate decorators (`workingInProgress`, `experimental`) with env-based bypass and warning/block behavior parity. |
| `ref/adk-python/src/google/adk/utils/instructions_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/model_name_utils.py` | `lib/src/utils/model_name_utils.dart` | `done` | Added model-name extraction and Gemini model/version detection helpers with env-flag check parity. |
| `ref/adk-python/src/google/adk/utils/output_schema_utils.py` | `lib/src/utils/output_schema_utils.dart` | `done` | Added output-schema-with-tools compatibility check using variant and Gemini version gating parity. |
| `ref/adk-python/src/google/adk/utils/streaming_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/variant_utils.py` | `lib/src/utils/variant_utils.dart` | `done` | Added Google LLM variant enum and environment-driven variant selection parity. |
| `ref/adk-python/src/google/adk/utils/vertex_ai_utils.py` | `-` | `missing` | No Dart counterpart found under lib/src. |
| `ref/adk-python/src/google/adk/utils/yaml_utils.py` | `lib/src/utils/yaml_utils.dart` | `done` | Added YAML/JSON loading and YAML dumping utilities with multiline-string style and exclusion controls parity. |
| `ref/adk-python/src/google/adk/version.py` | `lib/src/version.dart` | `done` | Added package version constant aligned with Python ADK baseline. |
