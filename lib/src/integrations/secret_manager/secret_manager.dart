/// Google Cloud Secret Manager client integration for ADK.
library;

import '../../tools/apihub_tool/clients/secret_client.dart' as apihub_secret;

export '../../tools/_google_access_token.dart'
    show resolveDefaultGoogleAccessToken;
export '../../tools/apihub_tool/clients/secret_client.dart'
    show
        SecretManagerSecretFetcher,
        resetSecretManagerSecretFetcher,
        setSecretManagerSecretFetcher;

/// Client for retrieving secrets from Google Cloud Secret Manager.
///
/// Extends the core Secret Manager client with location-aware regional endpoint
/// metadata and strict mutual-exclusion validation between
/// `serviceAccountJson` and `authToken`.
///
/// ```dart
/// final client = SecretManagerClient(
///   authToken: 'ya29.example-token',
///   location: 'us-central1',
/// );
/// final secret = await client.getSecret(
///   'projects/my-project/secrets/my-secret/versions/latest',
/// );
/// ```
class SecretManagerClient extends apihub_secret.SecretManagerClient {
  /// Creates a Secret Manager client.
  SecretManagerClient({
    String? serviceAccountJson,
    String? authToken,
    this.location,
  }) : super(serviceAccountJson: serviceAccountJson, authToken: authToken) {
    final bool hasServiceAccount =
        serviceAccountJson != null && serviceAccountJson.isNotEmpty;
    final bool hasAuthToken = authToken != null && authToken.isNotEmpty;
    if (hasServiceAccount && hasAuthToken) {
      throw ArgumentError(
        'Cannot provide both serviceAccountJson and authToken. Please provide '
        'only one authentication method, or neither to use Application Default '
        'Credentials.',
      );
    }
  }

  /// Optional regional location (for example, `'us-central1'`).
  ///
  /// When set, regional endpoint
  /// `https://secretmanager.{location}.rep.googleapis.com` is exposed via
  /// [apiEndpoint].
  final String? location;

  /// Effective API endpoint base URL for this client.
  String get apiEndpoint {
    final String? loc = location?.trim();
    if (loc != null && loc.isNotEmpty) {
      return 'https://secretmanager.$loc.rep.googleapis.com';
    }
    return 'https://secretmanager.googleapis.com';
  }
}
