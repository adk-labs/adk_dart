import 'dart:io';

Map<String, String> readSystemEnvironmentImpl() {
  return Map<String, String>.from(Platform.environment);
}

String readRuntimeLanguageVersionImpl() {
  return Platform.version.split(' ').first;
}
