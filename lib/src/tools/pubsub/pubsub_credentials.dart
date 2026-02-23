import '../_google_credentials.dart';

const String pubsubTokenCacheKey = 'pubsub_token_cache';
const List<String> pubsubDefaultScope = <String>[
  'https://www.googleapis.com/auth/pubsub',
];

class PubSubCredentialsConfig extends BaseGoogleCredentialsConfig {
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
