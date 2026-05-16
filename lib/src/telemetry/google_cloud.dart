/// Telemetry configuration, exporters, and tracing helpers.
library;

import 'dart:developer' as developer;
import 'dart:io';

import 'setup.dart';

/// Environment key for overriding default Cloud Logging log name.
const String gcpLogNameEnvVariableName = 'GOOGLE_CLOUD_DEFAULT_LOG_NAME';

/// Default Cloud Logging log name used by ADK telemetry.
const String defaultGcpLogName = 'adk-otel';

/// Default Cloud Trace OTLP endpoint.
const String defaultTelemetryTracesEndpoint =
    'https://telemetry.googleapis.com/v1/traces';

/// Default mTLS Cloud Trace OTLP endpoint.
const String defaultMtlsTelemetryTracesEndpoint =
    'https://telemetry.mtls.googleapis.com/v1/traces';

enum _MtlsEndpoint { auto, always, never }

/// Google authentication payload for telemetry exporters.
class GoogleAuthResult {
  /// Creates a Google authentication result.
  const GoogleAuthResult({required this.credentials, required this.projectId});

  /// Credential object used by exporters.
  final Object credentials;

  /// Resolved Google Cloud project identifier.
  final String? projectId;
}

/// Resolver callback that provides [GoogleAuthResult].
typedef GoogleAuthResolver = GoogleAuthResult Function();

GoogleAuthResolver _googleAuthResolver = _defaultGoogleAuthResolver;

GoogleAuthResult _defaultGoogleAuthResolver() {
  return const GoogleAuthResult(credentials: Object(), projectId: null);
}

/// Overrides the Google auth resolver.
///
/// This is intended for tests.
void setGoogleAuthResolverForTest(GoogleAuthResolver resolver) {
  _googleAuthResolver = resolver;
}

/// Restores the default Google auth resolver.
///
/// This is intended for tests.
void resetGoogleAuthResolverForTest() {
  _googleAuthResolver = _defaultGoogleAuthResolver;
}

/// Returns telemetry hooks for Google Cloud exporters.
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
    spanProcessors.add(
      getGcpSpanExporter(auth.credentials, environment: environment),
    );
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

/// Returns a Cloud Trace span exporter hook.
SpanProcessor getGcpSpanExporter(
  Object credentials, {
  Map<String, String>? environment,
  bool hasDefaultClientCertificate = false,
  bool? useClientCertificate,
}) {
  return BatchSpanProcessor(
    OtlpSpanExporter(
      session: credentials,
      endpoint: resolveTelemetryTracesEndpoint(
        environment: environment,
        hasDefaultClientCertificate: hasDefaultClientCertificate,
        useClientCertificate: useClientCertificate,
      ),
    ),
  );
}

/// Resolves the telemetry trace endpoint using Google API mTLS environment.
String resolveTelemetryTracesEndpoint({
  Map<String, String>? environment,
  bool hasDefaultClientCertificate = false,
  bool? useClientCertificate,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String rawEndpoint = (env['GOOGLE_API_USE_MTLS_ENDPOINT'] ?? 'auto')
      .toLowerCase();
  final _MtlsEndpoint endpointMode = _parseMtlsEndpoint(rawEndpoint);
  final bool clientCertEnabled =
      useClientCertificate ?? _useClientCertificateEffective(env);

  if (endpointMode == _MtlsEndpoint.always ||
      (endpointMode == _MtlsEndpoint.auto &&
          clientCertEnabled &&
          hasDefaultClientCertificate)) {
    return defaultMtlsTelemetryTracesEndpoint;
  }
  return defaultTelemetryTracesEndpoint;
}

_MtlsEndpoint _parseMtlsEndpoint(String value) {
  switch (value) {
    case 'always':
      return _MtlsEndpoint.always;
    case 'never':
      return _MtlsEndpoint.never;
    case 'auto':
      return _MtlsEndpoint.auto;
    default:
      developer.log(
        'Environment variable `GOOGLE_API_USE_MTLS_ENDPOINT` must be one of '
        '[auto, always, never]. Defaulting to auto.',
        name: 'adk_dart.telemetry',
      );
      return _MtlsEndpoint.auto;
  }
}

bool _useClientCertificateEffective(Map<String, String> environment) {
  final String raw =
      (environment['GOOGLE_API_USE_CLIENT_CERTIFICATE'] ?? 'false')
          .toLowerCase();
  if (raw != 'true' && raw != 'false') {
    developer.log(
      'Environment variable `GOOGLE_API_USE_CLIENT_CERTIFICATE` must be '
      'either `true` or `false`.',
      name: 'adk_dart.telemetry',
    );
  }
  return raw == 'true';
}

/// Returns a Cloud Monitoring metrics exporter hook.
MetricReader getGcpMetricsExporter(String projectId) {
  return PeriodicExportingMetricReader(
    CloudMonitoringMetricsExporter(projectId: projectId),
    exportIntervalMillis: 5000,
  );
}

/// Returns a Cloud Logging exporter hook.
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

/// Cloud Monitoring metrics exporter descriptor.
class CloudMonitoringMetricsExporter {
  /// Creates a Cloud Monitoring metrics exporter descriptor.
  const CloudMonitoringMetricsExporter({required this.projectId});

  /// Google Cloud project identifier.
  final String projectId;
}

/// Cloud Logging exporter descriptor.
class CloudLoggingExporter {
  /// Creates a Cloud Logging exporter descriptor.
  const CloudLoggingExporter({
    required this.projectId,
    required this.defaultLogName,
  });

  /// Google Cloud project identifier.
  final String projectId;

  /// Default log name used when writing entries.
  final String defaultLogName;
}

/// Builds an OpenTelemetry resource enriched with Google Cloud attributes.
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
