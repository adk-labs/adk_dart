import 'dart:developer' as developer;
import 'dart:io';

import 'setup.dart';

const String gcpLogNameEnvVariableName = 'GOOGLE_CLOUD_DEFAULT_LOG_NAME';
const String defaultGcpLogName = 'adk-otel';

class GoogleAuthResult {
  const GoogleAuthResult({required this.credentials, required this.projectId});

  final Object credentials;
  final String? projectId;
}

typedef GoogleAuthResolver = GoogleAuthResult Function();

GoogleAuthResolver _googleAuthResolver = _defaultGoogleAuthResolver;

GoogleAuthResult _defaultGoogleAuthResolver() {
  return const GoogleAuthResult(credentials: Object(), projectId: null);
}

void setGoogleAuthResolverForTest(GoogleAuthResolver resolver) {
  _googleAuthResolver = resolver;
}

void resetGoogleAuthResolverForTest() {
  _googleAuthResolver = _defaultGoogleAuthResolver;
}

OTelHooks getGcpExporters({
  bool enableCloudTracing = false,
  bool enableCloudMetrics = false,
  bool enableCloudLogging = false,
  GoogleAuthResult? googleAuth,
  Map<String, String>? environment,
}) {
  final GoogleAuthResult auth = googleAuth ?? _googleAuthResolver();
  final String? projectId = auth.projectId;

  if (projectId == null || projectId.isEmpty) {
    developer.log(
      'Cannot determine GCP Project. OTel GCP Exporters cannot be set up. '
      'Please make sure to log into correct GCP Project.',
      name: 'adk_dart.telemetry',
    );
    return OTelHooks();
  }

  final List<SpanProcessor> spanProcessors = <SpanProcessor>[];
  if (enableCloudTracing) {
    spanProcessors.add(getGcpSpanExporter(auth.credentials));
  }

  final List<MetricReader> metricReaders = <MetricReader>[];
  if (enableCloudMetrics) {
    metricReaders.add(getGcpMetricsExporter(projectId));
  }

  final List<LogRecordProcessor> logRecordProcessors = <LogRecordProcessor>[];
  if (enableCloudLogging) {
    logRecordProcessors.add(
      getGcpLogsExporter(projectId, environment: environment),
    );
  }

  return OTelHooks(
    spanProcessors: spanProcessors,
    metricReaders: metricReaders,
    logRecordProcessors: logRecordProcessors,
  );
}

SpanProcessor getGcpSpanExporter(Object credentials) {
  return BatchSpanProcessor(
    OtlpSpanExporter(
      session: credentials,
      endpoint: 'https://telemetry.googleapis.com/v1/traces',
    ),
  );
}

MetricReader getGcpMetricsExporter(String projectId) {
  return PeriodicExportingMetricReader(
    CloudMonitoringMetricsExporter(projectId: projectId),
    exportIntervalMillis: 5000,
  );
}

LogRecordProcessor getGcpLogsExporter(
  String projectId, {
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String logName = env[gcpLogNameEnvVariableName] ?? defaultGcpLogName;
  return BatchLogRecordProcessor(
    CloudLoggingExporter(projectId: projectId, defaultLogName: logName),
  );
}

class CloudMonitoringMetricsExporter {
  const CloudMonitoringMetricsExporter({required this.projectId});

  final String projectId;
}

class CloudLoggingExporter {
  const CloudLoggingExporter({
    required this.projectId,
    required this.defaultLogName,
  });

  final String projectId;
  final String defaultLogName;
}

OTelResource getGcpResource({
  String? projectId,
  Map<String, String>? environment,
  OTelResource Function()? gcpResourceDetector,
}) {
  OTelResource resource = OTelResource(
    attributes: projectId == null
        ? <String, Object?>{}
        : <String, Object?>{'gcp.project_id': projectId},
  );
  resource = resource.merge(
    detectOtelResourceFromEnvironment(environment: environment),
  );
  if (gcpResourceDetector != null) {
    resource = resource.merge(gcpResourceDetector());
  }
  return resource;
}
