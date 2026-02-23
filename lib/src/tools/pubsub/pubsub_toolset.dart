import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'client.dart';
import 'config.dart';
import 'message_tool.dart' as message_tool;
import 'pubsub_credentials.dart';

class PubSubToolset extends BaseToolset {
  PubSubToolset({
    super.toolFilter,
    PubSubCredentialsConfig? credentialsConfig,
    PubSubToolConfig? pubsubToolConfig,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = pubsubToolConfig ?? PubSubToolConfig();

  final PubSubCredentialsConfig? _credentialsConfig;
  final PubSubToolConfig _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.pubsubToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: message_tool.publishMessage,
        name: 'publish_message',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: message_tool.pullMessages,
        name: 'pull_messages',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: message_tool.acknowledgeMessages,
        name: 'acknowledge_messages',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
    ];

    return allTools
        .where((GoogleTool tool) => isToolSelected(tool, readonlyContext))
        .toList();
  }

  @override
  Future<void> close() async {
    await cleanupClients();
  }
}
