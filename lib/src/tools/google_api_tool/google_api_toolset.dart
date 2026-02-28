import 'dart:convert';

import '../../agents/readonly_context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_schemes.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../openapi_tool/openapi_spec_parser/openapi_toolset.dart';
import '../openapi_tool/openapi_spec_parser/rest_api_tool.dart';
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

  OpenAPIToolset? _openApiToolset;
  OpenIdConnectWithConfig? _oidcScheme;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    await _ensureLoaded();

    final List<BaseTool> openApiTools = await _openApiToolset!.getTools(
      readonlyContext: readonlyContext,
    );
    final List<BaseTool> tools = <BaseTool>[];

    for (final BaseTool baseTool in openApiTools) {
      if (baseTool is! RestApiTool) {
        continue;
      }

      final GoogleApiTool wrapped = GoogleApiTool.fromRestApiTool(
        baseTool,
        clientId: clientId,
        clientSecret: clientSecret,
        serviceAccount: serviceAccount,
        additionalHeaders: additionalHeaders,
      );
      wrapped.authScheme = _oidcScheme;

      if (isToolSelected(wrapped, readonlyContext)) {
        tools.add(wrapped);
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
  Future<void> close() async {
    final OpenAPIToolset? toolset = _openApiToolset;
    if (toolset != null) {
      await toolset.close();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_openApiToolset != null) {
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

    _oidcScheme = _buildOpenIdScheme(spec);

    _openApiToolset = OpenAPIToolset(
      specDict: spec,
      specStrType: 'yaml',
      authScheme: _oidcScheme,
      requestExecutor: requestExecutor == null
          ? null
          : _wrapGoogleApiRequestExecutor(requestExecutor!),
    );
  }
}

RestApiRequestExecutor _wrapGoogleApiRequestExecutor(
  GoogleApiRequestExecutor requestExecutor,
) {
  return ({required Map<String, Object?> requestParams}) async {
    final String method = '${requestParams['method'] ?? 'GET'}'.toUpperCase();
    final String rawUrl = '${requestParams['url'] ?? ''}';
    Uri uri = Uri.parse(rawUrl);

    final Map<String, Object?> queryParams = _readMap(requestParams['params']);
    if (queryParams.isNotEmpty) {
      final Map<String, String> mergedQuery = <String, String>{
        ...uri.queryParameters,
        for (final MapEntry<String, Object?> entry in queryParams.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      };
      uri = uri.replace(queryParameters: mergedQuery);
    }

    final Map<String, String> headers = <String, String>{
      for (final MapEntry<String, Object?> entry in _readMap(
        requestParams['headers'],
      ).entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };

    final Map<String, Object?> cookieParams = _readMap(requestParams['cookies']);
    if (cookieParams.isNotEmpty) {
      final String cookieHeader = cookieParams.entries
          .where((MapEntry<String, Object?> entry) => entry.value != null)
          .map((MapEntry<String, Object?> entry) => '${entry.key}=${entry.value}')
          .join('; ');
      if (cookieHeader.isNotEmpty) {
        headers['cookie'] = cookieHeader;
      }
    }

    Object? body;
    if (requestParams.containsKey('json')) {
      body = requestParams['json'];
    } else if (requestParams.containsKey('data')) {
      body = requestParams['data'];
    } else if (requestParams.containsKey('files')) {
      body = requestParams['files'];
    }

    final Map<String, Object?> response = await requestExecutor(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
    );

    final int statusCode = _readInt(response['status']) ??
        _readInt(response['statusCode']) ??
        500;
    final Object? bodyPayload = response.containsKey('body')
        ? response['body']
        : response['data'];

    final Map<String, List<String>> responseHeaders =
        _normalizeResponseHeaders(response['headers']);

    Object? jsonBody;
    String textBody = '';
    if (bodyPayload is String) {
      textBody = bodyPayload;
      try {
        jsonBody = jsonDecode(bodyPayload);
      } catch (_) {
        jsonBody = null;
      }
    } else if (bodyPayload != null) {
      jsonBody = bodyPayload;
      try {
        textBody = jsonEncode(bodyPayload);
      } catch (_) {
        textBody = '$bodyPayload';
      }
    }

    return RestApiResponse(
      statusCode: statusCode,
      text: textBody,
      jsonData: jsonBody,
      headers: responseHeaders,
    );
  };
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
  final List<String> scopeKeys = scopes.keys.toList(growable: false);

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
    scopes: scopeKeys.isEmpty ? const <String>[] : <String>[scopeKeys.first],
  );
}

Map<String, List<String>> _normalizeResponseHeaders(Object? value) {
  final Map<String, List<String>> headers = <String, List<String>>{};
  if (value is Map) {
    value.forEach((Object? key, Object? item) {
      final String name = '$key';
      if (item is List) {
        headers[name] = item.map((Object? element) => '$element').toList();
      } else if (item != null) {
        headers[name] = <String>['$item'];
      }
    });
  }
  return headers;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
