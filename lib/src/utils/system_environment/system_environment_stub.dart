/// Web and unsupported-platform stubs for system environment helpers.
library;

/// Returns an empty environment map for unsupported platforms.
Map<String, String> readSystemEnvironmentImpl() {
  return const <String, String>{};
}

/// Returns `web` as the runtime marker on unsupported platforms.
String readRuntimeLanguageVersionImpl() {
  return 'web';
}
