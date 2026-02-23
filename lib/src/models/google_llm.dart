import '../types/content.dart';
import '../utils/variant_utils.dart';
import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'cache_metadata.dart';
import 'gemini_context_cache_manager.dart';
import 'gemini_llm_connection.dart';
import 'llm_request.dart';
import 'llm_response.dart';

typedef GeminiGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);
typedef GeminiInteractionsInvoker =
    Stream<LlmResponse> Function(LlmRequest request, {required bool stream});
typedef GeminiLiveSessionFactory =
    GeminiLiveSession Function(LlmRequest request);

class ResourceExhaustedModelException implements Exception {
  ResourceExhaustedModelException(this.message);

  final String message;

  @override
  String toString() {
    return 'ResourceExhaustedModelException: $message';
  }
}

class Gemini extends BaseLlm {
  Gemini({
    super.model = 'gemini-2.5-flash',
    this.useInteractionsApi = false,
    this.retryOptions,
    this.baseUrl,
    this.speechConfig,
    this.cacheManager = const GeminiContextCacheManager(),
    this.environment,
    this.apiBackendOverride,
    this.interactionsInvoker,
    this.liveSessionFactory,
    GeminiGenerateHook? generateHook,
  }) : _generateHook = generateHook;

  final bool useInteractionsApi;
  final Object? retryOptions;
  final String? baseUrl;
  final Object? speechConfig;
  final GeminiContextCacheManager cacheManager;
  final Map<String, String>? environment;
  final GoogleLLMVariant? apiBackendOverride;
  final GeminiInteractionsInvoker? interactionsInvoker;
  final GeminiLiveSessionFactory? liveSessionFactory;
  final GeminiGenerateHook? _generateHook;

  GoogleLLMVariant get apiBackend =>
      apiBackendOverride ?? getGoogleLlmVariant(environment: environment);

  String get _liveApiVersion =>
      apiBackend == GoogleLLMVariant.vertexAi ? 'v1beta1' : 'v1alpha';

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
    _preprocessRequest(prepared);
    maybeAppendUserContent(prepared);
    prepared.config.httpOptions ??= HttpOptions();
    prepared.config.httpOptions!.headers = _mergeTrackingHeaders(
      prepared.config.httpOptions!.headers,
    );

    CacheMetadata? cacheMetadata;
    if (prepared.cacheConfig != null) {
      cacheMetadata = await cacheManager.handleContextCaching(prepared);
    }

    if (useInteractionsApi && interactionsInvoker != null) {
      await for (final LlmResponse response in interactionsInvoker!(
        prepared,
        stream: stream,
      )) {
        if (cacheMetadata != null) {
          cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
        }
        yield response;
      }
      return;
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

    try {
      final String text = _defaultText(prepared);
      final LlmResponse response = LlmResponse(
        modelVersion: prepared.model,
        content: Content.modelText(text),
        partial: stream ? false : null,
        turnComplete: true,
        interactionId: _deriveInteractionId(prepared),
      );
      if (cacheMetadata != null) {
        cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
      }
      yield response;
    } catch (error) {
      final String message = '$error';
      if (message.contains('429') ||
          message.toLowerCase().contains('resource_exhausted')) {
        throw ResourceExhaustedModelException(message);
      }
      rethrow;
    }
  }

  BaseLlmConnection connect(LlmRequest request) {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = prepared.model ?? model;
    prepared.liveConnectConfig.httpOptions ??= HttpOptions();
    prepared.liveConnectConfig.httpOptions!.headers = _mergeTrackingHeaders(
      prepared.liveConnectConfig.httpOptions!.headers,
    );
    prepared.liveConnectConfig.httpOptions!.apiVersion = _liveApiVersion;
    if (speechConfig != null) {
      prepared.liveConnectConfig.speechConfig = speechConfig;
    }
    if (prepared.config.systemInstruction != null &&
        prepared.config.systemInstruction!.isNotEmpty) {
      prepared.liveConnectConfig.systemInstruction = Content(
        role: 'system',
        parts: <Part>[Part.text(prepared.config.systemInstruction!)],
      );
    }
    prepared.liveConnectConfig.tools = prepared.config.tools
        ?.map((ToolDeclaration tool) => tool.copyWith())
        .toList();

    return GeminiLlmConnection(
      model: this,
      initialRequest: prepared,
      liveSession: liveSessionFactory?.call(prepared),
      apiBackend: apiBackend,
      modelVersion: prepared.model,
    );
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

  void _preprocessRequest(LlmRequest request) {
    if (apiBackend == GoogleLLMVariant.geminiApi) {
      request.config.labels = <String, String>{};
      for (final Content content in request.contents) {
        for (final Part part in content.parts) {
          if (part.inlineData != null && part.inlineData!.displayName != null) {
            part.inlineData = part.inlineData!.copyWith(displayName: null);
          }
          if (part.fileData != null && part.fileData!.displayName != null) {
            part.fileData = part.fileData!.copyWith(displayName: null);
          }
        }
      }
    }

    final List<ToolDeclaration>? tools = request.config.tools;
    if (tools != null &&
        tools.any((ToolDeclaration tool) => tool.computerUse != null)) {
      request.config.systemInstruction = null;
    }
  }

  Map<String, String> _mergeTrackingHeaders(Map<String, String>? headers) {
    final Map<String, String> merged = <String, String>{
      'x-goog-api-client': 'adk_dart',
    };
    if (headers != null) {
      merged.addAll(headers);
    }
    return merged;
  }
}

typedef GoogleLlm = Gemini;
