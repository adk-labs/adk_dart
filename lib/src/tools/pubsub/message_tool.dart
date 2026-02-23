import 'dart:convert';

import '../tool_context.dart';
import 'client.dart';
import 'config.dart';

Future<Map<String, Object?>> publishMessage({
  required String topicName,
  required String message,
  required Object credentials,
  required Object settings,
  Map<String, String>? attributes,
  String orderingKey = '',
  ToolContext? toolContext,
}) async {
  try {
    final PubSubToolConfig config = PubSubToolConfig.fromObject(settings);
    final PubSubPublisherClient publisherClient = await getPublisherClient(
      credentials: credentials,
      userAgent: <String?>[config.projectId, 'publish_message'],
      enableMessageOrdering: orderingKey.isNotEmpty,
    );
    final String messageId = await publisherClient.publish(
      topicName: topicName,
      data: utf8.encode(message),
      orderingKey: orderingKey,
      attributes: attributes,
    );
    return <String, Object?>{'message_id': messageId};
  } catch (error) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details':
          "Failed to publish message to topic '$topicName': $error",
    };
  }
}

String _decodeMessageData(List<int> data) {
  try {
    return utf8.decode(data);
  } catch (_) {
    return base64Encode(data);
  }
}

Future<Map<String, Object?>> pullMessages({
  required String subscriptionName,
  required Object credentials,
  required Object settings,
  int maxMessages = 1,
  bool autoAck = false,
  ToolContext? toolContext,
}) async {
  try {
    final PubSubToolConfig config = PubSubToolConfig.fromObject(settings);
    final PubSubSubscriberClient subscriberClient = await getSubscriberClient(
      credentials: credentials,
      userAgent: <String?>[config.projectId, 'pull_messages'],
    );
    final List<PulledPubSubMessage> received = await subscriberClient.pull(
      subscriptionName: subscriptionName,
      maxMessages: maxMessages,
    );

    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    final List<String> ackIds = <String>[];
    for (final PulledPubSubMessage message in received) {
      messages.add(<String, Object?>{
        'message_id': message.messageId,
        'data': _decodeMessageData(message.data),
        'attributes': Map<String, String>.from(message.attributes),
        'ordering_key': message.orderingKey,
        'publish_time': message.publishTime.toUtc().toIso8601String(),
        'ack_id': message.ackId,
      });
      ackIds.add(message.ackId);
    }

    if (autoAck && ackIds.isNotEmpty) {
      await subscriberClient.acknowledge(
        subscriptionName: subscriptionName,
        ackIds: ackIds,
      );
    }

    return <String, Object?>{'messages': messages};
  } catch (error) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details':
          "Failed to pull messages from subscription '$subscriptionName': $error",
    };
  }
}

Future<Map<String, Object?>> acknowledgeMessages({
  required String subscriptionName,
  required List<String> ackIds,
  required Object credentials,
  required Object settings,
  ToolContext? toolContext,
}) async {
  try {
    final PubSubToolConfig config = PubSubToolConfig.fromObject(settings);
    final PubSubSubscriberClient subscriberClient = await getSubscriberClient(
      credentials: credentials,
      userAgent: <String?>[config.projectId, 'acknowledge_messages'],
    );
    await subscriberClient.acknowledge(
      subscriptionName: subscriptionName,
      ackIds: ackIds,
    );
    return <String, Object?>{'status': 'SUCCESS'};
  } catch (error) {
    return <String, Object?>{
      'status': 'ERROR',
      'error_details':
          "Failed to acknowledge messages on subscription '$subscriptionName': $error",
    };
  }
}
