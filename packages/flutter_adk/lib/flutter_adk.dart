/// Flutter-facing ADK facade package.
///
/// This library re-exports the Web-safe ADK runtime surface from
/// `package:adk_dart/adk_core.dart`, plugin platform utilities, and
/// ready-to-use Flutter UI widgets and controllers.
library;

import 'flutter_adk_platform_interface.dart';

export 'package:adk_dart/adk_core.dart' hide State;

export 'src/controllers/adk_chat_controller.dart';
export 'src/models/adk_attachment_model.dart';
export 'src/models/adk_chat_message.dart';
export 'src/models/adk_prompt_suggestion_model.dart';
export 'src/models/adk_session_info.dart';
export 'src/models/adk_token_usage_model.dart';
export 'src/models/adk_tool_call_info.dart';
export 'src/models/adk_voice_state_model.dart';
export 'src/models/adk_workflow_step_model.dart';
export 'src/storage/adk_storage.dart';
export 'src/storage/adk_storage_session_service.dart';
export 'src/theme/adk_theme.dart';
export 'src/widgets/adk_agent_hierarchy_badge.dart';
export 'src/widgets/adk_agent_logger_view.dart';
export 'src/widgets/adk_chat_view.dart';
export 'src/widgets/adk_confirmation_dialog.dart';
export 'src/widgets/adk_dev_studio_view.dart';
export 'src/widgets/adk_event_stream_builder.dart';
export 'src/widgets/adk_floating_chat_button.dart';
export 'src/widgets/adk_message_bubble.dart';
export 'src/widgets/adk_prompt_suggestions_bar.dart';
export 'src/widgets/adk_session_drawer.dart';
export 'src/widgets/adk_structured_data_view.dart';
export 'src/widgets/adk_token_usage_badge.dart';
export 'src/widgets/adk_tool_call_card.dart';
export 'src/widgets/adk_tool_inspector_view.dart';
export 'src/widgets/adk_typing_indicator.dart';
export 'src/widgets/adk_voice_widgets.dart';
export 'src/widgets/adk_workflow_progress_indicator.dart';

/// Provides the Flutter-facing entry point for ADK platform features.
class FlutterAdk {
  /// Creates a Flutter plugin helper for platform-specific calls.
  const FlutterAdk();

  /// The platform version reported by the active [FlutterAdkPlatform].
  Future<String?> getPlatformVersion() {
    return FlutterAdkPlatform.instance.getPlatformVersion();
  }
}

