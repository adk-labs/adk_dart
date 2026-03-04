/// Retry defaults for evaluation-related model requests.
library;

import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../plugins/base_plugin.dart';

/// The HTTP status codes considered retryable by default.
const List<int> retryHttpStatusCodes = <int>[
  408, // Request timeout.
  429, // Too many requests.
  500, // Internal server error.
  502, // Bad gateway.
  503, // Service unavailable.
  504, // Gateway timeout.
];

/// The default HTTP retry strategy for evaluator model calls.
final HttpRetryOptions defaultHttpRetryOptions = HttpRetryOptions(
  attempts: 7,
  initialDelay: 5.0,
  maxDelay: 120.0,
  expBase: 2.0,
  httpStatusCodes: retryHttpStatusCodes,
);

/// Adds [defaultHttpRetryOptions] when [llmRequest] has no retry settings.
void addDefaultRetryOptionsIfNotPresent(LlmRequest llmRequest) {
  llmRequest.config.httpOptions ??= HttpOptions();
  llmRequest.config.httpOptions!.retryOptions ??= defaultHttpRetryOptions;
}

/// Plugin that ensures default retry options on outgoing model requests.
class EnsureRetryOptionsPlugin extends BasePlugin {
  /// Creates a plugin that injects default retry options.
  EnsureRetryOptionsPlugin() : super(name: 'ensure_retry_options_plugin');

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    addDefaultRetryOptionsIfNotPresent(llmRequest);
    return null;
  }
}
