import '../_google_credentials.dart';

const String bigtableTokenCacheKey = 'bigtable_token_cache';
const List<String> bigtableDefaultScope = <String>[
  'https://www.googleapis.com/auth/bigtable.admin',
  'https://www.googleapis.com/auth/bigtable.data',
];

class BigtableCredentialsConfig extends BaseGoogleCredentialsConfig {
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
