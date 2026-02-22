class FeatureFlags {
  FeatureFlags({Map<String, bool>? values})
    : _values = values ?? <String, bool>{};

  final Map<String, bool> _values;

  bool isEnabled(String flag, {bool defaultValue = false}) {
    return _values[flag] ?? defaultValue;
  }

  void set(String flag, bool enabled) {
    _values[flag] = enabled;
  }

  Map<String, bool> snapshot() => Map<String, bool>.from(_values);
}
