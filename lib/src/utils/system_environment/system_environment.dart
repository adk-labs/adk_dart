import 'system_environment_stub.dart'
    if (dart.library.io) 'system_environment_io.dart';

Map<String, String> readSystemEnvironment() {
  return readSystemEnvironmentImpl();
}

String readRuntimeLanguageVersion() {
  return readRuntimeLanguageVersionImpl();
}
