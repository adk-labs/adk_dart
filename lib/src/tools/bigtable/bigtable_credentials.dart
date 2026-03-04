/// Credential helpers for Bigtable tool authentication.
library;

import '../_google_credentials.dart';

/// Cache key for Bigtable OAuth tokens.
const String bigtableTokenCacheKey = 'bigtable_token_cache';

/// Default OAuth scopes used by Bigtable tools.
const List<String> bigtableDefaultScope = <String>[
  'https://www.googleapis.com/auth/bigtable.admin',
  'https://www.googleapis.com/auth/bigtable.data',
];

/// Credential configuration for Bigtable tools.
class BigtableCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates Bigtable credential configuration.
  BigtableCredentialsConfig({
    super.credentials,
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
  }) : super(tokenCacheKey: bigtableTokenCacheKey) {
    if (scopes == null || scopes!.isEmpty) {
      scopes = List<String>.from(bigtableDefaultScope);
    }
  }
}
