/// Registry for resolving model IDs to concrete adapter implementations.
library;

import 'anthropic_llm.dart';
import 'apigee_llm.dart';
import 'base_llm.dart';
import 'gemma_llm.dart';
import 'google_llm.dart';
import 'lite_llm.dart';

/// Factory function that creates an LLM adapter for a model string.
typedef LlmFactory = BaseLlm Function(String model);

class _RegistryEntry {
  _RegistryEntry({required this.patterns, required this.factory});

  final List<RegExp> patterns;
  final LlmFactory factory;
}

/// Registry that maps model patterns to concrete LLM adapters.
class LLMRegistry {
  LLMRegistry._();

  static final List<_RegistryEntry> _entries = <_RegistryEntry>[];
  static bool _defaultsRegistered = false;

  /// Registers a model [factory] for [supportedModels] regex patterns.
  static void register({
    required List<RegExp> supportedModels,
    required LlmFactory factory,
  }) {
    _entries.add(_RegistryEntry(patterns: supportedModels, factory: factory));
  }

  /// Creates a new adapter instance for [model].
  static BaseLlm newLlm(String model) {
    ensureDefaultModelsRegistered();
    return resolve(model)(model);
  }

  /// Resolves the factory responsible for [model].
  ///
  /// Throws a [StateError] when no registered pattern matches [model].
  static LlmFactory resolve(String model) {
    ensureDefaultModelsRegistered();
    for (final _RegistryEntry entry in _entries) {
      for (final RegExp pattern in entry.patterns) {
        if (pattern.hasMatch(model) && pattern.stringMatch(model) == model) {
          return entry.factory;
        }
      }
    }
    throw StateError('Model $model not found. Register it in LLMRegistry.');
  }

  /// Clears all registry entries, including built-in defaults.
  static void clear() {
    _entries.clear();
    _defaultsRegistered = false;
  }

  /// Registers built-in model families once.
  static void ensureDefaultModelsRegistered() {
    if (_defaultsRegistered) {
      return;
    }
    _defaultsRegistered = true;

    register(
      supportedModels: Gemini.supportedModels(),
      factory: (String model) => Gemini(model: model),
    );
    register(
      supportedModels: GemmaLlm.supportedModels(),
      factory: (String model) => GemmaLlm(model: model),
    );
    register(
      supportedModels: ApigeeLlm.supportedModels(),
      factory: (String model) => ApigeeLlm(model: model),
    );
    register(
      supportedModels: AnthropicLlm.supportedModels(),
      factory: (String model) => AnthropicLlm(model: model),
    );
    register(
      supportedModels: LiteLlm.supportedModels(),
      factory: (String model) => LiteLlm(model: model),
    );
  }
}
