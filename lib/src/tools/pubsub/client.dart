import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../../auth/auth_credential.dart';
import '../../version.dart';
import '../_google_credentials.dart';

const String pubSubUserAgent = 'adk-pubsub-tool google-adk/$adkVersion';
const Duration _cacheTtl = Duration(minutes: 30);
const String _defaultPubSubApiBaseUrl = 'https://pubsub.googleapis.com/v1';

abstract class PubSubPublisherClient {
  Future<String> publish({
    required String topicName,
    required List<int> data,
    Map<String, String>? attributes,
    String orderingKey = '',
  });

  Future<void> close();
}

class PulledPubSubMessage {
  PulledPubSubMessage({
    required this.messageId,
    required this.data,
    Map<String, String>? attributes,
    this.orderingKey = '',
    DateTime? publishTime,
    required this.ackId,
  }) : attributes = attributes ?? <String, String>{},
       publishTime = publishTime ?? DateTime.now().toUtc();

  final String messageId;
  final List<int> data;
  final Map<String, String> attributes;
  final String orderingKey;
  final DateTime publishTime;
  final String ackId;
}

abstract class PubSubSubscriberClient {
  Future<List<PulledPubSubMessage>> pull({
    required String subscriptionName,
    required int maxMessages,
  });

  Future<void> acknowledge({
    required String subscriptionName,
    required List<String> ackIds,
  });

  Future<void> close();
}

typedef PubSubPublisherFactory =
    Future<PubSubPublisherClient> Function({
      required Object credentials,
      required List<String> userAgents,
      required bool enableMessageOrdering,
    });

typedef PubSubSubscriberFactory =
    Future<PubSubSubscriberClient> Function({
      required Object credentials,
      required List<String> userAgents,
    });

class HttpPubSubPublisherClient implements PubSubPublisherClient {
  HttpPubSubPublisherClient({
    required this.accessToken,
    required List<String> userAgents,
    required this.enableMessageOrdering,
    this.apiBaseUrl = _defaultPubSubApiBaseUrl,
    HttpClient Function()? httpClientFactory,
  }) : userAgents = List<String>.from(userAgents),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final String accessToken;
  final List<String> userAgents;
  final bool enableMessageOrdering;
  final String apiBaseUrl;
  final HttpClient Function() _httpClientFactory;

  @override
  Future<String> publish({
    required String topicName,
    required List<int> data,
    Map<String, String>? attributes,
    String orderingKey = '',
  }) async {
    final Map<String, Object?> message = <String, Object?>{
      'data': base64Encode(data),
    };
    if (attributes != null && attributes.isNotEmpty) {
      message['attributes'] = attributes;
    }
    if (enableMessageOrdering && orderingKey.isNotEmpty) {
      message['orderingKey'] = orderingKey;
    }

    final Map<String, Object?> response = await _postJson(
      uri: Uri.parse('$apiBaseUrl/$topicName:publish'),
      accessToken: accessToken,
      userAgents: userAgents,
      body: <String, Object?>{
        'messages': <Map<String, Object?>>[message],
      },
      httpClientFactory: _httpClientFactory,
    );
    final List<Object?> messageIds = _asList(response['messageIds']);
    if (messageIds.isEmpty || _asString(messageIds.first).isEmpty) {
      throw StateError('Pub/Sub publish response did not include messageIds.');
    }
    return _asString(messageIds.first);
  }

  @override
  Future<void> close() async {}
}

class HttpPubSubSubscriberClient implements PubSubSubscriberClient {
  HttpPubSubSubscriberClient({
    required this.accessToken,
    required List<String> userAgents,
    this.apiBaseUrl = _defaultPubSubApiBaseUrl,
    HttpClient Function()? httpClientFactory,
  }) : userAgents = List<String>.from(userAgents),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final String accessToken;
  final List<String> userAgents;
  final String apiBaseUrl;
  final HttpClient Function() _httpClientFactory;

  @override
  Future<List<PulledPubSubMessage>> pull({
    required String subscriptionName,
    required int maxMessages,
  }) async {
    final Map<String, Object?> response = await _postJson(
      uri: Uri.parse('$apiBaseUrl/$subscriptionName:pull'),
      accessToken: accessToken,
      userAgents: userAgents,
      body: <String, Object?>{'maxMessages': maxMessages},
      httpClientFactory: _httpClientFactory,
    );
    final List<PulledPubSubMessage> messages = <PulledPubSubMessage>[];
    for (final Object? received in _asList(response['receivedMessages'])) {
      final Map<String, Object?> receivedMap = _asMap(received);
      final Map<String, Object?> messageMap = _asMap(receivedMap['message']);
      final String ackId = _asString(receivedMap['ackId']);
      if (ackId.isEmpty) {
        continue;
      }
      messages.add(
        PulledPubSubMessage(
          messageId: _asString(messageMap['messageId']),
          data: _decodeData(_asString(messageMap['data'])),
          attributes: _asStringMap(messageMap['attributes']),
          orderingKey: _asString(messageMap['orderingKey']),
          publishTime: _parsePublishTime(messageMap['publishTime']),
          ackId: ackId,
        ),
      );
    }
    return messages;
  }

  @override
  Future<void> acknowledge({
    required String subscriptionName,
    required List<String> ackIds,
  }) async {
    await _postJson(
      uri: Uri.parse('$apiBaseUrl/$subscriptionName:acknowledge'),
      accessToken: accessToken,
      userAgents: userAgents,
      body: <String, Object?>{'ackIds': List<String>.from(ackIds)},
      httpClientFactory: _httpClientFactory,
    );
  }

  @override
  Future<void> close() async {}
}

class _PublisherCacheEntry {
  _PublisherCacheEntry({required this.client, required this.expiration});

  final PubSubPublisherClient client;
  final DateTime expiration;
}

class _SubscriberCacheEntry {
  _SubscriberCacheEntry({required this.client, required this.expiration});

  final PubSubSubscriberClient client;
  final DateTime expiration;
}

PubSubPublisherFactory _publisherFactory = _defaultPublisherFactory;
PubSubSubscriberFactory _subscriberFactory = _defaultSubscriberFactory;

final Map<String, _PublisherCacheEntry> _publisherClientCache =
    <String, _PublisherCacheEntry>{};
final Map<String, _SubscriberCacheEntry> _subscriberClientCache =
    <String, _SubscriberCacheEntry>{};
final Map<String, String> _publisherCredentialBindings = <String, String>{};
final Map<String, String> _subscriberCredentialBindings = <String, String>{};

Future<PubSubPublisherClient> getPublisherClient({
  required Object credentials,
  Object? userAgent,
  bool enableMessageOrdering = false,
}) async {
  final DateTime now = DateTime.now().toUtc();
  final List<String> userAgents = _composeUserAgents(userAgent);
  final _CredentialFingerprint fingerprint = _credentialFingerprint(
    credentials,
  );
  final String bindingKey = _publisherBindingKey(
    sourceFingerprint: fingerprint.source,
    userAgents: userAgents,
    enableMessageOrdering: enableMessageOrdering,
  );
  final String key = _publisherCacheKey(
    bindingKey: bindingKey,
    tokenFingerprint: fingerprint.token,
  );
  await _evictExpiredPublisherClients(now);
  await _cleanupRotatedPublisherClient(bindingKey: bindingKey, newKey: key);

  final _PublisherCacheEntry? cached = _publisherClientCache[key];
  if (cached != null && cached.expiration.isAfter(now)) {
    _publisherCredentialBindings[bindingKey] = key;
    return cached.client;
  }

  final PubSubPublisherClient created = await _publisherFactory(
    credentials: credentials,
    userAgents: userAgents,
    enableMessageOrdering: enableMessageOrdering,
  );
  _publisherClientCache[key] = _PublisherCacheEntry(
    client: created,
    expiration: now.add(_cacheTtl),
  );
  _publisherCredentialBindings[bindingKey] = key;
  return created;
}

Future<PubSubSubscriberClient> getSubscriberClient({
  required Object credentials,
  Object? userAgent,
}) async {
  final DateTime now = DateTime.now().toUtc();
  final List<String> userAgents = _composeUserAgents(userAgent);
  final _CredentialFingerprint fingerprint = _credentialFingerprint(
    credentials,
  );
  final String bindingKey = _subscriberBindingKey(
    sourceFingerprint: fingerprint.source,
    userAgents: userAgents,
  );
  final String key = _subscriberCacheKey(
    bindingKey: bindingKey,
    tokenFingerprint: fingerprint.token,
  );
  await _evictExpiredSubscriberClients(now);
  await _cleanupRotatedSubscriberClient(bindingKey: bindingKey, newKey: key);

  final _SubscriberCacheEntry? cached = _subscriberClientCache[key];
  if (cached != null && cached.expiration.isAfter(now)) {
    _subscriberCredentialBindings[bindingKey] = key;
    return cached.client;
  }

  final PubSubSubscriberClient created = await _subscriberFactory(
    credentials: credentials,
    userAgents: userAgents,
  );
  _subscriberClientCache[key] = _SubscriberCacheEntry(
    client: created,
    expiration: now.add(_cacheTtl),
  );
  _subscriberCredentialBindings[bindingKey] = key;
  return created;
}

void setPubSubClientFactories({
  PubSubPublisherFactory? publisherFactory,
  PubSubSubscriberFactory? subscriberFactory,
}) {
  if (publisherFactory != null) {
    _publisherFactory = publisherFactory;
  }
  if (subscriberFactory != null) {
    _subscriberFactory = subscriberFactory;
  }
}

void resetPubSubClientFactories() {
  _publisherFactory = _defaultPublisherFactory;
  _subscriberFactory = _defaultSubscriberFactory;
}

Future<void> cleanupClients() async {
  final List<Future<void>> closing = <Future<void>>[];
  for (final _PublisherCacheEntry entry in _publisherClientCache.values) {
    closing.add(entry.client.close());
  }
  for (final _SubscriberCacheEntry entry in _subscriberClientCache.values) {
    closing.add(entry.client.close());
  }
  _publisherClientCache.clear();
  _subscriberClientCache.clear();
  _publisherCredentialBindings.clear();
  _subscriberCredentialBindings.clear();
  await Future.wait(closing);
}

Map<String, int> pubSubCacheSizes() {
  return UnmodifiableMapView<String, int>(<String, int>{
    'publisher': _publisherClientCache.length,
    'subscriber': _subscriberClientCache.length,
  });
}

Future<PubSubPublisherClient> _defaultPublisherFactory({
  required Object credentials,
  required List<String> userAgents,
  required bool enableMessageOrdering,
}) async {
  return HttpPubSubPublisherClient(
    accessToken: _extractAccessToken(credentials),
    userAgents: userAgents,
    enableMessageOrdering: enableMessageOrdering,
  );
}

Future<PubSubSubscriberClient> _defaultSubscriberFactory({
  required Object credentials,
  required List<String> userAgents,
}) async {
  return HttpPubSubSubscriberClient(
    accessToken: _extractAccessToken(credentials),
    userAgents: userAgents,
  );
}

String _publisherBindingKey({
  required String sourceFingerprint,
  required List<String> userAgents,
  required bool enableMessageOrdering,
}) {
  final String agentsPart = _fingerprintHash(_stableSerialize(userAgents));
  return '$sourceFingerprint::$agentsPart::$enableMessageOrdering';
}

String _publisherCacheKey({
  required String bindingKey,
  required String tokenFingerprint,
}) {
  return '$bindingKey::$tokenFingerprint';
}

String _subscriberBindingKey({
  required String sourceFingerprint,
  required List<String> userAgents,
}) {
  final String agentsPart = _fingerprintHash(_stableSerialize(userAgents));
  return '$sourceFingerprint::$agentsPart';
}

String _subscriberCacheKey({
  required String bindingKey,
  required String tokenFingerprint,
}) {
  return '$bindingKey::$tokenFingerprint';
}

Future<void> _cleanupRotatedPublisherClient({
  required String bindingKey,
  required String newKey,
}) async {
  final String? existingKey = _publisherCredentialBindings[bindingKey];
  if (existingKey == null || existingKey == newKey) {
    return;
  }
  final _PublisherCacheEntry? stale = _publisherClientCache.remove(existingKey);
  if (stale != null) {
    await stale.client.close();
  }
}

Future<void> _cleanupRotatedSubscriberClient({
  required String bindingKey,
  required String newKey,
}) async {
  final String? existingKey = _subscriberCredentialBindings[bindingKey];
  if (existingKey == null || existingKey == newKey) {
    return;
  }
  final _SubscriberCacheEntry? stale = _subscriberClientCache.remove(
    existingKey,
  );
  if (stale != null) {
    await stale.client.close();
  }
}

Future<void> _evictExpiredPublisherClients(DateTime now) async {
  final List<MapEntry<String, _PublisherCacheEntry>> expired =
      _publisherClientCache.entries
          .where(
            (MapEntry<String, _PublisherCacheEntry> entry) =>
                !entry.value.expiration.isAfter(now),
          )
          .toList(growable: false);
  if (expired.isEmpty) {
    return;
  }

  final Set<String> removedKeys = expired
      .map((MapEntry<String, _PublisherCacheEntry> entry) => entry.key)
      .toSet();
  _publisherCredentialBindings.removeWhere(
    (String _, String cacheKey) => removedKeys.contains(cacheKey),
  );
  for (final MapEntry<String, _PublisherCacheEntry> entry in expired) {
    _publisherClientCache.remove(entry.key);
    await entry.value.client.close();
  }
}

Future<void> _evictExpiredSubscriberClients(DateTime now) async {
  final List<MapEntry<String, _SubscriberCacheEntry>> expired =
      _subscriberClientCache.entries
          .where(
            (MapEntry<String, _SubscriberCacheEntry> entry) =>
                !entry.value.expiration.isAfter(now),
          )
          .toList(growable: false);
  if (expired.isEmpty) {
    return;
  }

  final Set<String> removedKeys = expired
      .map((MapEntry<String, _SubscriberCacheEntry> entry) => entry.key)
      .toSet();
  _subscriberCredentialBindings.removeWhere(
    (String _, String cacheKey) => removedKeys.contains(cacheKey),
  );
  for (final MapEntry<String, _SubscriberCacheEntry> entry in expired) {
    _subscriberClientCache.remove(entry.key);
    await entry.value.client.close();
  }
}

class _CredentialFingerprint {
  _CredentialFingerprint({required this.source, required this.token});

  final String source;
  final String token;
}

_CredentialFingerprint _credentialFingerprint(Object credentials) {
  final String token = _credentialToken(credentials);
  final Object sourceObject = _credentialSource(credentials, token);
  return _CredentialFingerprint(
    source: _fingerprintHash(_stableSerialize(sourceObject)),
    token: _fingerprintHash(token),
  );
}

String _credentialToken(Object credentials) {
  if (credentials is GoogleOAuthCredential) {
    return credentials.accessToken;
  }
  if (credentials is AuthCredential) {
    return credentials.oauth2?.accessToken ?? '';
  }
  if (credentials is Map) {
    final Object? snake = credentials['access_token'];
    final String snakeToken = _asString(snake);
    if (snakeToken.isNotEmpty) {
      return snakeToken;
    }
    final Object? camel = credentials['accessToken'];
    final String camelToken = _asString(camel);
    if (camelToken.isNotEmpty) {
      return camelToken;
    }
    final Object? oauth2 = credentials['oauth2'];
    if (oauth2 is Map) {
      final Object? nestedSnake = oauth2['access_token'];
      final String nestedSnakeToken = _asString(nestedSnake);
      if (nestedSnakeToken.isNotEmpty) {
        return nestedSnakeToken;
      }
      final Object? nestedCamel = oauth2['accessToken'];
      final String nestedCamelToken = _asString(nestedCamel);
      if (nestedCamelToken.isNotEmpty) {
        return nestedCamelToken;
      }
    }
  }
  if (credentials is String) {
    return credentials;
  }
  try {
    final dynamic dynamicCredential = credentials;
    final Object? token = dynamicCredential.accessToken;
    if (token is String && token.isNotEmpty) {
      return token;
    }
  } catch (_) {
    // Ignore dynamic access failures.
  }
  return '';
}

Object _credentialSource(Object credentials, String token) {
  if (credentials is GoogleOAuthCredential) {
    final Map<String, Object?> source = <String, Object?>{
      'type': 'GoogleOAuthCredential',
      'refresh_token': credentials.refreshToken ?? '',
      'client_id': credentials.clientId ?? '',
      'client_secret': credentials.clientSecret ?? '',
      'scopes': List<String>.from(credentials.scopes),
      'expires_at': credentials.expiresAt,
      'expires_in': credentials.expiresIn,
    };
    if (_isEmptySource(source)) {
      source['fallback_access_token'] = token;
    }
    return source;
  }

  if (credentials is AuthCredential) {
    final OAuth2Auth? oauth2 = credentials.oauth2;
    final Map<String, Object?> source = <String, Object?>{
      'type': 'AuthCredential',
      'auth_type': credentials.authType.name,
      'refresh_token': oauth2?.refreshToken ?? '',
      'client_id': oauth2?.clientId ?? '',
      'client_secret': oauth2?.clientSecret ?? '',
      'expires_at': oauth2?.expiresAt,
      'expires_in': oauth2?.expiresIn,
    };
    if (_isEmptySource(source)) {
      source['fallback_access_token'] = token;
    }
    return source;
  }

  if (credentials is Map) {
    final Map<String, Object?> source = _removeAccessTokenFields(credentials);
    if (source.isEmpty) {
      return <String, Object?>{'type': 'Map', 'fallback_access_token': token};
    }
    return <String, Object?>{'type': 'Map', 'payload': source};
  }

  if (credentials is String) {
    return <String, Object?>{'type': 'String', 'value': credentials};
  }

  try {
    final dynamic dynamicCredential = credentials;
    final List<Object?> scopes =
        (dynamicCredential.scopes as List?) ?? <Object?>[];
    final Map<String, Object?> source = <String, Object?>{
      'type': '${credentials.runtimeType}',
      'refresh_token': '${dynamicCredential.refreshToken ?? ''}',
      'client_id': '${dynamicCredential.clientId ?? ''}',
      'client_secret': '${dynamicCredential.clientSecret ?? ''}',
      'scopes': scopes.map((Object? value) => '$value').toList(),
      'expires_at': dynamicCredential.expiresAt,
      'expires_in': dynamicCredential.expiresIn,
    };
    if (_isEmptySource(source)) {
      source['fallback_access_token'] = token;
      source['fallback_value'] = '$credentials';
    }
    return source;
  } catch (_) {
    return <String, Object?>{
      'type': '${credentials.runtimeType}',
      'value': '$credentials',
      'token': token,
    };
  }
}

bool _isEmptySource(Map<String, Object?> source) {
  for (final MapEntry<String, Object?> entry in source.entries) {
    if (entry.key == 'type') {
      continue;
    }
    final Object? value = entry.value;
    if (value == null) {
      continue;
    }
    if (value is String && value.isEmpty) {
      continue;
    }
    if (value is Iterable && value.isEmpty) {
      continue;
    }
    return false;
  }
  return true;
}

Map<String, Object?> _removeAccessTokenFields(Map credentials) {
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<dynamic, dynamic> entry in credentials.entries) {
    final String key = '${entry.key}';
    if (key == 'access_token' || key == 'accessToken') {
      continue;
    }
    final Object? value = entry.value;
    if (value is Map) {
      result[key] = _removeAccessTokenFields(value);
      continue;
    }
    if (value is Iterable) {
      result[key] = value.map<Object?>((Object? item) {
        if (item is Map) {
          return _removeAccessTokenFields(item);
        }
        return item;
      }).toList();
      continue;
    }
    result[key] = value;
  }
  return result;
}

String _fingerprintHash(String input) {
  const int offset = 0x811c9dc5;
  const int prime = 0x01000193;
  int hash = offset;
  for (final int byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _stableSerialize(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return jsonEncode(value);
  }
  if (value is num || value is bool) {
    return '$value';
  }
  if (value is Iterable) {
    return '[${value.map<String>(_stableSerialize).join(',')}]';
  }
  if (value is Map) {
    final List<MapEntry<String, Object?>> entries =
        value.entries
            .map(
              (MapEntry<Object?, Object?> entry) =>
                  MapEntry<String, Object?>('${entry.key}', entry.value),
            )
            .toList(growable: false)
          ..sort(
            (MapEntry<String, Object?> a, MapEntry<String, Object?> b) =>
                a.key.compareTo(b.key),
          );
    return '{${entries.map<String>((MapEntry<String, Object?> entry) {
      return '${jsonEncode(entry.key)}:${_stableSerialize(entry.value)}';
    }).join(',')}}';
  }
  return jsonEncode('$value');
}

List<String> _composeUserAgents(Object? userAgent) {
  final List<String> merged = <String>[pubSubUserAgent];
  if (userAgent == null) {
    return merged;
  }
  if (userAgent is String) {
    if (userAgent.isNotEmpty) {
      merged.add(userAgent);
    }
    return merged;
  }
  if (userAgent is Iterable) {
    for (final Object? item in userAgent) {
      if (item == null) {
        continue;
      }
      final String value = '$item';
      if (value.isNotEmpty) {
        merged.add(value);
      }
    }
    return merged;
  }
  final String single = '$userAgent';
  if (single.isNotEmpty) {
    merged.add(single);
  }
  return merged;
}

String _extractAccessToken(Object credentials) {
  if (credentials is GoogleOAuthCredential &&
      credentials.accessToken.isNotEmpty) {
    return credentials.accessToken;
  }

  if (credentials is AuthCredential) {
    final String token = credentials.oauth2?.accessToken ?? '';
    if (token.isNotEmpty) {
      return token;
    }
  }

  if (credentials is Map) {
    final Object? snakeCase = credentials['access_token'];
    if (_asString(snakeCase).isNotEmpty) {
      return _asString(snakeCase);
    }
    final Object? camelCase = credentials['accessToken'];
    if (_asString(camelCase).isNotEmpty) {
      return _asString(camelCase);
    }
  }

  if (credentials is String && credentials.isNotEmpty) {
    return credentials;
  }

  try {
    final dynamic dynamicCredential = credentials;
    final Object? token = dynamicCredential.accessToken;
    if (token is String && token.isNotEmpty) {
      return token;
    }
  } catch (_) {
    // Ignore dynamic access failures.
  }

  throw ArgumentError(
    'Pub/Sub credentials must provide a non-empty access token.',
  );
}

Future<Map<String, Object?>> _postJson({
  required Uri uri,
  required String accessToken,
  required List<String> userAgents,
  required Map<String, Object?> body,
  required HttpClient Function() httpClientFactory,
}) async {
  final HttpClient httpClient = httpClientFactory();
  try {
    final HttpClientRequest request = await httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (userAgents.isNotEmpty) {
      request.headers.set(HttpHeaders.userAgentHeader, userAgents.join(' '));
    }
    request.write(jsonEncode(body));
    final HttpClientResponse response = await request.close();
    final String responseBody = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Pub/Sub API request failed (${response.statusCode}): $responseBody',
        uri: uri,
      );
    }
    if (responseBody.isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(responseBody);
    return _asMap(decoded);
  } finally {
    httpClient.close(force: true);
  }
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry<String, Object?>('$key', item),
    );
  }
  return <String, Object?>{};
}

String _asString(Object? value) {
  if (value == null) {
    return '';
  }
  return '$value';
}

Map<String, String> _asStringMap(Object? value) {
  final Map<String, Object?> source = _asMap(value);
  return source.map(
    (String key, Object? item) => MapEntry<String, String>(key, '$item'),
  );
}

List<int> _decodeData(String encoded) {
  if (encoded.isEmpty) {
    return const <int>[];
  }
  try {
    return base64Decode(encoded);
  } catch (_) {
    return utf8.encode(encoded);
  }
}

DateTime _parsePublishTime(Object? value) {
  final String parsed = _asString(value);
  if (parsed.isEmpty) {
    return DateTime.now().toUtc();
  }
  try {
    return DateTime.parse(parsed).toUtc();
  } catch (_) {
    return DateTime.now().toUtc();
  }
}
