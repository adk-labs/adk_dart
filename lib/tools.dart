/// Agent tools, toolsets, MCP tools, skills, and code executors.
///
/// Provides [BaseTool], [FunctionTool], [BaseToolset], [McpToolset],
/// [SkillToolset], and [AgentTool] for extending agent capabilities.
///
/// ```dart
/// import 'package:adk_dart/tools.dart';
///
/// final weatherTool = FunctionTool(
///   name: 'get_weather',
///   description: 'Fetches the current weather for a city.',
///   func: ({required String city}) => {'city': city, 'temp_c': 22},
/// );
/// ```
///
/// @docImport 'src/tools/agent_tool.dart';
/// @docImport 'src/tools/base_tool.dart';
/// @docImport 'src/tools/base_toolset.dart';
/// @docImport 'src/tools/function_tool.dart';
/// @docImport 'src/tools/mcp_tool/mcp_toolset.dart';
/// @docImport 'src/tools/skill_toolset.dart';
library;

export 'src/code_executors/agent_engine_sandbox_code_executor.dart';
export 'src/code_executors/base_code_executor.dart';
export 'src/code_executors/built_in_code_executor.dart';
export 'src/code_executors/cloud_run_sandbox_code_executor.dart';
export 'src/code_executors/code_execution_utils.dart';
export 'src/code_executors/code_executor_context.dart';
export 'src/code_executors/container_code_executor.dart';
export 'src/code_executors/gke_code_executor.dart';
export 'src/code_executors/unsafe_local_code_executor.dart';
export 'src/code_executors/vertex_ai_code_executor.dart';
export 'src/skills/_utils.dart';
export 'src/skills/models.dart';
export 'src/skills/prompt.dart';
export 'src/skills/skill_runtime.dart';
export 'src/tools/_automatic_function_calling_util.dart';
export 'src/tools/_forwarding_artifact_service.dart';
export 'src/tools/_function_parameter_parse_util.dart';
export 'src/tools/_function_tool_declarations.dart';
export 'src/tools/_gemini_schema_util.dart';
export 'src/tools/_google_credentials.dart';
export 'src/tools/_memory_entry_utils.dart';
export 'src/tools/agent_simulator/agent_simulator.dart';
export 'src/tools/agent_simulator/agent_simulator_config.dart';
export 'src/tools/agent_simulator/agent_simulator_engine.dart';
export 'src/tools/agent_simulator/agent_simulator_factory.dart';
export 'src/tools/agent_simulator/agent_simulator_plugin.dart';
export 'src/tools/agent_simulator/strategies/base.dart';
export 'src/tools/agent_simulator/strategies/tool_spec_mock_strategy.dart';
export 'src/tools/agent_simulator/tool_connection_analyzer.dart';
export 'src/tools/agent_simulator/tool_connection_map.dart';
export 'src/tools/agent_tool.dart';
export 'src/tools/api_registry.dart';
export 'src/tools/apihub_tool/apihub_tool.dart';
export 'src/tools/application_integration_tool/application_integration_tool.dart';
export 'src/tools/authenticated_function_tool.dart';
export 'src/tools/base_authenticated_tool.dart';
export 'src/tools/base_tool.dart';
export 'src/tools/base_toolset.dart';
export 'src/tools/bash_tool.dart';
export 'src/tools/bigquery/bigquery.dart'
    hide
        executeSql,
        getExecuteSql,
        getTableInfo,
        BigQueryToolset,
        ExecuteSqlTool,
        bigQuerySessionInfoKey;
export 'src/tools/bigtable/bigtable_credentials.dart';
export 'src/tools/bigtable/bigtable_toolset.dart';
export 'src/tools/bigtable/client.dart';
export 'src/tools/bigtable/metadata_tool.dart';
export 'src/tools/bigtable/query_tool.dart'
    hide executeSql, defaultMaxExecutedQueryResultRows;
export 'src/tools/bigtable/settings.dart';
export 'src/tools/computer_use/base_computer.dart';
export 'src/tools/computer_use/computer_use_tool.dart';
export 'src/tools/computer_use/computer_use_toolset.dart';
export 'src/tools/crewai_tool.dart';
export 'src/tools/data_agent/config.dart';
export 'src/tools/data_agent/credentials.dart';
export 'src/tools/data_agent/data_agent_tool.dart';
export 'src/tools/data_agent/data_agent_toolset.dart';
export 'src/tools/discovery_engine_search_tool.dart';
export 'src/tools/enterprise_search_tool.dart';
export 'src/tools/environment/daytona_environment.dart';
export 'src/tools/environment/environment.dart';
export 'src/tools/environment_simulation/environment_simulation.dart';
export 'src/tools/environment_simulation/environment_simulation_config.dart';
export 'src/tools/environment_simulation/environment_simulation_engine.dart';
export 'src/tools/environment_simulation/environment_simulation_factory.dart';
export 'src/tools/environment_simulation/environment_simulation_plugin.dart';
export 'src/tools/environment_simulation/strategies/base.dart';
export 'src/tools/environment_simulation/strategies/tool_spec_mock_strategy.dart';
export 'src/tools/environment_simulation/tool_connection_analyzer.dart';
export 'src/tools/environment_simulation/tool_connection_map.dart';
export 'src/tools/eventarc/config.dart';
export 'src/tools/eventarc/eventarc_toolset.dart';
export 'src/tools/eventarc/message_tool.dart' hide publishMessage;
export 'src/tools/example_tool.dart';
export 'src/tools/exit_loop_tool.dart';
export 'src/tools/function_tool.dart';
export 'src/tools/get_user_choice_tool.dart';
export 'src/tools/google_api_tool/google_api_tool.dart';
export 'src/tools/google_api_tool/google_api_toolset.dart';
export 'src/tools/google_api_tool/google_api_toolsets.dart';
export 'src/tools/google_api_tool/googleapi_to_openapi_converter.dart';
export 'src/tools/google_maps_grounding_tool.dart';
export 'src/tools/google_search_agent_tool.dart';
export 'src/tools/google_search_tool.dart';
export 'src/tools/google_tool.dart';
export 'src/tools/langchain_tool.dart';
export 'src/tools/load_artifacts_tool.dart';
export 'src/tools/load_mcp_resource_tool.dart';
export 'src/tools/load_memory_tool.dart';
export 'src/tools/load_web_page.dart';
export 'src/tools/long_running_tool.dart';
export 'src/tools/mcp_tool/agent_to_mcp.dart';
export 'src/tools/mcp_tool/conversion_utils.dart';
export 'src/tools/mcp_tool/mcp_session_manager.dart';
export 'src/tools/mcp_tool/mcp_tool.dart';
export 'src/tools/mcp_tool/mcp_toolset.dart';
export 'src/tools/mcp_tool/session_context.dart';
export 'src/tools/model_consult/force_escalation_plugin.dart';
export 'src/tools/model_consult/model_consult_tool.dart';
export 'src/tools/model_consult/model_consult_toolset.dart';
export 'src/tools/model_consult/observability_plugin.dart';
export 'src/tools/node_tool.dart';
export 'src/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.dart';
export 'src/tools/openapi_tool/openapi_spec_parser/openapi_toolset.dart';
export 'src/tools/openapi_tool/openapi_spec_parser/operation_parser.dart';
export 'src/tools/openapi_tool/openapi_spec_parser/rest_api_tool.dart';
export 'src/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.dart';
export 'src/tools/openapi_tool/openapi_tool.dart';
export 'src/tools/preload_memory_tool.dart';
export 'src/tools/pubsub/client.dart';
export 'src/tools/pubsub/config.dart';
export 'src/tools/pubsub/message_tool.dart';
export 'src/tools/pubsub/pubsub_credentials.dart';
export 'src/tools/pubsub/pubsub_toolset.dart';
export 'src/tools/remote_mcp_server.dart';
export 'src/tools/request_input_tool.dart';
export 'src/tools/retrieval/base_retrieval_tool.dart';
export 'src/tools/retrieval/files_retrieval.dart';
export 'src/tools/retrieval/llama_index_retrieval.dart';
export 'src/tools/retrieval/vertex_ai_rag_retrieval.dart';
export 'src/tools/runtime_bootstrap.dart';
export 'src/tools/set_model_response_tool.dart';
export 'src/tools/skill_toolset.dart';
export 'src/tools/spanner/admin_tool.dart' hide listInstances;
export 'src/tools/spanner/admin_toolset.dart';
export 'src/tools/spanner/client.dart';
export 'src/tools/spanner/metadata_tool.dart';
export 'src/tools/spanner/query_tool.dart';
export 'src/tools/spanner/search_tool.dart';
export 'src/tools/spanner/settings.dart';
export 'src/tools/spanner/spanner_credentials.dart';
export 'src/tools/spanner/spanner_toolset.dart';
export 'src/tools/spanner/utils.dart' hide executeSql;
export 'src/tools/tool_args_matcher/tool_args_matcher.dart';
export 'src/tools/tool_configs.dart';
export 'src/tools/tool_confirmation.dart';
export 'src/tools/tool_context.dart';
export 'src/tools/toolbox_toolset.dart';
export 'src/tools/toolsearch/tool_search_toolset.dart';
export 'src/tools/transfer_to_agent_tool.dart';
export 'src/tools/url_context_tool.dart';
export 'src/tools/vertex_ai_load_profiles_tool.dart';
export 'src/tools/vertex_ai_search_tool.dart';
export 'src/tools/vertex_rag_retrieval_tool.dart';
