/// Flutter-facing ADK facade package.
///
/// This library re-exports the Web-safe ADK runtime surface from
/// `package:adk_dart/adk_core.dart` and adds plugin platform utilities.
library;

import 'flutter_adk_platform_interface.dart';
export 'package:adk_dart/adk_core.dart' hide State;

/// Provides the Flutter-facing entry point for ADK platform features.
class FlutterAdk {
  /// Creates a Flutter plugin helper for platform-specific calls.
  const FlutterAdk();

  /// The platform version reported by the active [FlutterAdkPlatform].
  Future<String?> getPlatformVersion() {
    return FlutterAdkPlatform.instance.getPlatformVersion();
  }
}
