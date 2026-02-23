import '../../events/event.dart';
import '../../sessions/session.dart';
import 'shared.dart';
import 'v0.dart';

class StorageMetadataV1 {
  StorageMetadataV1({required this.key, required this.value});

  final String key;
  final String value;

  factory StorageMetadataV1.fromJson(Map<String, Object?> json) {
    return StorageMetadataV1(
      key: '${json['key'] ?? ''}',
      value: '${json['value'] ?? ''}',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'value': value,
  };
}

class StorageSessionV1 {
  StorageSessionV1({
    required this.appName,
    required this.userId,
    required this.id,
    Map<String, Object?>? state,
    DateTime? createTime,
    DateTime? updateTime,
    List<StorageEventV1>? storageEvents,
  }) : state = state ?? <String, Object?>{},
       createTime = createTime ?? DateTime.now().toUtc(),
       updateTime = updateTime ?? DateTime.now().toUtc(),
       storageEvents = storageEvents ?? <StorageEventV1>[];

  final String appName;
  final String userId;
  final String id;
  final Map<String, Object?> state;
  final DateTime createTime;
  final DateTime updateTime;
  final List<StorageEventV1> storageEvents;

  factory StorageSessionV1.fromJson(Map<String, Object?> json) {
    final List<StorageEventV1> events = <StorageEventV1>[];
    final Object? rawEvents = json['storage_events'] ?? json['storageEvents'];
    if (rawEvents is List) {
      for (final Object? item in rawEvents) {
        if (item is Map<String, Object?>) {
          events.add(StorageEventV1.fromJson(item));
        } else if (item is Map) {
          events.add(
            StorageEventV1.fromJson(
              item.map((Object? key, Object? value) => MapEntry('$key', value)),
            ),
          );
        }
      }
    }
    return StorageSessionV1(
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      id: '${json['id'] ?? ''}',
      state: _castMap(json['state']),
      createTime: _parseDateTime(json['create_time'] ?? json['createTime']),
      updateTime: _parseDateTime(json['update_time'] ?? json['updateTime']),
      storageEvents: events,
    );
  }

  double getUpdateTimestamp({bool isSqlite = false}) {
    return PreciseTimestamp.toSeconds(updateTime);
  }

  Session toSession({
    Map<String, Object?>? stateOverride,
    List<Event>? events,
    bool isSqlite = false,
  }) {
    return Session(
      appName: appName,
      userId: userId,
      id: id,
      state: stateOverride ?? <String, Object?>{},
      events: events ?? <Event>[],
      lastUpdateTime: getUpdateTimestamp(isSqlite: isSqlite),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'id': id,
      'state': state,
      'create_time': createTime.toUtc().toIso8601String(),
      'update_time': updateTime.toUtc().toIso8601String(),
      'storage_events': storageEvents
          .map((StorageEventV1 event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class StorageEventV1 {
  StorageEventV1({
    required this.id,
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.invocationId,
    DateTime? timestamp,
    Map<String, Object?>? eventData,
  }) : timestamp = timestamp ?? DateTime.now().toUtc(),
       eventData = eventData ?? <String, Object?>{};

  final String id;
  final String appName;
  final String userId;
  final String sessionId;
  final String invocationId;
  final DateTime timestamp;
  final Map<String, Object?> eventData;

  factory StorageEventV1.fromJson(Map<String, Object?> json) {
    return StorageEventV1(
      id: '${json['id'] ?? ''}',
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      sessionId: '${json['session_id'] ?? json['sessionId'] ?? ''}',
      invocationId: '${json['invocation_id'] ?? json['invocationId'] ?? ''}',
      timestamp: _parseDateTime(json['timestamp']),
      eventData: _castMap(json['event_data'] ?? json['eventData']),
    );
  }

  factory StorageEventV1.fromEvent({
    required Session session,
    required Event event,
  }) {
    return StorageEventV1(
      id: event.id,
      appName: session.appName,
      userId: session.userId,
      sessionId: session.id,
      invocationId: event.invocationId,
      timestamp: PreciseTimestamp.fromSeconds(event.timestamp),
      eventData: encodeEventData(event),
    );
  }

  Event toEvent() {
    return decodeEventData(
      eventData,
      id: id,
      invocationId: invocationId,
      timestamp: PreciseTimestamp.toSeconds(timestamp),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      'invocation_id': invocationId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'event_data': eventData,
    };
  }
}

Map<String, Object?> encodeEventData(Event event) {
  final StorageEventV0 v0 = StorageEventV0.fromEvent(
    session: Session(id: '', appName: '', userId: ''),
    event: event,
  );
  final Map<String, Object?> json = v0.toJson();
  json.remove('app_name');
  json.remove('user_id');
  json.remove('session_id');
  return json;
}

Event decodeEventData(
  Map<String, Object?> eventData, {
  String? id,
  String? invocationId,
  double? timestamp,
}) {
  final Map<String, Object?> merged = <String, Object?>{
    ...eventData,
    if (id != null) 'id': id,
    if (invocationId != null) 'invocation_id': invocationId,
    if (timestamp != null) 'timestamp': timestamp,
  };
  return StorageEventV0.fromJson(merged).toEvent();
}

Map<String, Object?> _castMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

DateTime _parseDateTime(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is num) {
    return PreciseTimestamp.fromSeconds(value);
  }
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
    final double? asDouble = double.tryParse(value);
    if (asDouble != null) {
      return PreciseTimestamp.fromSeconds(asDouble);
    }
  }
  return DateTime.now().toUtc();
}
