import '../events/event.dart';

class Session {
  Session({
    required this.id,
    required this.appName,
    required this.userId,
    Map<String, Object?>? state,
    List<Event>? events,
    this.lastUpdateTime = 0,
  }) : state = state ?? <String, Object?>{},
       events = events ?? <Event>[];

  String id;
  String appName;
  String userId;
  Map<String, Object?> state;
  List<Event> events;
  double lastUpdateTime;

  Session copyWith({
    String? id,
    String? appName,
    String? userId,
    Map<String, Object?>? state,
    List<Event>? events,
    double? lastUpdateTime,
  }) {
    return Session(
      id: id ?? this.id,
      appName: appName ?? this.appName,
      userId: userId ?? this.userId,
      state: state ?? Map<String, Object?>.from(this.state),
      events: events ?? this.events.map((event) => event.copyWith()).toList(),
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }
}
