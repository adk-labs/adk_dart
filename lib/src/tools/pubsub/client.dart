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

Future<PubSubPublisherClient> getPublisherClient({
  required Object credentials,
  Object? userAgent,
  bool enableMessageOrdering = false,
}) async {
  final DateTime now = DateTime.now().toUtc();
  final List<String> userAgents = _composeUserAgents(userAgent);
  final String key = _publisherCacheKey(
    credentials: credentials,
    userAgents: userAgents,
    enableMessageOrdering: enableMessageOrdering,
  );

  final _PublisherCacheEntry? cached = _publisherClientCache[key];
  if (cached != null && cached.expiration.isAfter(now)) {
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
  return created;
}

Future<PubSubSubscriberClient> getSubscriberClient({
  required Object credentials,
  Object? userAgent,
}) async {
  final DateTime now = DateTime.now().toUtc();
  final List<String> userAgents = _composeUserAgents(userAgent);
  final String key = _subscriberCacheKey(
    credentials: credentials,
    userAgents: userAgents,
  );

  final _SubscriberCacheEntry? cached = _subscriberClientCache[key];
  if (cached != null && cached.expiration.isAfter(now)) {
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

String _publisherCacheKey({
  required Object credentials,
  required List<String> userAgents,
  required bool enableMessageOrdering,
}) {
  final String idPart = identityHashCode(credentials).toString();
  final String agentsPart = userAgents.join('|');
  return '$idPart::$agentsPart::$enableMessageOrdering';
}

String _subscriberCacheKey({
  required Object credentials,
  required List<String> userAgents,
}) {
  final String idPart = identityHashCode(credentials).toString();
  final String agentsPart = userAgents.join('|');
  return '$idPart::$agentsPart';
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
