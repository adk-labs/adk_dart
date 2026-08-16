/// Tool function and helpers for publishing CloudEvents to Eventarc Advanced.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../types/id.dart';
import 'config.dart';

final RegExp _busRegex = RegExp(r'^projects/[^/]+/locations/[^/]+/messageBuses/[^/]+$');

/// Publishes a structured CloudEvent to Google Cloud Eventarc Advanced.
Future<Map<String, dynamic>> publishEventarcMessage({
  required String bus,
  required String type,
  required String source,
  EventarcToolConfig? settings,
  EventarcCredentialsConfig? credentials,
  Object? data,
  bool isBase64Encoded = false,
  bool includeTracingExtension = false,
  String? datacontenttype,
  String specversion = '1.0',
  String? subject,
  String? id,
  String? time,
  Map<String, String>? customAttributes,
  http.Client? httpClient,
}) async {
  if (!_busRegex.hasMatch(bus)) {
    throw ArgumentError.value(
      bus,
      'bus',
      'Must strictly match format: projects/*/locations/*/messageBuses/*',
    );
  }

  if (type.trim().isEmpty) {
    throw ArgumentError.value(type, 'type', 'CloudEvent type must not be empty.');
  }

  if (source.trim().isEmpty) {
    throw ArgumentError.value(source, 'source', 'CloudEvent source must not be empty.');
  }

  final String eventId = id ?? newAdkId(prefix: 'ce-');
  final String eventTime = time ?? DateTime.now().toUtc().toIso8601String();

  final Map<String, dynamic> cloudEvent = <String, dynamic>{
    'specversion': specversion,
    'id': eventId,
    'source': source,
    'type': type,
    'time': eventTime,
  };

  if (subject != null && subject.isNotEmpty) {
    cloudEvent['subject'] = subject;
  }

  if (datacontenttype != null) {
    cloudEvent['datacontenttype'] = datacontenttype;
  } else if (data != null && !isBase64Encoded) {
    cloudEvent['datacontenttype'] = 'application/json';
  }

  if (data != null) {
    if (isBase64Encoded) {
      cloudEvent['data_base64'] = data.toString();
    } else {
      cloudEvent['data'] = data;
    }
  }

  if (customAttributes != null) {
    customAttributes.forEach((String key, String value) {
      final String normalizedKey = key.toLowerCase();
      if (!cloudEvent.containsKey(normalizedKey)) {
        cloudEvent[normalizedKey] = value;
      }
    });
  }

  // Target Eventarc Advanced publishing endpoint
  final String endpoint =
      'https://eventarcpublishing.googleapis.com/v1/$bus:publishEvents';

  final Map<String, String> headers = <String, String>{
    'Content-Type': 'application/json',
  };

  if (credentials?.accessToken != null) {
    headers['Authorization'] = 'Bearer ${credentials!.accessToken}';
  }

  final Map<String, dynamic> requestBody = <String, dynamic>{
    'events': <Map<String, dynamic>>[cloudEvent],
  };

  final http.Client client = httpClient ?? http.Client();
  try {
    final http.Response response = await client.post(
      Uri.parse(endpoint),
      headers: headers,
      body: jsonEncode(requestBody),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return <String, dynamic>{
        'status': 'SUCCESS',
        'event_id': eventId,
        'bus': bus,
        'published_time': eventTime,
      };
    } else {
      return <String, dynamic>{
        'status': 'ERROR',
        'status_code': response.statusCode,
        'message': response.body,
        'event_id': eventId,
        'bus': bus,
      };
    }
  } catch (error) {
    return <String, dynamic>{
      'status': 'ERROR',
      'error': error.toString(),
      'event_id': eventId,
      'bus': bus,
    };
  } finally {
    if (httpClient == null) {
      client.close();
    }
  }
}

/// Alias for [publishEventarcMessage].
const Function publishMessage = publishEventarcMessage;
