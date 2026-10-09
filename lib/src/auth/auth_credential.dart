/// Authentication credential models used by auth tooling.
library;

/// Supported credential payload types.
enum AuthCredentialType {
  /// Static API key credential.
  apiKey,

  /// HTTP authentication credential (such as Basic or Bearer).
  http,

  /// OAuth 2.0 token and flow credential.
  oauth2,

  /// OpenID Connect token and flow credential.
  openIdConnect,

  /// Google Cloud service account credential.
  serviceAccount,
}

/// HTTP credential components.
class HttpCredentials {
  /// Creates HTTP credentials.
  HttpCredentials({this.username, this.password, this.token});

  /// Optional basic-auth username.
  String? username;

  /// Optional basic-auth password.
  String? password;

  /// Optional bearer/token value.
  String? token;

  /// Returns a deep copy of these HTTP credentials.
  HttpCredentials copyWith({
    Object? username = _sentinel,
    Object? password = _sentinel,
    Object? token = _sentinel,
  }) {
    return HttpCredentials(
      username: identical(username, _sentinel)
          ? this.username
          : username as String?,
      password: identical(password, _sentinel)
          ? this.password
          : password as String?,
      token: identical(token, _sentinel) ? this.token : token as String?,
    );
  }
}

/// HTTP authentication configuration.
class HttpAuth {
  /// Creates HTTP auth configuration.
  HttpAuth({
    required this.scheme,
    required this.credentials,
    Map<String, String>? additionalHeaders,
  }) : additionalHeaders = additionalHeaders ?? <String, String>{};

  /// HTTP auth scheme, such as `basic` or `bearer`.
  String scheme;

  /// HTTP credentials payload.
  HttpCredentials credentials;

  /// Additional headers to attach to requests.
  Map<String, String> additionalHeaders;

  /// Returns a deep copy of this HTTP auth configuration.
  HttpAuth copyWith({
    String? scheme,
    HttpCredentials? credentials,
    Map<String, String>? additionalHeaders,
  }) {
    return HttpAuth(
      scheme: scheme ?? this.scheme,
      credentials: credentials ?? this.credentials.copyWith(),
      additionalHeaders:
          additionalHeaders ?? Map<String, String>.from(this.additionalHeaders),
    );
  }
}

/// OAuth2 authentication payload.
class OAuth2Auth {
  /// Creates OAuth2 authentication data.
  OAuth2Auth({
    this.clientId,
    this.clientSecret,
    this.authUri,
    this.nonce,
    this.state,
    this.redirectUri,
    this.authResponseUri,
    this.authCode,
    this.accessToken,
    this.refreshToken,
    this.idToken,
    this.expiresAt,
    this.expiresIn,
    this.audience,
    this.prompt,
    this.codeVerifier,
    this.codeChallengeMethod,
    this.tokenEndpointAuthMethod = 'client_secret_basic',
  });

  /// OAuth2 client ID.
  String? clientId;

  /// OAuth2 client secret.
  String? clientSecret;

  /// Authorization URI.
  String? authUri;

  /// Nonce value used to bind an OAuth/OpenID Connect authorization request.
  String? nonce;

  /// OAuth state parameter.
  String? state;

  /// Redirect URI used by the client.
  String? redirectUri;

  /// Redirect response URI.
  String? authResponseUri;

  /// Authorization code.
  String? authCode;

  /// Access token.
  String? accessToken;

  /// Refresh token.
  String? refreshToken;

  /// OpenID ID token.
  String? idToken;

  /// Absolute token expiry time in epoch seconds.
  int? expiresAt;

  /// Relative token expiry in seconds.
  int? expiresIn;

  /// Audience for token exchange or ID token.
  String? audience;

  /// OAuth `prompt` parameter used when building the authorization URL.
  ///
  /// Defaults to `consent` when unset.
  String? prompt;

  /// PKCE code verifier retained for authorization-code token exchange.
  String? codeVerifier;

  /// PKCE code challenge method, for example `S256`.
  String? codeChallengeMethod;

  /// Token endpoint auth method.
  String tokenEndpointAuthMethod;

  /// Returns a deep copy of this OAuth2 auth payload.
  OAuth2Auth copyWith({
    Object? clientId = _sentinel,
    Object? clientSecret = _sentinel,
    Object? authUri = _sentinel,
    Object? nonce = _sentinel,
    Object? state = _sentinel,
    Object? redirectUri = _sentinel,
    Object? authResponseUri = _sentinel,
    Object? authCode = _sentinel,
    Object? accessToken = _sentinel,
    Object? refreshToken = _sentinel,
    Object? idToken = _sentinel,
    Object? expiresAt = _sentinel,
    Object? expiresIn = _sentinel,
    Object? audience = _sentinel,
    Object? prompt = _sentinel,
    Object? codeVerifier = _sentinel,
    Object? codeChallengeMethod = _sentinel,
    String? tokenEndpointAuthMethod,
  }) {
    return OAuth2Auth(
      clientId: identical(clientId, _sentinel)
          ? this.clientId
          : clientId as String?,
      clientSecret: identical(clientSecret, _sentinel)
          ? this.clientSecret
          : clientSecret as String?,
      authUri: identical(authUri, _sentinel)
          ? this.authUri
          : authUri as String?,
      nonce: identical(nonce, _sentinel) ? this.nonce : nonce as String?,
      state: identical(state, _sentinel) ? this.state : state as String?,
      redirectUri: identical(redirectUri, _sentinel)
          ? this.redirectUri
          : redirectUri as String?,
      authResponseUri: identical(authResponseUri, _sentinel)
          ? this.authResponseUri
          : authResponseUri as String?,
      authCode: identical(authCode, _sentinel)
          ? this.authCode
          : authCode as String?,
      accessToken: identical(accessToken, _sentinel)
          ? this.accessToken
          : accessToken as String?,
      refreshToken: identical(refreshToken, _sentinel)
          ? this.refreshToken
          : refreshToken as String?,
      idToken: identical(idToken, _sentinel)
          ? this.idToken
          : idToken as String?,
      expiresAt: identical(expiresAt, _sentinel)
          ? this.expiresAt
          : expiresAt as int?,
      expiresIn: identical(expiresIn, _sentinel)
          ? this.expiresIn
          : expiresIn as int?,
      audience: identical(audience, _sentinel)
          ? this.audience
          : audience as String?,
      prompt: identical(prompt, _sentinel) ? this.prompt : prompt as String?,
      codeVerifier: identical(codeVerifier, _sentinel)
          ? this.codeVerifier
          : codeVerifier as String?,
      codeChallengeMethod: identical(codeChallengeMethod, _sentinel)
          ? this.codeChallengeMethod
          : codeChallengeMethod as String?,
      tokenEndpointAuthMethod:
          tokenEndpointAuthMethod ?? this.tokenEndpointAuthMethod,
    );
  }
}

/// Google service account key fields.
class ServiceAccountCredential {
  /// Creates service-account credentials.
  ServiceAccountCredential({
    required this.projectId,
    required this.privateKeyId,
    required this.privateKey,
    required this.clientEmail,
    required this.clientId,
    required this.authUri,
    required this.tokenUri,
  });

  /// Project ID from the service account JSON.
  String projectId;

  /// Private key identifier.
  String privateKeyId;

  /// PEM private key.
  String privateKey;

  /// Service account email.
  String clientEmail;

  /// OAuth client ID.
  String clientId;

  /// Auth URI.
  String authUri;

  /// Token URI.
  String tokenUri;

  /// Returns a deep copy of this service-account credential.
  ServiceAccountCredential copyWith() {
    return ServiceAccountCredential(
      projectId: projectId,
      privateKeyId: privateKeyId,
      privateKey: privateKey,
      clientEmail: clientEmail,
      clientId: clientId,
      authUri: authUri,
      tokenUri: tokenUri,
    );
  }
}

/// Service-account auth configuration.
class ServiceAccountAuth {
  /// Creates service-account auth settings.
  ServiceAccountAuth({
    this.serviceAccountCredential,
    List<String>? scopes,
    this.useDefaultCredential = false,
    this.useIdToken = false,
    this.audience,
  }) : scopes = scopes ?? <String>[] {
    if (useIdToken && (audience == null || audience!.isEmpty)) {
      throw ArgumentError(
        'audience is required when useIdToken is true. '
        'Set it to the target service URL.',
      );
    }
  }

  /// Optional embedded service-account credentials.
  ServiceAccountCredential? serviceAccountCredential;

  /// OAuth scopes requested for token issuance.
  List<String> scopes;

  /// Whether to use environment default credentials.
  bool useDefaultCredential;

  /// Whether to request an ID token instead of access token.
  bool useIdToken;

  /// Target audience when [useIdToken] is enabled.
  String? audience;

  /// Returns a deep copy of this service-account auth configuration.
  ServiceAccountAuth copyWith() {
    return ServiceAccountAuth(
      serviceAccountCredential: serviceAccountCredential?.copyWith(),
      scopes: List<String>.from(scopes),
      useDefaultCredential: useDefaultCredential,
      useIdToken: useIdToken,
      audience: audience,
    );
  }
}

/// Union model for all supported authentication credentials.
class AuthCredential {
  /// Creates an authentication credential payload.
  AuthCredential({
    required this.authType,
    this.resourceRef,
    this.apiKey,
    this.http,
    this.oauth2,
    this.serviceAccount,
  });

  /// Credential type discriminator.
  AuthCredentialType authType;

  /// Optional resource reference.
  String? resourceRef;

  /// Optional API key value.
  String? apiKey;

  /// Optional HTTP auth payload.
  HttpAuth? http;

  /// Optional OAuth2 auth payload.
  OAuth2Auth? oauth2;

  /// Optional service-account auth payload.
  ServiceAccountAuth? serviceAccount;

  /// Returns a copied credential payload with optional overrides.
  AuthCredential copyWith({
    AuthCredentialType? authType,
    Object? resourceRef = _sentinel,
    Object? apiKey = _sentinel,
    Object? http = _sentinel,
    Object? oauth2 = _sentinel,
    Object? serviceAccount = _sentinel,
  }) {
    return AuthCredential(
      authType: authType ?? this.authType,
      resourceRef: identical(resourceRef, _sentinel)
          ? this.resourceRef
          : resourceRef as String?,
      apiKey: identical(apiKey, _sentinel) ? this.apiKey : apiKey as String?,
      http: identical(http, _sentinel)
          ? this.http?.copyWith()
          : http as HttpAuth?,
      oauth2: identical(oauth2, _sentinel)
          ? this.oauth2?.copyWith()
          : oauth2 as OAuth2Auth?,
      serviceAccount: identical(serviceAccount, _sentinel)
          ? this.serviceAccount?.copyWith()
          : serviceAccount as ServiceAccountAuth?,
    );
  }
}

const Object _sentinel = Object();
