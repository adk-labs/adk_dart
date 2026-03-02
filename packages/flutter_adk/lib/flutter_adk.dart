import 'flutter_adk_platform_interface.dart';
export 'package:adk_dart/adk_core.dart' hide State;

/// Provides the Flutter-facing entry point for ADK platform features.
class FlutterAdk {
  /// The platform version reported by the active [FlutterAdkPlatform].
  Future<String?> getPlatformVersion() {
    return FlutterAdkPlatform.instance.getPlatformVersion();
  }
}
