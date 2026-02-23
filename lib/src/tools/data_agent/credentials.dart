import '../_google_credentials.dart';

const String dataAgentTokenCacheKey = 'data_agent_token_cache';
const List<String> dataAgentDefaultScope = <String>[
  'https://www.googleapis.com/auth/bigquery',
];

class DataAgentCredentialsConfig extends BaseGoogleCredentialsConfig {
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
