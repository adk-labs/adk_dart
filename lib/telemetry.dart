/// Telemetry, tracing, metrics, and BigQuery agent analytics plugin.
///
/// Provides [BaseTelemetryService], [InMemoryTelemetryService],
/// [SqliteSpanExporter], and [BigQueryAgentAnalyticsPlugin].
///
/// ```dart
/// import 'package:adk_dart/telemetry.dart';
///
/// final telemetry = InMemoryTelemetryService();
/// ```
///
/// @docImport 'src/plugins/bigquery_agent_analytics_plugin.dart';
/// @docImport 'src/telemetry/base_telemetry_service.dart';
/// @docImport 'src/telemetry/in_memory_telemetry_service.dart';
/// @docImport 'src/telemetry/sqlite_span_exporter.dart';
library;

export 'src/plugins/bigquery_agent_analytics_plugin.dart';
export 'src/telemetry/base_telemetry_service.dart';
export 'src/telemetry/google_cloud.dart';
export 'src/telemetry/in_memory_telemetry_service.dart';
export 'src/telemetry/metrics.dart';
export 'src/telemetry/setup.dart';
export 'src/telemetry/sqlite_span_exporter.dart';
export 'src/telemetry/tracing.dart';
