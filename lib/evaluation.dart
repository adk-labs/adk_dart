/// Agent evaluation framework, metrics, LLM-as-a-Judge, and user simulation.
///
/// Provides [AgentEvaluator], [EvalSet], [EvalCase], [EvalMetric], and
/// multi-run aggregation models such as [MultiRunCaseResult] and [MethodResult].
///
/// ```dart
/// import 'package:adk_dart/evaluation.dart';
///
/// const metric = EvalMetric(
///   metricName: 'response_match_score',
///   threshold: 0.8,
/// );
/// ```
///
/// @docImport 'src/evaluation/agent_evaluator.dart';
/// @docImport 'src/evaluation/eval_case.dart';
/// @docImport 'src/evaluation/eval_case_result_multi_run_aggregator.dart';
/// @docImport 'src/evaluation/eval_metric.dart';
/// @docImport 'src/evaluation/eval_set.dart';
library;

export 'src/evaluation/_retry_options_utils.dart';
export 'src/evaluation/agent_evaluator.dart';
export 'src/evaluation/app_details.dart';
export 'src/evaluation/base_eval_service.dart';
export 'src/evaluation/common.dart';
export 'src/evaluation/constants.dart';
export 'src/evaluation/conversation_scenarios.dart';
export 'src/evaluation/custom_metric_evaluator.dart';
export 'src/evaluation/eval_case.dart';
export 'src/evaluation/eval_case_result_multi_run_aggregator.dart';
export 'src/evaluation/eval_config.dart';
export 'src/evaluation/eval_metric.dart';
export 'src/evaluation/eval_metrics.dart';
export 'src/evaluation/eval_result.dart';
export 'src/evaluation/eval_rubrics.dart';
export 'src/evaluation/eval_set.dart';
export 'src/evaluation/eval_set_results_manager.dart';
export 'src/evaluation/eval_set_results_manager_utils.dart';
export 'src/evaluation/eval_sets_manager.dart';
export 'src/evaluation/eval_sets_manager_utils.dart';
export 'src/evaluation/evaluation_constants.dart';
export 'src/evaluation/evaluation_generator.dart';
export 'src/evaluation/evaluator.dart';
export 'src/evaluation/final_response_match_v1.dart';
export 'src/evaluation/final_response_match_v2.dart';
export 'src/evaluation/gcs_eval_set_results_manager.dart';
export 'src/evaluation/gcs_eval_sets_manager.dart';
export 'src/evaluation/gcs_storage_store.dart';
export 'src/evaluation/hallucinations_v1.dart';
export 'src/evaluation/in_memory_eval_set_results_manager.dart';
export 'src/evaluation/in_memory_eval_sets_manager.dart';
export 'src/evaluation/llm_as_judge.dart';
export 'src/evaluation/llm_as_judge_utils.dart';
export 'src/evaluation/local_eval_service.dart';
export 'src/evaluation/local_eval_set_results_manager.dart';
export 'src/evaluation/local_eval_sets_manager.dart';
export 'src/evaluation/metric_evaluator_registry.dart';
export 'src/evaluation/metric_info_providers.dart';
export 'src/evaluation/multi_run_aggregation_methods.dart';
export 'src/evaluation/multi_turn_task_success_evaluator.dart';
export 'src/evaluation/multi_turn_tool_use_quality_evaluator.dart';
export 'src/evaluation/multi_turn_trajectory_quality_evaluator.dart';
export 'src/evaluation/request_intercepter_plugin.dart';
export 'src/evaluation/response_evaluator.dart';
export 'src/evaluation/rubric_based_evaluator.dart';
export 'src/evaluation/rubric_based_final_response_quality_v1.dart';
export 'src/evaluation/rubric_based_multi_turn_trajectory_evaluator.dart';
export 'src/evaluation/rubric_based_tool_use_quality_v1.dart';
export 'src/evaluation/safety_evaluator.dart';
export 'src/evaluation/simulation/cloud_tts_llm.dart';
export 'src/evaluation/simulation/llm_audio_user_simulator.dart';
export 'src/evaluation/simulation/llm_backed_user_simulator.dart';
export 'src/evaluation/simulation/llm_backed_user_simulator_prompts.dart';
export 'src/evaluation/simulation/per_turn_user_simulator_quality_prompts.dart';
export 'src/evaluation/simulation/per_turn_user_simulator_quality_v1.dart';
export 'src/evaluation/simulation/pre_built_personas.dart';
export 'src/evaluation/simulation/static_user_simulator.dart';
export 'src/evaluation/simulation/user_simulator.dart';
export 'src/evaluation/simulation/user_simulator_personas.dart';
export 'src/evaluation/simulation/user_simulator_provider.dart';
export 'src/evaluation/trajectory_evaluator.dart';
export 'src/evaluation/vertex_ai_eval_facade.dart';
export 'src/evaluation/vertex_ai_scenario_generation_facade.dart';
