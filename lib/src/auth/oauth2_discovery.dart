/// OAuth2/OpenID discovery models and network helper utilities.
library;

import 'dart:convert';
import 'dart:io';

/// Authorization server metadata discovered from well-known endpoints.
class AuthorizationServerMetadata {
  /// Creates authorization server metadata.
  AuthorizationServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    List<String>? scopesSupported,
    this.registrationEndpoint,
  }) : scopesSupported = scopesSupported ?? <String>[];

  /// Issuer URL.
  final String issuer;

  /// Authorization endpoint URL.
  final String authorizationEndpoint;

  /// Token endpoint URL.
  final String tokenEndpoint;

  /// Supported scopes.
  final List<String> scopesSupported;

  /// Optional dynamic client registration endpoint.
  final String? registrationEndpoint;

  /// Creates metadata from JSON payload.
  factory AuthorizationServerMetadata.fromJson(Map<String, Object?> json) {
    return AuthorizationServerMetadata(
      issuer: (json['issuer'] ?? '').toString(),
      authorizationEndpoint: (json['authorization_endpoint'] ?? '').toString(),
      tokenEndpoint: (json['token_endpoint'] ?? '').toString(),
      scopesSupported:
          (json['scopes_supported'] as List<Object?>?)
              ?.map((Object? value) => value?.toString() ?? '')
              .where((String value) => value.isNotEmpty)
              .toList() ??
          <String>[],
      registrationEndpoint: json['registration_endpoint']?.toString(),
    );
  }
}

/// Protected resource metadata discovered via RFC 9728 endpoints.
class ProtectedResourceMetadata {
  /// Creates protected resource metadata.
  ProtectedResourceMetadata({
    required this.resource,
    List<String>? authorizationServers,
  }) : authorizationServers = authorizationServers ?? <String>[];

  /// Protected resource URL.
  final String resource;

  /// Authorization servers trusted by the resource.
  final List<String> authorizationServers;

  /// Creates metadata from JSON payload.
  factory ProtectedResourceMetadata.fromJson(Map<String, Object?> json) {
    return ProtectedResourceMetadata(
      resource: (json['resource'] ?? '').toString(),
      authorizationServers:
          (json['authorization_servers'] as List<Object?>?)
              ?.map((Object? value) => value?.toString() ?? '')
              .where((String value) => value.isNotEmpty)
              .toList() ??
          <String>[],
    );
  }
}

/// HTTP GET function signature used by discovery.
typedef DiscoveryHttpGet =
    Future<({int statusCode, String body})> Function(Uri uri);

/// Performs OAuth2/OpenID discovery against standard well-known endpoints.
class OAuth2DiscoveryManager {
  /// Creates a discovery manager with optional custom HTTP transport.
  OAuth2DiscoveryManager({DiscoveryHttpGet? httpGet})
    : _httpGet = httpGet ?? _defaultHttpGet;

  final DiscoveryHttpGet _httpGet;

  /// Discovers authorization-server metadata for [issuerUrl].
  Future<AuthorizationServerMetadata?> discoverAuthServerMetadata(
    String issuerUrl,
  ) async {
    final Uri? parsed = Uri.tryParse(issuerUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }

    final String baseUrl =
        '${parsed.scheme}://${parsed.host}'
        '${parsed.hasPort ? ':${parsed.port}' : ''}';
    final String path = parsed.path;
    final List<String> endpointsToTry;
    if (path.isNotEmpty && path != '/') {
      final String normalizedPath = path.endsWith('/')
          ? path.substring(0, path.length - 1)
          : path;
      endpointsToTry = <String>[
        '$baseUrl/.well-known/oauth-authorization-server$normalizedPath',
        '$baseUrl/.well-known/openid-configuration$normalizedPath',
        '$baseUrl$normalizedPath/.well-known/openid-configuration',
      ];
    } else {
      endpointsToTry = <String>[
        '$baseUrl/.well-known/oauth-authorization-server',
        '$baseUrl/.well-known/openid-configuration',
      ];
    }

    for (final String endpoint in endpointsToTry) {
      final Uri? uri = Uri.tryParse(endpoint);
      if (uri == null) {
        continue;
      }
      try {
        final ({int statusCode, String body}) response = await _httpGet(uri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final Object? decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          continue;
        }
        final AuthorizationServerMetadata metadata =
            AuthorizationServerMetadata.fromJson(
              decoded.map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            );
        if (_normalizeUrl(metadata.issuer) == _normalizeUrl(issuerUrl)) {
          return metadata;
        }
      } on FormatException {
        continue;
      } on SocketException {
        continue;
      } on HttpException {
        continue;
      }
    }

    return null;
  }

  /// Discovers protected-resource metadata for [resourceUrl].
  Future<ProtectedResourceMetadata?> discoverResourceMetadata(
    String resourceUrl,
  ) async {
    final Uri? parsed = Uri.tryParse(resourceUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }

    final String baseUrl =
        '${parsed.scheme}://${parsed.host}'
        '${parsed.hasPort ? ':${parsed.port}' : ''}';
    final String path = parsed.path;
    final String endpoint = (path.isNotEmpty && path != '/')
        ? '$baseUrl/.well-known/oauth-protected-resource$path'
        : '$baseUrl/.well-known/oauth-protected-resource';
    final Uri? uri = Uri.tryParse(endpoint);
    if (uri == null) {
      return null;
    }

    try {
      final ({int statusCode, String body}) response = await _httpGet(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return null;
      }
      final ProtectedResourceMetadata metadata =
          ProtectedResourceMetadata.fromJson(
            decoded.map(
              (Object? key, Object? value) =>
                  MapEntry<String, Object?>(key.toString(), value),
            ),
          );
      if (_normalizeUrl(metadata.resource) == _normalizeUrl(resourceUrl)) {
        return metadata;
      }
    } on FormatException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    }

    return null;
  }
}

Future<({int statusCode, String body})> _defaultHttpGet(Uri uri) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decoder.bind(response).join();
    return (statusCode: response.statusCode, body: body);
  } finally {
    client.close();
  }
}

String _normalizeUrl(String url) {
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
