/// Large language model adapters, registries, routing, and request/response types.
///
/// Provides [BaseLlm], [Gemini], [Claude], [LiteLlm], [RoutedLlm],
/// [LlmRequest], [LlmResponse], and [toGenerateContentBody].
///
/// ```dart
/// import 'package:adk_dart/models.dart';
///
/// final model = Gemini(model: 'gemini-2.5-flash');
/// ```
///
/// @docImport 'src/models/anthropic_llm.dart';
/// @docImport 'src/models/base_llm.dart';
/// @docImport 'src/models/generate_content_body.dart';
/// @docImport 'src/models/google_llm.dart';
/// @docImport 'src/models/lite_llm.dart';
/// @docImport 'src/models/llm_request.dart';
/// @docImport 'src/models/llm_response.dart';
/// @docImport 'src/models/routed_llm.dart';
library;

export 'src/models/anthropic_llm.dart';
export 'src/models/apigee_llm.dart';
export 'src/models/base_llm.dart';
export 'src/models/base_llm_connection.dart';
export 'src/models/cache_metadata.dart';
export 'src/models/capabilities.dart';
export 'src/models/fallback_model.dart';
export 'src/models/gemini_context_cache_manager.dart';
export 'src/models/gemini_llm_connection.dart';
export 'src/models/gemma_llm.dart';
export 'src/models/generate_content_body.dart';
export 'src/models/google_llm.dart';
export 'src/models/interactions_utils.dart';
export 'src/models/lite_llm.dart';
export 'src/models/llm_request.dart';
export 'src/models/llm_response.dart';
export 'src/models/registry.dart';
export 'src/models/routed_llm.dart';
