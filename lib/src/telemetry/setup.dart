import 'dart:io';

const String otelExporterOtlpEndpoint = 'OTEL_EXPORTER_OTLP_ENDPOINT';
const String otelExporterOtlpTracesEndpoint =
    'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT';
const String otelExporterOtlpMetricsEndpoint =
    'OTEL_EXPORTER_OTLP_METRICS_ENDPOINT';
const String otelExporterOtlpLogsEndpoint = 'OTEL_EXPORTER_OTLP_LOGS_ENDPOINT';
const String otelServiceName = 'OTEL_SERVICE_NAME';
const String otelResourceAttributes = 'OTEL_RESOURCE_ATTRIBUTES';

class OTelResource {
  OTelResource({Map<String, Object?>? attributes})
    : attributes = attributes ?? <String, Object?>{};

  final Map<String, Object?> attributes;

  OTelResource merge(OTelResource other) {
    final Map<String, Object?> merged = <String, Object?>{}
      ..addAll(attributes)
      ..addAll(other.attributes);
    return OTelResource(attributes: merged);
  }
}

abstract class SpanProcessor {
  String get kind;
  Object get exporter;
}

abstract class MetricReader {
  String get kind;
  Object get exporter;
}

abstract class LogRecordProcessor {
  String get kind;
  Object get exporter;
}

class BatchSpanProcessor implements SpanProcessor {
  BatchSpanProcessor(this.exporter);

  @override
  final Object exporter;

  @override
  String get kind => 'batch_span_processor';
}

class PeriodicExportingMetricReader implements MetricReader {
  PeriodicExportingMetricReader(
    this.exporter, {
    this.exportIntervalMillis = 60000,
  });

  @override
  final Object exporter;
  final int exportIntervalMillis;

  @override
  String get kind => 'periodic_metric_reader';
}

class BatchLogRecordProcessor implements LogRecordProcessor {
  BatchLogRecordProcessor(this.exporter);

  @override
  final Object exporter;

  @override
  String get kind => 'batch_log_record_processor';
}

class OtlpSpanExporter {
  OtlpSpanExporter({this.endpoint, this.session});

  final String? endpoint;
  final Object? session;
}

class OtlpMetricExporter {
  const OtlpMetricExporter();
}

class OtlpLogExporter {
  const OtlpLogExporter();
}

class OTelHooks {
  OTelHooks({
    List<SpanProcessor>? spanProcessors,
    List<MetricReader>? metricReaders,
    List<LogRecordProcessor>? logRecordProcessors,
  }) : spanProcessors = spanProcessors ?? <SpanProcessor>[],
       metricReaders = metricReaders ?? <MetricReader>[],
       logRecordProcessors = logRecordProcessors ?? <LogRecordProcessor>[];

  final List<SpanProcessor> spanProcessors;
  final List<MetricReader> metricReaders;
  final List<LogRecordProcessor> logRecordProcessors;
}

class TracerProvider {
  TracerProvider({required this.resource});

  final OTelResource resource;
  final List<SpanProcessor> spanProcessors = <SpanProcessor>[];

  void addSpanProcessor(SpanProcessor processor) {
    spanProcessors.add(processor);
  }
}

class MeterProvider {
  MeterProvider({required this.metricReaders, required this.resource});

  final List<MetricReader> metricReaders;
  final OTelResource resource;
}

class LoggerProvider {
  LoggerProvider({required this.resource});

  final OTelResource resource;
  final List<LogRecordProcessor> logRecordProcessors = <LogRecordProcessor>[];

  void addLogRecordProcessor(LogRecordProcessor processor) {
    logRecordProcessors.add(processor);
  }
}

class EventLoggerProvider {
  EventLoggerProvider(this.loggerProvider);

  final LoggerProvider loggerProvider;
}

class OTelProviders {
  TracerProvider? tracerProvider;
  MeterProvider? meterProvider;
  LoggerProvider? loggerProvider;
  EventLoggerProvider? eventLoggerProvider;
}

final OTelProviders globalOtelProviders = OTelProviders();

void resetOtelProvidersForTest() {
  globalOtelProviders
    ..tracerProvider = null
    ..meterProvider = null
    ..loggerProvider = null
    ..eventLoggerProvider = null;
}

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

  if (spanProcessors.isNotEmpty) {
    final TracerProvider tracerProvider = TracerProvider(resource: resource);
    for (final SpanProcessor processor in spanProcessors) {
      tracerProvider.addSpanProcessor(processor);
    }
    providerRegistry.tracerProvider = tracerProvider;
  }

  if (metricReaders.isNotEmpty) {
    providerRegistry.meterProvider = MeterProvider(
      metricReaders: metricReaders,
      resource: resource,
    );
  }

  if (logRecordProcessors.isNotEmpty) {
    final LoggerProvider loggerProvider = LoggerProvider(resource: resource);
    for (final LogRecordProcessor processor in logRecordProcessors) {
      loggerProvider.addLogRecordProcessor(processor);
    }
    providerRegistry
      ..loggerProvider = loggerProvider
      ..eventLoggerProvider = EventLoggerProvider(loggerProvider);
  }
}

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

SpanProcessor getOtelSpanExporter() {
  return BatchSpanProcessor(OtlpSpanExporter());
}

MetricReader getOtelMetricsExporter() {
  return PeriodicExportingMetricReader(const OtlpMetricExporter());
}

LogRecordProcessor getOtelLogsExporter() {
  return BatchLogRecordProcessor(const OtlpLogExporter());
}

bool _hasValue(Map<String, String> environment, String key) {
  final String? value = environment[key];
  return value != null && value.isNotEmpty;
}
