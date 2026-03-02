/// Auth scheme models used by tools and OpenAPI integration.
library;

/// Supported high-level auth scheme types.
enum AuthSchemeType { apiKey, http, oauth2, openIdConnect }

/// Base security-scheme descriptor.
class SecurityScheme {
  /// Creates a security scheme descriptor.
  SecurityScheme({
    required this.type,
    this.description,
    this.name,
    this.inLocation,
    this.scheme,
    this.bearerFormat,
    this.openIdConnectUrl,
  });

  /// Scheme type discriminator.
  final AuthSchemeType type;

  /// Optional description text.
  final String? description;

  /// Name of header/query/cookie key for API key schemes.
  final String? name;

  /// Location of API key (`header`, `query`, `cookie`).
  final String? inLocation;

  /// HTTP scheme name.
  final String? scheme;

  /// Optional bearer token format.
  final String? bearerFormat;

  /// OpenID Connect discovery URL.
  final String? openIdConnectUrl;

  /// Serializes this scheme to JSON.
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

/// One OAuth flow configuration.
class OAuthFlow {
  /// Creates an OAuth flow descriptor.
  OAuthFlow({this.authorizationUrl, this.tokenUrl, Map<String, String>? scopes})
    : scopes = scopes ?? const <String, String>{};

  /// Authorization URL for the flow.
  final String? authorizationUrl;

  /// Token URL for the flow.
  final String? tokenUrl;

  /// Scope dictionary supported by the flow.
  final Map<String, String> scopes;

  /// Serializes this flow to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (authorizationUrl != null) 'authorization_url': authorizationUrl,
      if (tokenUrl != null) 'token_url': tokenUrl,
      if (scopes.isNotEmpty) 'scopes': scopes,
    };
  }
}

/// OAuth flow bundle.
class OAuthFlows {
  /// Creates an OAuth flows bundle.
  OAuthFlows({
    this.clientCredentials,
    this.authorizationCode,
    this.implicit,
    this.password,
  });

  /// Client credentials flow.
  final OAuthFlow? clientCredentials;

  /// Authorization code flow.
  final OAuthFlow? authorizationCode;

  /// Implicit flow.
  final OAuthFlow? implicit;

  /// Password flow.
  final OAuthFlow? password;
}

/// Supported OAuth grant types.
enum OAuthGrantType { clientCredentials, authorizationCode, implicit, password }

/// Returns the first configured grant type in [flow], if any.
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

/// OpenID Connect security scheme with resolved endpoint configuration.
class OpenIdConnectWithConfig extends SecurityScheme {
  /// Creates an OpenID Connect scheme with explicit endpoint fields.
  OpenIdConnectWithConfig({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.userinfoEndpoint,
    this.revocationEndpoint,
    List<String>? tokenEndpointAuthMethodsSupported,
    List<String>? grantTypesSupported,
    List<String>? scopes,
    super.description,
  }) : tokenEndpointAuthMethodsSupported =
           tokenEndpointAuthMethodsSupported ?? const <String>[],
       grantTypesSupported = grantTypesSupported ?? const <String>[],
       scopes = scopes ?? const <String>[],
       super(type: AuthSchemeType.openIdConnect);

  /// Authorization endpoint URL.
  final String authorizationEndpoint;

  /// Token endpoint URL.
  final String tokenEndpoint;

  /// Optional userinfo endpoint URL.
  final String? userinfoEndpoint;

  /// Optional revocation endpoint URL.
  final String? revocationEndpoint;

  /// Supported token endpoint auth methods.
  final List<String> tokenEndpointAuthMethodsSupported;

  /// Supported grant types.
  final List<String> grantTypesSupported;

  /// Supported scopes.
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

/// Alias used for generic auth scheme payloads.
typedef AuthScheme = Object;

/// OAuth2 scheme with flow configuration and optional issuer.
class ExtendedOAuth2 extends SecurityScheme {
  /// Creates an extended OAuth2 security scheme.
  ExtendedOAuth2({required this.flows, this.issuerUrl, super.description})
    : super(type: AuthSchemeType.oauth2);

  /// Configured OAuth flows.
  final OAuthFlows flows;

  /// Optional issuer URL.
  final String? issuerUrl;

  /// Serializes this scheme to JSON.
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
