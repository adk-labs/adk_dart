import 'dart:convert';
import 'dart:io';

import '../../../agents/readonly_context.dart';
import '../../../auth/auth_credential.dart';
import '../../../features/_feature_registry.dart';
import '../../../models/llm_request.dart';
import '../../../version.dart';
import '../../_gemini_schema_util.dart';
import '../../base_tool.dart';
import '../../tool_context.dart';
import '../auth/auth_helpers.dart';
import '../auth/credential_exchangers/auto_auth_credential_exchanger.dart';
import '../common/common.dart';
import 'openapi_spec_parser.dart';
import 'operation_parser.dart';
import 'tool_auth_handler.dart';

typedef AuthPreparationState = String;

typedef HeaderProvider = Map<String, String> Function(ReadonlyContext context);

typedef RestApiRequestExecutor =
    Future<RestApiResponse> Function({
      required Map<String, Object?> requestParams,
    });

String snakeToLowerCamel(String snakeCaseString) {
  if (!snakeCaseString.contains('_')) {
    return snakeCaseString;
  }

  final List<String> parts = snakeCaseString.split('_');
  return parts.asMap().entries.map((MapEntry<int, String> entry) {
    if (entry.key == 0) {
      return entry.value.toLowerCase();
    }
    if (entry.value.isEmpty) {
      return '';
    }
    return '${entry.value[0].toUpperCase()}${entry.value.substring(1).toLowerCase()}';
  }).join();
}

class RestApiResponse {
  RestApiResponse({
    required this.statusCode,
    this.text = '',
    this.jsonData,
    Map<String, List<String>>? headers,
  }) : headers = headers ?? <String, List<String>>{};

  final int statusCode;
  final String text;
  final Object? jsonData;
  final Map<String, List<String>> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class RestApiTool extends BaseTool {
  RestApiTool({
    required String name,
    required String description,
    required this.endpoint,
    required Object operation,
    Object? authScheme,
    Object? authCredential,
    bool shouldParseOperation = true,
    Object? sslVerify,
    HeaderProvider? headerProvider,
    String? credentialKey,
    RestApiRequestExecutor? requestExecutor,
  }) : operation = _readMap(operation),
       _sslVerify = sslVerify,
       _headerProvider = headerProvider,
       _credentialKey = credentialKey,
       _requestExecutor = requestExecutor ?? _request,
       credentialExchanger = AutoAuthCredentialExchanger(),
       super(
         name: name.length > 60 ? name.substring(0, 60) : name,
         description: description,
       ) {
    configureAuthCredential(authCredential);
    configureAuthScheme(authScheme);
    if (shouldParseOperation) {
      _operationParser = OperationParser(this.operation);
    }
  }

  final OperationEndpoint endpoint;
  final Map<String, Object?> operation;
  final RestApiRequestExecutor _requestExecutor;
  final AutoAuthCredentialExchanger credentialExchanger;

  late OperationParser _operationParser;

  Object? authScheme;
  AuthCredential? authCredential;

  final Map<String, String> _defaultHeaders = <String, String>{};
  Object? _sslVerify;
  HeaderProvider? _headerProvider;
  String? _credentialKey;

  static RestApiTool fromParsedOperation(
    ParsedOperation parsed, {
    Object? sslVerify,
    HeaderProvider? headerProvider,
    RestApiRequestExecutor? requestExecutor,
  }) {
    final OperationParser operationParser = OperationParser.load(
      parsed.operation,
      parsed.parameters,
      parsed.returnValue,
    );

    final String toolName = toSnakeCase(operationParser.getFunctionName());
    final RestApiTool generated = RestApiTool(
      name: toolName,
      description:
          _readString(parsed.operation['description']) ??
          _readString(parsed.operation['summary']) ??
          '',
      endpoint: parsed.endpoint,
      operation: parsed.operation,
      authScheme: parsed.authScheme,
      authCredential: parsed.authCredential,
      sslVerify: sslVerify,
      headerProvider: headerProvider,
      requestExecutor: requestExecutor,
    );
    generated._operationParser = operationParser;
    return generated;
  }

  static RestApiTool fromParsedOperationStr(String parsedOperationStr) {
    final ParsedOperation operation = parsedOperationFromJsonString(
      parsedOperationStr,
    );
    return RestApiTool.fromParsedOperation(operation);
  }

  @override
  FunctionDeclaration? getDeclaration() {
    final Map<String, Object?> schema = _operationParser.getJsonSchema();
    if (isFeatureEnabled(FeatureName.jsonSchemaForFuncDecl)) {
      return FunctionDeclaration(
        name: name,
        description: description,
        parameters: schema,
      );
    }
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: schema,
    );
  }

  void configureAuthScheme(Object? authScheme) {
    if (authScheme is Map<String, Object?>) {
      this.authScheme = dictToAuthScheme(authScheme);
      return;
    }
    if (authScheme is Map) {
      this.authScheme = dictToAuthScheme(
        authScheme.map((Object? key, Object? value) => MapEntry('$key', value)),
      );
      return;
    }
    this.authScheme = authScheme;
  }

  void configureAuthCredential(Object? authCredential) {
    if (authCredential is AuthCredential) {
      this.authCredential = authCredential.copyWith();
      return;
    }
    if (authCredential is String && authCredential.isNotEmpty) {
      this.authCredential = _credentialFromJsonString(authCredential);
      return;
    }
    if (authCredential is Map) {
      this.authCredential = _credentialFromMap(
        authCredential.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        ),
      );
      return;
    }
    this.authCredential = null;
  }

  void configureCredentialKey(String? credentialKey) {
    _credentialKey = credentialKey;
  }

  void configureSslVerify([Object? sslVerify]) {
    _sslVerify = sslVerify;
  }

  void setDefaultHeaders(Map<String, String> headers) {
    _defaultHeaders
      ..clear()
      ..addAll(headers);
  }

  AuthParameterBinding _prepareAuthRequestParams(
    Object authScheme,
    AuthCredential authCredential,
  ) {
    return credentialToParam(authScheme, authCredential);
  }

  Map<String, Object?> prepareRequestParams(
    List<ApiParameter> parameters,
    Map<String, Object?> kwargs,
  ) {
    return _prepareRequestParams(parameters, kwargs);
  }

  Map<String, Object?> _prepareRequestParams(
    List<ApiParameter> parameters,
    Map<String, Object?> kwargs,
  ) {
    final String method = endpoint.method.toLowerCase();
    if (method.isEmpty) {
      throw ArgumentError('Operation method not found.');
    }

    final Map<String, Object?> pathParams = <String, Object?>{};
    final Map<String, Object?> queryParams = <String, Object?>{};
    final Map<String, Object?> headerParams = <String, Object?>{};
    final Map<String, Object?> cookieParams = <String, Object?>{};

    headerParams['User-Agent'] = 'google-adk/$adkVersion (tool: $name)';

    final Map<String, String> additionalHeaders =
        authCredential?.http?.additionalHeaders ?? <String, String>{};
    headerParams.addAll(additionalHeaders);

    final Map<String, ApiParameter> paramsMap = <String, ApiParameter>{
      for (final ApiParameter parameter in parameters)
        parameter.pyName: parameter,
    };

    for (final MapEntry<String, Object?> entry in kwargs.entries) {
      final ApiParameter? parameter = paramsMap[entry.key];
      if (parameter == null) {
        continue;
      }

      final String originalName = parameter.originalName;
      switch (parameter.paramLocation) {
        case 'path':
          pathParams[originalName] = entry.value;
          break;
        case 'query':
          if (_isTruthy(entry.value)) {
            queryParams[originalName] = entry.value;
          }
          break;
        case 'header':
          headerParams[originalName] = entry.value;
          break;
        case 'cookie':
          cookieParams[originalName] = entry.value;
          break;
      }
    }

    final String normalizedBaseUrl = endpoint.baseUrl.endsWith('/')
        ? endpoint.baseUrl.substring(0, endpoint.baseUrl.length - 1)
        : endpoint.baseUrl;
    final String url =
        '$normalizedBaseUrl${_formatPath(endpoint.path, pathParams)}';

    final Map<String, Object?> bodyKwargs = <String, Object?>{};
    final Map<String, Object?> requestBody = _readMap(operation['requestBody']);
    final Map<String, Object?> content = _readMap(requestBody['content']);
    if (content.isNotEmpty) {
      final String mimeType = content.keys.first;
      final Map<String, Object?> mediaTypeObject = _readMap(content[mimeType]);
      final Map<String, Object?> schema = _readMap(mediaTypeObject['schema']);

      Object? bodyData;
      final String schemaType = (_readString(schema['type']) ?? '')
          .toLowerCase();
      if (schemaType == 'object') {
        final Map<String, Object?> objectBody = <String, Object?>{};
        for (final ApiParameter parameter in parameters) {
          if (parameter.paramLocation == 'body' &&
              kwargs.containsKey(parameter.pyName)) {
            objectBody[parameter.originalName] = kwargs[parameter.pyName];
          }
        }
        bodyData = objectBody;
      } else if (schemaType == 'array') {
        for (final ApiParameter parameter in parameters) {
          if (parameter.paramLocation == 'body' &&
              parameter.pyName == 'array') {
            bodyData = kwargs['array'];
            break;
          }
        }
      } else {
        for (final ApiParameter parameter in parameters) {
          if (parameter.paramLocation == 'body' &&
              parameter.originalName.isEmpty) {
            bodyData = kwargs.containsKey(parameter.pyName)
                ? kwargs[parameter.pyName]
                : null;
            break;
          }
        }
      }

      if ((mimeType == 'application/json' || mimeType.endsWith('+json')) &&
          bodyData != null) {
        bodyKwargs['json'] = bodyData;
      } else if (mimeType == 'application/x-www-form-urlencoded') {
        bodyKwargs['data'] = bodyData;
      } else if (mimeType == 'multipart/form-data') {
        bodyKwargs['files'] = bodyData;
      } else if (mimeType == 'application/octet-stream') {
        bodyKwargs['data'] = bodyData;
      } else if (mimeType == 'text/plain') {
        bodyKwargs['data'] = bodyData;
      }

      if (mimeType.isNotEmpty) {
        headerParams['Content-Type'] = mimeType;
      }
    }

    final Map<String, Object?> filteredQueryParams = <String, Object?>{
      for (final MapEntry<String, Object?> entry in queryParams.entries)
        if (entry.value != null) entry.key: entry.value,
    };

    for (final MapEntry<String, String> entry in _defaultHeaders.entries) {
      headerParams.putIfAbsent(entry.key, () => entry.value);
    }

    return <String, Object?>{
      'method': method,
      'url': url,
      'params': filteredQueryParams,
      'headers': headerParams,
      'cookies': cookieParams,
      ...bodyKwargs,
    };
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) {
    return call(args: args, toolContext: toolContext);
  }

  Future<Map<String, Object?>> call({
    required Map<String, dynamic> args,
    ToolContext? toolContext,
  }) async {
    final ToolAuthHandler authHandler = ToolAuthHandler.fromToolContext(
      toolContext,
      authScheme,
      authCredential,
      credentialExchanger: credentialExchanger,
      credentialKey: _credentialKey,
    );

    final AuthPreparationResult authResult = await authHandler
        .prepareAuthCredentials();
    final String authState = authResult.state;
    final Object? effectiveAuthScheme = authResult.authScheme;
    final AuthCredential? effectiveAuthCredential = authResult.authCredential;

    if (authState == 'pending') {
      return <String, Object?>{
        'pending': true,
        'message': 'Needs your authorization to access your data.',
      };
    }

    List<ApiParameter> apiParams = _operationParser.getParameters();
    final Map<String, Object?> apiArgs = <String, Object?>{
      for (final MapEntry<String, dynamic> entry in args.entries)
        entry.key: entry.value,
    };

    for (final ApiParameter parameter in apiParams) {
      if (apiArgs.containsKey(parameter.pyName)) {
        continue;
      }
      final Object? defaultValue = parameter.paramSchema['default'];
      if (parameter.required && defaultValue != null) {
        apiArgs[parameter.pyName] = defaultValue;
      }
    }

    if (effectiveAuthScheme != null && effectiveAuthCredential != null) {
      final AuthParameterBinding authBinding = _prepareAuthRequestParams(
        effectiveAuthScheme,
        effectiveAuthCredential,
      );
      if (authBinding.parameter != null && authBinding.args != null) {
        apiParams = <ApiParameter>[authBinding.parameter!, ...apiParams];
        apiArgs.addAll(authBinding.args!);
      }
    }

    final Map<String, Object?> requestParams = _prepareRequestParams(
      apiParams,
      apiArgs,
    );
    if (_sslVerify != null) {
      requestParams['verify'] = _sslVerify;
    }

    if (_headerProvider != null && toolContext != null) {
      final Map<String, String> providerHeaders = _headerProvider!(toolContext);
      if (providerHeaders.isNotEmpty) {
        final Map<String, Object?> headers = _readMap(requestParams['headers']);
        headers.addAll(providerHeaders);
        requestParams['headers'] = headers;
      }
    }

    RestApiResponse response;
    try {
      response = await _requestExecutor(requestParams: requestParams);
    } catch (error) {
      return <String, Object?>{
        'error':
            'Tool $name execution failed. Analyze this execution error and your inputs. '
            'Retry with adjustments if applicable. But make sure don\'t retry more than 3 times. '
            'Execution Error: $error',
      };
    }

    if (response.isSuccess) {
      final Object? jsonData = response.jsonData;
      if (jsonData is Map<String, Object?>) {
        return jsonData;
      }
      if (jsonData is List) {
        return <String, Object?>{'data': jsonData};
      }

      if (response.text.isNotEmpty) {
        try {
          final Object? decoded = jsonDecode(response.text);
          if (decoded is Map) {
            return decoded.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
          }
          return <String, Object?>{'data': decoded};
        } catch (_) {
          return <String, Object?>{'text': response.text};
        }
      }
      return <String, Object?>{};
    }

    final String errorDetails = response.text;
    return <String, Object?>{
      'error':
          'Tool $name execution failed. Analyze this execution error and your inputs. '
          'Retry with adjustments if applicable. But make sure don\'t retry more than 3 times. '
          'Execution Error: Status Code: ${response.statusCode}, $errorDetails',
    };
  }

  @override
  String toString() {
    return 'RestApiTool(name="$name", description="$description", endpoint="$endpoint")';
  }

  String toDetailedString() {
    return 'RestApiTool(name="$name", description="$description", endpoint="$endpoint", '
        'operation="$operation", authScheme="$authScheme", authCredential="$authCredential")';
  }
}

Future<RestApiResponse> _request({
  required Map<String, Object?> requestParams,
}) async {
  final String method = (_readString(requestParams['method']) ?? '')
      .toUpperCase();
  final String rawUrl = _readString(requestParams['url']) ?? '';
  final Map<String, Object?> params = _readMap(requestParams['params']);
  final Map<String, Object?> headers = _readMap(requestParams['headers']);
  final Map<String, Object?> cookies = _readMap(requestParams['cookies']);

  Uri uri = Uri.parse(rawUrl);
  if (params.isNotEmpty) {
    final Map<String, String> query = <String, String>{
      for (final MapEntry<String, Object?> entry in params.entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    uri = uri.replace(queryParameters: query.isEmpty ? null : query);
  }

  final Object? verify = requestParams['verify'];
  final HttpClient client = _buildHttpClient(verify);
  try {
    final HttpClientRequest request = await client.openUrl(method, uri);

    for (final MapEntry<String, Object?> entry in headers.entries) {
      if (entry.value == null) {
        continue;
      }
      request.headers.set(entry.key, '${entry.value}');
    }

    if (cookies.isNotEmpty) {
      final String cookieHeader = cookies.entries
          .where((MapEntry<String, Object?> entry) => entry.value != null)
          .map(
            (MapEntry<String, Object?> entry) => '${entry.key}=${entry.value}',
          )
          .join('; ');
      if (cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
    }

    if (requestParams.containsKey('json')) {
      if (request.headers.contentType == null) {
        request.headers.contentType = ContentType.json;
      }
      request.write(jsonEncode(requestParams['json']));
    } else if (requestParams.containsKey('data')) {
      final Object? data = requestParams['data'];
      if (data is Map) {
        request.write(
          data.entries
              .map(
                (MapEntry<Object?, Object?> entry) =>
                    '${Uri.encodeQueryComponent('${entry.key}')}=${Uri.encodeQueryComponent('${entry.value ?? ''}')}',
              )
              .join('&'),
        );
      } else if (data is List<int>) {
        request.add(data);
      } else if (data != null) {
        request.write('$data');
      }
    } else if (requestParams.containsKey('files')) {
      final Object? files = requestParams['files'];
      if (files is Map<String, Object?>) {
        request.write(jsonEncode(files));
      } else if (files is List<int>) {
        request.add(files);
      }
    }

    final HttpClientResponse response = await request.close();
    final List<int> bytes = await response.fold<List<int>>(<int>[], (
      List<int> previous,
      List<int> element,
    ) {
      previous.addAll(element);
      return previous;
    });

    final String text = utf8.decode(bytes, allowMalformed: true);
    Object? parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
    }

    final Map<String, List<String>> responseHeaders = <String, List<String>>{};
    response.headers.forEach((String name, List<String> values) {
      responseHeaders[name] = List<String>.from(values);
    });

    return RestApiResponse(
      statusCode: response.statusCode,
      text: text,
      jsonData: parsed,
      headers: responseHeaders,
    );
  } finally {
    client.close(force: true);
  }
}

HttpClient _buildHttpClient(Object? verify) {
  if (verify is SecurityContext) {
    return HttpClient(context: verify);
  }

  if (verify is String && verify.isNotEmpty) {
    try {
      final SecurityContext context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificates(verify);
      return HttpClient(context: context);
    } catch (_) {
      return HttpClient();
    }
  }

  final HttpClient client = HttpClient();
  if (verify == false) {
    client.badCertificateCallback = (X509Certificate _, String __, int ___) =>
        true;
  }
  return client;
}

String _formatPath(String path, Map<String, Object?> pathParams) {
  return path.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (Match match) {
    final String key = match.group(1) ?? '';
    if (!pathParams.containsKey(key)) {
      return match.group(0) ?? '';
    }
    return '${pathParams[key] ?? ''}';
  });
}

bool _isTruthy(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.isNotEmpty;
  }
  if (value is List || value is Set) {
    return (value as Iterable).isNotEmpty;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  return true;
}

AuthCredential _credentialFromJsonString(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw ArgumentError('Invalid auth credential json: $source');
  }
  return _credentialFromMap(
    decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
  );
}

AuthCredential _credentialFromMap(Map<String, Object?> data) {
  final String authTypeString =
      _readString(data['authType']) ?? _readString(data['auth_type']) ?? '';
  final AuthCredentialType authType =
      _authCredentialTypeFromString(authTypeString) ?? AuthCredentialType.http;

  return AuthCredential(
    authType: authType,
    resourceRef:
        _readString(data['resourceRef']) ?? _readString(data['resource_ref']),
    apiKey: _readString(data['apiKey']) ?? _readString(data['api_key']),
    http: _parseHttpAuth(data['http']),
    oauth2: _parseOAuth2(data['oauth2']),
    serviceAccount: _parseServiceAccount(
      data['serviceAccount'] ?? data['service_account'],
    ),
  );
}

AuthCredentialType? _authCredentialTypeFromString(String? value) {
  final String normalized = (value ?? '').toLowerCase();
  switch (normalized) {
    case 'apikey':
    case 'api_key':
      return AuthCredentialType.apiKey;
    case 'http':
      return AuthCredentialType.http;
    case 'oauth2':
      return AuthCredentialType.oauth2;
    case 'openidconnect':
    case 'open_id_connect':
    case 'openid_connect':
      return AuthCredentialType.openIdConnect;
    case 'serviceaccount':
    case 'service_account':
      return AuthCredentialType.serviceAccount;
  }
  return null;
}

HttpAuth? _parseHttpAuth(Object? value) {
  if (value is HttpAuth) {
    return value;
  }
  final Map<String, Object?> map = _readMap(value);
  if (map.isEmpty) {
    return null;
  }

  final Map<String, Object?> credentials = _readMap(map['credentials']);
  final Map<String, String> additionalHeaders = <String, String>{};
  final Map<String, Object?> headers = _readMap(
    map['additionalHeaders'] ?? map['additional_headers'],
  );
  for (final MapEntry<String, Object?> entry in headers.entries) {
    additionalHeaders[entry.key] = '${entry.value ?? ''}';
  }

  return HttpAuth(
    scheme: _readString(map['scheme']) ?? 'bearer',
    credentials: HttpCredentials(
      username: _readString(credentials['username']),
      password: _readString(credentials['password']),
      token: _readString(credentials['token']),
    ),
    additionalHeaders: additionalHeaders,
  );
}

OAuth2Auth? _parseOAuth2(Object? value) {
  if (value is OAuth2Auth) {
    return value;
  }
  final Map<String, Object?> map = _readMap(value);
  if (map.isEmpty) {
    return null;
  }

  return OAuth2Auth(
    clientId: _readString(map['clientId']) ?? _readString(map['client_id']),
    clientSecret:
        _readString(map['clientSecret']) ?? _readString(map['client_secret']),
    authUri: _readString(map['authUri']) ?? _readString(map['auth_uri']),
    state: _readString(map['state']),
    redirectUri:
        _readString(map['redirectUri']) ?? _readString(map['redirect_uri']),
    authResponseUri:
        _readString(map['authResponseUri']) ??
        _readString(map['auth_response_uri']),
    authCode: _readString(map['authCode']) ?? _readString(map['auth_code']),
    accessToken:
        _readString(map['accessToken']) ?? _readString(map['access_token']),
    refreshToken:
        _readString(map['refreshToken']) ?? _readString(map['refresh_token']),
    expiresAt: _readInt(map['expiresAt']) ?? _readInt(map['expires_at']),
    expiresIn: _readInt(map['expiresIn']) ?? _readInt(map['expires_in']),
    audience: _readString(map['audience']),
    tokenEndpointAuthMethod:
        _readString(map['tokenEndpointAuthMethod']) ??
        _readString(map['token_endpoint_auth_method']) ??
        'client_secret_basic',
  );
}

ServiceAccountAuth? _parseServiceAccount(Object? value) {
  if (value is ServiceAccountAuth) {
    return value;
  }
  final Map<String, Object?> map = _readMap(value);
  if (map.isEmpty) {
    return null;
  }

  final Map<String, Object?> credentialMap = _readMap(
    map['serviceAccountCredential'] ?? map['service_account_credential'],
  );
  ServiceAccountCredential? credential;
  if (credentialMap.isNotEmpty) {
    credential = ServiceAccountCredential(
      projectId:
          _readString(credentialMap['projectId']) ??
          _readString(credentialMap['project_id']) ??
          '',
      privateKeyId:
          _readString(credentialMap['privateKeyId']) ??
          _readString(credentialMap['private_key_id']) ??
          '',
      privateKey:
          _readString(credentialMap['privateKey']) ??
          _readString(credentialMap['private_key']) ??
          '',
      clientEmail:
          _readString(credentialMap['clientEmail']) ??
          _readString(credentialMap['client_email']) ??
          '',
      clientId:
          _readString(credentialMap['clientId']) ??
          _readString(credentialMap['client_id']) ??
          '',
      authUri:
          _readString(credentialMap['authUri']) ??
          _readString(credentialMap['auth_uri']) ??
          '',
      tokenUri:
          _readString(credentialMap['tokenUri']) ??
          _readString(credentialMap['token_uri']) ??
          '',
    );
  }

  final List<String> scopes = _readList(
    map['scopes'],
  ).map((Object? value) => '$value').toList(growable: false);
  return ServiceAccountAuth(
    serviceAccountCredential: credential,
    scopes: scopes,
    useDefaultCredential: _readBool(
      map['useDefaultCredential'] ?? map['use_default_credential'],
    ),
  );
}

Map<String, Object?> _readMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> _readList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return <Object?>[];
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
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

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String normalized = value.toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}
