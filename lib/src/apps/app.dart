import '../agents/base_agent.dart';
import '../plugins/base_plugin.dart';

void validateAppName(String name) {
  final RegExp pattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  if (!pattern.hasMatch(name)) {
    throw ArgumentError(
      "Invalid app name '$name': must be a valid identifier.",
    );
  }
  if (name == 'user') {
    throw ArgumentError(
      "App name cannot be 'user'; reserved for end-user input.",
    );
  }
}

class ResumabilityConfig {
  ResumabilityConfig({this.isResumable = false});

  bool isResumable;
}

class EventsCompactionConfig {
  EventsCompactionConfig({
    this.compactionInterval = 0,
    this.overlapSize = 0,
    this.tokenThreshold,
    this.eventRetentionSize,
    this.summarizer,
  }) {
    final bool tokenSet = tokenThreshold != null;
    final bool retentionSet = eventRetentionSize != null;
    if (tokenSet != retentionSet) {
      throw ArgumentError(
        'tokenThreshold and eventRetentionSize must be set together.',
      );
    }
  }

  int compactionInterval;
  int overlapSize;
  int? tokenThreshold;
  int? eventRetentionSize;
  Object? summarizer;
}

class App {
  App({
    required this.name,
    required this.rootAgent,
    List<BasePlugin>? plugins,
    this.eventsCompactionConfig,
    this.contextCacheConfig,
    this.resumabilityConfig,
  }) : plugins = plugins ?? <BasePlugin>[] {
    validateAppName(name);
  }

  String name;
  BaseAgent rootAgent;
  List<BasePlugin> plugins;
  EventsCompactionConfig? eventsCompactionConfig;
  Object? contextCacheConfig;
  ResumabilityConfig? resumabilityConfig;
}
