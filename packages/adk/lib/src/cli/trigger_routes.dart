/// Event-driven HTTP trigger routes (Pub/Sub and Eventarc) for ADK server deployments.
///
/// ```dart
/// final router = TriggerRouter(
///   getRunnerAsync: (appName) => serverContext.getRunner(appName),
///   sessionService: serverContext.sessionService,
///   triggerSources: const ['pubsub', 'eventarc'],
/// );
/// ```
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/base_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/types/content.dart';

/// Default maximum concurrent trigger invocations per server instance.
const int defaultMaxConcurrent = 10;

/// Default maximum retry attempts on transient/rate-limit errors.
const int defaultMaxRetries = 3;

/// Default base delay in seconds for exponential backoff.
const double defaultBaseDelaySeconds = 1.0;

/// Default maximum delay cap in seconds for exponential backoff.
const double defaultMaxDelaySeconds = 10.0;

/// Session state key under which trigger delivery metadata is injected.
const String triggerDeliveryStateKey = 'trigger_delivery';

/// Supported trigger source identifiers (`pubsub`, `eventarc`).
const Set<String> supportedTriggerSources = <String>{'pubsub', 'eventarc'};

/// Exception raised when a trigger invocation encounters a transient error
/// (such as HTTP 429 or `RESOURCE_EXHAUSTED`) that should be retried.
///
/// ```dart
/// throw TransientError('Rate limit exceeded (429)');
/// ```
class TransientError implements Exception {
  /// Creates a [TransientError] with a human-readable [message].
  const TransientError([this.message = 'Transient error']);

  /// Error description.
  final String message;

  @override
  String toString() => 'TransientError: $message';
}

/// Exception thrown by a [TriggerAuthVerifier] when a request is unauthorized
/// or forbidden.
///
/// ```dart
/// throw const TriggerAuthException(
///   statusCode: HttpStatus.unauthorized,
///   message: 'Missing bearer token.',
/// );
/// ```
class TriggerAuthException implements Exception {
  /// Creates a [TriggerAuthException] with [statusCode] and [message].
  const TriggerAuthException({
    this.statusCode = HttpStatus.unauthorized,
    required this.message,
  });

  /// HTTP status code to return (`401` or `403`).
  final int statusCode;

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'TriggerAuthException($statusCode): $message';
}

/// Optional callback used to authenticate incoming trigger HTTP requests.
///
/// Throw a [TriggerAuthException] to reject the request with a `401` or `403`
/// status code.
typedef TriggerAuthVerifier = FutureOr<void> Function(HttpRequest request);

/// Inner message structure inside a Google Cloud Pub/Sub push notification.
///
/// ```dart
/// final message = PubSubMessage.fromJson({
///   'data': 'SGVsbG8=',
///   'messageId': 'msg-1',
///   'attributes': {'env': 'prod'},
/// });
/// ```
class PubSubMessage {
  /// Creates a [PubSubMessage].
  PubSubMessage({
    this.data,
    Map<String, String>? attributes,
    this.messageId,
    this.publishTime,
  }) : attributes = attributes ?? const <String, String>{};

  /// Parses a [PubSubMessage] from a JSON map.
  factory PubSubMessage.fromJson(Map<String, Object?> json) {
    final Object? rawData = json['data'];
    final Object? rawAttributes = json['attributes'];
    final Map<String, String> parsedAttributes = <String, String>{};
    if (rawAttributes is Map) {
      rawAttributes.forEach((Object? key, Object? value) {
        if (key != null && value != null) {
          parsedAttributes['$key'] = '$value';
        }
      });
    }
    final String? messageId =
        (json['messageId'] ?? json['message_id'])?.toString();
    final String? publishTime =
        (json['publishTime'] ?? json['publish_time'])?.toString();
    return PubSubMessage(
      data: rawData?.toString(),
      attributes: parsedAttributes,
      messageId: messageId,
      publishTime: publishTime,
    );
  }

  /// Base64-encoded message data payload.
  final String? data;

  /// Key-value attributes attached to the Pub/Sub message.
  final Map<String, String> attributes;

  /// Unique Pub/Sub message identifier.
  final String? messageId;

  /// RFC 3339 timestamp when the message was published.
  final String? publishTime;

  /// Converts this message to a JSON-serializable map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (data != null) 'data': data,
      if (attributes.isNotEmpty) 'attributes': attributes,
      if (messageId != null) 'messageId': messageId,
      if (publishTime != null) 'publishTime': publishTime,
    };
  }
}

/// Request envelope sent by a Google Cloud Pub/Sub push subscription.
///
/// ```dart
/// final request = PubSubTriggerRequest.fromJson({
///   'message': {'data': 'SGVsbG8=', 'messageId': '1'},
///   'subscription': 'projects/my-proj/subscriptions/my-sub',
/// });
/// ```
class PubSubTriggerRequest {
  /// Creates a [PubSubTriggerRequest].
  PubSubTriggerRequest({
    required this.message,
    this.subscription,
    this.userId = 'pubsub_trigger_user',
    this.sessionId,
  });

  /// Parses a [PubSubTriggerRequest] from a JSON map.
  ///
  /// Throws a [FormatException] when the required `message` object is missing.
  factory PubSubTriggerRequest.fromJson(Map<String, Object?> json) {
    final Object? rawMessage = json['message'];
    if (rawMessage is! Map) {
      throw const FormatException(
        "Pub/Sub trigger request requires a 'message' object.",
      );
    }
    final Map<String, Object?> messageMap = rawMessage.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    final String userIdRaw =
        (json['user_id'] ?? json['userId'])?.toString().trim() ?? '';
    final String? sessionIdRaw =
        (json['session_id'] ?? json['sessionId'])?.toString().trim();
    return PubSubTriggerRequest(
      message: PubSubMessage.fromJson(messageMap),
      subscription: json['subscription']?.toString(),
      userId: userIdRaw.isEmpty ? 'pubsub_trigger_user' : userIdRaw,
      sessionId: (sessionIdRaw == null || sessionIdRaw.isEmpty)
          ? null
          : sessionIdRaw,
    );
  }

  /// Pub/Sub push message payload.
  final PubSubMessage message;

  /// Subscription resource name that delivered the message.
  final String? subscription;

  /// User identifier for the ADK session.
  final String userId;

  /// Optional session identifier to reuse across invocations.
  final String? sessionId;
}

/// Request envelope sent by Eventarc (structured or binary CloudEvents).
///
/// ```dart
/// final request = EventarcTriggerRequest.fromJson(
///   {'data': {'orderId': 42}, 'type': 'google.cloud.audit.log.v1.written'},
///   headers: {'ce-id': 'evt-1', 'ce-source': '//cloudaudit.googleapis.com'},
/// );
/// ```
class EventarcTriggerRequest {
  /// Creates an [EventarcTriggerRequest].
  EventarcTriggerRequest({
    this.data,
    this.userId = 'eventarc_trigger_user',
    this.sessionId,
    this.id,
    this.source,
    this.type,
    this.subject,
    this.time,
    Map<String, Object?>? extraFields,
  }) : extraFields = extraFields ?? const <String, Object?>{};

  /// Parses an [EventarcTriggerRequest] from a JSON [body] and optional HTTP [headers].
  factory EventarcTriggerRequest.fromJson(
    Map<String, Object?> body, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final Map<String, String> lowerHeaders = <String, String>{
      for (final MapEntry<String, String> entry in headers.entries)
        entry.key.toLowerCase(): entry.value,
    };

    String? readAttr(String key) {
      final Object? fromBody = body[key];
      if (fromBody != null && '$fromBody'.trim().isNotEmpty) {
        return '$fromBody'.trim();
      }
      final String? fromHeader = lowerHeaders['ce-$key'];
      if (fromHeader != null && fromHeader.trim().isNotEmpty) {
        return fromHeader.trim();
      }
      return null;
    }

    final String userIdRaw =
        (body['user_id'] ?? body['userId'] ?? lowerHeaders['ce-userid'])
                ?.toString()
                .trim() ??
            '';
    final String? sessionIdRaw =
        (body['session_id'] ?? body['sessionId'] ?? lowerHeaders['ce-sessionid'])
            ?.toString()
            .trim();

    const Set<String> knownKeys = <String>{
      'data',
      'user_id',
      'userId',
      'session_id',
      'sessionId',
      'id',
      'source',
      'type',
      'subject',
      'time',
      'specversion',
      'datacontenttype',
    };
    final Map<String, Object?> extraFields = <String, Object?>{
      for (final MapEntry<String, Object?> entry in body.entries)
        if (!knownKeys.contains(entry.key)) entry.key: entry.value,
    };

    return EventarcTriggerRequest(
      data: body['data'],
      userId: userIdRaw.isEmpty ? 'eventarc_trigger_user' : userIdRaw,
      sessionId: (sessionIdRaw == null || sessionIdRaw.isEmpty)
          ? null
          : sessionIdRaw,
      id: readAttr('id'),
      source: readAttr('source'),
      type: readAttr('type'),
      subject: readAttr('subject'),
      time: readAttr('time'),
      extraFields: extraFields,
    );
  }

  /// Event payload (`Map`, `String`, or `null`).
  final Object? data;

  /// User identifier for the ADK session.
  final String userId;

  /// Optional session identifier to reuse across invocations.
  final String? sessionId;

  /// CloudEvent `id` attribute.
  final String? id;

  /// CloudEvent `source` attribute.
  final String? source;

  /// CloudEvent `type` attribute.
  final String? type;

  /// CloudEvent `subject` attribute.
  final String? subject;

  /// CloudEvent `time` attribute.
  final String? time;

  /// Additional top-level fields present in the event body.
  final Map<String, Object?> extraFields;
}

/// Response returned by `/apps/{app_name}/trigger/*` endpoints.
///
/// ```dart
/// final response = TriggerResponse(
///   sessionId: 'sess-1',
///   response: 'Processed event.',
/// );
/// ```
class TriggerResponse {
  /// Creates a [TriggerResponse].
  const TriggerResponse({
    required this.sessionId,
    required this.response,
    this.status = 'success',
  });

  /// Session identifier used for the agent run.
  final String sessionId;

  /// Concatenated model text output from the agent run.
  final String response;

  /// Execution status string (defaults to `'success'`).
  final String status;

  /// Serializes this response to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'session_id': sessionId,
      'response': response,
      'status': status,
    };
  }
}

class _AsyncSemaphore {
  _AsyncSemaphore(this.maxCount) : _available = maxCount;

  final int maxCount;
  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> withPermit<T>(Future<T> Function() action) async {
    if (_available > 0) {
      _available -= 1;
    } else {
      final Completer<void> waiter = Completer<void>();
      _waiters.addLast(waiter);
      await waiter.future;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _available += 1;
      }
    }
  }
}

/// Router that handles `/apps/{app_name}/trigger/pubsub` and
/// `/apps/{app_name}/trigger/eventarc` requests with concurrency control and
/// exponential backoff retry on transient/rate-limit errors.
///
/// ```dart
/// final router = TriggerRouter(
///   getRunnerAsync: (appName) => context.getRunner(appName),
///   sessionService: context.sessionService,
///   triggerSources: const ['pubsub', 'eventarc'],
/// );
/// ```
class TriggerRouter {
  /// Creates a [TriggerRouter].
  TriggerRouter({
    required this.getRunnerAsync,
    required this.sessionService,
    required Iterable<String> triggerSources,
    this.verifyAuth,
    this.maxConcurrent = defaultMaxConcurrent,
    this.maxRetries = defaultMaxRetries,
    this.baseDelaySeconds = defaultBaseDelaySeconds,
    this.maxDelaySeconds = defaultMaxDelaySeconds,
  }) : enabledSources = triggerSources
           .map((String s) => s.trim().toLowerCase())
           .where((String s) => s.isNotEmpty)
           .toSet(),
       _semaphore = _AsyncSemaphore(math.max(1, maxConcurrent)) {
    for (final String source in enabledSources) {
      if (!supportedTriggerSources.contains(source)) {
        throw ArgumentError.value(
          source,
          'triggerSources',
          'Unsupported trigger source "$source". Supported: ${supportedTriggerSources.join(', ')}.',
        );
      }
    }
  }

  /// Callback that resolves the [Runner] for a given `appName`.
  final Future<Runner> Function(String appName) getRunnerAsync;

  /// Session service used to look up or create trigger sessions.
  final BaseSessionService sessionService;

  /// Enabled trigger sources (`pubsub` and/or `eventarc`).
  final Set<String> enabledSources;

  /// Optional authentication verifier invoked before processing a trigger request.
  final TriggerAuthVerifier? verifyAuth;

  /// Maximum concurrent trigger executions allowed per instance.
  final int maxConcurrent;

  /// Maximum retry attempts on transient or rate-limit errors.
  final int maxRetries;

  /// Base delay in seconds for exponential backoff.
  final double baseDelaySeconds;

  /// Maximum delay cap in seconds for exponential backoff.
  final double maxDelaySeconds;

  final _AsyncSemaphore _semaphore;
  final math.Random _random = math.Random();

  /// Whether [source] (`pubsub` or `eventarc`) is enabled on this router.
  bool isSourceEnabled(String source) =>
      enabledSources.contains(source.trim().toLowerCase());

  /// Processes a parsed [PubSubTriggerRequest] for [appName] and returns a
  /// [TriggerResponse].
  Future<TriggerResponse> handlePubSubRequest({
    required String appName,
    required PubSubTriggerRequest triggerRequest,
  }) {
    return _semaphore.withPermit(() async {
      final PubSubMessage msg = triggerRequest.message;
      String decodedText = '';
      if (msg.data != null && msg.data!.isNotEmpty) {
        try {
          final List<int> bytes = base64Decode(msg.data!.trim());
          decodedText = utf8.decode(bytes, allowMalformed: true);
        } on FormatException catch (error) {
          throw FormatException('Invalid base64 in message.data: $error');
        }
      }

      final List<Part> parts = <Part>[];
      if (decodedText.isNotEmpty) {
        parts.add(Part.text(decodedText));
      }
      if (msg.attributes.isNotEmpty) {
        parts.add(Part.text('Attributes: ${jsonEncode(msg.attributes)}'));
      }
      if (parts.isEmpty) {
        parts.add(Part.text('[empty message]'));
      }

      final Map<String, Object?> stateDelta = <String, Object?>{
        triggerDeliveryStateKey: <String, Object?>{
          'source': 'pubsub',
          'message_id': msg.messageId,
          'publish_time': msg.publishTime,
          'subscription': triggerRequest.subscription,
          'attributes': msg.attributes,
        },
      };

      return _executeTriggerRun(
        appName: appName,
        userId: triggerRequest.userId,
        sessionId: triggerRequest.sessionId,
        content: Content(role: 'user', parts: parts),
        stateDelta: stateDelta,
      );
    });
  }

  /// Processes a parsed [EventarcTriggerRequest] for [appName] and returns a
  /// [TriggerResponse].
  Future<TriggerResponse> handleEventarcRequest({
    required String appName,
    required EventarcTriggerRequest triggerRequest,
  }) {
    return _semaphore.withPermit(() async {
      Object? payload = triggerRequest.data;
      if (payload == null && triggerRequest.extraFields.isNotEmpty) {
        payload = triggerRequest.extraFields;
      }

      String textContent = '';
      if (payload is Map &&
          payload.containsKey('message') &&
          payload['message'] is Map) {
        final Map<Object?, Object?> innerMsg =
            payload['message'] as Map<Object?, Object?>;
        final List<String> subParts = <String>[];
        final Object? b64Data = innerMsg['data'];
        if (b64Data is String && b64Data.isNotEmpty) {
          try {
            subParts.add(
              utf8.decode(base64Decode(b64Data.trim()), allowMalformed: true),
            );
          } on FormatException {
            subParts.add(b64Data);
          }
        }
        final Object? attrs = innerMsg['attributes'];
        if (attrs is Map && attrs.isNotEmpty) {
          subParts.add('Attributes: ${jsonEncode(attrs)}');
        }
        textContent = subParts.join('\n');
      } else if (payload is Map || payload is List) {
        textContent = jsonEncode(payload);
      } else if (payload is String) {
        textContent = payload;
      } else if (payload != null) {
        textContent = '$payload';
      }

      final List<Part> parts = <Part>[];
      if (textContent.isNotEmpty) {
        parts.add(Part.text(textContent));
      }

      final Map<String, String> ceAttributes = <String, String>{
        if (triggerRequest.id != null) 'id': triggerRequest.id!,
        if (triggerRequest.source != null) 'source': triggerRequest.source!,
        if (triggerRequest.type != null) 'type': triggerRequest.type!,
        if (triggerRequest.subject != null) 'subject': triggerRequest.subject!,
        if (triggerRequest.time != null) 'time': triggerRequest.time!,
      };
      if (ceAttributes.isNotEmpty) {
        parts.add(Part.text('Event Metadata: ${jsonEncode(ceAttributes)}'));
      }
      if (parts.isEmpty) {
        parts.add(Part.text('[empty event]'));
      }

      final Map<String, Object?> stateDelta = <String, Object?>{
        triggerDeliveryStateKey: <String, Object?>{
          'source': 'eventarc',
          'event_id': triggerRequest.id,
          'event_type': triggerRequest.type,
          'event_source': triggerRequest.source,
          'event_subject': triggerRequest.subject,
          'event_time': triggerRequest.time,
          'attributes': ceAttributes,
        },
      };

      return _executeTriggerRun(
        appName: appName,
        userId: triggerRequest.userId,
        sessionId: triggerRequest.sessionId,
        content: Content(role: 'user', parts: parts),
        stateDelta: stateDelta,
      );
    });
  }

  Future<TriggerResponse> _executeTriggerRun({
    required String appName,
    required String userId,
    required String? sessionId,
    required Content content,
    required Map<String, Object?> stateDelta,
  }) async {
    final Runner runner = await getRunnerAsync(appName);
    final Session session = await _getOrCreateSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );

    final List<Event> events = await _runWithRetry(
      runner: runner,
      userId: userId,
      sessionId: session.id,
      newMessage: content,
      stateDelta: stateDelta,
    );

    final List<String> responseTexts = <String>[];
    for (final Event event in events) {
      final Content? eventContent = event.content;
      if (eventContent == null || eventContent.role != 'model') {
        continue;
      }
      for (final Part part in eventContent.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          responseTexts.add(part.text!);
        }
      }
    }

    return TriggerResponse(
      sessionId: session.id,
      response: responseTexts.join('\n'),
    );
  }

  Future<Session> _getOrCreateSession({
    required String appName,
    required String userId,
    required String? sessionId,
  }) async {
    if (sessionId != null && sessionId.isNotEmpty) {
      final Session? existing = await sessionService.getSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      if (existing != null) {
        return existing;
      }
      return sessionService.createSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
    }
    return sessionService.createSession(appName: appName, userId: userId);
  }

  Future<List<Event>> _runWithRetry({
    required Runner runner,
    required String userId,
    required String sessionId,
    required Content newMessage,
    required Map<String, Object?> stateDelta,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt += 1) {
      try {
        final List<Event> collected = <Event>[];
        await for (final Event event in runner.runAsync(
          userId: userId,
          sessionId: sessionId,
          newMessage: newMessage,
          stateDelta: stateDelta,
        )) {
          if (event.errorCode != null && _isRateLimitValue(event.errorCode!)) {
            throw TransientError(
              'Rate limit error from model: ${event.errorCode} - ${event.errorMessage}',
            );
          }
          collected.add(event);
        }
        return collected;
      } catch (error) {
        final bool isTransient =
            error is TransientError || _isRateLimitError(error);
        if (!isTransient || attempt >= maxRetries) {
          rethrow;
        }
        final double expDelay = math.min(
          baseDelaySeconds * math.pow(2, attempt),
          maxDelaySeconds,
        );
        final double jitteredDelay = expDelay * (0.5 + _random.nextDouble() * 0.5);
        final int delayMs = (jitteredDelay * 1000).round();
        if (delayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
    return const <Event>[];
  }

  static bool _isRateLimitValue(String value) {
    final String upper = value.toUpperCase();
    return upper.contains('429') || upper.contains('RESOURCE_EXHAUSTED');
  }

  static bool _isRateLimitError(Object error) {
    return _isRateLimitValue(error.toString());
  }
}
