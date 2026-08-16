/// Configuration models for Google Cloud Eventarc Advanced integrations.
library;

import '../_google_credentials.dart';

/// Configuration options for the Eventarc publish tool.
class EventarcToolConfig {
  /// Creates an Eventarc tool configuration.
  const EventarcToolConfig({
    this.defaultBus,
    this.defaultSource,
    this.retryAttempts = 3,
    this.timeout = const Duration(seconds: 30),
  });

  /// Optional default Eventarc message bus resource name.
  ///
  /// Format: `projects/*/locations/*/messageBuses/*`
  final String? defaultBus;

  /// Optional default CloudEvent source URI-reference.
  final String? defaultSource;

  /// Number of retry attempts on transient network failures.
  final int retryAttempts;

  /// Request timeout duration.
  final Duration timeout;
}

/// Credentials configuration for Eventarc.
class EventarcCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates an Eventarc credentials configuration.
  EventarcCredentialsConfig({
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
    super.tokenCacheKey,
    Object? credentials,
    String? accessToken,
    this.serviceAccountEmail,
  }) : super(
         credentials:
             accessToken != null
                 ? GoogleOAuthCredential(accessToken: accessToken)
                 : credentials,
       );

  /// Optional service account email.
  final String? serviceAccountEmail;

  /// Explicit access token, when present.
  String? get accessToken =>
      credentials is GoogleOAuthCredential
          ? (credentials! as GoogleOAuthCredential).accessToken
          : null;
}
