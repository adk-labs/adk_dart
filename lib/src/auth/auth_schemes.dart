enum AuthSchemeType { apiKey, http, oauth2, openIdConnect }

class SecurityScheme {
  SecurityScheme({
    required this.type,
    this.description,
    this.name,
    this.inLocation,
    this.scheme,
    this.bearerFormat,
    this.openIdConnectUrl,
  });

  final AuthSchemeType type;
  final String? description;
  final String? name;
  final String? inLocation;
  final String? scheme;
  final String? bearerFormat;
  final String? openIdConnectUrl;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      if (description != null) 'description': description,
      if (name != null) 'name': name,
      if (inLocation != null) 'in': inLocation,
      if (scheme != null) 'scheme': scheme,
      if (bearerFormat != null) 'bearer_format': bearerFormat,
      if (openIdConnectUrl != null) 'open_id_connect_url': openIdConnectUrl,
    };
  }
}

class OAuthFlow {
  OAuthFlow({this.authorizationUrl, this.tokenUrl, Map<String, String>? scopes})
    : scopes = scopes ?? const <String, String>{};

  final String? authorizationUrl;
  final String? tokenUrl;
  final Map<String, String> scopes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (authorizationUrl != null) 'authorization_url': authorizationUrl,
      if (tokenUrl != null) 'token_url': tokenUrl,
      if (scopes.isNotEmpty) 'scopes': scopes,
    };
  }
}

class OAuthFlows {
  OAuthFlows({
    this.clientCredentials,
    this.authorizationCode,
    this.implicit,
    this.password,
  });

  final OAuthFlow? clientCredentials;
  final OAuthFlow? authorizationCode;
  final OAuthFlow? implicit;
  final OAuthFlow? password;
}

enum OAuthGrantType { clientCredentials, authorizationCode, implicit, password }

OAuthGrantType? oauthGrantTypeFromFlow(OAuthFlows flow) {
  if (flow.clientCredentials != null) {
    return OAuthGrantType.clientCredentials;
  }
  if (flow.authorizationCode != null) {
    return OAuthGrantType.authorizationCode;
  }
  if (flow.implicit != null) {
    return OAuthGrantType.implicit;
  }
  if (flow.password != null) {
    return OAuthGrantType.password;
  }
  return null;
}

class OpenIdConnectWithConfig extends SecurityScheme {
  OpenIdConnectWithConfig({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.userinfoEndpoint,
    this.revocationEndpoint,
    List<String>? tokenEndpointAuthMethodsSupported,
    List<String>? grantTypesSupported,
    List<String>? scopes,
    String? description,
  }) : tokenEndpointAuthMethodsSupported =
           tokenEndpointAuthMethodsSupported ?? const <String>[],
       grantTypesSupported = grantTypesSupported ?? const <String>[],
       scopes = scopes ?? const <String>[],
       super(type: AuthSchemeType.openIdConnect, description: description);

  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? userinfoEndpoint;
  final String? revocationEndpoint;
  final List<String> tokenEndpointAuthMethodsSupported;
  final List<String> grantTypesSupported;
  final List<String> scopes;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'authorization_endpoint': authorizationEndpoint,
      'token_endpoint': tokenEndpoint,
      if (userinfoEndpoint != null) 'userinfo_endpoint': userinfoEndpoint,
      if (revocationEndpoint != null) 'revocation_endpoint': revocationEndpoint,
      if (tokenEndpointAuthMethodsSupported.isNotEmpty)
        'token_endpoint_auth_methods_supported':
            tokenEndpointAuthMethodsSupported,
      if (grantTypesSupported.isNotEmpty)
        'grant_types_supported': grantTypesSupported,
      if (scopes.isNotEmpty) 'scopes': scopes,
    };
  }
}

typedef AuthScheme = Object;

class ExtendedOAuth2 extends SecurityScheme {
  ExtendedOAuth2({required this.flows, this.issuerUrl, String? description})
    : super(type: AuthSchemeType.oauth2, description: description);

  final OAuthFlows flows;
  final String? issuerUrl;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'flows': <String, Object?>{
        if (flows.clientCredentials != null)
          'client_credentials': flows.clientCredentials!.toJson(),
        if (flows.authorizationCode != null)
          'authorization_code': flows.authorizationCode!.toJson(),
        if (flows.implicit != null) 'implicit': flows.implicit!.toJson(),
        if (flows.password != null) 'password': flows.password!.toJson(),
      },
      if (issuerUrl != null) 'issuer_url': issuerUrl,
    };
  }
}
