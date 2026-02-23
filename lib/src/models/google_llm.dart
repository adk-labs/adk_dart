import '../types/content.dart';
import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'cache_metadata.dart';
import 'gemini_context_cache_manager.dart';
import 'gemini_llm_connection.dart';
import 'llm_request.dart';
import 'llm_response.dart';

typedef GeminiGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);

class Gemini extends BaseLlm {
  Gemini({
    super.model = 'gemini-2.5-flash',
    this.useInteractionsApi = false,
    this.retryOptions,
    this.baseUrl,
    this.speechConfig,
    GeminiGenerateHook? generateHook,
  }) : _generateHook = generateHook;

  final bool useInteractionsApi;
  final Object? retryOptions;
  final String? baseUrl;
  final Object? speechConfig;
  final GeminiGenerateHook? _generateHook;

  static List<RegExp> supportedModels() {
    return <RegExp>[
      RegExp(r'gemini-.*'),
      RegExp(r'model-optimizer-.*'),
      RegExp(r'projects\/.+\/locations\/.+\/endpoints\/.+'),
      RegExp(
        r'projects\/.+\/locations\/.+\/publishers\/google\/models\/gemini.+',
      ),
    ];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = prepared.model ?? model;
    maybeAppendUserContent(prepared);

    final GeminiContextCacheManager cacheManager =
        const GeminiContextCacheManager();
    CacheMetadata? cacheMetadata;
    if (prepared.cacheConfig != null) {
      cacheMetadata = await cacheManager.handleContextCaching(prepared);
    }

    if (_generateHook != null) {
      await for (final LlmResponse response in _generateHook(
        prepared,
        stream,
      )) {
        if (cacheMetadata != null) {
          cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
        }
        yield response;
      }
      return;
    }

    final String text = _defaultText(prepared);
    final LlmResponse response = LlmResponse(
      modelVersion: model,
      content: Content.modelText(text),
      partial: stream ? false : null,
      turnComplete: true,
      interactionId: _deriveInteractionId(prepared),
    );
    if (cacheMetadata != null) {
      cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
    }
    yield response;
  }

  BaseLlmConnection connect(LlmRequest request) {
    return GeminiLlmConnection(model: this, initialRequest: request);
  }

  String _defaultText(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      if (content.role != 'user') {
        continue;
      }
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final String? text = content.parts[j].text;
        if (text != null && text.isNotEmpty) {
          return 'Gemini response: $text';
        }
      }
    }
    return 'Gemini response.';
  }

  String? _deriveInteractionId(LlmRequest request) {
    final String? previous = request.previousInteractionId;
    if (previous == null || previous.isEmpty) {
      return null;
    }
    return '${previous}_next';
  }
}

typedef GoogleLlm = Gemini;
