/// Diagnostic and system inspection utilities for the ADK CLI toolchain.
library;

import 'dart:io';

import 'version.dart';

/// Diagnostics report for the local ADK developer environment.
class AdkSystemInfo {
  /// Collects local environment diagnostics for the active Dart runtime.
  static Map<String, dynamic> collect() {
    return <String, dynamic>{
      'adk_package_version': adkPackageVersion,
      'adk_spec_version': adkSpecVersion,
      'dart_version': Platform.version,
      'operating_system': Platform.operatingSystem,
      'operating_system_version': Platform.operatingSystemVersion,
      'number_of_processors': Platform.numberOfProcessors,
      'executable': Platform.executable,
      'resolved_executable': Platform.resolvedExecutable,
    };
  }

  /// Formats the system diagnostics as a readable multi-line summary string.
  static String formatSummary() {
    final Map<String, dynamic> info = collect();
    final StringBuffer sb = StringBuffer();
    sb.writeln('ADK Dart CLI Environment Diagnostics:');
    sb.writeln('  Package Version : ${info['adk_package_version']}');
    sb.writeln('  Spec Version    : ${info['adk_spec_version']}');
    sb.writeln('  Dart SDK        : ${info['dart_version']}');
    sb.writeln('  Platform OS     : ${info['operating_system']} (${info['operating_system_version']})');
    sb.writeln('  CPU Cores       : ${info['number_of_processors']}');
    sb.writeln('  Executable Path : ${info['executable']}');
    return sb.toString();
  }
}
