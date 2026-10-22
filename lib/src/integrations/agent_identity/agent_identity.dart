/// Google Cloud Agent Identity and IAM Connector authentication integration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../agents/context.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_schemes.dart';
import '../../auth/auth_tool.dart';
import '../../auth/base_auth_provider.dart';
import '../../flows/llm_flows/functions.dart';
import '../../types/content.dart';

/// Default interval between non-interactive token polling attempts.
const Duration defaultNonInteractivePollInterval = Duration(seconds: 1);

/// Default timeout for non-interactive token polling.
const Duration defaultNonInteractivePollTimeout = Duration(seconds: 10);

/// Default endpoint for the Google Cloud IAM Connectors API.
const String defaultIamConnectorsEndpoint =
    'https://iamconnectors.googleapis.com';

/// Security scheme identifying a Google Cloud Auth Provider or IAM Connector.
///
/// ```dart
/// final scheme = GcpAuthProviderScheme(
///   name: 'projects/my-proj/locations/us-central1/connectors/my-conn',
///   scopes: <String>['https://www.googleapis.com/auth/cloud-platform'],
///   continueUri: 'https://example.com/callback',
/// );
/// ```
class GcpAuthProviderScheme extends SecurityScheme {
  /// Creates a [GcpAuthProviderScheme].
  GcpAuthProviderScheme({
    required String name,
    List<String>? scopes,
    this.continueUri,
    super.description,
  }) : _name = name,
       scopes = scopes == null ? null : List<String>.unmodifiable(scopes),
       super(type: AuthSchemeType.oauth2, name: name);

  /// Deserializes a [GcpAuthProviderScheme] from a JSON map.
  factory GcpAuthProviderScheme.fromJson(Map<String, Object?> json) {
    final Object? rawScopes = json['scopes'];
    final List<String>? scopes = rawScopes is List
        ? rawScopes.map((Object? item) => '$item').toList()
        : null;
    return GcpAuthProviderScheme(
      name: (json['name'] as String?) ?? '',
      scopes: scopes,
      continueUri:
          (json['continue_uri'] as String?) ?? (json['continueUri'] as String?),
      description: json['description'] as String?,
    );
  }

  /// Parses [rawScheme] from a [GcpAuthProviderScheme], JSON map, or JSON string.
  factory GcpAuthProviderScheme.parse(Object rawScheme) {
    if (rawScheme is GcpAuthProviderScheme) {
      return rawScheme;
    }
    if (rawScheme is Map<String, Object?>) {
      return GcpAuthProviderScheme.fromJson(rawScheme);
    }
    if (rawScheme is Map) {
      return GcpAuthProviderScheme.fromJson(
        rawScheme.map((Object? k, Object? v) => MapEntry('$k', v)),
      );
    }
    if (rawScheme is String && rawScheme.trim().isNotEmpty) {
      final String trimmed = rawScheme.trim();
      if (trimmed.startsWith('{')) {
        final Object? decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return GcpAuthProviderScheme.fromJson(
            decoded.map((Object? k, Object? v) => MapEntry('$k', v)),
          );
        }
      }
      return GcpAuthProviderScheme(name: trimmed);
    }
    throw ArgumentError(
      'Unsupported authScheme value for GcpAuthProviderScheme: $rawScheme',
    );
  }

  /// Discriminator field matching ADK Python's `GcpAuthProviderScheme.type_field`.
  final String typeField = 'gcpAuthProviderScheme';

  final String _name;

  /// Resource name of the AuthProvider or IAM Connector.
  @override
  String get name => _name;

  /// Optional list of OAuth scopes to request.
  final List<String>? scopes;

  /// Optional redirect URI after user completes interactive consent.
  final String? continueUri;

  /// Serializes this scheme to a JSON-compatible map.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type_field': typeField,
      'type': 'oauth2',
      'name': name,
      'scopes': ?scopes,
      'continue_uri': ?continueUri,
      'description': ?description,
    };
  }

  /// Serializes this scheme to a JSON string suitable for [AuthConfig.authScheme].
  String toJsonString() => jsonEncode(toJson());
}

/// State of an Agent Identity credential retrieval request.
enum AgentIdentityResponseState {
  /// Unspecified state.
  unspecified,

  /// Credentials were minted and are ready for use.
  success,

  /// Credentials are being prepared asynchronously; caller should poll.
  pending,

  /// End-user explicitly rejected consent.
  consentRejected,

  /// Interactive browser consent at `consentUri` is required.
  uriConsentRequired,
}

/// HTTP authorization header/token pair returned by Agent Identity.
class AgentIdentityHttpAuthorization {
  /// Creates an [AgentIdentityHttpAuthorization].
  const AgentIdentityHttpAuthorization({
    required this.authorizationHeader,
    required this.token,
    this.apiKey,
  });

  /// HTTP header name (for example `'Authorization'`).
  final String authorizationHeader;

  /// Header value (for example `'Bearer ya29...'`).
  final String token;

  /// Optional API key to pass via `X-GOOG-API-KEY`.
  final String? apiKey;
}

/// Response returned from [AgentIdentityCredentialsClient.getCredentials].
class AgentIdentityCredentialsResponse {
  /// Creates an [AgentIdentityCredentialsResponse].
  const AgentIdentityCredentialsResponse({
    required this.state,
    this.httpAuthorization,
    this.consentUri,
    this.stateId,
  });

  /// State of the credential retrieval operation.
  final AgentIdentityResponseState state;

  /// Authorization details when [state] is [AgentIdentityResponseState.success].
  final AgentIdentityHttpAuthorization? httpAuthorization;

  /// Interactive consent URL when [state] is [AgentIdentityResponseState.uriConsentRequired].
  final String? consentUri;

  /// Anti-CSRF nonce when [state] is [AgentIdentityResponseState.uriConsentRequired].
  final String? stateId;
}

/// Abstract client for the Google Cloud Agent Identity Credentials API.
abstract interface class AgentIdentityCredentialsClient {
  /// Requests credentials for [userId] and [authScheme].
  Future<AgentIdentityCredentialsResponse> getCredentials({
    required String userId,
    required GcpAuthProviderScheme authScheme,
  });
}

/// Default HTTP/configurable implementation of [AgentIdentityCredentialsClient].
///
/// ```dart
/// final client = HttpAgentIdentityCredentialsClient();
/// ```
class HttpAgentIdentityCredentialsClient
    implements AgentIdentityCredentialsClient {
  /// Creates an [HttpAgentIdentityCredentialsClient].
  HttpAgentIdentityCredentialsClient({
    Future<AgentIdentityCredentialsResponse> Function({
      required String userId,
      required GcpAuthProviderScheme authScheme,
    })?
    handler,
  }) : _handler = handler;

  final Future<AgentIdentityCredentialsResponse> Function({
    required String userId,
    required GcpAuthProviderScheme authScheme,
  })?
  _handler;

  @override
  Future<AgentIdentityCredentialsResponse> getCredentials({
    required String userId,
    required GcpAuthProviderScheme authScheme,
  }) async {
    if (_handler != null) {
      return _handler(userId: userId, authScheme: authScheme);
    }
    throw StateError(
      'AgentIdentityCredentialsClient is not configured with a live handler.',
    );
  }
}

/// Credentials provider backed by Google Cloud Agent Identity.
///
/// ```dart
/// final provider = AgentIdentityCredentialsProvider(client: customClient);
/// ```
class AgentIdentityCredentialsProvider extends BaseAuthProvider {
  /// Creates an [AgentIdentityCredentialsProvider].
  AgentIdentityCredentialsProvider({
    AgentIdentityCredentialsClient? client,
    this.pollInterval = defaultNonInteractivePollInterval,
    this.pollTimeout = defaultNonInteractivePollTimeout,
  }) : _client = client;

  final AgentIdentityCredentialsClient? _client;

  /// Polling interval while the credential state is `pending`.
  final Duration pollInterval;

  /// Maximum duration to poll while the credential state is `pending`.
  final Duration pollTimeout;

  /// Active [AgentIdentityCredentialsClient].
  AgentIdentityCredentialsClient get client =>
      _client ?? HttpAgentIdentityCredentialsClient();

  @override
  Iterable<Object> get supportedAuthSchemes =>
      const <Type>[GcpAuthProviderScheme];

  @override
  Future<AuthCredential?> getAuthCredential(
    AuthConfig authConfig,
    Context context,
  ) async {
    final GcpAuthProviderScheme scheme = GcpAuthProviderScheme.parse(
      authConfig.authScheme,
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    AgentIdentityCredentialsResponse response = await client.getCredentials(
      userId: context.userId,
      authScheme: scheme,
    );

    while (response.state == AgentIdentityResponseState.pending) {
      if (stopwatch.elapsed >= pollTimeout) {
        throw StateError('Polling for token timed out.');
      }
      if (pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
      response = await client.getCredentials(
        userId: context.userId,
        authScheme: scheme,
      );
    }

    switch (response.state) {
      case AgentIdentityResponseState.success:
        final AgentIdentityHttpAuthorization? auth = response.httpAuthorization;
        if (auth == null ||
            auth.authorizationHeader.isEmpty ||
            auth.token.isEmpty) {
          throw StateError(
            'Token retrieval succeeded, but token or header is missing in the response.',
          );
        }
        return buildHttpAuthCredential(
          header: auth.authorizationHeader,
          token: auth.token,
          apiKey: auth.apiKey,
        );
      case AgentIdentityResponseState.consentRejected:
        throw StateError('User rejected authorization consent.');
      case AgentIdentityResponseState.uriConsentRequired:
        if (isConsentCompleted(context)) {
          throw StateError(
            'Interactive authorization required after consent completed.',
          );
        }
        if (response.consentUri == null || response.consentUri!.isEmpty) {
          throw StateError('Consent URI is missing in the response.');
        }
        if (response.stateId == null || response.stateId!.isEmpty) {
          throw StateError('State ID is missing in the response.');
        }
        return AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(
            authUri: response.consentUri,
            nonce: response.stateId,
          ),
        );
      case AgentIdentityResponseState.pending:
      case AgentIdentityResponseState.unspecified:
        throw StateError(
          'Unexpected response state during token retrieval: ${response.state}.',
        );
    }
  }
}

/// Long-running operation returned by the Google Cloud IAM Connectors API.
class IamConnectorOperation {
  /// Creates an [IamConnectorOperation].
  const IamConnectorOperation({
    this.name = '',
    this.done = false,
    this.metadata = const <String, Object?>{},
    this.response = const <String, Object?>{},
    this.error,
  });

  /// Deserializes an [IamConnectorOperation] from a JSON map.
  factory IamConnectorOperation.fromJson(Map<String, Object?> json) {
    return IamConnectorOperation(
      name: (json['name'] as String?) ?? '',
      done: (json['done'] as bool?) ?? false,
      metadata: _toStringKeyMap(json['metadata']),
      response: _toStringKeyMap(json['response']),
      error: json['error'] is Map ? _toStringKeyMap(json['error']) : null,
    );
  }

  /// Long-running operation resource name.
  final String name;

  /// Whether the operation has completed.
  final bool done;

  /// Operation metadata map (e.g. `state`, `consent_uri`, `state_id`).
  final Map<String, Object?> metadata;

  /// Operation response map (e.g. `header`, `token`, `api_key`).
  final Map<String, Object?> response;

  /// Optional error map when the operation failed.
  final Map<String, Object?>? error;
}

/// Abstract client for the Google Cloud IAM Connectors API.
abstract interface class IamConnectorCredentialsClient {
  /// Calls `RetrieveAuthorization` for [userId] and [authScheme].
  Future<IamConnectorOperation> retrieveAuthorization({
    required String userId,
    required GcpAuthProviderScheme authScheme,
  });
}

/// Default HTTP implementation of [IamConnectorCredentialsClient].
///
/// ```dart
/// final client = HttpIamConnectorCredentialsClient(
///   accessToken: 'ya29.example',
/// );
/// ```
class HttpIamConnectorCredentialsClient
    implements IamConnectorCredentialsClient {
  /// Creates an [HttpIamConnectorCredentialsClient].
  HttpIamConnectorCredentialsClient({
    this.endpoint = defaultIamConnectorsEndpoint,
    this.accessToken,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Base URL of the IAM Connectors service.
  final String endpoint;

  /// Optional OAuth2 bearer access token used to call the IAM Connectors API.
  final String? accessToken;

  final HttpClient Function() _httpClientFactory;

  @override
  Future<IamConnectorOperation> retrieveAuthorization({
    required String userId,
    required GcpAuthProviderScheme authScheme,
  }) async {
    final HttpClient httpClient = _httpClientFactory();
    try {
      final String base = endpoint.endsWith('/')
          ? endpoint.substring(0, endpoint.length - 1)
          : endpoint;
      final Uri uri = Uri.parse(
        '$base/v1alpha/${authScheme.name}:retrieveAuthorization',
      );
      final HttpClientRequest request = await httpClient.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (accessToken != null && accessToken!.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      final Map<String, Object?> body = <String, Object?>{
        'client_user_id': userId,
        if (authScheme.scopes != null) 'scopes': authScheme.scopes,
        if (authScheme.continueUri != null)
          'continue_uri': authScheme.continueUri,
      };
      request.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse response = await request.close();
      final String responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'IAM Connector retrieveAuthorization failed (${response.statusCode}): $responseText',
          uri: uri,
        );
      }
      final Object? decoded = jsonDecode(responseText);
      if (decoded is Map) {
        return IamConnectorOperation.fromJson(
          decoded.map((Object? k, Object? v) => MapEntry('$k', v)),
        );
      }
      return const IamConnectorOperation();
    } finally {
      httpClient.close(force: false);
    }
  }
}

/// Credentials provider backed by Google Cloud IAM Connectors.
///
/// ```dart
/// final provider = IamConnectorCredentialsProvider(client: customClient);
/// ```
class IamConnectorCredentialsProvider extends BaseAuthProvider {
  /// Creates an [IamConnectorCredentialsProvider].
  IamConnectorCredentialsProvider({
    IamConnectorCredentialsClient? client,
    this.pollInterval = defaultNonInteractivePollInterval,
    this.pollTimeout = defaultNonInteractivePollTimeout,
  }) : _client = client;

  final IamConnectorCredentialsClient? _client;

  /// Polling interval while the LRO metadata state is `consent_pending`.
  final Duration pollInterval;

  /// Maximum duration to poll while the LRO metadata state is `consent_pending`.
  final Duration pollTimeout;

  /// Active [IamConnectorCredentialsClient].
  IamConnectorCredentialsClient get client =>
      _client ?? HttpIamConnectorCredentialsClient();

  @override
  Iterable<Object> get supportedAuthSchemes =>
      const <Type>[GcpAuthProviderScheme];

  @override
  Future<AuthCredential?> getAuthCredential(
    AuthConfig authConfig,
    Context context,
  ) async {
    final GcpAuthProviderScheme scheme = GcpAuthProviderScheme.parse(
      authConfig.authScheme,
    );

    final Stopwatch stopwatch = Stopwatch()..start();
    IamConnectorOperation operation = await client.retrieveAuthorization(
      userId: context.userId,
      authScheme: scheme,
    );

    while (!operation.done &&
        _extractConnectorState(operation.metadata) == 'consent_pending') {
      if (stopwatch.elapsed >= pollTimeout) {
        throw StateError('Polling for token timed out.');
      }
      if (pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
      operation = await client.retrieveAuthorization(
        userId: context.userId,
        authScheme: scheme,
      );
    }

    if (operation.error != null) {
      throw StateError(
        'Authorization retrieval failed with error: ${operation.error}',
      );
    }

    if (operation.done) {
      final String? header =
          (operation.response['header'] ??
                  operation.response['authorization_header'] ??
                  operation.response['authorizationHeader'])
              as String?;
      final String? token = operation.response['token'] as String?;
      final String? apiKey =
          (operation.response['api_key'] ?? operation.response['apiKey'])
              as String?;
      if (header == null || header.isEmpty || token == null || token.isEmpty) {
        throw StateError(
          'Token retrieval succeeded, but token or header is missing in the response.',
        );
      }
      return buildHttpAuthCredential(
        header: header,
        token: token,
        apiKey: apiKey,
      );
    }

    final String state = _extractConnectorState(operation.metadata);
    if (state == 'uri_consent_required') {
      if (isConsentCompleted(context)) {
        throw StateError(
          'Interactive authorization required after consent completed.',
        );
      }
      final String? consentUri =
          (operation.metadata['consent_uri'] ??
                  operation.metadata['consentUri'])
              as String?;
      final String? stateId =
          (operation.metadata['state_id'] ?? operation.metadata['stateId'])
              as String?;
      if (consentUri == null || consentUri.isEmpty) {
        throw StateError('Consent URI is missing in the response.');
      }
      if (stateId == null || stateId.isEmpty) {
        throw StateError('State ID is missing in the response.');
      }
      return AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(authUri: consentUri, nonce: stateId),
      );
    }

    throw StateError(
      'Unexpected response state during token retrieval: $state.',
    );
  }
}

/// Composite authentication provider for Google Cloud Auth Providers and IAM Connectors.
///
/// Automatically routes `projects/*/locations/*/connectors/*` resource names to
/// [IamConnectorCredentialsProvider] and all other [GcpAuthProviderScheme]
/// resource names to [AgentIdentityCredentialsProvider].
///
/// ```dart
/// final provider = GcpAuthProvider(
///   agentIdentityProvider: AgentIdentityCredentialsProvider(client: aiClient),
///   iamConnectorProvider: IamConnectorCredentialsProvider(client: iamClient),
/// );
/// ```
class GcpAuthProvider extends BaseAuthProvider {
  /// Creates a [GcpAuthProvider].
  GcpAuthProvider({
    AgentIdentityCredentialsProvider? agentIdentityProvider,
    IamConnectorCredentialsProvider? iamConnectorProvider,
  }) : _agentIdentityProvider = agentIdentityProvider,
       _iamConnectorProvider = iamConnectorProvider;

  static final RegExp _connectorNamePattern = RegExp(
    r'^projects/[^/]+/locations/[^/]+/connectors/[^/]+$',
  );

  AgentIdentityCredentialsProvider? _agentIdentityProvider;
  IamConnectorCredentialsProvider? _iamConnectorProvider;

  /// Lazily initialized [AgentIdentityCredentialsProvider].
  AgentIdentityCredentialsProvider get agentIdentityProvider =>
      _agentIdentityProvider ??= AgentIdentityCredentialsProvider();

  /// Lazily initialized [IamConnectorCredentialsProvider].
  IamConnectorCredentialsProvider get iamConnectorProvider =>
      _iamConnectorProvider ??= IamConnectorCredentialsProvider();

  /// Returns `true` if [schemeName] matches an IAM Connector resource path.
  static bool isIamConnectorName(String schemeName) =>
      _connectorNamePattern.hasMatch(schemeName);

  @override
  Iterable<Object> get supportedAuthSchemes =>
      const <Type>[GcpAuthProviderScheme];

  @override
  Future<AuthCredential?> getAuthCredential(
    AuthConfig authConfig,
    Context context,
  ) async {
    final GcpAuthProviderScheme scheme = GcpAuthProviderScheme.parse(
      authConfig.authScheme,
    );
    if (isIamConnectorName(scheme.name)) {
      return iamConnectorProvider.getAuthCredential(authConfig, context);
    }
    return agentIdentityProvider.getAuthCredential(authConfig, context);
  }
}

/// Builds an [AuthCredential] from an authorization [header], [token], and optional [apiKey].
AuthCredential buildHttpAuthCredential({
  required String header,
  required String token,
  String? apiKey,
}) {
  if (header.toLowerCase() == 'authorization' &&
      token.toLowerCase().startsWith('bearer ')) {
    final String bearerToken = token.substring(7);
    return AuthCredential(
      authType: AuthCredentialType.http,
      http: HttpAuth(
        scheme: 'bearer',
        credentials: HttpCredentials(token: bearerToken),
        additionalHeaders: (apiKey != null && apiKey.isNotEmpty)
            ? <String, String>{'X-GOOG-API-KEY': apiKey}
            : null,
      ),
    );
  }

  final Map<String, String> additionalHeaders = <String, String>{
    header: token,
    if (apiKey != null && apiKey.isNotEmpty) 'X-GOOG-API-KEY': apiKey,
  };
  return AuthCredential(
    authType: AuthCredentialType.http,
    http: HttpAuth(
      scheme: '',
      credentials: HttpCredentials(token: ''),
      additionalHeaders: additionalHeaders,
    ),
  );
}

/// Returns `true` if the current turn's user content already contains a
/// completed `adk_request_credential` function response.
bool isConsentCompleted(Context context) {
  final Content? userContent = context.userContent;
  if (userContent == null) {
    return false;
  }
  for (final Part part in userContent.parts) {
    if (part.functionResponse != null &&
        part.functionResponse!.name == requestEucFunctionCallName) {
      return true;
    }
  }
  return false;
}

String _extractConnectorState(Map<String, Object?> metadata) {
  final Object? raw = metadata['state'];
  if (raw == null) {
    return 'unspecified';
  }
  final String normalized = '$raw'.toLowerCase();
  if (normalized.contains('consent_pending') || normalized == 'pending') {
    return 'consent_pending';
  }
  if (normalized.contains('uri_consent_required')) {
    return 'uri_consent_required';
  }
  return normalized;
}

Map<String, Object?> _toStringKeyMap(Object? raw) {
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return const <String, Object?>{};
}
