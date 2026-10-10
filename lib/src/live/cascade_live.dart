/// BaseLlm wrapper that adds cascaded live audio support to any text model.
library;

import '../features/_feature_decorator.dart';
import '../features/_feature_registry.dart';
import '../models/base_llm.dart';
import '../models/base_llm_connection.dart';
import '../models/capabilities.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import 'cascade_live_connection.dart';
import 'transforms.dart';

/// Wraps any text [BaseLlm] with speech-to-text and text-to-speech transforms
/// to support live audio sessions.
///
/// Non-live calls via [generateContent] delegate directly to the underlying
/// model, while [connect] returns a [CascadeLiveConnection] that orchestrates
/// the `STT -> LLM -> TTS` pipeline.
///
/// ```dart
/// final model = CascadeLive(
///   model: 'gemini-2.5-flash',
///   stt: mySttTransform,
///   tts: myTtsTransform,
/// );
/// ```
class CascadeLive extends BaseLlm {
  /// Creates a cascaded live model wrapper around [model] (`String` model name
  /// or [BaseLlm] instance) with [stt] and [tts] stream transforms.
  CascadeLive({
    required Object model,
    required this.stt,
    required this.tts,
  }) : _llm = model is BaseLlm ? model : null,
       super(model: _extractModelName(model)) {
    experimental(FeatureName.cascadeLive).checkEnabled();
  }

  static String _extractModelName(Object model) {
    if (model is BaseLlm) {
      if (model.model.isEmpty) {
        throw ArgumentError.value(
          model,
          'model',
          'CascadeLive requires an LLM `model`.',
        );
      }
      return model.model;
    }
    if (model is String) {
      if (model.isEmpty) {
        throw ArgumentError.value(
          model,
          'model',
          'CascadeLive requires an LLM `model`.',
        );
      }
      return model;
    }
    throw ArgumentError.value(
      model,
      'model',
      'model must be a non-empty String or a BaseLlm instance.',
    );
  }

  /// Speech-to-text ingress transform.
  final LiveIngress stt;

  /// Text-to-speech egress transform.
  final LiveEgress tts;

  BaseLlm? _llm;

  /// The cached underlying [BaseLlm] instance, or `null` if not yet resolved.
  BaseLlm? get resolvedLlm => _llm;

  BaseLlm _resolveLlm() {
    return _llm ??= LLMRegistry.newLlm(model);
  }

  @override
  LlmCapabilities get capabilities => _resolveLlm().capabilities;

  /// Serializes this model configuration to a JSON-compatible map without
  /// leaking the cached [BaseLlm] instance.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'model': model,
      'stt': stt,
      'tts': tts,
    };
  }

  /// Delegates content generation directly to the underlying [BaseLlm].
  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    return _resolveLlm().generateContent(request, stream: stream);
  }

  /// Opens a [CascadeLiveConnection] for [request].
  BaseLlmConnection connect(LlmRequest request) {
    final BaseLlm llm = _resolveLlm();
    return CascadeLiveConnection(request, llm, stt, tts);
  }
}
