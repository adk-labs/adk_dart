/// Agent Registry-backed MCP and Remote A2A integration helpers.
library;

import 'dart:convert';
import 'dart:io';

import '../../a2a/protocol.dart';
import '../../agents/readonly_context.dart';
import '../../agents/remote_a2a_agent.dart';
import '../../tools/_google_access_token.dart';
import '../../tools/mcp_tool/mcp_session_manager.dart';
import '../../tools/mcp_tool/mcp_toolset.dart';

const String _agentRegistryBaseUrl =
    'https://agentregistry.googleapis.com/v1alpha';

/// Supported Agent Registry protocol types.
enum AgentRegistryProtocolType {
  typeUnspecified('TYPE_UNSPECIFIED'),
  a2aAgent('A2A_AGENT'),
  custom('CUSTOM');

  const AgentRegistryProtocolType(this.value);

  /// Wire value used by Agent Registry APIs.
  final String value;
}

/// HTTP GET response payload used by [AgentRegistry].
class AgentRegistryHttpResponse {
  /// Creates an HTTP response wrapper.
  AgentRegistryHttpResponse({
    required this.statusCode,
    required this.body,
    Map<String, String>? headers,
  }) : headers = headers ?? <String, String>{};

  /// HTTP status code.
  final int statusCode;

  /// Decoded response body.
  final Map<String, Object?> body;

  /// Response headers.
  final Map<String, String> headers;
}

/// Function that executes one Agent Registry GET request.
typedef AgentRegistryHttpGetProvider =
    Future<AgentRegistryHttpResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
    });

/// Function that resolves auth headers for Agent Registry and downstream calls.
typedef AgentRegistryAuthHeadersProvider =
    Future<Map<String, String>> Function();

/// Client for interacting with Google Cloud Agent Registry.
class AgentRegistry {
  /// Creates an Agent Registry client.
  AgentRegistry({
    required this.projectId,
    required this.location,
    this.headerProvider,
    AgentRegistryHttpGetProvider? httpGetProvider,
    AgentRegistryAuthHeadersProvider? authHeadersProvider,
  }) : _httpGetProvider =
           httpGetProvider ?? _defaultAgentRegistryHttpGetProvider,
       _authHeadersProvider =
           authHeadersProvider ?? _defaultAgentRegistryAuthHeadersProvider {
    if (projectId.trim().isEmpty || location.trim().isEmpty) {
      throw ArgumentError('projectId and location must be provided');
    }
  }

  /// Google Cloud project id.
  final String projectId;

  /// Google Cloud location.
  final String location;

  /// Optional header provider forwarded to constructed MCP toolsets.
  final Map<String, String> Function(ReadonlyContext)? headerProvider;

  final AgentRegistryHttpGetProvider _httpGetProvider;
  final AgentRegistryAuthHeadersProvider _authHeadersProvider;

  String get _basePath => 'projects/$projectId/locations/$location';

  /// Lists registered MCP servers.
  Future<Map<String, Object?>> listMcpServers({
    String? filter,
    int? pageSize,
    String? pageToken,
  }) {
    return _makeRequest(
      'mcpServers',
      params: <String, String>{
        if (filter != null && filter.isNotEmpty) 'filter': filter,
        if (pageSize != null) 'pageSize': '$pageSize',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      },
    );
  }

  /// Retrieves one MCP server resource.
  Future<Map<String, Object?>> getMcpServer(String name) {
    return _makeRequest(name);
  }

  /// Builds an [McpToolset] from one registered MCP server.
  Future<McpToolset> getMcpToolset(String mcpServerName) async {
    final Map<String, Object?> serverDetails = await getMcpServer(
      mcpServerName,
    );
    final String prefix = _cleanName(
      _readString(serverDetails['displayName']).isEmpty
          ? mcpServerName
          : _readString(serverDetails['displayName']),
    );
    final String? endpointUri =
        getConnectionUri(serverDetails, protocolBinding: 'JSONRPC') ??
        getConnectionUri(serverDetails, protocolBinding: 'HTTP_JSON') ??
        getConnectionUri(serverDetails, protocolBinding: 'http_json');
    if (endpointUri == null || endpointUri.isEmpty) {
      throw ArgumentError(
        'MCP server endpoint URI not found for `$mcpServerName`.',
      );
    }

    return McpToolset(
      connectionParams: StreamableHTTPConnectionParams(
        url: endpointUri,
        headers: await _authHeadersProvider(),
      ),
      toolNamePrefix: prefix,
      headerProvider: headerProvider,
    );
  }

  /// Lists registered A2A agents.
  Future<Map<String, Object?>> listAgents({
    String? filter,
    int? pageSize,
    String? pageToken,
  }) {
    return _makeRequest(
      'agents',
      params: <String, String>{
        if (filter != null && filter.isNotEmpty) 'filter': filter,
        if (pageSize != null) 'pageSize': '$pageSize',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      },
    );
  }

  /// Retrieves detailed metadata for one Agent Registry agent.
  Future<Map<String, Object?>> getAgentInfo(String name) {
    return _makeRequest(name);
  }

  /// Builds a ready-to-use [RemoteA2aAgent] from Agent Registry metadata.
  Future<RemoteA2aAgent> getRemoteA2aAgent(String agentName) async {
    final Map<String, Object?> agentInfo = await getAgentInfo(agentName);

    final AgentCard? storedCard = _tryStoredAgentCard(agentInfo);
    if (storedCard != null) {
      return RemoteA2aAgent(
        name: _cleanName(storedCard.name),
        agentCard: storedCard,
        description: storedCard.description,
      );
    }

    final String name = _cleanName(
      _readString(agentInfo['displayName']).isEmpty
          ? agentName
          : _readString(agentInfo['displayName']),
    );
    final String description = _readString(agentInfo['description']);
    final String version = _readString(agentInfo['version']);
    final String? url = getConnectionUri(
      agentInfo,
      protocolType: AgentRegistryProtocolType.a2aAgent,
    );
    if (url == null || url.isEmpty) {
      throw ArgumentError(
        'A2A connection URI not found for agent `$agentName`.',
      );
    }

    final List<AgentSkill> skills = _readAgentSkills(agentInfo['skills']);
    final AgentCard agentCard = AgentCard(
      name: name,
      description: description,
      url: url,
      version: version,
      skills: skills,
      capabilities: AgentCapabilities(
        values: <String, Object?>{'streaming': false, 'polling': false},
      ),
      defaultInputModes: <String>['text'],
      defaultOutputModes: <String>['text'],
    );
    return RemoteA2aAgent(
      name: name,
      agentCard: agentCard,
      description: description,
    );
  }

  /// Extracts the first matching endpoint URI from Agent Registry details.
  String? getConnectionUri(
    Map<String, Object?> resourceDetails, {
    AgentRegistryProtocolType? protocolType,
    String? protocolBinding,
  }) {
    final List<Map<String, Object?>> protocols = <Map<String, Object?>>[];
    final Object? nestedProtocols = resourceDetails['protocols'];
    if (nestedProtocols is List) {
      protocols.addAll(
        nestedProtocols.whereType<Map>().map(_toStringObjectMap),
      );
    }
    if (resourceDetails['interfaces'] is List) {
      protocols.add(<String, Object?>{
        'interfaces': resourceDetails['interfaces'],
      });
    }

    for (final Map<String, Object?> protocol in protocols) {
      if (protocolType != null &&
          _readString(protocol['type']) != protocolType.value) {
        continue;
      }
      final Object? interfaces = protocol['interfaces'];
      if (interfaces is! List) {
        continue;
      }
      for (final Object? interfaceValue in interfaces) {
        if (interfaceValue is! Map) {
          continue;
        }
        final Map<String, Object?> interfaceMap = _toStringObjectMap(
          interfaceValue,
        );
        if (protocolBinding != null &&
            _readString(interfaceMap['protocolBinding']) != protocolBinding) {
          continue;
        }
        final String url = _readString(interfaceMap['url']);
        if (url.isNotEmpty) {
          return url;
        }
      }
    }
    return null;
  }

  Future<Map<String, Object?>> _makeRequest(
    String path, {
    Map<String, String>? params,
  }) async {
    final Uri uri = _buildRequestUri(path, params: params);
    try {
      final AgentRegistryHttpResponse response = await _httpGetProvider(
        uri,
        headers: <String, String>{
          ...await _authHeadersProvider(),
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'API request failed with status ${response.statusCode}: '
          '${_responseBodySummary(response.body)}',
        );
      }
      return response.body;
    } on SocketException catch (error) {
      throw StateError('API request failed (network error): $error');
    } on HandshakeException catch (error) {
      throw StateError('API request failed (network error): $error');
    } catch (error) {
      if (error is StateError) {
        rethrow;
      }
      throw StateError('API request failed: $error');
    }
  }

  Uri _buildRequestUri(String path, {Map<String, String>? params}) {
    final String resolvedPath = path.startsWith('projects/')
        ? '/v1alpha/$path'
        : '/v1alpha/$_basePath/$path';
    return Uri.parse(_agentRegistryBaseUrl).replace(
      path: resolvedPath,
      queryParameters: params == null || params.isEmpty ? null : params,
    );
  }

  AgentCard? _tryStoredAgentCard(Map<String, Object?> agentInfo) {
    final Object? cardValue = agentInfo['card'];
    if (cardValue is! Map) {
      return null;
    }
    final Map<String, Object?> card = _toStringObjectMap(cardValue);
    if (_readString(card['type']) != 'A2A_AGENT_CARD') {
      return null;
    }
    final Object? contentValue = card['content'];
    if (contentValue is! Map) {
      return null;
    }
    return AgentCard.fromJson(
      _normalizeAgentCardJson(_toStringObjectMap(contentValue)),
    );
  }

  List<AgentSkill> _readAgentSkills(Object? rawSkills) {
    if (rawSkills is! List) {
      return const <AgentSkill>[];
    }
    return rawSkills
        .whereType<Map>()
        .map(
          (Map skill) => AgentSkill.fromJson(
            _normalizeAgentSkillJson(_toStringObjectMap(skill)),
          ),
        )
        .toList(growable: false);
  }
}

Map<String, Object?> _normalizeAgentCardJson(Map<String, Object?> raw) {
  return <String, Object?>{
    ...raw,
    if (!raw.containsKey('default_input_modes') &&
        raw['defaultInputModes'] != null)
      'default_input_modes': raw['defaultInputModes'],
    if (!raw.containsKey('default_output_modes') &&
        raw['defaultOutputModes'] != null)
      'default_output_modes': raw['defaultOutputModes'],
    if (!raw.containsKey('supports_authenticated_extended_card') &&
        raw['supportsAuthenticatedExtendedCard'] != null)
      'supports_authenticated_extended_card':
          raw['supportsAuthenticatedExtendedCard'],
    if (!raw.containsKey('doc_url') && raw['docUrl'] != null)
      'doc_url': raw['docUrl'],
    if (!raw.containsKey('security_schemes') && raw['securitySchemes'] != null)
      'security_schemes': raw['securitySchemes'],
    if (raw['skills'] is List)
      'skills': (raw['skills'] as List)
          .whereType<Map>()
          .map(
            (Map skill) => _normalizeAgentSkillJson(_toStringObjectMap(skill)),
          )
          .toList(growable: false),
  };
}

Map<String, Object?> _normalizeAgentSkillJson(Map<String, Object?> raw) {
  return <String, Object?>{
    ...raw,
    if (!raw.containsKey('input_modes') && raw['inputModes'] != null)
      'input_modes': raw['inputModes'],
    if (!raw.containsKey('output_modes') && raw['outputModes'] != null)
      'output_modes': raw['outputModes'],
  };
}

String _cleanName(String name) {
  String clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  clean = clean.replaceAll(RegExp(r'_+'), '_');
  clean = clean.replaceAll(RegExp(r'^_+|_+$'), '');
  if (clean.isEmpty) {
    return 'agent';
  }
  final String first = clean[0];
  final bool startsValid = RegExp(r'[A-Za-z_]').hasMatch(first);
  return startsValid ? clean : '_$clean';
}

String _readString(Object? value) => value is String ? value : '${value ?? ''}';

Map<String, Object?> _toStringObjectMap(Map value) {
  return value.map(
    (Object? key, Object? innerValue) =>
        MapEntry<String, Object?>('$key', innerValue),
  );
}

String _responseBodySummary(Map<String, Object?> body) {
  final Object? error = body['error'];
  if (error != null) {
    return '$error';
  }
  final String encoded = jsonEncode(body);
  return encoded.length <= 200 ? encoded : '${encoded.substring(0, 200)}...';
}

Future<AgentRegistryHttpResponse> _defaultAgentRegistryHttpGetProvider(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    final String bodyText = await utf8.decoder.bind(response).join();
    final Object? decoded = bodyText.trim().isEmpty
        ? <String, Object?>{}
        : jsonDecode(bodyText);
    final Map<String, Object?> body = decoded is Map
        ? _toStringObjectMap(decoded)
        : <String, Object?>{};
    final Map<String, String> responseHeaders = <String, String>{};
    response.headers.forEach((String key, List<String> values) {
      responseHeaders[key] = values.join(',');
    });
    return AgentRegistryHttpResponse(
      statusCode: response.statusCode,
      body: body,
      headers: responseHeaders,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> _defaultAgentRegistryAuthHeadersProvider() async {
  final String token = await resolveDefaultGoogleAccessToken();
  return <String, String>{'Authorization': 'Bearer $token'};
}
