import 'dart:convert';
import 'dart:io';

import '../../../auth/auth_credential.dart';
import '../../../auth/auth_schemes.dart';
import '../common/common.dart';

const String internalAuthPrefix = '_auth_prefix_vaf_';

typedef OpenIdConfigFetcher = Future<Map<String, Object?>> Function(String url);

class AuthParameterBinding {
  AuthParameterBinding({this.parameter, this.args});

  final ApiParameter? parameter;
  final Map<String, Object?>? args;
}

class OpenIdConfig {
  OpenIdConfig({
    required this.clientId,
    required this.authUri,
    required this.tokenUri,
    required this.clientSecret,
    this.redirectUri,
  });

  final String clientId;
  final String authUri;
  final String tokenUri;
  final String clientSecret;
  final String? redirectUri;
}

({SecurityScheme authScheme, AuthCredential? authCredential})
tokenToSchemeCredential(
  String tokenType, {
  String? location,
  String? name,
  String? credentialValue,
}) {
  final String normalized = tokenType.toLowerCase();
  if (normalized == 'apikey') {
    final String inLocation = location ?? 'header';
    if (inLocation != 'header' &&
        inLocation != 'query' &&
        inLocation != 'cookie') {
      throw ArgumentError('Invalid location for apiKey: $location');
    }
    final SecurityScheme scheme = SecurityScheme(
      type: AuthSchemeType.apiKey,
      inLocation: inLocation,
      name: name,
    );
    final AuthCredential? credential = credentialValue == null
        ? null
        : AuthCredential(
            authType: AuthCredentialType.apiKey,
            apiKey: credentialValue,
          );
    return (authScheme: scheme, authCredential: credential);
  }

  if (normalized == 'oauth2token') {
    final SecurityScheme scheme = SecurityScheme(
      type: AuthSchemeType.http,
      scheme: 'bearer',
      bearerFormat: 'JWT',
    );
    final AuthCredential? credential = credentialValue == null
        ? null
        : AuthCredential(
            authType: AuthCredentialType.http,
            http: HttpAuth(
              scheme: 'bearer',
              credentials: HttpCredentials(token: credentialValue),
            ),
          );
    return (authScheme: scheme, authCredential: credential);
  }

  throw ArgumentError('Invalid security scheme type: $tokenType');
}

({SecurityScheme authScheme, AuthCredential authCredential})
serviceAccountDictToSchemeCredential(
  Map<String, Object?> config,
  List<String> scopes,
) {
  final ServiceAccountCredential credential = ServiceAccountCredential(
    projectId: _readString(config['project_id']) ?? '',
    privateKeyId: _readString(config['private_key_id']) ?? '',
    privateKey: _readString(config['private_key']) ?? '',
    clientEmail: _readString(config['client_email']) ?? '',
    clientId: _readString(config['client_id']) ?? '',
    authUri: _readString(config['auth_uri']) ?? '',
    tokenUri: _readString(config['token_uri']) ?? '',
  );
  return serviceAccountSchemeCredential(
    ServiceAccountAuth(
      serviceAccountCredential: credential,
      scopes: List<String>.from(scopes),
    ),
  );
}

({SecurityScheme authScheme, AuthCredential authCredential})
serviceAccountSchemeCredential(ServiceAccountAuth config) {
  return (
    authScheme: SecurityScheme(
      type: AuthSchemeType.http,
      scheme: 'bearer',
      bearerFormat: 'JWT',
    ),
    authCredential: AuthCredential(
      authType: AuthCredentialType.serviceAccount,
      serviceAccount: config,
    ),
  );
}

({OpenIdConnectWithConfig authScheme, AuthCredential authCredential})
openidDictToSchemeCredential(
  Map<String, Object?> config,
  List<String> scopes,
  Map<String, Object?> credential,
) {
  final String authorizationEndpoint =
      _readString(
        config['authorization_endpoint'] ?? config['authorizationEndpoint'],
      ) ??
      '';
  final String tokenEndpoint =
      _readString(config['token_endpoint'] ?? config['tokenEndpoint']) ?? '';
  if (authorizationEndpoint.isEmpty || tokenEndpoint.isEmpty) {
    throw ArgumentError(
      'Invalid OpenID Connect configuration: authorization/token endpoint is missing.',
    );
  }

  final OpenIdConnectWithConfig scheme = OpenIdConnectWithConfig(
    authorizationEndpoint: authorizationEndpoint,
    tokenEndpoint: tokenEndpoint,
    userinfoEndpoint: _readString(
      config['userinfo_endpoint'] ?? config['userinfoEndpoint'],
    ),
    revocationEndpoint: _readString(
      config['revocation_endpoint'] ?? config['revocationEndpoint'],
    ),
    scopes: List<String>.from(scopes),
    description: _readString(config['description']),
  );

  Map<String, Object?> normalizedCredential = credential;
  if (credential.length == 1) {
    final Object? first = credential.values.first;
    if (first is Map) {
      final Map<String, Object?> nested = first.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      if (nested.containsKey('client_id') &&
          nested.containsKey('client_secret')) {
        normalizedCredential = nested;
      }
    }
  }

  final String? clientId = _readString(
    normalizedCredential['client_id'] ?? normalizedCredential['clientId'],
  );
  final String? clientSecret = _readString(
    normalizedCredential['client_secret'] ??
        normalizedCredential['clientSecret'],
  );
  if (clientId == null || clientId.isEmpty) {
    throw ArgumentError(
      'Missing required fields in credential_dict: client_id',
    );
  }
  if (clientSecret == null || clientSecret.isEmpty) {
    throw ArgumentError(
      'Missing required fields in credential_dict: client_secret',
    );
  }

  return (
    authScheme: scheme,
    authCredential: AuthCredential(
      authType: AuthCredentialType.openIdConnect,
      oauth2: OAuth2Auth(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: _readString(
          normalizedCredential['redirect_uri'] ??
              normalizedCredential['redirectUri'],
        ),
      ),
    ),
  );
}

Future<({OpenIdConnectWithConfig authScheme, AuthCredential authCredential})>
openidUrlToSchemeCredential(
  String openidUrl,
  List<String> scopes,
  Map<String, Object?> credential, {
  OpenIdConfigFetcher? configFetcher,
}) async {
  final OpenIdConfigFetcher fetcher = configFetcher ?? _defaultOpenIdFetcher;
  final Map<String, Object?> config = await fetcher(openidUrl);
  config['openIdConnectUrl'] = openidUrl;
  return openidDictToSchemeCredential(config, scopes, credential);
}

AuthParameterBinding credentialToParam(
  Object authScheme,
  AuthCredential? authCredential,
) {
  final AuthCredential? credential = authCredential;
  if (credential == null) {
    return AuthParameterBinding();
  }

  final AuthSchemeType? schemeType = _schemeType(authScheme);
  if (schemeType == AuthSchemeType.apiKey && credential.apiKey != null) {
    final String name = _schemeName(authScheme) ?? '';
    final String inLocation = _schemeInLocation(authScheme) ?? 'header';
    return AuthParameterBinding(
      parameter: ApiParameter(
        originalName: name,
        paramLocation: inLocation,
        paramSchema: <String, Object?>{'type': 'string'},
        description: _schemeDescription(authScheme) ?? '',
        pyName: '$internalAuthPrefix$name',
      ),
      args: <String, Object?>{'$internalAuthPrefix$name': credential.apiKey},
    );
  }

  if (credential.authType == AuthCredentialType.http) {
    final String? token = credential.http?.credentials.token;
    if (token == null || token.isEmpty) {
      throw ArgumentError('Invalid HTTP auth credentials');
    }
    return AuthParameterBinding(
      parameter: ApiParameter(
        originalName: 'Authorization',
        paramLocation: 'header',
        paramSchema: <String, Object?>{'type': 'string'},
        description: _schemeDescription(authScheme) ?? 'Bearer token',
        pyName: '${internalAuthPrefix}Authorization',
      ),
      args: <String, Object?>{
        '${internalAuthPrefix}Authorization': 'Bearer $token',
      },
    );
  }

  if (schemeType == AuthSchemeType.oauth2 ||
      schemeType == AuthSchemeType.openIdConnect) {
    final String? token = credential.http?.credentials.token;
    if (token == null || token.isEmpty) {
      return AuthParameterBinding();
    }
    return AuthParameterBinding(
      parameter: ApiParameter(
        originalName: 'Authorization',
        paramLocation: 'header',
        paramSchema: <String, Object?>{'type': 'string'},
        description: _schemeDescription(authScheme) ?? 'Bearer token',
        pyName: '${internalAuthPrefix}Authorization',
      ),
      args: <String, Object?>{
        '${internalAuthPrefix}Authorization': 'Bearer $token',
      },
    );
  }

  throw ArgumentError('Invalid security scheme and credential combination');
}

Object dictToAuthScheme(Map<String, Object?> data) {
  final String type = _readString(data['type'])?.toLowerCase() ?? '';
  if (type.isEmpty) {
    throw ArgumentError("Missing 'type' field in security scheme dictionary.");
  }

  switch (type) {
    case 'apikey':
    case 'api_key':
      return SecurityScheme(
        type: AuthSchemeType.apiKey,
        description: _readString(data['description']),
        name: _readString(data['name']),
        inLocation: _readString(data['in']),
      );
    case 'http':
      return SecurityScheme(
        type: AuthSchemeType.http,
        description: _readString(data['description']),
        scheme: _readString(data['scheme']),
        bearerFormat: _readString(
          data['bearerFormat'] ?? data['bearer_format'],
        ),
      );
    case 'oauth2':
      return ExtendedOAuth2(
        description: _readString(data['description']),
        issuerUrl: _readString(data['issuerUrl'] ?? data['issuer_url']),
        flows: _parseFlows(_readMap(data['flows'])),
      );
    case 'openidconnect':
    case 'open_id_connect':
      return OpenIdConnectWithConfig(
        authorizationEndpoint:
            _readString(data['authorization_endpoint']) ?? '',
        tokenEndpoint: _readString(data['token_endpoint']) ?? '',
        userinfoEndpoint: _readString(data['userinfo_endpoint']),
        revocationEndpoint: _readString(data['revocation_endpoint']),
        description: _readString(data['description']),
      );
    default:
      throw ArgumentError('Invalid security scheme type: $type');
  }
}

Future<Map<String, Object?>> _defaultOpenIdFetcher(String url) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    if (response.statusCode >= 400) {
      throw HttpException(
        'Failed to fetch OpenID configuration from $url: ${response.statusCode}',
      );
    }
    final Object? decoded = jsonDecode(body);
    return _readMap(decoded);
  } finally {
    client.close(force: true);
  }
}

OAuthFlows _parseFlows(Map<String, Object?> flows) {
  OAuthFlow? toFlow(Object? value) {
    final Map<String, Object?> map = _readMap(value);
    if (map.isEmpty) {
      return null;
    }
    final Object? rawScopes = map['scopes'];
    final Map<String, String> scopes;
    if (rawScopes is Map) {
      scopes = rawScopes.map(
        (Object? key, Object? item) => MapEntry('$key', '$item'),
      );
    } else {
      scopes = <String, String>{};
    }
    return OAuthFlow(
      authorizationUrl: _readString(
        map['authorizationUrl'] ?? map['authorization_url'],
      ),
      tokenUrl: _readString(map['tokenUrl'] ?? map['token_url']),
      scopes: scopes,
    );
  }

  return OAuthFlows(
    clientCredentials: toFlow(
      flows['clientCredentials'] ?? flows['client_credentials'],
    ),
    authorizationCode: toFlow(
      flows['authorizationCode'] ?? flows['authorization_code'],
    ),
    implicit: toFlow(flows['implicit']),
    password: toFlow(flows['password']),
  );
}

AuthSchemeType? _schemeType(Object scheme) {
  if (scheme is SecurityScheme) {
    return scheme.type;
  }
  if (scheme is Map) {
    final String value = _readString(scheme['type'])?.toLowerCase() ?? '';
    switch (value) {
      case 'apikey':
      case 'api_key':
        return AuthSchemeType.apiKey;
      case 'http':
        return AuthSchemeType.http;
      case 'oauth2':
        return AuthSchemeType.oauth2;
      case 'openidconnect':
      case 'open_id_connect':
      case 'open_id_connect_with_config':
        return AuthSchemeType.openIdConnect;
    }
  }
  return null;
}

String? _schemeName(Object scheme) {
  if (scheme is SecurityScheme) {
    return scheme.name;
  }
  if (scheme is Map) {
    return _readString(scheme['name']);
  }
  return null;
}

String? _schemeInLocation(Object scheme) {
  if (scheme is SecurityScheme) {
    return scheme.inLocation;
  }
  if (scheme is Map) {
    return _readString(scheme['in']);
  }
  return null;
}

String? _schemeDescription(Object scheme) {
  if (scheme is SecurityScheme) {
    return scheme.description;
  }
  if (scheme is Map) {
    return _readString(scheme['description']);
  }
  return null;
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

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
}
