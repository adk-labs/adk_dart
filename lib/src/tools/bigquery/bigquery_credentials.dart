/// Credential defaults and cache keys for BigQuery tool access.
library;

import '../_google_credentials.dart';

/// Token-cache key used by BigQuery credential refresh flows.
const String bigqueryTokenCacheKey = 'bigquery_token_cache';

/// Default OAuth scopes required for BigQuery operations.
const List<String> bigqueryDefaultScope = <String>[
  'https://www.googleapis.com/auth/bigquery',
];

/// Credential configuration for BigQuery tools.
class BigQueryCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates credential settings for BigQuery tool calls.
  BigQueryCredentialsConfig({
    super.credentials,
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
  }) : super(tokenCacheKey: bigqueryTokenCacheKey) {
    if (scopes == null || scopes!.isEmpty) {
      scopes = List<String>.from(bigqueryDefaultScope);
    }
  }
}
