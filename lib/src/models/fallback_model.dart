/// A model that falls back to backup models when a call fails.
library;

import 'dart:developer' as developer;

import 'anthropic_llm.dart';
import 'apigee_llm.dart';
import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'capabilities.dart';
import 'gemini_rest_api_client.dart';
import 'llm_request.dart';
import 'llm_response.dart';
import 'registry.dart';
import '../types/content.dart';

String _modelName(Object entry) {
  if (entry is BaseLlm) {
    return entry.model;
  }
  if (entry is String) {
    return entry;
  }
  throw ArgumentError('Model entry must be a String or BaseLlm, got: $entry');
}

int? _extractStatusCode(Object error) {
  if (error is GeminiRestApiException) {
    return error.statusCode;
  }
  if (error is AnthropicApiException) {
    return error.statusCode;
  }
  if (error is ChatCompletionsHttpException) {
    return error.statusCode;
  }
  if (error is RecoverableLiveConnectionException) {
    return error.code;
  }

  try {
    final dynamic dynamicError = error;
    final Object? status = dynamicError.statusCode;
    if (status is int) {
      return status;
    }
  } catch (_) {}

  try {
    final dynamic dynamicError = error;
    final Object? code = dynamicError.code;
    if (code is int) {
      return code;
    }
  } catch (_) {}

  return null;
}

class _RequestSnapshot {
  _RequestSnapshot({
    required this.contents,
    required this.config,
    required this.liveConnectConfig,
    required this.isManagedAgent,
  });

  final List<Content> contents;
  final GenerateContentConfig config;
  final LiveConnectConfig liveConnectConfig;
  final bool isManagedAgent;

  factory _RequestSnapshot.of(LlmRequest request) {
    return _RequestSnapshot(
      contents: request.contents.map((Content c) => c.copyWith()).toList(),
      config: request.config.copyWith(),
      liveConnectConfig: request.liveConnectConfig.copyWith(),
      isManagedAgent: request.isManagedAgent,
    );
  }

  void restore(LlmRequest request) {
    request.contents = contents.map((Content c) => c.copyWith()).toList();
    request.config = config.copyWith();
    request.liveConnectConfig = liveConnectConfig.copyWith();
    request.isManagedAgent = isManagedAgent;
  }
}

/// Tries a sequence of models in order, moving on when one fails.
///
/// Each model is tried once. Only failures that carry one of
/// [retriableStatusCodes] trigger a fallback to the next model in the list.
class FallbackModel extends BaseLlm {
  /// Default HTTP status codes that cause the next model to be tried.
  static const Set<int> defaultStatusCodes = <int>{
    429, // Too many requests.
    500, // Internal server error.
    502, // Bad gateway.
    503, // Service unavailable.
    504, // Gateway timeout.
  };

  /// Creates a fallback model that delegates to [models] in order.
  FallbackModel({
    required List<Object> models,
    Set<int>? retriableStatusCodes,
    String? model,
  })  : models = List<Object>.unmodifiable(models),
        retriableStatusCodes =
            retriableStatusCodes != null
                ? Set<int>.unmodifiable(retriableStatusCodes)
                : defaultStatusCodes,
        super(model: _deriveModelName(models, model));

  static String _deriveModelName(List<Object> models, String? model) {
    if (models.isEmpty) {
      throw ArgumentError('models must not be empty');
    }
    final String primaryName = _modelName(models.first);
    if (model != null && model.isNotEmpty && model != primaryName) {
      throw ArgumentError(
        'FallbackModel.model is derived from the first entry of `models` and cannot be set directly: got "$model", expected "$primaryName". List the models to try in `models`.',
      );
    }
    return primaryName;
  }

  /// The models to try, in order. The first entry is the primary model.
  final List<Object> models;

  /// The HTTP status codes that cause the next model to be tried.
  final Set<int> retriableStatusCodes;

  final Map<String, BaseLlm> _resolved = <String, BaseLlm>{};

  BaseLlm _delegate(Object entry) {
    if (entry is BaseLlm) {
      return entry;
    }
    if (entry is String) {
      return _resolved.putIfAbsent(entry, () => LLMRegistry.newLlm(entry));
    }
    throw ArgumentError('Model entry must be a String or BaseLlm, got: $entry');
  }

  bool _shouldFallBack(Object error) {
    final int? statusCode = _extractStatusCode(error);
    return statusCode != null && retriableStatusCodes.contains(statusCode);
  }

  @override
  LlmCapabilities get capabilities => _delegate(models.first).capabilities;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final int lastIndex = models.length - 1;

    for (int index = 0; index < models.length; index++) {
      final BaseLlm delegate = _delegate(models[index]);
      final _RequestSnapshot? pristine =
          index < lastIndex ? _RequestSnapshot.of(request) : null;
      request.model = delegate.model;
      bool responseYielded = false;

      try {
        await for (final LlmResponse response in delegate.generateContent(
          request,
          stream: stream,
        )) {
          responseYielded = true;
          yield response;
        }
        return;
      } catch (error) {
        if (responseYielded || !_shouldFallBack(error)) {
          rethrow;
        }
        if (index == lastIndex) {
          rethrow;
        }
        developer.log(
          'Model ${delegate.model} failed with status ${_extractStatusCode(error)}; falling back to next model.',
          name: 'adk_dart.models.fallback',
        );
        pristine?.restore(request);
      }
    }
  }

  /// Creates a live connection using the first model that connects successfully.
  BaseLlmConnection connect(LlmRequest request) {
    final int lastIndex = models.length - 1;

    for (int index = 0; index < models.length; index++) {
      final BaseLlm delegate = _delegate(models[index]);
      final _RequestSnapshot? pristine =
          index < lastIndex ? _RequestSnapshot.of(request) : null;
      request.model = delegate.model;

      try {
        final dynamic dynamicDelegate = delegate;
        final Object? connection = dynamicDelegate.connect(request);
        if (connection is BaseLlmConnection) {
          return connection;
        }
        throw StateError(
          'Delegate model `${delegate.model}` did not return a BaseLlmConnection.',
        );
      } catch (error) {
        if (index == lastIndex || !_shouldFallBack(error)) {
          rethrow;
        }
        developer.log(
          'Model ${delegate.model} failed to connect with status ${_extractStatusCode(error)}; falling back to next model.',
          name: 'adk_dart.models.fallback',
        );
        pristine?.restore(request);
      }
    }

    throw StateError('No models available in FallbackModel to connect.');
  }
}
