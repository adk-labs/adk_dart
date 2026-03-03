/// Telemetry configuration, exporters, and tracing helpers.
library;

import 'dart:io';

/// Environment key for the base OTLP endpoint.
const String otelExporterOtlpEndpoint = 'OTEL_EXPORTER_OTLP_ENDPOINT';

/// Environment key for the OTLP traces endpoint.
const String otelExporterOtlpTracesEndpoint =
    'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT';

/// Environment key for the OTLP metrics endpoint.
const String otelExporterOtlpMetricsEndpoint =
    'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT';

/// Environment key for the OTLP logs endpoint.
const String otelExporterOtlpLogsEndpoint = 'OTEL_EXPORTER_OTLP_LOGS_ENDPOINT';

/// Environment key for service name resource attribute.
const String otelServiceName = 'OTEL_SERVICE_NAME';

/// Environment key for comma-separated OpenTelemetry resource attributes.
const String otelResourceAttributes = 'OTEL_RESOURCE_ATTRIBUTES';

/// OpenTelemetry resource attributes used by telemetry providers.
class OTelResource {
  /// Creates a resource with optional [attributes].
  OTelResource({Map<String, Object?>? attributes})
    : attributes = attributes ?? <String, Object?>{};

  /// Resource attributes keyed by attribute name.
  final Map<String, Object?> attributes;

  /// Merges this resource with [other].
  ///
  /// Values in [other] override keys from this resource.
  OTelResource merge(OTelResource other) {
    final Map<String, Object?> merged = <String, Object?>{}
      ..addAll(attributes)
      ..addAll(other.attributes);
    return OTelResource(attributes: merged);
  }
}

/// Interface for span processors used by a tracer provider.
abstract class SpanProcessor {
  /// Processor kind identifier.
  String get kind;

  /// Exporter instance used by this processor.
  Object get exporter;
}

/// Interface for metric readers used by a meter provider.
abstract class MetricReader {
  /// Reader kind identifier.
  String get kind;

  /// Exporter instance used by this reader.
  Object get exporter;
}

/// Interface for log record processors used by a logger provider.
abstract class LogRecordProcessor {
  /// Processor kind identifier.
  String get kind;

  /// Exporter instance used by this processor.
  Object get exporter;
}

/// Batch span processor wrapper.
class BatchSpanProcessor implements SpanProcessor {
  /// Creates a batch span processor for [exporter].
  BatchSpanProcessor(this.exporter);

  @override
  final Object exporter;

  @override
  String get kind => 'batch_span_processor';
}

/// Metric reader that periodically exports telemetry.
class PeriodicExportingMetricReader implements MetricReader {
  /// Creates a periodic metric reader.
  PeriodicExportingMetricReader(
    this.exporter, {
    this.exportIntervalMillis = 60000,
  });

  @override
  final Object exporter;

  /// Export interval in milliseconds.
  final int exportIntervalMillis;

  @override
  String get kind => 'periodic_metric_reader';
}

/// Batch log record processor wrapper.
class BatchLogRecordProcessor implements LogRecordProcessor {
  /// Creates a batch log record processor for [exporter].
  BatchLogRecordProcessor(this.exporter);

  @override
  final Object exporter;

  @override
  String get kind => 'batch_log_record_processor';
}

/// OTLP span exporter configuration.
class OtlpSpanExporter {
  /// Creates an OTLP span exporter.
  OtlpSpanExporter({this.endpoint, this.session});

  /// Optional endpoint override.
  final String? endpoint;

  /// Optional HTTP session or transport handle.
  final Object? session;
}

/// OTLP metric exporter placeholder type.
class OtlpMetricExporter {
  /// Creates an OTLP metric exporter.
  const OtlpMetricExporter();
}

/// OTLP log exporter placeholder type.
class OtlpLogExporter {
  /// Creates an OTLP log exporter.
  const OtlpLogExporter();
}

/// Collection of telemetry hooks to register on providers.
class OTelHooks {
  /// Creates telemetry hook groups.
  OTelHooks({
    List<SpanProcessor>? spanProcessors,
    List<MetricReader>? metricReaders,
    List<LogRecordProcessor>? logRecordProcessors,
  }) : spanProcessors = spanProcessors ?? <SpanProcessor>[],
       metricReaders = metricReaders ?? <MetricReader>[],
       logRecordProcessors = logRecordProcessors ?? <LogRecordProcessor>[];

  /// Span processors to register.
  final List<SpanProcessor> spanProcessors;

  /// Metric readers to register.
  final List<MetricReader> metricReaders;

  /// Log record processors to register.
  final List<LogRecordProcessor> logRecordProcessors;
}

/// Tracer provider container used by ADK telemetry setup.
class TracerProvider {
  /// Creates a tracer provider bound to [resource].
  TracerProvider({required this.resource});

  /// The resource associated with this provider.
  final OTelResource resource;

  /// Registered span processors.
  final List<SpanProcessor> spanProcessors = <SpanProcessor>[];

  /// Adds a [processor] to this provider.
  void addSpanProcessor(SpanProcessor processor) {
    spanProcessors.add(processor);
  }
}

/// Meter provider container used by ADK telemetry setup.
class MeterProvider {
  /// Creates a meter provider.
  MeterProvider({required this.metricReaders, required this.resource});

  /// Registered metric readers.
  final List<MetricReader> metricReaders;

  /// The resource associated with this provider.
  final OTelResource resource;
}

/// Logger provider container used by ADK telemetry setup.
class LoggerProvider {
  /// Creates a logger provider bound to [resource].
  LoggerProvider({required this.resource});

  /// The resource associated with this provider.
  final OTelResource resource;

  /// Registered log record processors.
  final List<LogRecordProcessor> logRecordProcessors = <LogRecordProcessor>[];

  /// Adds a [processor] to this provider.
  void addLogRecordProcessor(LogRecordProcessor processor) {
    logRecordProcessors.add(processor);
  }
}

/// Event logger provider wrapper around [LoggerProvider].
class EventLoggerProvider {
  /// Creates an event logger provider.
  EventLoggerProvider(this.loggerProvider);

  /// Backing logger provider.
  final LoggerProvider loggerProvider;
}

/// Registry of globally configured telemetry providers.
class OTelProviders {
  /// Global tracer provider, if configured.
  TracerProvider? tracerProvider;

  /// Global meter provider, if configured.
  MeterProvider? meterProvider;

  /// Global logger provider, if configured.
  LoggerProvider? loggerProvider;

  /// Global event logger provider, if configured.
  EventLoggerProvider? eventLoggerProvider;
}

/// Mutable global telemetry provider registry.
final OTelProviders globalOtelProviders = OTelProviders();

/// Clears all global telemetry providers.
///
/// This is primarily used by tests.
void resetOtelProvidersForTest() {
  globalOtelProviders
    ..tracerProvider = null
    ..meterProvider = null
    ..loggerProvider = null
    ..eventLoggerProvider = null;
}

/// Initializes telemetry providers when exporters are available.
///
/// Existing providers in [providers] are preserved.
void maybeSetOtelProviders({
  List<OTelHooks>? otelHooksToSetup,
  OTelResource? otelResource,
  Map<String, String>? environment,
  OTelProviders? providers,
}) {
  final List<OTelHooks> hooks = List<OTelHooks>.from(
    otelHooksToSetup ?? <OTelHooks>[],
  )..add(getOtelExporters(environment: environment));
  final OTelResource resource =
      otelResource ??
      detectOtelResourceFromEnvironment(environment: environment);
  final OTelProviders providerRegistry = providers ?? globalOtelProviders;

  final List<SpanProcessor> spanProcessors = <SpanProcessor>[];
  final List<MetricReader> metricReaders = <MetricReader>[];
  final List<LogRecordProcessor> logRecordProcessors = <LogRecordProcessor>[];

  for (final OTelHooks hook in hooks) {
    spanProcessors.addAll(hook.spanProcessors);
    metricReaders.addAll(hook.metricReaders);
    logRecordProcessors.addAll(hook.logRecordProcessors);
  }

  if (spanProcessors.isNotEmpty && providerRegistry.tracerProvider == null) {
    final TracerProvider tracerProvider = TracerProvider(resource: resource);
    for (final SpanProcessor processor in spanProcessors) {
      tracerProvider.addSpanProcessor(processor);
    }
    providerRegistry.tracerProvider = tracerProvider;
  }

  if (metricReaders.isNotEmpty && providerRegistry.meterProvider == null) {
    providerRegistry.meterProvider = MeterProvider(
      metricReaders: metricReaders,
      resource: resource,
    );
  }

  if (logRecordProcessors.isNotEmpty &&
      providerRegistry.loggerProvider == null) {
    final LoggerProvider loggerProvider = LoggerProvider(resource: resource);
    for (final LogRecordProcessor processor in logRecordProcessors) {
      loggerProvider.addLogRecordProcessor(processor);
    }
    providerRegistry
      ..loggerProvider = loggerProvider
      ..eventLoggerProvider = EventLoggerProvider(loggerProvider);
  }
}

/// Builds an [OTelResource] from environment variables.
OTelResource detectOtelResourceFromEnvironment({
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final Map<String, Object?> attributes = <String, Object?>{};

  final String? serviceName = env[otelServiceName];
  if (serviceName != null && serviceName.isNotEmpty) {
    attributes['service.name'] = serviceName;
  }

  final String? resourceAttrs = env[otelResourceAttributes];
  if (resourceAttrs != null && resourceAttrs.isNotEmpty) {
    for (final String pair in resourceAttrs.split(',')) {
      final int splitIndex = pair.indexOf('=');
      if (splitIndex <= 0 || splitIndex == pair.length - 1) {
        continue;
      }
      final String key = pair.substring(0, splitIndex).trim();
      final String value = pair.substring(splitIndex + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      attributes[key] = value;
    }
  }

  return OTelResource(attributes: attributes);
}

/// Detects OTLP exporter hooks from environment variables.
OTelHooks getOtelExporters({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;

  final bool hasTraceExporter =
      _hasValue(env, otelExporterOtlpEndpoint) ||
      _hasValue(env, otelExporterOtlpTracesEndpoint);
  final bool hasMetricExporter =
      _hasValue(env, otelExporterOtlpEndpoint) ||
      _hasValue(env, otelExporterOtlpMetricsEndpoint);
  final bool hasLogExporter =
      _hasValue(env, otelExporterOtlpEndpoint) ||
      _hasValue(env, otelExporterOtlpLogsEndpoint);

  final List<SpanProcessor> spanProcessors = hasTraceExporter
      ? <SpanProcessor>[getOtelSpanExporter()]
      : <SpanProcessor>[];
  final List<MetricReader> metricReaders = hasMetricExporter
      ? <MetricReader>[getOtelMetricsExporter()]
      : <MetricReader>[];
  final List<LogRecordProcessor> logRecordProcessors = hasLogExporter
      ? <LogRecordProcessor>[getOtelLogsExporter()]
      : <LogRecordProcessor>[];

  return OTelHooks(
    spanProcessors: spanProcessors,
    metricReaders: metricReaders,
    logRecordProcessors: logRecordProcessors,
  );
}

/// Default OTLP span exporter hook.
SpanProcessor getOtelSpanExporter() {
  return BatchSpanProcessor(OtlpSpanExporter());
}

/// Default OTLP metric exporter hook.
MetricReader getOtelMetricsExporter() {
  return PeriodicExportingMetricReader(const OtlpMetricExporter());
}

/// Default OTLP log exporter hook.
LogRecordProcessor getOtelLogsExporter() {
  return BatchLogRecordProcessor(const OtlpLogExporter());
}

bool _hasValue(Map<String, String> environment, String key) {
  final String? value = environment[key];
  return value != null && value.isNotEmpty;
}
