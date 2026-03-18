/// Core session model used across runners and session services.
library;

import '../events/event.dart';

/// A conversational session containing state and event history.
class Session {
  /// Creates a session value.
  Session({
    required this.id,
    required this.appName,
    required this.userId,
    Map<String, Object?>? state,
    List<Event>? events,
    this.lastUpdateTime = 0,
    this.storageUpdateMarker,
  }) : state = state ?? <String, Object?>{},
       events = events ?? <Event>[];

  /// Unique session identifier.
  String id;

  /// Application name associated with this session.
  String appName;

  /// User identifier associated with this session.
  String userId;

  /// Session-scoped state map, including prefixed app and user entries.
  Map<String, Object?> state;

  /// Chronological event history for this session.
  List<Event> events;

  /// Timestamp of the last update in seconds since epoch.
  double lastUpdateTime;

  /// Exact storage revision marker used for stale-writer detection.
  String? storageUpdateMarker;

  /// Returns a deep-copied session with optional field overrides.
  Session copyWith({
    String? id,
    String? appName,
    String? userId,
    Map<String, Object?>? state,
    List<Event>? events,
    double? lastUpdateTime,
    Object? storageUpdateMarker = _sessionSentinel,
  }) {
    return Session(
      id: id ?? this.id,
      appName: appName ?? this.appName,
      userId: userId ?? this.userId,
      state: state ?? Map<String, Object?>.from(this.state),
      events: events ?? this.events.map((event) => event.copyWith()).toList(),
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      storageUpdateMarker: identical(storageUpdateMarker, _sessionSentinel)
          ? this.storageUpdateMarker
          : storageUpdateMarker as String?,
    );
  }
}

const Object _sessionSentinel = Object();
