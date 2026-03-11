/// Registry for pluggable auth provider integrations.
library;

import 'dart:convert';

import 'auth_schemes.dart';
import 'base_auth_provider.dart';

/// Registry that resolves auth providers for serialized auth scheme payloads.
class AuthProviderRegistry {
  final Map<Object, BaseAuthProvider> _providers = <Object, BaseAuthProvider>{};

  /// Registers [providerInstance] for [authSchemeType].
  ///
  /// Supported registration keys include [Type], [String], [AuthSchemeType],
  /// and [SecurityScheme].
  void register(Object authSchemeType, BaseAuthProvider providerInstance) {
    _providers[_normalizeRegistrationKey(authSchemeType)] = providerInstance;
  }

  /// Returns the provider registered for [authScheme], if any.
  BaseAuthProvider? getProvider(Object authScheme) {
    for (final Object key in _candidateKeys(authScheme)) {
      final BaseAuthProvider? provider = _providers[key];
      if (provider != null) {
        return provider;
      }
    }
    return null;
  }

  Object _normalizeRegistrationKey(Object authSchemeType) {
    if (authSchemeType is Type) {
      return authSchemeType;
    }
    if (authSchemeType is AuthSchemeType) {
      return authSchemeType.name.toLowerCase();
    }
    if (authSchemeType is SecurityScheme) {
      return authSchemeType.type.name.toLowerCase();
    }
    if (authSchemeType is String) {
      final List<Object> keys = _candidateKeys(authSchemeType);
      return keys.isEmpty ? authSchemeType.toLowerCase() : keys.first;
    }
    return authSchemeType.runtimeType;
  }

  List<Object> _candidateKeys(Object authScheme) {
    final Set<Object> keys = <Object>{};

    void addString(String? value) {
      final String? normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) {
        return;
      }
      keys.add(normalized);
      keys.add(normalized.toLowerCase());
    }

    if (authScheme is Type) {
      keys.add(authScheme);
      return keys.toList(growable: false);
    }

    if (authScheme is AuthSchemeType) {
      addString(authScheme.name);
      return keys.toList(growable: false);
    }

    if (authScheme is SecurityScheme) {
      keys.add(authScheme.runtimeType);
      addString(authScheme.type.name);
      addString(authScheme.scheme);
      return keys.toList(growable: false);
    }

    if (authScheme is String) {
      addString(authScheme);
      final Object? decoded = _tryDecodeJson(authScheme);
      if (decoded is Map) {
        addString('${decoded['type'] ?? decoded['type_']}');
        addString('${decoded['scheme']}');
      }
      return keys.toList(growable: false);
    }

    keys.add(authScheme.runtimeType);
    addString('$authScheme');
    return keys.toList(growable: false);
  }

  Object? _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
