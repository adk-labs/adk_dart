import '../_google_credentials.dart';

const String spannerTokenCacheKey = 'spanner_token_cache';
const List<String> spannerDefaultScope = <String>[
  'https://www.googleapis.com/auth/spanner.admin',
  'https://www.googleapis.com/auth/spanner.data',
];

class SpannerCredentialsConfig extends BaseGoogleCredentialsConfig {
  SpannerCredentialsConfig({
    super.credentials,
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
  }) : super(tokenCacheKey: spannerTokenCacheKey) {
    if (scopes == null || scopes!.isEmpty) {
      scopes = List<String>.from(spannerDefaultScope);
    }
  }
}
