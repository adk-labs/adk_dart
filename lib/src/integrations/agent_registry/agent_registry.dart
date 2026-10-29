/// Agent Registry-backed MCP and Remote A2A integration helpers.
library;

import 'dart:convert';
import 'dart:io';

import '../../a2a/protocol.dart' hide SecurityScheme;
import '../../agents/readonly_context.dart';
import '../../agents/remote_a2a_agent.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_schemes.dart';
import '../../auth/auth_tool.dart';
import '../agent_identity/agent_identity.dart' show GcpAuthProviderScheme;
import '../../tools/base_tool.dart';
import '../../tools/_google_access_token.dart';
import '../../tools/mcp_tool/mcp_session_manager.dart';
import '../../tools/mcp_tool/mcp_toolset.dart';

export '../agent_identity/agent_identity.dart' show GcpAuthProviderScheme;

const String _agentRegistryBaseUrl =
    'https://agentregistry.googleapis.com/v1alpha';
const String _gcpMcpServerDestinationIdKey = 'gcp.mcp.server.destination.id';
const String _runtimeReferenceAttribute =
    'apphub.googleapis.com/RuntimeReference';

/// Selects the `authProviderBinding` from the most recently updated binding.
Map<String, Object?>? selectAuthProviderBinding(
  List<Map<String, Object?>> bindings, [
  String resourceName = '',
]) {
  if (bindings.isEmpty) {
    return null;
  }
  Map<String, Object?>? newest;
  (String, String)? newestKey;
  for (final Map<String, Object?> binding in bindings) {
    final Map<String, Object?>? candidate = _extractAuthProviderBindingMap(
      binding,
    );
    if (candidate == null) {
      continue;
    }
    final (String, String) key = _updateTimeKey(binding);
    if (newest == null ||
        newestKey == null ||
        _compareUpdateTimeKey(key, newestKey) > 0) {
      newest = candidate;
      newestKey = key;
    }
  }
  return newest;
}

/// Builds a [GcpAuthProviderScheme] from an `authProviderBinding` payload.
GcpAuthProviderScheme? schemeFromBinding(
  Map<String, Object?>? authProviderBinding, {
  String? continueUri,
}) {
  if (authProviderBinding == null || authProviderBinding.isEmpty) {
    return null;
  }
  final String authProvider = _readString(
    authProviderBinding['authProvider'] ?? authProviderBinding['auth_provider'],
  ).trim();
  if (authProvider.isEmpty) {
    return null;
  }
  final Object? rawScopes = authProviderBinding['scopes'];
  final List<String>? scopes = rawScopes is List
      ? rawScopes
            .map((Object? item) => _readString(item).trim())
            .where((String item) => item.isNotEmpty)
            .toList(growable: false)
      : null;
  final String bindingContinueUri = _readString(
    authProviderBinding['continueUri'] ?? authProviderBinding['continue_uri'],
  ).trim();
  final String? resolvedContinueUri =
      (continueUri != null && continueUri.trim().isNotEmpty)
      ? continueUri.trim()
      : (bindingContinueUri.isNotEmpty ? bindingContinueUri : null);
  return GcpAuthProviderScheme(
    name: authProvider,
    scopes: scopes != null && scopes.isNotEmpty ? scopes : null,
    continueUri: resolvedContinueUri,
  );
}

/// Supported Agent Registry protocol types.
enum AgentRegistryProtocolType {
  /// Unspecified protocol type.
  typeUnspecified('TYPE_UNSPECIFIED'),

  /// Agent-to-Agent (A2A) protocol.
  a2aAgent('A2A_AGENT'),

  /// Custom protocol type.
  custom('CUSTOM');

  /// Creates an Agent Registry protocol type with its wire [value].
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

/// Function that executes one Agent Registry POST request with a JSON body.
typedef AgentRegistryHttpPostProvider =
    Future<AgentRegistryHttpResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
      Object? body,
    });

/// Function that resolves auth headers for Agent Registry and downstream calls.
typedef AgentRegistryAuthHeadersProvider =
    Future<Map<String, String>> Function();

/// MCP toolset backed by a single registered Agent Registry MCP server.
class AgentRegistrySingleMcpToolset extends McpToolset {
  /// Creates an Agent Registry MCP toolset.
  AgentRegistrySingleMcpToolset({
    required this.destinationResourceId,
    this.mcpServerId,
    required super.connectionParams,
    super.toolNamePrefix,
    super.headerProvider,
    this.authScheme,
    this.authCredential,
    this.continueUri,
    AuthConfig? authConfig,
  }) : super(
         authConfig:
             authConfig ??
             _buildAuthConfig(
               authScheme: authScheme,
               authCredential: authCredential,
             ),
       );

  /// Destination resource identifier recorded on tool spans.
  final String? destinationResourceId;

  /// Stable MCP server identifier from Agent Registry.
  final String? mcpServerId;

  /// Resolved or caller-provided auth scheme.
  final Object? authScheme;

  /// Optional auth credential paired with [authScheme].
  final AuthCredential? authCredential;

  /// Optional caller-supplied continue URI preserved across rebinds.
  final String? continueUri;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> tools = await super.getTools(
      readonlyContext: readonlyContext,
    );
    if (destinationResourceId == null || destinationResourceId!.isEmpty) {
      return tools;
    }

    for (final BaseTool tool in tools) {
      tool.customMetadata ??= <String, dynamic>{};
      tool.customMetadata![_gcpMcpServerDestinationIdKey] =
          destinationResourceId;
    }
    return tools;
  }
}

/// Remote A2A agent constructed from an Agent Registry entry.
class AgentRegistryRemoteA2aAgent extends RemoteA2aAgent {
  /// Creates an Agent Registry remote A2A agent.
  AgentRegistryRemoteA2aAgent({
    required super.name,
    required super.agentCard,
    super.description,
    this.authScheme,
    this.authCredential,
    AuthConfig? authConfig,
  }) : authConfig =
           authConfig ??
           _buildAuthConfig(
             authScheme: authScheme,
             authCredential: authCredential,
           );

  /// Resolved or caller-provided auth scheme.
  final Object? authScheme;

  /// Optional auth credential paired with [authScheme].
  final AuthCredential? authCredential;

  /// Optional constructed [AuthConfig] for this agent.
  final AuthConfig? authConfig;
}

/// Client for interacting with Google Cloud Agent Registry.
class AgentRegistry {
  /// Creates an Agent Registry client.
  AgentRegistry({
    required this.projectId,
    required this.location,
    this.headerProvider,
    AgentRegistryHttpGetProvider? httpGetProvider,
    AgentRegistryHttpPostProvider? httpPostProvider,
    AgentRegistryAuthHeadersProvider? authHeadersProvider,
  }) : _httpGetProvider =
           httpGetProvider ?? _defaultAgentRegistryHttpGetProvider,
       _httpPostProvider =
           httpPostProvider ?? _defaultAgentRegistryHttpPostProvider,
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
  final AgentRegistryHttpPostProvider _httpPostProvider;
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

  /// Searches registered MCP servers.
  ///
  /// [searchType] accepts `KEYWORD` or `SEMANTIC`.
  Future<Map<String, Object?>> searchMcpServers({
    String? searchString,
    String? searchType,
    String? filter,
    String? orderBy,
    int? pageSize,
    String? pageToken,
  }) {
    return _search(
      'mcpServers',
      searchString: searchString,
      searchType: searchType,
      filter: filter,
      orderBy: orderBy,
      pageSize: pageSize,
      pageToken: pageToken,
    );
  }

  /// Builds an [McpToolset] from one registered MCP server.
  Future<McpToolset> getMcpToolset(
    String mcpServerName, {
    Object? authScheme,
    AuthCredential? authCredential,
    String? continueUri,
    bool resolveBindings = false,
  }) async {
    final Map<String, Object?> serverDetails = await getMcpServer(
      mcpServerName,
    );
    final String? mcpServerId = switch (serverDetails['mcpServerId']) {
      final String value when value.trim().isNotEmpty => value,
      _ => null,
    };
    final Object? attributes = serverDetails['attributes'];
    final Object? runtimeReference = attributes is Map
        ? attributes[_runtimeReferenceAttribute]
        : null;
    final Object? runtimeReferenceUri = runtimeReference is Map
        ? runtimeReference['uri']
        : null;
    final String? destinationResourceId = switch (runtimeReferenceUri) {
      final String value when value.trim().isNotEmpty => value,
      _ => mcpServerId,
    };
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

    Object? resolvedAuthScheme = authScheme;
    if (resolvedAuthScheme == null) {
      resolvedAuthScheme = _resolveInlineAuthScheme(
        serverDetails,
        mcpServerName,
        continueUri: continueUri,
      );
      if (resolvedAuthScheme == null &&
          (resolveBindings || continueUri != null)) {
        resolvedAuthScheme = await resolveAuthProviderScheme(
          mcpServerId,
          mcpServerName,
          continueUri: continueUri,
        );
      }
    }

    return AgentRegistrySingleMcpToolset(
      destinationResourceId: destinationResourceId,
      mcpServerId: mcpServerId,
      connectionParams: StreamableHTTPConnectionParams(
        url: endpointUri,
        headers: await _authHeadersProvider(),
      ),
      toolNamePrefix: prefix,
      headerProvider: headerProvider,
      authScheme: resolvedAuthScheme,
      authCredential: authCredential,
      continueUri: continueUri,
    );
  }

  /// Resolves the [GcpAuthProviderScheme] bound to [resourceId] via `bindings`.
  Future<GcpAuthProviderScheme?> resolveAuthProviderScheme(
    String? resourceId,
    String resourceName, {
    String? continueUri,
  }) async {
    if (resourceId == null || resourceId.trim().isEmpty) {
      return null;
    }
    try {
      final List<Map<String, Object?>> bindings =
          await _listAuthProviderBindings('bindings', resourceId.trim());
      final Map<String, Object?>? selected = selectAuthProviderBinding(
        bindings,
        resourceName,
      );
      return schemeFromBinding(selected, continueUri: continueUri);
    } catch (_) {
      return null;
    }
  }

  /// Resolves the [GcpAuthProviderScheme] available to [sourceIdentifier] for
  /// [resourceId] via `bindings:fetchAvailable`.
  Future<GcpAuthProviderScheme?> fetchAvailableAuthScheme(
    String resourceId,
    String sourceIdentifier, {
    String? continueUri,
  }) async {
    final List<Map<String, Object?>> bindings = await _listAuthProviderBindings(
      'bindings:fetchAvailable',
      resourceId,
      params: <String, String>{
        'sourceIdentifier': sourceIdentifier,
        'targetIdentifier': resourceId,
      },
    );
    final List<Map<String, Object?>> ownBindings = bindings
        .where((Map<String, Object?> binding) {
          final Object? source = binding['source'];
          if (source is! Map) {
            return false;
          }
          return _readString(source['identifier']) == sourceIdentifier;
        })
        .toList(growable: false);
    final Map<String, Object?>? selected = selectAuthProviderBinding(
      ownBindings.isNotEmpty ? ownBindings : bindings,
      resourceId,
    );
    return schemeFromBinding(selected, continueUri: continueUri);
  }

  Future<List<Map<String, Object?>>> _listAuthProviderBindings(
    String path,
    String resourceId, {
    Map<String, String>? params,
  }) async {
    final Map<String, String> queryParams = <String, String>{...?params};
    final List<Map<String, Object?>> bindings = <Map<String, Object?>>[];
    while (true) {
      final Map<String, Object?> data = await _makeRequest(
        path,
        params: queryParams,
      );
      final Object? rawBindings = data['bindings'];
      if (rawBindings is List) {
        for (final Object? entry in rawBindings) {
          if (entry is! Map) {
            continue;
          }
          final Map<String, Object?> binding = _toStringObjectMap(entry);
          final Object? target = binding['target'];
          final String targetId = target is Map
              ? _readString(target['identifier'])
              : '';
          final Map<String, Object?>? authProviderBinding =
              _extractAuthProviderBindingMap(binding);
          final String authProvider = authProviderBinding == null
              ? ''
              : _readString(
                  authProviderBinding['authProvider'] ??
                      authProviderBinding['auth_provider'],
                );
          if ((targetId.isEmpty || targetId.endsWith(resourceId)) &&
              authProvider.isNotEmpty) {
            bindings.add(binding);
          }
        }
      }
      final String pageToken = _readString(data['nextPageToken']);
      if (pageToken.isEmpty) {
        return bindings;
      }
      queryParams['pageToken'] = pageToken;
    }
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

  /// Searches registered A2A agents.
  ///
  /// [searchType] accepts `KEYWORD` or `SEMANTIC`.
  Future<Map<String, Object?>> searchAgents({
    String? searchString,
    String? searchType,
    String? filter,
    String? orderBy,
    int? pageSize,
    String? pageToken,
  }) {
    return _search(
      'agents',
      searchString: searchString,
      searchType: searchType,
      filter: filter,
      orderBy: orderBy,
      pageSize: pageSize,
      pageToken: pageToken,
    );
  }

  /// Retrieves detailed metadata for one Agent Registry agent.
  Future<Map<String, Object?>> getAgentInfo(String name) {
    return _makeRequest(name);
  }

  /// Executes a `POST {resourceType}:search` request against the registry.
  Future<Map<String, Object?>> _search(
    String resourceType, {
    String? searchString,
    String? searchType,
    String? filter,
    String? orderBy,
    int? pageSize,
    String? pageToken,
  }) {
    final Map<String, Object?> jsonData = <String, Object?>{
      'searchString': ?searchString,
      'searchType': ?searchType,
      'filter': ?filter,
      'orderBy': ?orderBy,
      'pageSize': ?pageSize,
      'pageToken': ?pageToken,
    };
    return _makeRequest('$resourceType:search', method: 'POST', body: jsonData);
  }

  /// Builds a ready-to-use [RemoteA2aAgent] from Agent Registry metadata.
  Future<RemoteA2aAgent> getRemoteA2aAgent(
    String agentName, {
    Object? authScheme,
    AuthCredential? authCredential,
    String? continueUri,
    bool resolveBindings = false,
  }) async {
    final Map<String, Object?> agentInfo = await getAgentInfo(agentName);
    final String? agentId = switch (agentInfo['agentId']) {
      final String value when value.trim().isNotEmpty => value,
      _ => null,
    };
    Object? resolvedAuthScheme = authScheme;
    if (resolvedAuthScheme == null) {
      resolvedAuthScheme = _resolveInlineAuthScheme(
        agentInfo,
        agentName,
        continueUri: continueUri,
      );
      if (resolvedAuthScheme == null &&
          (resolveBindings || continueUri != null)) {
        resolvedAuthScheme = await resolveAuthProviderScheme(
          agentId,
          agentName,
          continueUri: continueUri,
        );
      }
    }

    final AgentCard? storedCard = _tryStoredAgentCard(agentInfo);
    if (storedCard != null) {
      return AgentRegistryRemoteA2aAgent(
        name: _cleanName(storedCard.name),
        agentCard: storedCard,
        description: storedCard.description,
        authScheme: resolvedAuthScheme,
        authCredential: authCredential,
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
    return AgentRegistryRemoteA2aAgent(
      name: name,
      agentCard: agentCard,
      description: description,
      authScheme: resolvedAuthScheme,
      authCredential: authCredential,
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
    String method = 'GET',
    Map<String, String>? params,
    Object? body,
  }) async {
    // POST requests (search) carry a JSON body, not query params.
    final Uri uri = _buildRequestUri(
      path,
      params: method == 'POST' ? null : params,
    );
    try {
      final Map<String, String> headers = <String, String>{
        ...await _authHeadersProvider(),
        'Content-Type': 'application/json',
      };
      final AgentRegistryHttpResponse response = method == 'POST'
          ? await _httpPostProvider(uri, headers: headers, body: body)
          : await _httpGetProvider(uri, headers: headers);
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

(String, String) _updateTimeKey(Map<String, Object?> binding) {
  final String raw = _readString(
    binding['updateTime'] ?? binding['update_time'],
  ).replaceFirst(RegExp(r'Z$'), '');
  final int dotIndex = raw.indexOf('.');
  if (dotIndex < 0) {
    return (raw, ''.padRight(9, '0'));
  }
  final String seconds = raw.substring(0, dotIndex);
  final String fraction = raw.substring(dotIndex + 1).padRight(9, '0');
  return (seconds, fraction);
}

int _compareUpdateTimeKey((String, String) a, (String, String) b) {
  final int first = a.$1.compareTo(b.$1);
  if (first != 0) {
    return first;
  }
  return a.$2.compareTo(b.$2);
}

Map<String, Object?>? _extractAuthProviderBindingMap(
  Map<String, Object?> item,
) {
  final Object? nested =
      item['authProviderBinding'] ?? item['auth_provider_binding'];
  if (nested is Map) {
    final Map<String, Object?> map = _toStringObjectMap(nested);
    final String provider = _readString(
      map['authProvider'] ?? map['auth_provider'],
    ).trim();
    if (provider.isNotEmpty) {
      return map;
    }
  }
  final String directProvider = _readString(
    item['authProvider'] ?? item['auth_provider'],
  ).trim();
  if (directProvider.isNotEmpty) {
    return item;
  }
  return null;
}

GcpAuthProviderScheme? _resolveInlineAuthScheme(
  Map<String, Object?> resourceDetails,
  String resourceName, {
  String? continueUri,
}) {
  final Object? rawList =
      resourceDetails['authProviderBindings'] ??
      resourceDetails['auth_provider_bindings'] ??
      resourceDetails['bindings'];
  if (rawList is List) {
    final List<Map<String, Object?>> bindings = rawList
        .whereType<Map>()
        .map(_toStringObjectMap)
        .toList(growable: false);
    final Map<String, Object?>? selected = selectAuthProviderBinding(
      bindings,
      resourceName,
    );
    if (selected != null) {
      return schemeFromBinding(selected, continueUri: continueUri);
    }
  }
  final Object? singleBinding =
      resourceDetails['authProviderBinding'] ??
      resourceDetails['auth_provider_binding'];
  if (singleBinding is Map) {
    return schemeFromBinding(
      _toStringObjectMap(singleBinding),
      continueUri: continueUri,
    );
  }
  return null;
}

AuthConfig? _buildAuthConfig({
  required Object? authScheme,
  required AuthCredential? authCredential,
}) {
  if (authScheme == null && authCredential == null) {
    return null;
  }
  final String serializedScheme;
  if (authScheme is String) {
    serializedScheme = authScheme;
  } else if (authScheme is SecurityScheme) {
    serializedScheme = jsonEncode(authScheme.toJson());
  } else if (authScheme is Map) {
    serializedScheme = jsonEncode(authScheme);
  } else if (authScheme != null) {
    serializedScheme = '$authScheme';
  } else {
    serializedScheme = '';
  }
  return AuthConfig(
    authScheme: serializedScheme,
    rawAuthCredential: authCredential,
  );
}

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

Future<AgentRegistryHttpResponse> _defaultAgentRegistryHttpPostProvider(
  Uri uri, {
  required Map<String, String> headers,
  Object? body,
}) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client.postUrl(uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }
    final HttpClientResponse response = await request.close();
    final String bodyText = await utf8.decoder.bind(response).join();
    final Object? decoded = bodyText.trim().isEmpty
        ? <String, Object?>{}
        : jsonDecode(bodyText);
    final Map<String, Object?> responseBody = decoded is Map
        ? _toStringObjectMap(decoded)
        : <String, Object?>{};
    final Map<String, String> responseHeaders = <String, String>{};
    response.headers.forEach((String key, List<String> values) {
      responseHeaders[key] = values.join(',');
    });
    return AgentRegistryHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
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
