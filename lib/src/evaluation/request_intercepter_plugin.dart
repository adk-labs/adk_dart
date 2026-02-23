import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../plugins/base_plugin.dart';
import '../types/id.dart';

const String llmRequestIdKey = '__llm_request_key__';

class RequestIntercepterPlugin extends BasePlugin {
  RequestIntercepterPlugin({String name = 'request_intercepter_plugin'})
    : super(name: name);

  final Map<String, LlmRequest> _llmRequestsCache = <String, LlmRequest>{};

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    final String requestId = newAdkId(prefix: 'llm_req_');
    _llmRequestsCache[requestId] = llmRequest;
    callbackContext.state[llmRequestIdKey] = requestId;
    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    final Object? requestId = callbackContext.state[llmRequestIdKey];
    if (requestId == null) {
      return null;
    }
    llmResponse.customMetadata ??= <String, dynamic>{};
    llmResponse.customMetadata![llmRequestIdKey] = requestId;
    return null;
  }

  LlmRequest? getModelRequest(LlmResponse llmResponse) {
    final Object? requestId = llmResponse.customMetadata?[llmRequestIdKey];
    if (requestId is! String) {
      return null;
    }
    return _llmRequestsCache[requestId];
  }
}
