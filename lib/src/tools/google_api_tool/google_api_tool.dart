import 'dart:convert';
import 'dart:io';

import '../../auth/auth_credential.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
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
      final Object? isRequired = parameter['required'];
      if (isRequired == true) {
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
    required this.operation,
    required this.baseUrl,
    this.authCredential,
    this.authScheme,
    Map<String, String>? defaultHeaders,
    GoogleApiRequestExecutor? requestExecutor,
  }) : _defaultHeaders = defaultHeaders ?? <String, String>{},
       _requestExecutor = requestExecutor ?? _defaultHttpRequestExecutor,
       super(
         name: operation.declarationName,
         description: operation.description.isEmpty
             ? operation.summary
             : operation.description,
       );

  final GoogleApiOperation operation;
  final String baseUrl;
  AuthCredential? authCredential;
  Object? authScheme;
  final GoogleApiRequestExecutor _requestExecutor;
  final Map<String, String> _defaultHeaders;

  @override
  FunctionDeclaration? getDeclaration() {
    return operation.toDeclaration();
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Uri resolvedUri = _buildUri(args);
    final Map<String, String> headers = _buildHeaders();
    final Object? body = args['body'];

    final Map<String, Object?> response = await _requestExecutor(
      method: operation.method.toUpperCase(),
      uri: resolvedUri,
      headers: headers,
      body: body,
    );
    return response;
  }

  void configureAuth(String clientId, String clientSecret) {
    authCredential = AuthCredential(
      authType: AuthCredentialType.openIdConnect,
      oauth2: OAuth2Auth(clientId: clientId, clientSecret: clientSecret),
    );
  }

  void configureSaAuth(ServiceAccountAuth serviceAccount) {
    authScheme = 'service_account';
    authCredential = AuthCredential(
      authType: AuthCredentialType.serviceAccount,
      serviceAccount: serviceAccount,
    );
  }

  void setDefaultHeaders(Map<String, String> headers) {
    _defaultHeaders
      ..clear()
      ..addAll(headers);
  }

  Uri _buildUri(Map<String, dynamic> args) {
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

    final String normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final String normalizedPath = resolvedPath.startsWith('/')
        ? resolvedPath
        : '/$resolvedPath';
    return Uri.parse(
      '$normalizedBase$normalizedPath',
    ).replace(queryParameters: query.isEmpty ? null : query);
  }

  Map<String, String> _buildHeaders() {
    final Map<String, String> headers = <String, String>{
      'accept': 'application/json',
      ..._defaultHeaders,
    };
    final AuthCredential? credential = authCredential;
    if (credential?.oauth2?.accessToken != null &&
        credential!.oauth2!.accessToken!.isNotEmpty) {
      headers['authorization'] = 'Bearer ${credential.oauth2!.accessToken}';
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
