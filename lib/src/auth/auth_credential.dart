enum AuthCredentialType { apiKey, http, oauth2, openIdConnect, serviceAccount }

class HttpCredentials {
  HttpCredentials({this.username, this.password, this.token});

  String? username;
  String? password;
  String? token;
}

class HttpAuth {
  HttpAuth({
    required this.scheme,
    required this.credentials,
    Map<String, String>? additionalHeaders,
  }) : additionalHeaders = additionalHeaders ?? <String, String>{};

  String scheme;
  HttpCredentials credentials;
  Map<String, String> additionalHeaders;
}

class OAuth2Auth {
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

  String? clientId;
  String? clientSecret;
  String? authUri;
  String? state;
  String? redirectUri;
  String? authResponseUri;
  String? authCode;
  String? accessToken;
  String? refreshToken;
  String? idToken;
  int? expiresAt;
  int? expiresIn;
  String? audience;
  String tokenEndpointAuthMethod;
}

class ServiceAccountCredential {
  ServiceAccountCredential({
    required this.projectId,
    required this.privateKeyId,
    required this.privateKey,
    required this.clientEmail,
    required this.clientId,
    required this.authUri,
    required this.tokenUri,
  });

  String projectId;
  String privateKeyId;
  String privateKey;
  String clientEmail;
  String clientId;
  String authUri;
  String tokenUri;
}

class ServiceAccountAuth {
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

  ServiceAccountCredential? serviceAccountCredential;
  List<String> scopes;
  bool useDefaultCredential;
  bool useIdToken;
  String? audience;
}

class AuthCredential {
  AuthCredential({
    required this.authType,
    this.resourceRef,
    this.apiKey,
    this.http,
    this.oauth2,
    this.serviceAccount,
  });

  AuthCredentialType authType;
  String? resourceRef;
  String? apiKey;
  HttpAuth? http;
  OAuth2Auth? oauth2;
  ServiceAccountAuth? serviceAccount;

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
