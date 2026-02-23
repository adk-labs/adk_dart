import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('google credential config parity', () {
    test('BigQueryCredentialsConfig sets default scope and cache key', () {
      final BigQueryCredentialsConfig config = BigQueryCredentialsConfig(
        clientId: 'cid',
        clientSecret: 'csec',
      );
      expect(config.tokenCacheKey, bigqueryTokenCacheKey);
      expect(config.scopes, bigqueryDefaultScope);
    });

    test('BigtableCredentialsConfig sets default scope and cache key', () {
      final BigtableCredentialsConfig config = BigtableCredentialsConfig(
        clientId: 'cid',
        clientSecret: 'csec',
      );
      expect(config.tokenCacheKey, bigtableTokenCacheKey);
      expect(config.scopes, bigtableDefaultScope);
    });

    test('PubSubCredentialsConfig sets default scope and cache key', () {
      final PubSubCredentialsConfig config = PubSubCredentialsConfig(
        clientId: 'cid',
        clientSecret: 'csec',
      );
      expect(config.tokenCacheKey, pubsubTokenCacheKey);
      expect(config.scopes, pubsubDefaultScope);
    });

    test('SpannerCredentialsConfig sets default scope and cache key', () {
      final SpannerCredentialsConfig config = SpannerCredentialsConfig(
        clientId: 'cid',
        clientSecret: 'csec',
      );
      expect(config.tokenCacheKey, spannerTokenCacheKey);
      expect(config.scopes, spannerDefaultScope);
    });

    test('DataAgentCredentialsConfig sets default scope and cache key', () {
      final DataAgentCredentialsConfig config = DataAgentCredentialsConfig(
        clientId: 'cid',
        clientSecret: 'csec',
      );
      expect(config.tokenCacheKey, dataAgentTokenCacheKey);
      expect(config.scopes, dataAgentDefaultScope);
    });

    test('explicit scopes override defaults', () {
      final BigQueryCredentialsConfig config = BigQueryCredentialsConfig(
        clientId: 'cid',
        clientSecret: 'csec',
        scopes: <String>['scope://custom'],
      );
      expect(config.scopes, <String>['scope://custom']);
    });

    test(
      'external access token key remains valid and defaults scope post-init',
      () {
        final PubSubCredentialsConfig config = PubSubCredentialsConfig(
          externalAccessTokenKey: 'token_key',
        );
        expect(config.externalAccessTokenKey, 'token_key');
        expect(config.scopes, pubsubDefaultScope);
        expect(config.tokenCacheKey, pubsubTokenCacheKey);
      },
    );
  });
}
