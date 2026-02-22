class TelemetryLogRecord {
  TelemetryLogRecord({
    required this.timestamp,
    required this.message,
    Map<String, Object?>? attributes,
  }) : attributes = attributes ?? <String, Object?>{};

  final DateTime timestamp;
  final String message;
  final Map<String, Object?> attributes;
}

class TelemetrySpan {
  TelemetrySpan({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.parentSpanId,
    Map<String, Object?>? attributes,
    List<TelemetryLogRecord>? logs,
  }) : attributes = attributes ?? <String, Object?>{},
       logs = logs ?? <TelemetryLogRecord>[];

  final String id;
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  final String? parentSpanId;
  final Map<String, Object?> attributes;
  final List<TelemetryLogRecord> logs;

  bool get isOpen => endTime == null;
}

abstract class BaseTelemetryService {
  TelemetrySpan startSpan(
    String name, {
    String? parentSpanId,
    Map<String, Object?>? attributes,
  });

  void endSpan(
    String spanId, {
    Map<String, Object?>? attributes,
    Object? error,
  });

  void log(String spanId, String message, {Map<String, Object?>? attributes});

  List<TelemetrySpan> snapshot();
}
