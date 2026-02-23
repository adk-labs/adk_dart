import '../../agents/readonly_context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_schemes.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import 'google_api_tool.dart';
import 'googleapi_to_openapi_converter.dart';

class GoogleApiToolset extends BaseToolset {
  GoogleApiToolset(
    this.apiName,
    this.apiVersion, {
    this.clientId,
    this.clientSecret,
    super.toolFilter,
    this.serviceAccount,
    super.toolNamePrefix,
    Map<String, String>? additionalHeaders,
    this.discoverySpec,
    this.openApiSpec,
    this.specFetcher,
    this.requestExecutor,
  }) : additionalHeaders = additionalHeaders ?? <String, String>{};

  final String apiName;
  final String apiVersion;
  String? clientId;
  String? clientSecret;
  ServiceAccountAuth? serviceAccount;
  final Map<String, String> additionalHeaders;
  final Map<String, Object?>? discoverySpec;
  final Map<String, Object?>? openApiSpec;
  final GoogleDiscoverySpecFetcher? specFetcher;
  final GoogleApiRequestExecutor? requestExecutor;

  List<GoogleApiOperation>? _operations;
  String? _baseUrl;
  OpenIdConnectWithConfig? _oidcScheme;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    await _ensureLoaded();
    final List<BaseTool> tools = <BaseTool>[];
    for (final GoogleApiOperation operation in _operations!) {
      final GoogleApiTool tool = GoogleApiTool(
        operation: operation,
        baseUrl: _baseUrl!,
        defaultHeaders: additionalHeaders,
        requestExecutor: requestExecutor,
      );
      if (serviceAccount != null) {
        tool.configureSaAuth(serviceAccount!);
      } else if (clientId != null &&
          clientId!.isNotEmpty &&
          clientSecret != null &&
          clientSecret!.isNotEmpty) {
        tool.configureAuth(clientId!, clientSecret!);
      }
      tool.authScheme = _oidcScheme;
      if (isToolSelected(tool, readonlyContext)) {
        tools.add(tool);
      }
    }
    return tools;
  }

  void setToolFilter(Object filter) {
    toolFilter = filter;
  }

  void configureAuth(String clientId, String clientSecret) {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
  }

  void configureSaAuth(ServiceAccountAuth serviceAccount) {
    this.serviceAccount = serviceAccount;
  }

  @override
  Future<void> close() async {}

  Future<void> _ensureLoaded() async {
    if (_operations != null && _baseUrl != null) {
      return;
    }

    final Map<String, Object?> spec;
    if (openApiSpec != null) {
      spec = Map<String, Object?>.from(openApiSpec!);
    } else {
      final GoogleApiToOpenApiConverter converter = GoogleApiToOpenApiConverter(
        apiName,
        apiVersion,
        discoverySpec: discoverySpec,
        specFetcher: specFetcher,
      );
      spec = await converter.convert();
    }

    _baseUrl = _extractBaseUrl(spec);
    _operations = _extractOperations(spec);
    _oidcScheme = _buildOpenIdScheme(spec);
  }
}

String _extractBaseUrl(Map<String, Object?> openApiSpec) {
  final List<Object?> servers = _readList(openApiSpec['servers']);
  if (servers.isEmpty) {
    return '';
  }
  final Map<String, Object?> first = _readMap(servers.first);
  return '${first['url'] ?? ''}';
}

OpenIdConnectWithConfig _buildOpenIdScheme(Map<String, Object?> openApiSpec) {
  final Map<String, Object?> components = _readMap(openApiSpec['components']);
  final Map<String, Object?> securitySchemes = _readMap(
    components['securitySchemes'],
  );
  final Map<String, Object?> oauth2 = _readMap(securitySchemes['oauth2']);
  final Map<String, Object?> flows = _readMap(oauth2['flows']);
  final Map<String, Object?> authCode = _readMap(flows['authorizationCode']);
  final Map<String, Object?> scopes = _readMap(authCode['scopes']);
  final List<String> scopeKeys = scopes.keys.toList();

  return OpenIdConnectWithConfig(
    authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
    userinfoEndpoint: 'https://openidconnect.googleapis.com/v1/userinfo',
    revocationEndpoint: 'https://oauth2.googleapis.com/revoke',
    tokenEndpointAuthMethodsSupported: const <String>[
      'client_secret_post',
      'client_secret_basic',
    ],
    grantTypesSupported: const <String>['authorization_code'],
    scopes: scopeKeys,
  );
}

List<GoogleApiOperation> _extractOperations(Map<String, Object?> openApiSpec) {
  final Map<String, Object?> paths = _readMap(openApiSpec['paths']);
  final List<GoogleApiOperation> operations = <GoogleApiOperation>[];
  for (final MapEntry<String, Object?> pathEntry in paths.entries) {
    final Map<String, Object?> pathItem = _readMap(pathEntry.value);
    for (final MapEntry<String, Object?> methodEntry in pathItem.entries) {
      final String method = methodEntry.key.toUpperCase();
      final Map<String, Object?> operation = _readMap(methodEntry.value);
      final String operationId = '${operation['operationId'] ?? ''}';
      if (operationId.isEmpty) {
        continue;
      }
      final List<Map<String, Object?>> parameters = _readList(
        operation['parameters'],
      ).map(_readMap).toList();
      final Map<String, Object?> requestBody = _readMap(
        operation['requestBody'],
      );
      final Map<String, Object?> content = _readMap(requestBody['content']);
      final Map<String, Object?> appJson = _readMap(
        content['application/json'],
      );
      final Map<String, Object?> schema = _readMap(appJson['schema']);
      operations.add(
        GoogleApiOperation(
          operationId: operationId,
          method: method,
          path: pathEntry.key,
          summary: '${operation['summary'] ?? ''}',
          description: '${operation['description'] ?? ''}',
          parameters: parameters,
          requestBodySchema: schema.isEmpty ? null : schema,
        ),
      );
    }
  }
  return operations;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}
