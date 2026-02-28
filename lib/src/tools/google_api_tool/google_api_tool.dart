import 'dart:convert';
import 'dart:io';

import '../../auth/auth_credential.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../openapi_tool/auth/auth_helpers.dart';
import '../openapi_tool/openapi_spec_parser/rest_api_tool.dart';
import '../tool_context.dart';

typedef GoogleApiRequestExecutor =
    Future<Map<String, Object?>> Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      Object? body,
    });

class GoogleApiOperation {
  GoogleApiOperation({
    required this.operationId,
    required this.method,
    required this.path,
    this.summary = '',
    this.description = '',
    List<Map<String, Object?>>? parameters,
    this.requestBodySchema,
  }) : parameters = parameters ?? <Map<String, Object?>>[];

  final String operationId;
  final String method;
  final String path;
  final String summary;
  final String description;
  final List<Map<String, Object?>> parameters;
  final Map<String, Object?>? requestBodySchema;

  String get declarationName => _sanitizeName(operationId);

  FunctionDeclaration toDeclaration() {
    final Map<String, Object?> properties = <String, Object?>{};
    final List<String> required = <String>[];
    for (final Map<String, Object?> parameter in parameters) {
      final String name = '${parameter['name'] ?? ''}';
      if (name.isEmpty) {
        continue;
      }
      properties[name] = _readMap(parameter['schema']);
      if (parameter['required'] == true) {
        required.add(name);
      }
    }
    if (requestBodySchema != null) {
      properties['body'] = requestBodySchema!;
    }
    return FunctionDeclaration(
      name: declarationName,
      description: description.isEmpty ? summary : description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
      },
    );
  }
}

class GoogleApiTool extends BaseTool {
  GoogleApiTool({
    required GoogleApiOperation operation,
    required String baseUrl,
    AuthCredential? authCredential,
    Object? authScheme,
    Map<String, String>? defaultHeaders,
    GoogleApiRequestExecutor? requestExecutor,
  }) : _operation = operation,
       _baseUrl = baseUrl,
       _defaultHeaders = defaultHeaders ?? <String, String>{},
       _legacyRequestExecutor = requestExecutor ?? _defaultHttpRequestExecutor,
       _restApiTool = null,
       _authCredential = authCredential,
       _authScheme = authScheme,
       super(
         name: operation.declarationName,
         description: operation.description.isEmpty
             ? operation.summary
             : operation.description,
       );

  GoogleApiTool.fromRestApiTool(
    RestApiTool restApiTool, {
    String? clientId,
    String? clientSecret,
    ServiceAccountAuth? serviceAccount,
    Map<String, String>? additionalHeaders,
  }) : _operation = null,
       _baseUrl = null,
       _defaultHeaders = <String, String>{},
       _legacyRequestExecutor = null,
       _restApiTool = restApiTool,
       _authCredential = restApiTool.authCredential,
       _authScheme = restApiTool.authScheme,
       super(name: restApiTool.name, description: restApiTool.description) {
    if (additionalHeaders != null && additionalHeaders.isNotEmpty) {
      restApiTool.setDefaultHeaders(additionalHeaders);
    }
    if (serviceAccount != null) {
      configureSaAuth(serviceAccount);
    } else if (clientId != null &&
        clientId.isNotEmpty &&
        clientSecret != null &&
        clientSecret.isNotEmpty) {
      configureAuth(clientId, clientSecret);
    }
  }

  final GoogleApiOperation? _operation;
  final String? _baseUrl;
  final GoogleApiRequestExecutor? _legacyRequestExecutor;
  final Map<String, String> _defaultHeaders;
  final RestApiTool? _restApiTool;

  AuthCredential? _authCredential;
  Object? _authScheme;

  AuthCredential? get authCredential => _authCredential;

  set authCredential(AuthCredential? value) {
    _authCredential = value;
    _restApiTool?.configureAuthCredential(value);
  }

  Object? get authScheme => _authScheme;

  set authScheme(Object? value) {
    _authScheme = value;
    _restApiTool?.configureAuthScheme(value);
  }

  @override
  FunctionDeclaration? getDeclaration() {
    final RestApiTool? delegate = _restApiTool;
    if (delegate != null) {
      return delegate.getDeclaration();
    }
    return _operation?.toDeclaration();
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final RestApiTool? delegate = _restApiTool;
    if (delegate != null) {
      if (_authScheme != null) {
        delegate.configureAuthScheme(_authScheme);
      }
      if (_authCredential != null) {
        delegate.configureAuthCredential(_authCredential);
      }
      return delegate.run(args: args, toolContext: toolContext);
    }

    final Uri resolvedUri = _buildUri(args);
    final Map<String, String> headers = _buildHeaders(args);
    final Object? body = args['body'];

    return _legacyRequestExecutor!(
      method: _operation!.method.toUpperCase(),
      uri: resolvedUri,
      headers: headers,
      body: body,
    );
  }

  void configureAuth(String clientId, String clientSecret) {
    authCredential = AuthCredential(
      authType: AuthCredentialType.openIdConnect,
      oauth2: OAuth2Auth(clientId: clientId, clientSecret: clientSecret),
    );
  }

  void configureSaAuth(ServiceAccountAuth serviceAccount) {
    final binding = serviceAccountSchemeCredential(serviceAccount);
    authScheme = binding.authScheme;
    authCredential = binding.authCredential;
  }

  void setDefaultHeaders(Map<String, String> headers) {
    final RestApiTool? delegate = _restApiTool;
    if (delegate != null) {
      delegate.setDefaultHeaders(headers);
      return;
    }
    _defaultHeaders
      ..clear()
      ..addAll(headers);
  }

  Uri _buildUri(Map<String, dynamic> args) {
    final GoogleApiOperation operation = _operation!;
    String resolvedPath = operation.path;
    final Map<String, String> query = <String, String>{};

    for (final Map<String, Object?> parameter in operation.parameters) {
      final String name = '${parameter['name'] ?? ''}';
      if (name.isEmpty || !args.containsKey(name)) {
        continue;
      }
      final String location = '${parameter['in'] ?? 'query'}';
      final Object? value = args[name];
      if (value == null) {
        continue;
      }
      if (location == 'path') {
        resolvedPath = resolvedPath.replaceAll(
          '{$name}',
          Uri.encodeComponent('$value'),
        );
      } else if (location == 'query') {
        query[name] = '$value';
      }
    }

    final String normalizedBase = _baseUrl!.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final String normalizedPath = resolvedPath.startsWith('/')
        ? resolvedPath
        : '/$resolvedPath';
    return Uri.parse(
      '$normalizedBase$normalizedPath',
    ).replace(queryParameters: query.isEmpty ? null : query);
  }

  Map<String, String> _buildHeaders(Map<String, dynamic> args) {
    final GoogleApiOperation operation = _operation!;
    final Map<String, String> headers = <String, String>{
      'accept': 'application/json',
      ..._defaultHeaders,
    };

    for (final Map<String, Object?> parameter in operation.parameters) {
      final String name = '${parameter['name'] ?? ''}';
      if (name.isEmpty || !args.containsKey(name)) {
        continue;
      }
      final Object? value = args[name];
      if (value == null) {
        continue;
      }
      final String location = '${parameter['in'] ?? 'query'}';
      if (location == 'header') {
        headers[name] = '$value';
      }
    }

    final List<String> cookieParts = <String>[];
    for (final Map<String, Object?> parameter in operation.parameters) {
      final String name = '${parameter['name'] ?? ''}';
      if (name.isEmpty || !args.containsKey(name)) {
        continue;
      }
      final Object? value = args[name];
      if (value == null) {
        continue;
      }
      final String location = '${parameter['in'] ?? 'query'}';
      if (location == 'cookie') {
        cookieParts.add('$name=$value');
      }
    }
    if (cookieParts.isNotEmpty) {
      headers[HttpHeaders.cookieHeader] = cookieParts.join('; ');
    }

    final AuthCredential? credential = _authCredential;
    if (credential?.oauth2?.accessToken != null &&
        credential!.oauth2!.accessToken!.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] =
          'Bearer ${credential.oauth2!.accessToken}';
    }
    return headers;
  }
}

Future<Map<String, Object?>> _defaultHttpRequestExecutor({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  Object? body,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decodeStream(response);
    final Map<String, List<String>> responseHeaders = <String, List<String>>{};
    response.headers.forEach((String name, List<String> values) {
      responseHeaders[name] = List<String>.from(values);
    });
    Object? parsed;
    if (responseBody.isNotEmpty) {
      try {
        parsed = jsonDecode(responseBody);
      } catch (_) {
        parsed = responseBody;
      }
    }

    return <String, Object?>{
      'status': response.statusCode,
      'headers': responseHeaders,
      'body': parsed,
    };
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

String _sanitizeName(String operationId) {
  final String candidate = operationId
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return candidate.isEmpty ? 'google_api_operation' : candidate;
}
