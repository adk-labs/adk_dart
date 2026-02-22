import 'base_llm.dart';

typedef LlmFactory = BaseLlm Function(String model);

class _RegistryEntry {
  _RegistryEntry({required this.patterns, required this.factory});

  final List<RegExp> patterns;
  final LlmFactory factory;
}

class LLMRegistry {
  LLMRegistry._();

  static final List<_RegistryEntry> _entries = <_RegistryEntry>[];

  static void register({
    required List<RegExp> supportedModels,
    required LlmFactory factory,
  }) {
    _entries.add(_RegistryEntry(patterns: supportedModels, factory: factory));
  }

  static BaseLlm newLlm(String model) {
    return resolve(model)(model);
  }

  static LlmFactory resolve(String model) {
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
  }
}
