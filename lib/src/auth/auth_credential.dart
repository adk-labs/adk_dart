/// Authentication credential models used by auth tooling.
library;

/// Supported credential payload types.
enum AuthCredentialType { apiKey, http, oauth2, openIdConnect, serviceAccount }

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
}

/// OAuth2 authentication payload.
class OAuth2Auth {
  /// Creates OAuth2 authentication data.
  OAuth2Auth({
    this.clientId,
    this.clientSecret,
    this.authUri,
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
    this.tokenEndpointAuthMethod = 'client_secret_basic',
  });

  /// OAuth2 client ID.
  String? clientId;

  /// OAuth2 client secret.
  String? clientSecret;

  /// Authorization URI.
  String? authUri;

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

  /// Token endpoint auth method.
  String tokenEndpointAuthMethod;
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
      http: identical(http, _sentinel) ? this.http : http as HttpAuth?,
      oauth2: identical(oauth2, _sentinel)
          ? this.oauth2
          : oauth2 as OAuth2Auth?,
      serviceAccount: identical(serviceAccount, _sentinel)
          ? this.serviceAccount
          : serviceAccount as ServiceAccountAuth?,
    );
  }
}

const Object _sentinel = Object();
