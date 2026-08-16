/// Toolset exposing Google Cloud Eventarc Advanced publishing capabilities.
library;

import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'config.dart';
import 'message_tool.dart' as message_tool;

/// Toolset for publishing structured CloudEvents to Eventarc Advanced buses.
class EventarcToolset extends BaseToolset {
  /// Creates an Eventarc toolset.
  EventarcToolset({
    super.toolFilter,
    EventarcCredentialsConfig? credentialsConfig,
    EventarcToolConfig? toolConfig,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = toolConfig ?? const EventarcToolConfig();

  final EventarcCredentialsConfig? _credentialsConfig;
  final EventarcToolConfig _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.eventarcToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: message_tool.publishMessage,
        name: 'publish_message',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
    ];

    return allTools
        .where((GoogleTool tool) => isToolSelected(tool, readonlyContext))
        .toList();
  }
}
