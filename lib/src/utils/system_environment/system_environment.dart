/// Platform-conditional system environment and runtime version helpers.
library;

import 'system_environment_stub.dart'
    if (dart.library.io) 'system_environment_io.dart';

/// Returns process environment values for the active platform.
Map<String, String> readSystemEnvironment() {
  return readSystemEnvironmentImpl();
}

/// Returns the runtime language version string.
String readRuntimeLanguageVersion() {
  return readRuntimeLanguageVersionImpl();
}
