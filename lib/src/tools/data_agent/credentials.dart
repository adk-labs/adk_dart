/// Credential helpers for Data Agent tool authentication.
library;

import '../_google_credentials.dart';

/// Cache key for Data Agent OAuth tokens.
const String dataAgentTokenCacheKey = 'data_agent_token_cache';

/// Default OAuth scopes used by Data Agent tools.
const List<String> dataAgentDefaultScope = <String>[
  'https://www.googleapis.com/auth/bigquery',
];

/// Credential configuration for Data Agent tools.
class DataAgentCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates Data Agent credential configuration.
  DataAgentCredentialsConfig({
    super.credentials,
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
  }) : super(tokenCacheKey: dataAgentTokenCacheKey) {
    if (scopes == null || scopes!.isEmpty) {
      scopes = List<String>.from(dataAgentDefaultScope);
    }
  }
}
