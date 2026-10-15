/// Router-driven language model wrapper with failover support.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'capabilities.dart';
import 'llm_request.dart';
import 'llm_response.dart';

/// Error context passed to an [LlmRouter] when a candidate model fails before
/// yielding any responses.
class RoutedLlmErrorContext {
  /// Creates a routed LLM error context.
  const RoutedLlmErrorContext({
    required this.failedKeys,
    required this.lastError,
  });

  /// Keys of models that have already failed during this routing attempt.
  final Set<String> failedKeys;

  /// The error thrown by the most recently attempted model.
  final Object lastError;
}

/// Function that selects a model key from [models] for [request].
///
/// When called after a failure, [errorContext] provides the set of already
/// tried keys and the last error. Returning `null` stops failover and rethrows
/// the last error.
typedef LlmRouter =
    FutureOr<String?> Function(
      Map<String, BaseLlm> models,
      LlmRequest request, {
      RoutedLlmErrorContext? errorContext,
    });

/// Runs [runFn] against items selected by [router], failing over if an item
/// throws before emitting its first value.
Stream<TYield> runWithRouting<T, C, TYield>(
  Map<String, T> items,
  C context,
  FutureOr<String?> Function(
    Map<String, T> items,
    C context, {
    RoutedLlmErrorContext? errorContext,
  })
  router,
  Stream<TYield> Function(T item) runFn,
) async* {
  final Map<String, T> unmodifiableItems = Map<String, T>.unmodifiable(items);
  final String? initialKey = await router(unmodifiableItems, context);
  if (initialKey == null || initialKey.isEmpty) {
    throw StateError('Initial routing failed, no item selected.');
  }

  String selectedKey = initialKey;
  developer.log(
    'Router selected initial key: $selectedKey',
    name: 'adk_dart.models.routed_llm',
  );
  T? selectedItem = unmodifiableItems[selectedKey];
  if (selectedItem == null) {
    throw ArgumentError('Item not found for key: $selectedKey');
  }

  final Set<String> triedKeys = <String>{selectedKey};

  while (true) {
    bool firstYielded = false;
    try {
      await for (final TYield result in runFn(selectedItem as T)) {
        firstYielded = true;
        yield result;
      }
      return;
    } catch (error) {
      if (firstYielded) {
        rethrow;
      }

      final String? nextKey = await router(
        unmodifiableItems,
        context,
        errorContext: RoutedLlmErrorContext(
          failedKeys: Set<String>.unmodifiable(triedKeys),
          lastError: error,
        ),
      );

      developer.log(
        'Router selected next key: $nextKey',
        name: 'adk_dart.models.routed_llm',
      );

      if (nextKey == null || triedKeys.contains(nextKey)) {
        rethrow;
      }

      selectedKey = nextKey;
      selectedItem = unmodifiableItems[selectedKey];
      if (selectedItem == null) {
        throw ArgumentError('Item not found for key: $selectedKey');
      }
      triedKeys.add(selectedKey);
    }
  }
}

/// A [BaseLlm] implementation that delegates to one of multiple models based
/// on an [LlmRouter] function.
///
/// ```dart
/// final model = RoutedLlm(
///   models: <String, BaseLlm>{
///     'fast': Gemini(model: 'gemini-2.5-flash'),
///     'pro': Gemini(model: 'gemini-2.5-pro'),
///   },
///   router: (models, request, {errorContext}) =>
///       errorContext == null ? 'fast' : 'pro',
/// );
/// ```
class RoutedLlm extends BaseLlm {
  /// Creates a [RoutedLlm] from a map or list of [BaseLlm] instances and a
  /// [router] callback.
  ///
  /// [models] must be either a `Map<String, BaseLlm>` or a `List<BaseLlm>`.
  RoutedLlm({
    required Object models,
    required this.router,
    String modelName = 'routed-llm',
  }) : models = Map<String, BaseLlm>.unmodifiable(_normalizeModels(models)),
       super(
         model: modelName == 'routed-llm'
             ? _computeModelName(_normalizeModels(models))
             : modelName,
       );

  /// Candidate models keyed by router key.
  final Map<String, BaseLlm> models;

  /// Router function used to select and fail over between [models].
  final LlmRouter router;

  static Map<String, BaseLlm> _normalizeModels(Object models) {
    if (models is Map<String, BaseLlm>) {
      return Map<String, BaseLlm>.from(models);
    }
    if (models is List<BaseLlm>) {
      return <String, BaseLlm>{
        for (final BaseLlm m in models) m.model: m,
      };
    }
    if (models is Iterable<BaseLlm>) {
      return <String, BaseLlm>{
        for (final BaseLlm m in models) m.model: m,
      };
    }
    throw ArgumentError(
      'RoutedLlm models must be a Map<String, BaseLlm> or List<BaseLlm>.',
    );
  }

  static String _computeModelName(Map<String, BaseLlm> modelsMap) {
    final String joined = modelsMap.entries
        .map((MapEntry<String, BaseLlm> e) => '${e.key} (${e.value.model})')
        .join(', ');
    return 'RoutedLlm[$joined]';
  }

  @override
  LlmCapabilities get capabilities => models.isEmpty
      ? super.capabilities
      : models.values.first.capabilities;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    developer.log(
      'Routing request via $model',
      name: 'adk_dart.models.routed_llm',
    );
    yield* runWithRouting<BaseLlm, LlmRequest, LlmResponse>(
      models,
      request,
      router,
      (BaseLlm selected) {
        request.model = selected.model;
        return selected.generateContent(request, stream: stream);
      },
    );
  }

  /// Creates a live connection by delegating to the model selected by [router].
  Future<BaseLlmConnection> connect(LlmRequest request) async {
    final Stream<BaseLlmConnection> stream =
        runWithRouting<BaseLlm, LlmRequest, BaseLlmConnection>(
          models,
          request,
          router,
          (BaseLlm selected) async* {
            request.model = selected.model;
            final dynamic dynamicSelected = selected;
            final Object? result = await Future<Object?>.value(
              dynamicSelected.connect(request),
            );
            if (result is BaseLlmConnection) {
              yield result;
              return;
            }
            throw StateError(
              'Delegate model `${selected.model}` did not return a BaseLlmConnection.',
            );
          },
        );
    final List<BaseLlmConnection> connections = await stream.take(1).toList();
    if (connections.isEmpty) {
      throw StateError(
        'Failed to establish connection: No connection yielded.',
      );
    }
    return connections.first;
  }
}
