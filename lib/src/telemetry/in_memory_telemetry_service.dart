/// Telemetry configuration, exporters, and tracing helpers.
library;

import '../types/id.dart';
import 'base_telemetry_service.dart';

/// In-memory telemetry implementation for local development and tests.
class InMemoryTelemetryService extends BaseTelemetryService {
  /// Creates an in-memory telemetry collector.
  InMemoryTelemetryService();

  final Map<String, TelemetrySpan> _spans = <String, TelemetrySpan>{};
  final List<String> _order = <String>[];

  @override
  /// Starts and tracks a new in-memory span.
  TelemetrySpan startSpan(
    String name, {
    String? parentSpanId,
    Map<String, Object?>? attributes,
  }) {
    final TelemetrySpan span = TelemetrySpan(
      id: newAdkId(prefix: 'span_'),
      name: name,
      startTime: DateTime.now().toUtc(),
      parentSpanId: parentSpanId,
      attributes: attributes,
    );
    _spans[span.id] = span;
    _order.add(span.id);
    return span;
  }

  @override
  /// Ends an existing span if it is currently open.
  void endSpan(
    String spanId, {
    Map<String, Object?>? attributes,
    Object? error,
  }) {
    final TelemetrySpan? span = _spans[spanId];
    if (span == null || span.endTime != null) {
      return;
    }
    if (attributes != null) {
      span.attributes.addAll(attributes);
    }
    if (error != null) {
      span.attributes['error'] = '$error';
    }
    span.endTime = DateTime.now().toUtc();
  }

  @override
  /// Records a log entry for the given [spanId].
  void log(String spanId, String message, {Map<String, Object?>? attributes}) {
    final TelemetrySpan? span = _spans[spanId];
    if (span == null) {
      return;
    }
    span.logs.add(
      TelemetryLogRecord(
        timestamp: DateTime.now().toUtc(),
        message: message,
        attributes: attributes,
      ),
    );
  }

  @override
  /// Returns deep-copied spans in creation order.
  List<TelemetrySpan> snapshot() {
    return _order.map((String id) {
      final TelemetrySpan span = _spans[id]!;
      return TelemetrySpan(
        id: span.id,
        name: span.name,
        startTime: span.startTime,
        endTime: span.endTime,
        parentSpanId: span.parentSpanId,
        attributes: Map<String, Object?>.from(span.attributes),
        logs: span.logs
            .map(
              (TelemetryLogRecord log) => TelemetryLogRecord(
                timestamp: log.timestamp,
                message: log.message,
                attributes: Map<String, Object?>.from(log.attributes),
              ),
            )
            .toList(),
      );
    }).toList();
  }
}
