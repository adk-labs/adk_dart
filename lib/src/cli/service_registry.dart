import 'dart:io';

import '../artifacts/base_artifact_service.dart';
import '../artifacts/file_artifact_service.dart';
import '../artifacts/gcs_artifact_service.dart';
import '../artifacts/in_memory_artifact_service.dart';
import '../memory/base_memory_service.dart';
import '../memory/in_memory_memory_service.dart';
import '../memory/vertex_ai_memory_bank_service.dart';
import '../memory/vertex_ai_rag_memory_service.dart';
import '../sessions/base_session_service.dart';
import '../sessions/database_session_service.dart';
import '../sessions/in_memory_session_service.dart';
import '../sessions/sqlite_session_service.dart';
import '../sessions/vertex_ai_session_service.dart';
import '../tools/_google_access_token.dart';
import '../utils/yaml_utils.dart';
import 'utils/envs.dart';

typedef ServiceFactory<T> =
    T Function(String uri, {Map<String, Object?>? kwargs});

class ServiceRegistry {
  final Map<String, ServiceFactory<BaseSessionService>> _sessionFactories =
      <String, ServiceFactory<BaseSessionService>>{};
  final Map<String, ServiceFactory<BaseArtifactService>> _artifactFactories =
      <String, ServiceFactory<BaseArtifactService>>{};
  final Map<String, ServiceFactory<BaseMemoryService>> _memoryFactories =
      <String, ServiceFactory<BaseMemoryService>>{};

  void registerSessionService(
    String scheme,
    ServiceFactory<BaseSessionService> factory,
  ) {
    _sessionFactories[scheme] = factory;
  }

  void registerArtifactService(
    String scheme,
    ServiceFactory<BaseArtifactService> factory,
  ) {
    _artifactFactories[scheme] = factory;
  }

  void registerMemoryService(
    String scheme,
    ServiceFactory<BaseMemoryService> factory,
  ) {
    _memoryFactories[scheme] = factory;
  }

  BaseSessionService? createSessionService(
    String uri, {
    Map<String, Object?>? kwargs,
  }) {
    final String scheme = _uriScheme(uri);
    final ServiceFactory<BaseSessionService>? factory =
        _sessionFactories[scheme];
    if (factory == null) {
      return null;
    }
    return factory(uri, kwargs: kwargs);
  }

  BaseArtifactService? createArtifactService(
    String uri, {
    Map<String, Object?>? kwargs,
  }) {
    final String scheme = _uriScheme(uri);
    final ServiceFactory<BaseArtifactService>? factory =
        _artifactFactories[scheme];
    if (factory == null) {
      return null;
    }
    return factory(uri, kwargs: kwargs);
  }

  BaseMemoryService? createMemoryService(
    String uri, {
    Map<String, Object?>? kwargs,
  }) {
    final String scheme = _uriScheme(uri);
    final ServiceFactory<BaseMemoryService>? factory = _memoryFactories[scheme];
    if (factory == null) {
      return null;
    }
    return factory(uri, kwargs: kwargs);
  }
}

ServiceRegistry? _serviceRegistryInstance;
final Map<String, ServiceFactory<Object>> _customYamlClassFactories =
    <String, ServiceFactory<Object>>{};

ServiceRegistry getServiceRegistry() {
  _serviceRegistryInstance ??= ServiceRegistry().._registerBuiltinServices();
  return _serviceRegistryInstance!;
}

void resetServiceRegistryForTest() {
  _serviceRegistryInstance = null;
  _customYamlClassFactories.clear();
}

void registerServiceClassFactory(
  String classPath,
  ServiceFactory<Object> factory,
) {
  _customYamlClassFactories[classPath] = factory;
}

void loadServicesModule(String agentsDir) {
  final Directory directory = Directory(agentsDir);
  if (!directory.existsSync()) {
    return;
  }

  final List<String> yamlNames = <String>['services.yaml', 'services.yml'];
  for (final String fileName in yamlNames) {
    final File file = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    if (!file.existsSync()) {
      continue;
    }
    final Object? decoded = loadYamlFile(file.path);
    if (decoded is Map) {
      _registerServicesFromYamlConfig(
        decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
        getServiceRegistry(),
      );
    }
  }
}

extension on ServiceRegistry {
  void _registerBuiltinServices() {
    registerSessionService('memory', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      return InMemorySessionService();
    });

    registerSessionService('agentengine', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      final Uri parsed = Uri.parse(uri);
      final Map<String, Object?> params = _parseAgentEngineKwargs(
        '${parsed.authority}${parsed.path}',
        kwargs?['agents_dir'] as String?,
      );
      return VertexAiSessionService(
        project: params['project'] as String?,
        location: params['location'] as String?,
        agentEngineId: params['agent_engine_id'] as String?,
      );
    });

    registerSessionService('sqlite', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      final Uri parsed = Uri.parse(uri);
      final String dbPath = parsed.path;
      if (dbPath.isEmpty || dbPath == '/') {
        return InMemorySessionService();
      }
      return SqliteSessionService(uri);
    });

    registerSessionService('postgresql', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      return _createNetworkDatabaseSessionService('postgresql', uri);
    });
    registerSessionService('mysql', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      return _createNetworkDatabaseSessionService('mysql', uri);
    });

    registerArtifactService('memory', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      return InMemoryArtifactService();
    });

    registerArtifactService('gs', (String uri, {Map<String, Object?>? kwargs}) {
      final Uri parsed = Uri.parse(uri);
      return GcsArtifactService(
        _resolveGsBucketName(parsed),
        httpRequestProvider: _sendGcsArtifactHttpRequest,
        authHeadersProvider: _resolveGcsArtifactAuthHeaders,
      );
    });

    registerArtifactService('file', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      final Uri parsed = Uri.parse(uri);
      if (parsed.authority.isNotEmpty && parsed.authority != 'localhost') {
        throw ArgumentError(
          'file:// artifact URIs must reference the local filesystem.',
        );
      }
      if (parsed.path.isEmpty) {
        throw ArgumentError(
          'file:// artifact URIs must include a path component.',
        );
      }
      return FileArtifactService(Uri.decodeFull(parsed.path));
    });

    registerMemoryService('memory', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      return InMemoryMemoryService();
    });

    registerMemoryService('rag', (String uri, {Map<String, Object?>? kwargs}) {
      final String ragCorpus = Uri.parse(uri).authority;
      if (ragCorpus.isEmpty) {
        throw ArgumentError('Rag corpus can not be empty.');
      }

      final String agentsDir = '${kwargs?['agents_dir'] ?? ''}';
      final (String project, String location) = _loadGcpConfig(
        agentsDir: agentsDir,
        serviceName: 'RAG memory service',
      );
      return VertexAiRagMemoryService(
        ragCorpus:
            'projects/$project/locations/$location/ragCorpora/$ragCorpus',
      );
    });

    registerMemoryService('agentengine', (
      String uri, {
      Map<String, Object?>? kwargs,
    }) {
      final Uri parsed = Uri.parse(uri);
      final Map<String, Object?> params = _parseAgentEngineKwargs(
        '${parsed.authority}${parsed.path}',
        kwargs?['agents_dir'] as String?,
      );
      return VertexAiMemoryBankService(
        project: params['project'] as String?,
        location: params['location'] as String?,
        agentEngineId: params['agent_engine_id'] as String,
      );
    });
  }
}

Future<GcsArtifactHttpResponse> _sendGcsArtifactHttpRequest(
  GcsArtifactHttpRequest request,
) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest rawRequest = await client.openUrl(
      request.method,
      request.uri,
    );
    request.headers.forEach(rawRequest.headers.set);
    if (request.bodyBytes.isNotEmpty) {
      rawRequest.add(request.bodyBytes);
    }

    final HttpClientResponse response = await rawRequest.close();
    final List<int> bodyBytes = await response.fold<List<int>>(
      <int>[],
      (List<int> previous, List<int> element) {
        previous.addAll(element);
        return previous;
      },
    );
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      if (values.isNotEmpty) {
        headers[name] = values.join(',');
      }
    });

    return GcsArtifactHttpResponse(
      statusCode: response.statusCode,
      headers: headers,
      bodyBytes: bodyBytes,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> _resolveGcsArtifactAuthHeaders() async {
  final String token = await resolveDefaultGoogleAccessToken(
    scopes: const <String>[
      'https://www.googleapis.com/auth/devstorage.read_write',
    ],
  );
  return <String, String>{
    HttpHeaders.authorizationHeader: 'Bearer $token',
    HttpHeaders.acceptHeader: ContentType.json.mimeType,
    HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
  };
}

String _resolveGsBucketName(Uri parsed) {
  final String authority = parsed.authority.trim();
  if (authority.isNotEmpty) {
    return authority;
  }

  final List<String> segments = parsed.pathSegments
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  if (segments.isNotEmpty) {
    return Uri.decodeComponent(segments.first);
  }
  throw ArgumentError(
    'gs:// artifact URIs must include a bucket name. '
    'Example: gs://my-bucket',
  );
}

String _uriScheme(String uri) {
  final Uri parsed = Uri.parse(uri);
  return parsed.scheme;
}

BaseSessionService _createNetworkDatabaseSessionService(
  String scheme,
  String dbUrl,
) {
  try {
    return DatabaseSessionService(dbUrl);
  } catch (error) {
    throw StateError(
      'Failed to initialize `$scheme://` session backend for URI `$dbUrl`: $error',
    );
  }
}

(String, String) _loadGcpConfig({
  required String agentsDir,
  required String serviceName,
}) {
  if (agentsDir.trim().isEmpty) {
    throw ArgumentError('agents_dir must be provided for $serviceName');
  }
  loadDotenvForAgent('', agentsDir);
  final String? project = getCliEnvironmentValue('GOOGLE_CLOUD_PROJECT');
  final String? location = getCliEnvironmentValue('GOOGLE_CLOUD_LOCATION');
  if (project == null ||
      project.isEmpty ||
      location == null ||
      location.isEmpty) {
    throw StateError('GOOGLE_CLOUD_PROJECT or GOOGLE_CLOUD_LOCATION not set.');
  }
  return (project, location);
}

Map<String, Object?> _parseAgentEngineKwargs(
  String uriPart,
  String? agentsDir,
) {
  if (uriPart.trim().isEmpty) {
    throw ArgumentError(
      'Agent engine resource name or resource id cannot be empty.',
    );
  }

  if (!uriPart.contains('/')) {
    final (String project, String location) = _loadGcpConfig(
      agentsDir: agentsDir ?? '',
      serviceName: 'short-form agent engine IDs',
    );
    return <String, Object?>{
      'project': project,
      'location': location,
      'agent_engine_id': uriPart,
    };
  }

  final List<String> parts = uriPart.split('/');
  if (!(parts.length == 6 &&
      parts[0] == 'projects' &&
      parts[2] == 'locations' &&
      parts[4] == 'reasoningEngines')) {
    throw ArgumentError(
      'Agent engine resource name is mal-formatted. It should be of format: '
      'projects/{project_id}/locations/{location}/reasoningEngines/{resource_id}',
    );
  }
  return <String, Object?>{
    'project': parts[1],
    'location': parts[3],
    'agent_engine_id': parts[5],
  };
}

void _registerServicesFromYamlConfig(
  Map<String, Object?> config,
  ServiceRegistry registry,
) {
  final Object? rawServices = config['services'];
  if (rawServices is! List) {
    return;
  }

  for (final Object? item in rawServices) {
    if (item is! Map) {
      continue;
    }
    final Map<String, Object?> serviceConfig = item.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    final String scheme = '${serviceConfig['scheme'] ?? ''}'.trim();
    final String serviceType = '${serviceConfig['type'] ?? ''}'.trim();
    final String classPath = '${serviceConfig['class'] ?? ''}'.trim();
    if (scheme.isEmpty || serviceType.isEmpty || classPath.isEmpty) {
      continue;
    }

    final ServiceFactory<Object>? genericFactory =
        _customYamlClassFactories[classPath];
    if (genericFactory == null) {
      continue;
    }

    switch (serviceType) {
      case 'session':
        registry.registerSessionService(scheme, (
          String uri, {
          Map<String, Object?>? kwargs,
        }) {
          final Object service = genericFactory(uri, kwargs: kwargs);
          if (service is! BaseSessionService) {
            throw ArgumentError(
              '$classPath does not produce a BaseSessionService.',
            );
          }
          return service;
        });
      case 'artifact':
        registry.registerArtifactService(scheme, (
          String uri, {
          Map<String, Object?>? kwargs,
        }) {
          final Object service = genericFactory(uri, kwargs: kwargs);
          if (service is! BaseArtifactService) {
            throw ArgumentError(
              '$classPath does not produce a BaseArtifactService.',
            );
          }
          return service;
        });
      case 'memory':
        registry.registerMemoryService(scheme, (
          String uri, {
          Map<String, Object?>? kwargs,
        }) {
          final Object service = genericFactory(uri, kwargs: kwargs);
          if (service is! BaseMemoryService) {
            throw ArgumentError(
              '$classPath does not produce a BaseMemoryService.',
            );
          }
          return service;
        });
      default:
        continue;
    }
  }
}
