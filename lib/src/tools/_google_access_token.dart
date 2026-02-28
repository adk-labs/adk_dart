import 'dart:async';
import 'dart:convert';
import 'dart:io';

const List<String> _googleAccessTokenEnvKeys = <String>[
  'GOOGLE_OAUTH_ACCESS_TOKEN',
  'GOOGLE_ACCESS_TOKEN',
  'ACCESS_TOKEN',
];

Future<String> resolveDefaultGoogleAccessToken({
  List<String> scopes = const <String>[],
}) async {
  for (final String envKey in _googleAccessTokenEnvKeys) {
    final String? value = Platform.environment[envKey]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  final String? fromGcloud = await _resolveFromGcloud(scopes: scopes);
  if (fromGcloud != null && fromGcloud.isNotEmpty) {
    return fromGcloud;
  }

  final String? fromMetadata = await _resolveFromMetadataServer();
  if (fromMetadata != null && fromMetadata.isNotEmpty) {
    return fromMetadata;
  }

  throw StateError(
    'Unable to resolve Google access token. '
    'Set GOOGLE_OAUTH_ACCESS_TOKEN (or GOOGLE_ACCESS_TOKEN), '
    'or login with `gcloud auth application-default login`, '
    'or run on GCP metadata-enabled runtime.',
  );
}

Future<String?> _resolveFromGcloud({required List<String> scopes}) async {
  final List<String> arguments = <String>[
    'auth',
    'application-default',
    'print-access-token',
    if (scopes.isNotEmpty) ...<String>[
      '--scopes',
      scopes.join(','),
    ],
  ];
  try {
    final ProcessResult result = await Process.run(
      'gcloud',
      arguments,
    ).timeout(const Duration(seconds: 4));
    if (result.exitCode != 0) {
      return null;
    }
    final String token = '${result.stdout}'.trim();
    if (token.isEmpty) {
      return null;
    }
    return token;
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  }
}

Future<String?> _resolveFromMetadataServer() async {
  final Uri uri = Uri(
    scheme: 'http',
    host: 'metadata.google.internal',
    path: '/computeMetadata/v1/instance/service-accounts/default/token',
  );
  final HttpClient client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    request.headers.set('Metadata-Flavor', 'Google');
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final String body = await utf8.decoder.bind(response).join();
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      return null;
    }
    final Object? token = decoded['access_token'];
    if (token == null) {
      return null;
    }
    final String text = '$token'.trim();
    if (text.isEmpty) {
      return null;
    }
    return text;
  } on SocketException {
    return null;
  } on HandshakeException {
    return null;
  } on TimeoutException {
    return null;
  } on FormatException {
    return null;
  } finally {
    client.close(force: true);
  }
}
