import '../_google_credentials.dart';

const String bigqueryTokenCacheKey = 'bigquery_token_cache';
const List<String> bigqueryDefaultScope = <String>[
  'https://www.googleapis.com/auth/bigquery',
];

class BigQueryCredentialsConfig extends BaseGoogleCredentialsConfig {
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
