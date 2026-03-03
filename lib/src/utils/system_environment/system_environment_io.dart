/// IO-backed system environment helpers.
library;

import 'dart:io';

/// Returns a copy of [Platform.environment].
Map<String, String> readSystemEnvironmentImpl() {
  return Map<String, String>.from(Platform.environment);
}

/// Returns the current Dart runtime version.
String readRuntimeLanguageVersionImpl() {
  return Platform.version.split(' ').first;
}
