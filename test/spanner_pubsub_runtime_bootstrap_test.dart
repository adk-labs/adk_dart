import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RuntimeFakeSpannerClient implements SpannerClient {
  @override
  String userAgent = '';

  @override
  SpannerInstance instance(String instanceId) {
    throw StateError('Not used in runtime bootstrap tests.');
  }
}

class _RuntimeFakeSpannerAdminClient implements SpannerAdminClient {
  @override
  Future<void> createDatabase({
    required String instanceId,
    required String databaseId,
  }) async {}

  @override
  Future<void> createInstance({
    required String instanceId,
    required String configId,
    required String displayName,
    int nodes = 1,
  }) async {}

  @override
  Map<String, Object?> getInstance(String instanceId) => <String, Object?>{};

  @override
  Map<String, Object?> getInstanceConfig(String configId) =>
      <String, Object?>{};

  @override
  Iterable<String> listDatabases(String instanceId) sync* {}

  @override
  Iterable<String> listInstanceConfigs() sync* {}

  @override
  Iterable<String> listInstances() sync* {}

  @override
  String userAgent = '';
}

class _RuntimeFakePublisherClient implements PubSubPublisherClient {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<String> publish({
    required String topicName,
    required List<int> data,
    Map<String, String>? attributes,
    String orderingKey = '',
  }) async {
    return 'msg-1';
  }
}

class _RuntimeFakeSubscriberClient implements PubSubSubscriberClient {
  int closeCount = 0;

  @override
  Future<void> acknowledge({
    required String subscriptionName,
    required List<String> ackIds,
  }) async {}

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<List<PulledPubSubMessage>> pull({
    required String subscriptionName,
    required int maxMessages,
  }) async {
    return <PulledPubSubMessage>[];
  }
}

void main() {
  setUp(() async {
    await resetSpannerPubSubRuntime();
  });

  tearDown(() async {
    await resetSpannerPubSubRuntime();
  });

  test('configure and reset helpers wire runtime factories together', () async {
    final _RuntimeFakeSpannerClient spannerClient = _RuntimeFakeSpannerClient();
    final _RuntimeFakeSpannerAdminClient spannerAdminClient =
        _RuntimeFakeSpannerAdminClient();
    final _RuntimeFakePublisherClient publisherClient =
        _RuntimeFakePublisherClient();
    final _RuntimeFakeSubscriberClient subscriberClient =
        _RuntimeFakeSubscriberClient();

    configureSpannerPubSubRuntime(
      spannerAdminClientFactory:
          ({required String project, required Object credentials}) {
            expect(project, 'proj-1');
            return spannerAdminClient;
          },
      spannerClientFactory:
          ({required String project, required Object credentials}) {
            expect(project, 'proj-1');
            return spannerClient;
          },
      spannerEmbedder:
          ({
            required String vertexAiEmbeddingModelName,
            required List<String> contents,
            int? outputDimensionality,
            Object? genAiClient,
          }) {
            return <List<double>>[
              <double>[1.0, 2.0],
            ];
          },
      pubSubPublisherFactory:
          ({
            required Object credentials,
            required List<String> userAgents,
            required bool enableMessageOrdering,
          }) async {
            return publisherClient;
          },
      pubSubSubscriberFactory:
          ({
            required Object credentials,
            required List<String> userAgents,
          }) async {
            return subscriberClient;
          },
    );

    final SpannerClient resolvedSpannerClient = getSpannerClient(
      project: 'proj-1',
      credentials: Object(),
    );
    final SpannerAdminClient resolvedSpannerAdminClient = getSpannerAdminClient(
      project: 'proj-1',
      credentials: Object(),
    );
    expect(identical(resolvedSpannerClient, spannerClient), isTrue);
    expect(resolvedSpannerClient.userAgent, spannerUserAgent);
    expect(identical(resolvedSpannerAdminClient, spannerAdminClient), isTrue);
    expect(resolvedSpannerAdminClient.userAgent, spannerAdminUserAgent);

    final PubSubPublisherClient resolvedPublisher = await getPublisherClient(
      credentials: <String, Object?>{'access_token': 'token-1'},
      userAgent: 'runtime-test',
    );
    final PubSubSubscriberClient resolvedSubscriber = await getSubscriberClient(
      credentials: <String, Object?>{'access_token': 'token-1'},
      userAgent: 'runtime-test',
    );

    expect(identical(resolvedPublisher, publisherClient), isTrue);
    expect(identical(resolvedSubscriber, subscriberClient), isTrue);
    expect(pubSubCacheSizes(), <String, int>{'publisher': 1, 'subscriber': 1});

    final List<List<double>> embedding = embedContents(
      vertexAiEmbeddingModelName: 'text-embedding-005',
      contents: <String>['hello world'],
    );
    expect(embedding, <List<double>>[
      <double>[1.0, 2.0],
    ]);

    await resetSpannerPubSubRuntime();

    expect(publisherClient.closeCount, 1);
    expect(subscriberClient.closeCount, 1);
    expect(pubSubCacheSizes(), <String, int>{'publisher': 0, 'subscriber': 0});
    final SpannerClient defaultSpannerClient = getSpannerClient(
      project: 'proj-1',
      credentials: <String, Object?>{'access_token': 'token-reset'},
    );
    final SpannerAdminClient defaultSpannerAdminClient = getSpannerAdminClient(
      project: 'proj-1',
      credentials: <String, Object?>{'access_token': 'token-reset'},
    );
    expect(
      defaultSpannerClient.runtimeType.toString().toLowerCase(),
      contains('spanner'),
    );
    expect(defaultSpannerClient.userAgent, spannerUserAgent);
    expect(
      defaultSpannerAdminClient.runtimeType.toString().toLowerCase(),
      contains('spanner'),
    );
    expect(defaultSpannerAdminClient.userAgent, spannerAdminUserAgent);
    expect(
      () => embedContents(
        vertexAiEmbeddingModelName: 'text-embedding-005',
        contents: <String>['hello world'],
      ),
      throwsA(isA<SpannerEmbedderNotConfiguredException>()),
    );
  });

  test('reset helper can skip pubsub client cleanup', () async {
    final _RuntimeFakePublisherClient publisherClient =
        _RuntimeFakePublisherClient();
    final _RuntimeFakeSubscriberClient subscriberClient =
        _RuntimeFakeSubscriberClient();

    configureSpannerPubSubRuntime(
      pubSubPublisherFactory:
          ({
            required Object credentials,
            required List<String> userAgents,
            required bool enableMessageOrdering,
          }) async {
            return publisherClient;
          },
      pubSubSubscriberFactory:
          ({
            required Object credentials,
            required List<String> userAgents,
          }) async {
            return subscriberClient;
          },
    );

    await getPublisherClient(
      credentials: <String, Object?>{'access_token': 'token-2'},
    );
    await getSubscriberClient(
      credentials: <String, Object?>{'access_token': 'token-2'},
    );

    await resetSpannerPubSubRuntime(cleanupPubSubClients: false);

    expect(publisherClient.closeCount, 0);
    expect(subscriberClient.closeCount, 0);
    expect(pubSubCacheSizes(), <String, int>{'publisher': 1, 'subscriber': 1});

    await cleanupClients();

    expect(publisherClient.closeCount, 1);
    expect(subscriberClient.closeCount, 1);
    expect(pubSubCacheSizes(), <String, int>{'publisher': 0, 'subscriber': 0});
  });
}
