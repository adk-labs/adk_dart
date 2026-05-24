/// Experimental OpenAI model integration.
library;

import '../../models/apigee_llm.dart';
import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../utils/system_environment/system_environment.dart';

const String _openAiApiKeyEnv = 'OPENAI_API_KEY';

/// Experimental direct OpenAI chat-completions adapter.
///
/// This mirrors Python's `google.adk.labs.openai.OpenAILlm` surface while
/// reusing ADK Dart's OpenAI-compatible request/response conversion.
class OpenAILlm extends BaseLlm {
  /// Creates an OpenAI adapter for [model].
  OpenAILlm({
    required super.model,
    this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1/chat/completions',
    Map<String, String>? headers,
    Map<String, String>? environment,
    ApigeeCompletionsClient? completionsClient,
  }) : headers = headers ?? const <String, String>{},
       environment = environment ?? _safeEnvironment,
       _completionsClient = completionsClient ?? ChatCompletionsHttpClient();

  /// Optional explicit API key. Falls back to `OPENAI_API_KEY`.
  final String? apiKey;

  /// Chat completions endpoint URL.
  final String baseUrl;

  /// Additional headers sent with each request.
  final Map<String, String> headers;

  /// Environment map used for API key lookup.
  final Map<String, String> environment;

  final ApigeeCompletionsClient _completionsClient;

  /// Regex patterns supported by this experimental adapter.
  static List<RegExp> supportedModels() {
    return <RegExp>[
      RegExp(r'gpt-.+'),
      RegExp(r'o[0-9].*'),
      RegExp(r'openai\/.+'),
    ];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String resolvedApiKey = apiKey ?? environment[_openAiApiKeyEnv] ?? '';
    if (resolvedApiKey.isEmpty) {
      throw ArgumentError(
        'The $_openAiApiKeyEnv environment variable must be set.',
      );
    }

    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = _openAiModelId(prepared.model ?? model);
    maybeAppendUserContent(prepared);

    yield* _completionsClient.generateContent(
      request: prepared,
      stream: stream,
      baseUrl: baseUrl,
      headers: <String, String>{
        ...headers,
        'Authorization': 'Bearer $resolvedApiKey',
      },
    );
  }
}

String _openAiModelId(String model) {
  final String trimmed = model.trim();
  if (trimmed.startsWith('openai/')) {
    return trimmed.substring('openai/'.length);
  }
  return trimmed;
}

Map<String, String> get _safeEnvironment {
  try {
    return readSystemEnvironment();
  } catch (_) {
    return <String, String>{};
  }
}
