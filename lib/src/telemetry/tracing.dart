import 'dart:async';

import 'base_telemetry_service.dart';

Future<T> traceSpan<T>(
  BaseTelemetryService telemetryService,
  String name,
  Future<T> Function(TelemetrySpan span) run, {
  String? parentSpanId,
  Map<String, Object?>? attributes,
}) async {
  final TelemetrySpan span = telemetryService.startSpan(
    name,
    parentSpanId: parentSpanId,
    attributes: attributes,
  );
  try {
    final T value = await run(span);
    telemetryService.endSpan(span.id);
    return value;
  } catch (error) {
    telemetryService.endSpan(span.id, error: error);
    rethrow;
  }
}
