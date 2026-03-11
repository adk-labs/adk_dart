import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/auth/auth_provider_registry.dart';
import 'package:adk_dart/src/auth/base_auth_provider.dart';
import 'package:test/test.dart';

class _SchemeA {}

class _SchemeB {}

class _StubAuthProvider extends BaseAuthProvider {
  _StubAuthProvider(this.credential);

  final AuthCredential? credential;

  @override
  Future<AuthCredential?> getAuthCredential(
    AuthConfig authConfig,
    Context context,
  ) async {
    return credential;
  }
}

void main() {
  group('AuthProviderRegistry', () {
    test('registers and resolves providers by runtime type', () {
      final AuthProviderRegistry registry = AuthProviderRegistry();
      final _StubAuthProvider providerA = _StubAuthProvider(null);
      final _StubAuthProvider providerB = _StubAuthProvider(null);

      registry.register(_SchemeA, providerA);
      registry.register(_SchemeB, providerB);

      expect(registry.getProvider(_SchemeA()), same(providerA));
      expect(registry.getProvider(_SchemeB()), same(providerB));
    });

    test('matches serialized security scheme payloads by type', () {
      final AuthProviderRegistry registry = AuthProviderRegistry();
      final _StubAuthProvider provider = _StubAuthProvider(null);

      registry.register(AuthSchemeType.oauth2, provider);

      final String serializedScheme = jsonEncode(
        SecurityScheme(type: AuthSchemeType.oauth2).toJson(),
      );
      expect(registry.getProvider(serializedScheme), same(provider));
    });
  });
}
