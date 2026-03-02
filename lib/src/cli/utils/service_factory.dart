/// Service factory helpers for CLI runtime storage and backend selection.
library;

import 'dart:io';

import '../../artifacts/base_artifact_service.dart';
import '../../artifacts/in_memory_artifact_service.dart';
import '../../memory/base_memory_service.dart';
import '../../memory/in_memory_memory_service.dart';
import '../../sessions/base_session_service.dart';
import '../../sessions/database_session_service.dart';
import '../../sessions/in_memory_session_service.dart';
import '../../utils/env_utils.dart';
import '../service_registry.dart';
import 'dot_adk_folder.dart';
import 'local_storage.dart';

/// Environment variable that disables local `.adk` storage services.
const String disableLocalStorageEnv = 'ADK_DISABLE_LOCAL_STORAGE';

/// Environment variable that forces local `.adk` storage services.
const String forceLocalStorageEnv = 'ADK_FORCE_LOCAL_STORAGE';

/// Cloud Run environment variable used for runtime detection.
const String cloudRunServiceEnv = 'K_SERVICE';

/// Kubernetes environment variable used for runtime detection.
const String kubernetesHostEnv = 'KUBERNETES_SERVICE_HOST';

/// Redacts sensitive URI components before writing logs.
String redactUriForLog(String uri) {
  if (uri.trim().isEmpty) {
    return '<empty>';
  }
  final String sanitized = uri.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
  if (!sanitized.contains('://')) {
    return '<scheme-missing>';
  }

  final Uri parsed;
  try {
    parsed = Uri.parse(sanitized);
  } on FormatException {
    return '<unparseable>';
  }
  if (parsed.scheme.isEmpty) {
    return '<scheme-missing>';
  }

  final String authority = parsed.hasAuthority
      ? (parsed.userInfo.isEmpty ? parsed.authority : parsed.host)
      : '';
  final String query = parsed.queryParametersAll.isEmpty
      ? ''
      : parsed.queryParametersAll.keys
            .map((String key) => '$key=<redacted>')
            .join('&');
  return Uri(
    scheme: parsed.scheme,
    userInfo: '',
    host: authority == parsed.host ? parsed.host : authority,
    port: parsed.hasPort ? parsed.port : 0,
    path: parsed.path,
    query: query.isEmpty ? null : query,
  ).replace(port: parsed.hasPort ? parsed.port : null).toString();
}

/// Whether the current process appears to be running on Cloud Run.
bool isCloudRun([Map<String, String>? environment]) {
  final Map<String, String> env = environment ?? Platform.environment;
  return (env[cloudRunServiceEnv] ?? '').isNotEmpty;
}

/// Whether the current process appears to be running on Kubernetes.
bool isKubernetes([Map<String, String>? environment]) {
  final Map<String, String> env = environment ?? Platform.environment;
  return (env[kubernetesHostEnv] ?? '').isNotEmpty;
}

/// Whether [dir] is writable by creating and deleting a probe file.
bool isDirWritable(Directory dir) {
  if (!dir.existsSync()) {
    return false;
  }
  try {
    final File probe = File(
      '${dir.path}${Platform.pathSeparator}.adk_probe_${DateTime.now().microsecondsSinceEpoch}',
    );
    probe.writeAsStringSync('probe');
    probe.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Resolves whether local storage should be used for CLI services.
///
/// Returns a tuple of `(enabled, warningMessage)`.
(bool, String?) resolveUseLocalStorage({
  required Directory basePath,
  required bool requested,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  if (isEnvEnabled(disableLocalStorageEnv, environment: env)) {
    return (
      false,
      'Local storage is disabled by $disableLocalStorageEnv; using in-memory services.',
    );
  }

  if (isEnvEnabled(forceLocalStorageEnv, environment: env)) {
    if (!isDirWritable(basePath)) {
      return (
        false,
        'Local storage is forced by $forceLocalStorageEnv, but ${basePath.path} is not writable; using in-memory services.',
      );
    }
    return (true, null);
  }

  if (!requested) {
    return (false, null);
  }
  if (isCloudRun(env) || isKubernetes(env)) {
    return (
      false,
      'Detected Cloud Run/Kubernetes runtime; using in-memory services instead of local .adk storage.',
    );
  }
  if (!isDirWritable(basePath)) {
    return (
      false,
      'Agents directory ${basePath.path} is not writable; using in-memory services instead of local .adk storage.',
    );
  }
  return (true, null);
}

/// Creates a session service from CLI options and environment context.
BaseSessionService createSessionServiceFromOptions({
  required Object baseDir,
  String? sessionServiceUri,
  Map<String, Object?>? sessionDbKwargs,
  Map<String, String>? appNameToDir,
  bool useLocalStorage = true,
}) {
  final Directory basePath = directoryFromArg(
    baseDir,
    parameterName: 'baseDir',
  );
  final ServiceRegistry registry = getServiceRegistry();

  final Map<String, Object?> kwargs = <String, Object?>{
    'agents_dir': basePath.path,
    ...?sessionDbKwargs,
  };

  if (sessionServiceUri != null && sessionServiceUri.isNotEmpty) {
    final BaseSessionService? service = registry.createSessionService(
      sessionServiceUri,
      kwargs: kwargs,
    );
    if (service != null) {
      return service;
    }
    return DatabaseSessionService(sessionServiceUri);
  }

  final (bool enabled, String? _) = resolveUseLocalStorage(
    basePath: basePath,
    requested: useLocalStorage,
  );
  if (!enabled) {
    return InMemorySessionService();
  }

  try {
    return createLocalSessionService(
      baseDir: basePath.path,
      perAgent: true,
      appNameToDir: appNameToDir,
    );
  } on FileSystemException {
    return InMemorySessionService();
  }
}

/// Creates a memory service from CLI options and environment context.
BaseMemoryService createMemoryServiceFromOptions({
  required Object baseDir,
  String? memoryServiceUri,
}) {
  final Directory basePath = directoryFromArg(
    baseDir,
    parameterName: 'baseDir',
  );
  final ServiceRegistry registry = getServiceRegistry();

  if (memoryServiceUri != null && memoryServiceUri.isNotEmpty) {
    final BaseMemoryService? service = registry.createMemoryService(
      memoryServiceUri,
      kwargs: <String, Object?>{'agents_dir': basePath.path},
    );
    if (service == null) {
      throw ArgumentError(
        'Unsupported memory service URI: ${redactUriForLog(memoryServiceUri)}',
      );
    }
    return service;
  }

  return InMemoryMemoryService();
}

/// Creates an artifact service from CLI options and environment context.
BaseArtifactService createArtifactServiceFromOptions({
  required Object baseDir,
  String? artifactServiceUri,
  bool strictUri = false,
  bool useLocalStorage = true,
}) {
  final Directory basePath = directoryFromArg(
    baseDir,
    parameterName: 'baseDir',
  );
  final ServiceRegistry registry = getServiceRegistry();

  if (artifactServiceUri != null && artifactServiceUri.isNotEmpty) {
    final BaseArtifactService? service = registry.createArtifactService(
      artifactServiceUri,
      kwargs: <String, Object?>{'agents_dir': basePath.path},
    );
    if (service == null) {
      if (strictUri) {
        throw ArgumentError(
          'Unsupported artifact service URI: ${redactUriForLog(artifactServiceUri)}',
        );
      }
      return InMemoryArtifactService();
    }
    return service;
  }

  final (bool enabled, String? _) = resolveUseLocalStorage(
    basePath: basePath,
    requested: useLocalStorage,
  );
  if (!enabled) {
    return InMemoryArtifactService();
  }

  try {
    return createLocalArtifactService(baseDir: basePath.path);
  } on FileSystemException {
    return InMemoryArtifactService();
  }
}
