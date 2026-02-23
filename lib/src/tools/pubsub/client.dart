import 'dart:collection';

import '../../version.dart';

const String pubSubUserAgent = 'adk-pubsub-tool google-adk/$adkVersion';
const Duration _cacheTtl = Duration(minutes: 30);

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
}) {
  throw UnsupportedError(
    'No default Pub/Sub publisher client is available in adk_dart. '
    'Inject a publisher factory with setPubSubClientFactories().',
  );
}

Future<PubSubSubscriberClient> _defaultSubscriberFactory({
  required Object credentials,
  required List<String> userAgents,
}) {
  throw UnsupportedError(
    'No default Pub/Sub subscriber client is available in adk_dart. '
    'Inject a subscriber factory with setPubSubClientFactories().',
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
