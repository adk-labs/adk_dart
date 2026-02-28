import 'dart:collection';

import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../plugins/base_plugin.dart';
import '../types/id.dart';

const String llmRequestIdKey = '__llm_request_key__';

class RequestIntercepterPlugin extends BasePlugin {
  RequestIntercepterPlugin({
    String name = 'request_intercepter_plugin',
    int maxCachedRequests = 1000,
  }) : _maxCachedRequests = maxCachedRequests,
       super(name: name) {
    if (maxCachedRequests <= 0) {
      throw ArgumentError.value(
        maxCachedRequests,
        'maxCachedRequests',
        'must be greater than 0',
      );
    }
  }

  final int _maxCachedRequests;
  final LinkedHashMap<String, LlmRequest> _llmRequestsCache =
      LinkedHashMap<String, LlmRequest>();

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    final String requestId = newAdkId(prefix: 'llm_req_');
    _llmRequestsCache[requestId] = llmRequest;
    _enforceCacheLimit();
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
    return _llmRequestsCache.remove(requestId);
  }

  void _enforceCacheLimit() {
    while (_llmRequestsCache.length > _maxCachedRequests) {
      final String oldestKey = _llmRequestsCache.keys.first;
      _llmRequestsCache.remove(oldestKey);
    }
  }
}
