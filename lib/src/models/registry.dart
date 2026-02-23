import 'anthropic_llm.dart';
import 'apigee_llm.dart';
import 'base_llm.dart';
import 'gemma_llm.dart';
import 'google_llm.dart';
import 'lite_llm.dart';

typedef LlmFactory = BaseLlm Function(String model);

class _RegistryEntry {
  _RegistryEntry({required this.patterns, required this.factory});

  final List<RegExp> patterns;
  final LlmFactory factory;
}

class LLMRegistry {
  LLMRegistry._();

  static final List<_RegistryEntry> _entries = <_RegistryEntry>[];
  static bool _defaultsRegistered = false;

  static void register({
    required List<RegExp> supportedModels,
    required LlmFactory factory,
  }) {
    _entries.add(_RegistryEntry(patterns: supportedModels, factory: factory));
  }

  static BaseLlm newLlm(String model) {
    ensureDefaultModelsRegistered();
    return resolve(model)(model);
  }

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

  static void clear() {
    _entries.clear();
    _defaultsRegistered = false;
  }

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
