import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../plugins/base_plugin.dart';

const List<int> retryHttpStatusCodes = <int>[
  408, // Request timeout.
  429, // Too many requests.
  500, // Internal server error.
  502, // Bad gateway.
  503, // Service unavailable.
  504, // Gateway timeout.
];

final HttpRetryOptions defaultHttpRetryOptions = HttpRetryOptions(
  attempts: 7,
  initialDelay: 5.0,
  maxDelay: 120.0,
  expBase: 2.0,
  httpStatusCodes: retryHttpStatusCodes,
);

void addDefaultRetryOptionsIfNotPresent(LlmRequest llmRequest) {
  llmRequest.config.httpOptions ??= HttpOptions();
  llmRequest.config.httpOptions!.retryOptions ??= defaultHttpRetryOptions;
}

class EnsureRetryOptionsPlugin extends BasePlugin {
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
