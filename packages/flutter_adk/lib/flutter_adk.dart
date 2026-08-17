/// Flutter-facing ADK facade package.
///
/// This library re-exports the Web-safe ADK runtime surface from
/// `package:adk_dart/adk_core.dart`, plugin platform utilities, and
/// ready-to-use Flutter UI widgets and controllers.
library;

import 'flutter_adk_platform_interface.dart';

export 'package:adk_dart/adk_core.dart' hide State;

export 'src/controllers/adk_chat_controller.dart';
export 'src/models/adk_chat_message.dart';
export 'src/widgets/adk_chat_view.dart';
export 'src/widgets/adk_event_stream_builder.dart';
export 'src/widgets/adk_message_bubble.dart';
export 'src/widgets/adk_typing_indicator.dart';

/// Provides the Flutter-facing entry point for ADK platform features.
class FlutterAdk {
  /// Creates a Flutter plugin helper for platform-specific calls.
  const FlutterAdk();

  /// The platform version reported by the active [FlutterAdkPlatform].
  Future<String?> getPlatformVersion() {
    return FlutterAdkPlatform.instance.getPlatformVersion();
  }
}

