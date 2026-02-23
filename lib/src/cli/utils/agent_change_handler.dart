import 'agent_loader.dart';
import 'shared_value.dart';

class AgentChangeEventHandler {
  AgentChangeEventHandler({
    required this.agentLoader,
    required this.runnersToClean,
    required this.currentAppNameRef,
  });

  final AgentLoader agentLoader;
  final Set<String> runnersToClean;
  final SharedValue<String> currentAppNameRef;

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
