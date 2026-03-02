/// Mutable feature flag map used by feature-gating helpers.
library;

/// Simple in-memory feature flag storage.
class FeatureFlags {
  /// Creates feature flag storage with optional initial [values].
  FeatureFlags({Map<String, bool>? values})
    : _values = values ?? <String, bool>{};

  final Map<String, bool> _values;

  /// Whether [flag] is enabled, falling back to [defaultValue].
  bool isEnabled(String flag, {bool defaultValue = false}) {
    return _values[flag] ?? defaultValue;
  }

  /// Sets [flag] to [enabled].
  void set(String flag, bool enabled) {
    _values[flag] = enabled;
  }

  /// Returns a defensive copy of current flag values.
  Map<String, bool> snapshot() => Map<String, bool>.from(_values);
}
