/// API Registry-backed MCP tool discovery and loading helpers.
library;

import 'dart:convert';
import 'dart:io';

import '../agents/readonly_context.dart';
import '_google_access_token.dart';
import 'base_toolset.dart';
import 'mcp_tool/mcp_session_manager.dart';
import 'mcp_tool/mcp_toolset.dart';

const String _apiRegistryBaseUrl = 'https://cloudapiregistry.googleapis.com';

/// HTTP GET response payload used by [ApiRegistry].
class ApiRegistryHttpResponse {
  /// Creates an HTTP response wrapper.
  ApiRegistryHttpResponse({
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

/// Function that executes one API Registry list request.
typedef ApiRegistryHttpGetProvider =
    Future<ApiRegistryHttpResponse> Function(
      Uri uri, {
      required Map<String, String> headers,
    });

/// Function that resolves auth headers for API Registry and MCP calls.
typedef ApiRegistryAuthHeadersProvider = Future<Map<String, String>> Function();

/// Registered MCP server connection details.
class RegisteredMcpServer {
  /// Creates a registered MCP server entry.
  RegisteredMcpServer({
    required this.name,
    required this.connectionParams,
    Map<String, Object?>? payload,
  }) : payload = payload == null
           ? <String, Object?>{}
           : Map<String, Object?>.from(payload);

  /// Logical server name used for lookups.
  final String name;

  /// Connection parameters for this MCP server.
  final McpConnectionParams connectionParams;

  /// Raw API Registry payload for the MCP server, when available.
  final Map<String, Object?> payload;
}

/// Registry that resolves MCP-backed toolsets for ADK tools.
class ApiRegistry {
  /// Creates an API registry scoped to one API Registry project.
  ApiRegistry({
    required this.apiRegistryProjectId,
    this.location = 'global',
    this.headerProvider,
    ApiRegistryAuthHeadersProvider? authHeadersProvider,
    Iterable<RegisteredMcpServer>? mcpServers,
  }) : _authHeadersProvider =
           authHeadersProvider ?? _defaultApiRegistryAuthHeadersProvider {
    if (mcpServers != null) {
      for (final RegisteredMcpServer server in mcpServers) {
        _mcpServers[server.name] = server;
      }
    }
  }

  /// API Registry project identifier.
  final String apiRegistryProjectId;

  /// API Registry location.
  final String location;

  /// Optional header provider used when connecting to MCP servers.
  final Map<String, String> Function(ReadonlyContext)? headerProvider;
  final ApiRegistryAuthHeadersProvider _authHeadersProvider;
  final Map<String, RegisteredMcpServer> _mcpServers =
      <String, RegisteredMcpServer>{};

  /// Creates a registry and loads MCP servers from Google Cloud API Registry.
  static Future<ApiRegistry> create({
    required String apiRegistryProjectId,
    String location = 'global',
    Map<String, String> Function(ReadonlyContext)? headerProvider,
    ApiRegistryHttpGetProvider? httpGetProvider,
    ApiRegistryAuthHeadersProvider? authHeadersProvider,
  }) async {
    final ApiRegistry registry = ApiRegistry(
      apiRegistryProjectId: apiRegistryProjectId,
      location: location,
      headerProvider: headerProvider,
      authHeadersProvider: authHeadersProvider,
    );
    await registry.refresh(httpGetProvider: httpGetProvider);
    return registry;
  }

  /// Registers or replaces an MCP server entry.
  void registerMcpServer({
    required String name,
    required McpConnectionParams connectionParams,
  }) {
    _mcpServers[name] = RegisteredMcpServer(
      name: name,
      connectionParams: connectionParams,
    );
  }

  /// Lists registered MCP server names.
  List<String> listMcpServers() {
    return _mcpServers.keys.toList(growable: false);
  }

  /// Reloads MCP server entries from Google Cloud API Registry.
  Future<void> refresh({ApiRegistryHttpGetProvider? httpGetProvider}) async {
    final ApiRegistryHttpGetProvider getProvider =
        httpGetProvider ?? _defaultApiRegistryHttpGetProvider;
    final Map<String, String> authHeaders = await _authHeadersProvider();
    final Uri baseUri = Uri.parse(_apiRegistryBaseUrl);
    String? pageToken;
    final Map<String, RegisteredMcpServer> loaded =
        <String, RegisteredMcpServer>{};

    do {
      final Uri uri = _buildListMcpServersUri(
        baseUri: baseUri,
        projectId: apiRegistryProjectId,
        location: location,
        pageToken: pageToken,
      );
      final ApiRegistryHttpResponse response = await getProvider(
        uri,
        headers: <String, String>{
          ...authHeaders,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Error fetching MCP servers from API Registry '
          '(HTTP ${response.statusCode}).',
          uri: uri,
        );
      }

      final Object? mcpServers = response.body['mcpServers'];
      if (mcpServers is List) {
        for (final Object? item in mcpServers) {
          if (item is! Map) {
            continue;
          }
          final Map<String, Object?> payload = item.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          );
          final RegisteredMcpServer? server = _serverFromPayload(
            payload: payload,
            authHeaders: authHeaders,
          );
          if (server != null) {
            loaded[server.name] = server;
          }
        }
      }

      final Object? next = response.body['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
    } while (pageToken != null);

    _mcpServers
      ..clear()
      ..addAll(loaded);
  }

  /// Returns an [McpToolset] bound to [mcpServerName].
  McpToolset getToolset(
    String mcpServerName, {
    Object? toolFilter,
    String? toolNamePrefix,
  }) {
    final RegisteredMcpServer? server = _mcpServers[mcpServerName];
    if (server == null) {
      throw ArgumentError('MCP server `$mcpServerName` not found.');
    }

    return McpToolset(
      connectionParams: server.connectionParams,
      toolFilter: toolFilter is ToolPredicate || toolFilter is List<String>
          ? toolFilter
          : null,
      toolNamePrefix: toolNamePrefix,
      headerProvider: headerProvider,
    );
  }

  static RegisteredMcpServer? _serverFromPayload({
    required Map<String, Object?> payload,
    required Map<String, String> authHeaders,
  }) {
    final Object? nameValue = payload['name'];
    if (nameValue is! String || nameValue.isEmpty) {
      return null;
    }
    final Object? urlsValue = payload['urls'];
    if (urlsValue is! List || urlsValue.isEmpty) {
      return null;
    }
    final String? firstUrl = urlsValue.first is String
        ? urlsValue.first as String
        : null;
    if (firstUrl == null || firstUrl.isEmpty) {
      return null;
    }
    final String resolvedUrl =
        firstUrl.startsWith('http://') || firstUrl.startsWith('https://')
        ? firstUrl
        : 'https://$firstUrl';
    return RegisteredMcpServer(
      name: nameValue,
      connectionParams: StreamableHTTPConnectionParams(
        url: resolvedUrl,
        headers: authHeaders,
      ),
      payload: payload,
    );
  }
}

Uri _buildListMcpServersUri({
  required Uri baseUri,
  required String projectId,
  required String location,
  String? pageToken,
}) {
  final String base = baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
  final Uri uri = Uri.parse(
    '$base/v1beta/projects/${Uri.encodeComponent(projectId)}/locations/'
    '${Uri.encodeComponent(location)}/mcpServers',
  );
  if (pageToken == null || pageToken.isEmpty) {
    return uri;
  }
  return uri.replace(queryParameters: <String, String>{'pageToken': pageToken});
}

Future<ApiRegistryHttpResponse> _defaultApiRegistryHttpGetProvider(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    final List<int> bodyBytes = await response.fold<List<int>>(<int>[], (
      List<int> previous,
      List<int> element,
    ) {
      previous.addAll(element);
      return previous;
    });
    final Object? decoded = bodyBytes.isEmpty
        ? <String, Object?>{}
        : jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    final Map<String, Object?> body = decoded is Map
        ? decoded.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          )
        : <String, Object?>{};
    final Map<String, String> responseHeaders = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      if (values.isNotEmpty) {
        responseHeaders[name] = values.join(',');
      }
    });
    return ApiRegistryHttpResponse(
      statusCode: response.statusCode,
      body: body,
      headers: responseHeaders,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> _defaultApiRegistryAuthHeadersProvider() async {
  final String token = await resolveDefaultGoogleAccessToken(
    scopes: const <String>['https://www.googleapis.com/auth/cloud-platform'],
  );
  final String? quotaProjectId = Platform
      .environment['GOOGLE_CLOUD_QUOTA_PROJECT']
      ?.trim();
  return <String, String>{
    'Authorization': 'Bearer $token',
    if (quotaProjectId != null && quotaProjectId.isNotEmpty)
      'x-goog-user-project': quotaProjectId,
  };
}
