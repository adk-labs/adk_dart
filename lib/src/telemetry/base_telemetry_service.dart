/// One log entry recorded under a telemetry span.
class TelemetryLogRecord {
  /// Creates a span log entry.
  TelemetryLogRecord({
    required this.timestamp,
    required this.message,
    Map<String, Object?>? attributes,
  }) : attributes = attributes ?? <String, Object?>{};

  /// UTC timestamp when the log entry was produced.
  final DateTime timestamp;

  /// Human-readable log message.
  final String message;

  /// Structured key-value attributes for this log entry.
  final Map<String, Object?> attributes;
}

/// Span model representing one traced operation.
class TelemetrySpan {
  /// Creates a telemetry span descriptor.
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

  /// Unique span identifier.
  final String id;

  /// Span name, typically operation-oriented.
  final String name;

  /// UTC start time for the span.
  final DateTime startTime;

  /// UTC end time, or `null` while span is open.
  DateTime? endTime;

  /// Optional parent span identifier.
  final String? parentSpanId;

  /// Span-level attributes.
  final Map<String, Object?> attributes;

  /// Logs emitted during span execution.
  final List<TelemetryLogRecord> logs;

  /// Whether the span has not been closed yet.
  bool get isOpen => endTime == null;
}

/// Contract for telemetry trace/span lifecycle services.
abstract class BaseTelemetryService {
  /// Creates and opens a span for [name].
  BaseTelemetryService();

  /// Starts a new span.
  TelemetrySpan startSpan(
    String name, {
    String? parentSpanId,
    Map<String, Object?>? attributes,
  });

  /// Closes a span and optionally attaches [attributes] and [error].
  void endSpan(
    String spanId, {
    Map<String, Object?>? attributes,
    Object? error,
  });

  /// Adds one log [message] to the given [spanId].
  void log(String spanId, String message, {Map<String, Object?>? attributes});

  /// Returns an immutable-style snapshot of all known spans.
  List<TelemetrySpan> snapshot();
}
