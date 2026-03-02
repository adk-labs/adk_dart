/// Application-level configuration models for ADK runtime.
library;

import '../agents/base_agent.dart';
import '../plugins/base_plugin.dart';

/// Validates that [name] is a supported app identifier.
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

/// Resumability settings for an app.
class ResumabilityConfig {
  /// Creates resumability settings.
  ResumabilityConfig({this.isResumable = false});

  /// Whether invocation resumption is enabled.
  bool isResumable;
}

/// Configuration for event compaction behavior.
class EventsCompactionConfig {
  /// Creates event compaction settings.
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

  /// User-turn interval for sliding-window compaction.
  int compactionInterval;

  /// Number of recent user turns to keep un-compacted.
  int overlapSize;

  /// Optional token threshold for token-based compaction.
  int? tokenThreshold;

  /// Optional number of recent events to retain when compacting.
  int? eventRetentionSize;

  /// Optional summarizer callback.
  Object? summarizer;
}

/// App container describing root agent, plugins, and runtime options.
class App {
  /// Creates an app configuration.
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

  /// Application name.
  String name;

  /// Root agent for this app.
  BaseAgent rootAgent;

  /// Plugins attached to app execution.
  List<BasePlugin> plugins;

  /// Optional event-compaction configuration.
  EventsCompactionConfig? eventsCompactionConfig;

  /// Optional context cache configuration.
  Object? contextCacheConfig;

  /// Optional resumability configuration.
  ResumabilityConfig? resumabilityConfig;
}
