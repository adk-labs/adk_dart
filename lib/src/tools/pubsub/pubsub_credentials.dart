import '../_google_credentials.dart';

const String pubsubTokenCacheKey = 'pubsub_token_cache';
const List<String> pubsubDefaultScope = <String>[
  'https://www.googleapis.com/auth/pubsub',
];

/// Google credential config specialized for Pub/Sub tool usage.
class PubSubCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates Pub/Sub credential configuration with default scopes.
  PubSubCredentialsConfig({
    super.credentials,
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
  }) : super(tokenCacheKey: pubsubTokenCacheKey) {
    if (scopes == null || scopes!.isEmpty) {
      scopes = List<String>.from(pubsubDefaultScope);
    }
  }
}
