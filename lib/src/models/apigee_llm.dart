import 'google_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

class ApigeeLlm extends Gemini {
  ApigeeLlm({
    required String model,
    this.proxyUrl,
    this.customHeaders,
    this.apiType = ApiType.unknown,
    super.retryOptions,
    GeminiGenerateHook? generateHook,
  }) : super(model: model, generateHook: generateHook) {
    if (!_validateModelString(model)) {
      throw ArgumentError('Invalid model string: $model');
    }
  }

  final String? proxyUrl;
  final Map<String, String>? customHeaders;
  final ApiType apiType;

  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'apigee\/.*')];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    request.model = _getModelId(request.model ?? model);
    return super.generateContent(request, stream: stream);
  }
}

enum ApiType { unknown, chatCompletions, genai }

bool _validateModelString(String model) {
  if (!model.startsWith('apigee/')) {
    return false;
  }
  return model.split('/').length >= 2;
}

String _getModelId(String model) {
  final List<String> segments = model.split('/');
  if (segments.length <= 1) {
    return model;
  }
  if (segments.first != 'apigee') {
    return model;
  }
  if (segments.length == 2) {
    return segments[1];
  }
  if (segments[1] == 'openai' ||
      segments[1] == 'gemini' ||
      segments[1] == 'vertex_ai') {
    return segments.sublist(2).join('/');
  }
  return segments.sublist(1).join('/');
}
