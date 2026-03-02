/// File-change handlers used by reload-capable CLI workflows.
library;

import 'agent_loader.dart';
import 'shared_value.dart';

/// Handles agent source file change events for cache invalidation.
class AgentChangeEventHandler {
  /// Creates a file-change event handler for the active app.
  AgentChangeEventHandler({
    required this.agentLoader,
    required this.runnersToClean,
    required this.currentAppNameRef,
  });

  /// Agent loader cache manager.
  final AgentLoader agentLoader;

  /// App names whose runners should be restarted.
  final Set<String> runnersToClean;

  /// Mutable pointer to the currently selected app name.
  final SharedValue<String> currentAppNameRef;

  /// Processes one modified [sourcePath] and marks the app for reload.
  void onModified(String sourcePath) {
    final String lower = sourcePath.toLowerCase();
    if (!lower.endsWith('.py') &&
        !lower.endsWith('.yaml') &&
        !lower.endsWith('.yml') &&
        !lower.endsWith('.dart')) {
      return;
    }
    final String appName = currentAppNameRef.value;
    agentLoader.removeAgentFromCache(appName);
    runnersToClean.add(appName);
  }
}
