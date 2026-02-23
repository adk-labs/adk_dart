import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakePublisherClient implements PubSubPublisherClient {
  _FakePublisherClient({this.throwOnPublish = false, this.messageId = 'm-1'});

  final bool throwOnPublish;
  final String messageId;
  final List<Map<String, Object?>> published = <Map<String, Object?>>[];
  int closeCount = 0;

  @override
  Future<String> publish({
    required String topicName,
    required List<int> data,
    Map<String, String>? attributes,
    String orderingKey = '',
  }) async {
    if (throwOnPublish) {
      throw StateError('publish failed');
    }
    published.add(<String, Object?>{
      'topic_name': topicName,
      'data': data,
      'attributes': attributes ?? <String, String>{},
      'ordering_key': orderingKey,
    });
    return messageId;
  }

  @override
  Future<void> close() async {
    closeCount += 1;
  }
}

class _FakeSubscriberClient implements PubSubSubscriberClient {
  _FakeSubscriberClient({
    List<PulledPubSubMessage>? pulledMessages,
    this.throwOnPull = false,
    this.throwOnAcknowledge = false,
  }) : pulledMessages = pulledMessages ?? <PulledPubSubMessage>[];

  final List<PulledPubSubMessage> pulledMessages;
  final bool throwOnPull;
  final bool throwOnAcknowledge;
  final List<Map<String, Object?>> acknowledgeCalls = <Map<String, Object?>>[];
  int closeCount = 0;

  @override
  Future<void> acknowledge({
    required String subscriptionName,
    required List<String> ackIds,
  }) async {
    if (throwOnAcknowledge) {
      throw StateError('ack failed');
    }
    acknowledgeCalls.add(<String, Object?>{
      'subscription_name': subscriptionName,
      'ack_ids': List<String>.from(ackIds),
    });
  }

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<List<PulledPubSubMessage>> pull({
    required String subscriptionName,
    required int maxMessages,
  }) async {
    if (throwOnPull) {
      throw StateError('pull failed');
    }
    return pulledMessages.take(maxMessages).toList();
  }
}

Context _newToolContext({String? functionCallId, Map<String, Object?>? state}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_pubsub',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_pubsub',
      appName: 'app',
      userId: 'u1',
      state: state ?? <String, Object?>{},
    ),
  );
  return Context(invocationContext, functionCallId: functionCallId);
}

void main() {
  tearDown(() async {
    await cleanupClients();
    resetPubSubClientFactories();
  });

  group('pubsub config parity', () {
    test('supports default and strict fields', () {
      final PubSubToolConfig empty = PubSubToolConfig.fromObject(null);
      expect(empty.projectId, isNull);

      final PubSubToolConfig snake = PubSubToolConfig.fromJson(
        <String, Object?>{'project_id': 'p1'},
      );
      expect(snake.projectId, 'p1');
      expect(snake.toJson()['project_id'], 'p1');

      expect(
        () => PubSubToolConfig.fromJson(<String, Object?>{'unknown': 'x'}),
        throwsArgumentError,
      );
    });
  });

  group('pubsub client parity', () {
    test('caches publisher/subscriber clients and cleans up', () async {
      int publisherCreations = 0;
      int subscriberCreations = 0;
      final _FakePublisherClient publisher = _FakePublisherClient();
      final _FakeSubscriberClient subscriber = _FakeSubscriberClient();

      setPubSubClientFactories(
        publisherFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
              required bool enableMessageOrdering,
            }) async {
              publisherCreations += 1;
              expect(userAgents.first, pubSubUserAgent);
              return publisher;
            },
        subscriberFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
            }) async {
              subscriberCreations += 1;
              expect(userAgents.first, pubSubUserAgent);
              return subscriber;
            },
      );

      final Object credentialRef = Object();
      final PubSubPublisherClient publisher1 = await getPublisherClient(
        credentials: credentialRef,
        userAgent: <String>['ua'],
      );
      final PubSubPublisherClient publisher2 = await getPublisherClient(
        credentials: credentialRef,
        userAgent: <String>['ua'],
      );
      final PubSubSubscriberClient subscriber1 = await getSubscriberClient(
        credentials: credentialRef,
      );
      final PubSubSubscriberClient subscriber2 = await getSubscriberClient(
        credentials: credentialRef,
      );

      expect(identical(publisher1, publisher2), isTrue);
      expect(identical(subscriber1, subscriber2), isTrue);
      expect(publisherCreations, 1);
      expect(subscriberCreations, 1);
      expect(pubSubCacheSizes(), <String, int>{
        'publisher': 1,
        'subscriber': 1,
      });

      await cleanupClients();
      expect(publisher.closeCount, 1);
      expect(subscriber.closeCount, 1);
      expect(pubSubCacheSizes(), <String, int>{
        'publisher': 0,
        'subscriber': 0,
      });
    });

    test('default factory requires access token in credentials', () async {
      await expectLater(
        () => getPublisherClient(credentials: Object()),
        throwsArgumentError,
      );
      await expectLater(
        () => getSubscriberClient(credentials: <String, Object?>{}),
        throwsArgumentError,
      );
    });
  });

  group('pubsub http client parity', () {
    test(
      'publisher client sends publish request and parses message id',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await server.close(force: true);
        });

        final Completer<void> handled = Completer<void>();
        unawaited(() async {
          await for (final HttpRequest request in server) {
            expect(request.method, 'POST');
            expect(request.uri.path, '/v1/projects/p/topics/t1:publish');
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              'Bearer token-123',
            );
            expect(
              request.headers.value(HttpHeaders.userAgentHeader),
              contains('pubsub-test'),
            );
            final Object? payload = jsonDecode(
              await utf8.decodeStream(request),
            );
            expect(payload, isA<Map>());
            final List<Object?> messages =
                ((payload as Map)['messages'] as List).cast<Object?>();
            final Map message = messages.single as Map;
            expect(message['orderingKey'], 'order-1');
            expect(message['attributes'], <String, String>{'k': 'v'});

            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, Object?>{
                'messageIds': <String>['m-http-1'],
              }),
            );
            await request.response.close();
            handled.complete();
            break;
          }
        }());

        final HttpPubSubPublisherClient client = HttpPubSubPublisherClient(
          accessToken: 'token-123',
          userAgents: <String>['pubsub-test'],
          enableMessageOrdering: true,
          apiBaseUrl: 'http://${server.address.host}:${server.port}/v1',
        );

        final String messageId = await client.publish(
          topicName: 'projects/p/topics/t1',
          data: utf8.encode('hello'),
          attributes: <String, String>{'k': 'v'},
          orderingKey: 'order-1',
        );

        expect(messageId, 'm-http-1');
        await handled.future.timeout(const Duration(seconds: 2));
      },
    );

    test('subscriber client pulls and acknowledges via REST', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      int calls = 0;
      final Completer<void> handled = Completer<void>();
      unawaited(() async {
        await for (final HttpRequest request in server) {
          calls += 1;
          expect(request.method, 'POST');
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer token-xyz',
          );

          if (request.uri.path.endsWith(':pull')) {
            final Object? payload = jsonDecode(
              await utf8.decodeStream(request),
            );
            expect((payload as Map)['maxMessages'], 2);
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(<String, Object?>{
                'receivedMessages': <Object?>[
                  <String, Object?>{
                    'ackId': 'ack-1',
                    'message': <String, Object?>{
                      'messageId': 'm-1',
                      'data': base64Encode(utf8.encode('hello')),
                      'attributes': <String, String>{'a': '1'},
                      'orderingKey': 'o-1',
                      'publishTime': '2026-02-23T10:00:00Z',
                    },
                  },
                ],
              }),
            );
            await request.response.close();
            continue;
          }

          if (request.uri.path.endsWith(':acknowledge')) {
            final Object? payload = jsonDecode(
              await utf8.decodeStream(request),
            );
            expect((payload as Map)['ackIds'], <String>['ack-1']);
            request.response.headers.contentType = ContentType.json;
            request.response.write('{}');
            await request.response.close();
            if (calls >= 2) {
              handled.complete();
            }
            break;
          }
        }
      }());

      final HttpPubSubSubscriberClient client = HttpPubSubSubscriberClient(
        accessToken: 'token-xyz',
        userAgents: <String>['pubsub-test'],
        apiBaseUrl: 'http://${server.address.host}:${server.port}/v1',
      );

      final List<PulledPubSubMessage> pulled = await client.pull(
        subscriptionName: 'projects/p/subscriptions/s1',
        maxMessages: 2,
      );
      expect(pulled, hasLength(1));
      expect(pulled.single.messageId, 'm-1');
      expect(utf8.decode(pulled.single.data), 'hello');
      expect(pulled.single.attributes, <String, String>{'a': '1'});
      expect(pulled.single.orderingKey, 'o-1');

      await client.acknowledge(
        subscriptionName: 'projects/p/subscriptions/s1',
        ackIds: <String>['ack-1'],
      );
      await handled.future.timeout(const Duration(seconds: 2));
    });
  });

  group('pubsub message tool parity', () {
    test('publish_message publishes payload and returns message_id', () async {
      final _FakePublisherClient publisher = _FakePublisherClient(
        messageId: 'm-42',
      );
      setPubSubClientFactories(
        publisherFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
              required bool enableMessageOrdering,
            }) async {
              expect(enableMessageOrdering, isTrue);
              expect(userAgents, contains('project-x'));
              expect(userAgents, contains('publish_message'));
              return publisher;
            },
      );

      final Map<String, Object?> result = await publishMessage(
        topicName: 'projects/p/topics/t1',
        message: 'hello',
        credentials: GoogleOAuthCredential(accessToken: 'token'),
        settings: PubSubToolConfig(projectId: 'project-x'),
        attributes: <String, String>{'k': 'v'},
        orderingKey: 'order-1',
      );

      expect(result['message_id'], 'm-42');
      expect(publisher.published, hasLength(1));
      expect(publisher.published.single['ordering_key'], 'order-1');
      expect(
        utf8.decode((publisher.published.single['data'] as List).cast<int>()),
        'hello',
      );
    });

    test('publish_message returns ERROR when client throws', () async {
      setPubSubClientFactories(
        publisherFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
              required bool enableMessageOrdering,
            }) async {
              return _FakePublisherClient(throwOnPublish: true);
            },
      );

      final Map<String, Object?> result = await publishMessage(
        topicName: 'projects/p/topics/t1',
        message: 'hello',
        credentials: GoogleOAuthCredential(accessToken: 'token'),
        settings: PubSubToolConfig(),
      );
      expect(result['status'], 'ERROR');
      expect(
        '${result['error_details']}',
        contains('Failed to publish message'),
      );
    });

    test('pull_messages decodes message payloads and auto-acks', () async {
      final _FakeSubscriberClient subscriber = _FakeSubscriberClient(
        pulledMessages: <PulledPubSubMessage>[
          PulledPubSubMessage(
            messageId: 'm1',
            data: utf8.encode('hello'),
            attributes: <String, String>{'a': '1'},
            orderingKey: 'key-1',
            publishTime: DateTime.utc(2026, 2, 23, 10, 0, 0),
            ackId: 'ack-1',
          ),
          PulledPubSubMessage(
            messageId: 'm2',
            data: <int>[0x80, 0x81],
            publishTime: DateTime.utc(2026, 2, 23, 10, 0, 1),
            ackId: 'ack-2',
          ),
        ],
      );
      setPubSubClientFactories(
        subscriberFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
            }) async {
              expect(userAgents, contains('pull_messages'));
              return subscriber;
            },
      );

      final Map<String, Object?> result = await pullMessages(
        subscriptionName: 'projects/p/subscriptions/s1',
        credentials: GoogleOAuthCredential(accessToken: 'token'),
        settings: PubSubToolConfig(projectId: 'project-y'),
        maxMessages: 2,
        autoAck: true,
      );

      expect(result['messages'], isA<List>());
      final List<Object?> messages = (result['messages'] as List)
          .cast<Object?>();
      expect(messages, hasLength(2));
      expect((messages[0] as Map)['data'], 'hello');
      expect((messages[1] as Map)['data'], base64Encode(<int>[0x80, 0x81]));
      expect(subscriber.acknowledgeCalls, hasLength(1));
      expect(subscriber.acknowledgeCalls.single['ack_ids'], <String>[
        'ack-1',
        'ack-2',
      ]);
    });

    test('pull_messages returns ERROR when subscriber pull fails', () async {
      setPubSubClientFactories(
        subscriberFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
            }) async {
              return _FakeSubscriberClient(throwOnPull: true);
            },
      );

      final Map<String, Object?> result = await pullMessages(
        subscriptionName: 'projects/p/subscriptions/s1',
        credentials: GoogleOAuthCredential(accessToken: 'token'),
        settings: PubSubToolConfig(),
      );
      expect(result['status'], 'ERROR');
      expect('${result['error_details']}', contains('Failed to pull messages'));
    });

    test('acknowledge_messages returns SUCCESS and handles failures', () async {
      final _FakeSubscriberClient okSubscriber = _FakeSubscriberClient();
      setPubSubClientFactories(
        subscriberFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
            }) async {
              return okSubscriber;
            },
      );
      final Map<String, Object?> ok = await acknowledgeMessages(
        subscriptionName: 'projects/p/subscriptions/s1',
        ackIds: <String>['ack-1'],
        credentials: GoogleOAuthCredential(accessToken: 'token'),
        settings: PubSubToolConfig(),
      );
      expect(ok['status'], 'SUCCESS');

      await cleanupClients();
      setPubSubClientFactories(
        subscriberFactory:
            ({
              required Object credentials,
              required List<String> userAgents,
            }) async {
              return _FakeSubscriberClient(throwOnAcknowledge: true);
            },
      );
      final Map<String, Object?> failed = await acknowledgeMessages(
        subscriptionName: 'projects/p/subscriptions/s1',
        ackIds: <String>['ack-1'],
        credentials: GoogleOAuthCredential(accessToken: 'token'),
        settings: PubSubToolConfig(),
      );
      expect(failed['status'], 'ERROR');
      expect('${failed['error_details']}', contains('Failed to acknowledge'));
    });
  });

  group('pubsub toolset parity', () {
    test('returns tools and supports name-based filter', () async {
      final PubSubToolset all = PubSubToolset();
      final List<BaseTool> allTools = await all.getTools();
      expect(allTools.map((BaseTool tool) => tool.name).toSet(), <String>{
        'publish_message',
        'pull_messages',
        'acknowledge_messages',
      });

      final PubSubToolset filtered = PubSubToolset(
        toolFilter: <String>['pull_messages'],
      );
      final List<BaseTool> filteredTools = await filtered.getTools();
      expect(filteredTools, hasLength(1));
      expect(filteredTools.single.name, 'pull_messages');
    });

    test(
      'GoogleTool bridge injects credentials/settings for pull_messages',
      () async {
        final _FakeSubscriberClient subscriber = _FakeSubscriberClient(
          pulledMessages: <PulledPubSubMessage>[
            PulledPubSubMessage(
              messageId: 'm1',
              data: utf8.encode('bridge'),
              ackId: 'ack-1',
            ),
          ],
        );
        setPubSubClientFactories(
          subscriberFactory:
              ({
                required Object credentials,
                required List<String> userAgents,
              }) async {
                expect(credentials, isA<GoogleOAuthCredential>());
                expect(userAgents, contains('bridge-project'));
                return subscriber;
              },
        );

        final PubSubToolset toolset = PubSubToolset(
          credentialsConfig: PubSubCredentialsConfig(
            externalAccessTokenKey: 'external_token',
          ),
          pubsubToolConfig: PubSubToolConfig(projectId: 'bridge-project'),
        );
        final BaseTool pullTool = (await toolset.getTools()).singleWhere(
          (BaseTool tool) => tool.name == 'pull_messages',
        );

        final Object? response = await pullTool.run(
          args: <String, dynamic>{
            'subscriptionName': 'projects/p/subscriptions/s1',
            'maxMessages': 1,
          },
          toolContext: _newToolContext(
            state: <String, Object?>{'external_token': 'token-bridge'},
          ),
        );
        final Map<String, Object?> payload = response! as Map<String, Object?>;
        expect((payload['messages'] as List).length, 1);
        expect(((payload['messages'] as List).first as Map)['data'], 'bridge');
      },
    );
  });
}
