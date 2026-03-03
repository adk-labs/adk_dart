/// Credential defaults and cache keys for Spanner tools.
library;

import '../_google_credentials.dart';

/// Token cache key used for Spanner credential refresh flow.
const String spannerTokenCacheKey = 'spanner_token_cache';

/// Default OAuth scopes required by Spanner tools.
const List<String> spannerDefaultScope = <String>[
  'https://www.googleapis.com/auth/spanner.admin',
  'https://www.googleapis.com/auth/spanner.data',
];

/// Credential configuration used by Spanner Google tools.
class SpannerCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates credential settings for Spanner APIs.
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
