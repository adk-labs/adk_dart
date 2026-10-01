/// Event.customMetadata keys and utilities that only ADK internal code may write.
library;

import '../sessions/session.dart';
import 'event.dart';

/// Prefix of `customMetadata` keys that callers cannot set.
///
/// Keys with this prefix are dropped from `RunConfig.customMetadata`, both where
/// it is merged into events and where it is copied into the invocation context,
/// and from events that are restored into a session or received from a remote A2A
/// agent. Stored events keep them, but they are removed from API responses, saved
/// session files, CLI output and A2A messages.
const String internalMetadataPrefix = '__adk_internal_';

/// Set on events that ADK restored into a session from outside it.
const String restoredEventKey = '${internalMetadataPrefix}restored_event';

bool _isInternalKey(Object? key) {
  return key is String && key.startsWith(internalMetadataPrefix);
}

Map<String, Object?> _dropInternalKeys(Map<String, Object?> metadata) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in metadata.entries)
      if (!_isInternalKey(entry.key)) entry.key: entry.value,
  };
}

/// Returns [metadata] without keys that have the internal prefix.
Map<String, Object?>? withoutInternalMetadata(Map<String, Object?>? metadata) {
  if (metadata == null) {
    return null;
  }
  return _dropInternalKeys(metadata);
}

/// Returns [metadata] as callers see it, without internal keys.
/// Returns null if no keys remain.
Map<String, Object?>? publicMetadata(Map<String, Object?>? metadata) {
  if (metadata == null) {
    return null;
  }
  final Map<String, Object?> kept = _dropInternalKeys(metadata);
  return kept.isEmpty ? null : kept;
}

/// Returns only the keys of [metadata] that have the internal prefix.
Map<String, Object?> internalMetadata(Map<String, Object?>? metadata) {
  if (metadata == null) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in metadata.entries)
      if (_isInternalKey(entry.key)) entry.key: entry.value,
  };
}

/// Marks an event restored from outside the session, in place or returning updated event.
Event markRestored(Event event) {
  final Map<String, Object?> clean = withoutInternalMetadata(event.customMetadata) ?? <String, Object?>{};
  clean[restoredEventKey] = true;
  event.customMetadata = clean;
  return event;
}

/// Returns the event as callers see it, without internal metadata.
Event publicEvent(Event event) {
  final Map<String, Object?>? metadata = event.customMetadata;
  if (metadata == null || !metadata.keys.any(_isInternalKey)) {
    return event;
  }
  return event.copyWith(customMetadata: publicMetadata(metadata));
}

/// Returns the session as callers see it, without internal metadata.
Session publicSession(Session session) {
  final List<Event> publicEvents = session.events.map(publicEvent).toList();
  return Session(
    id: session.id,
    appName: session.appName,
    userId: session.userId,
    state: session.state,
    events: publicEvents,
    lastUpdateTime: session.lastUpdateTime,
  );
}
