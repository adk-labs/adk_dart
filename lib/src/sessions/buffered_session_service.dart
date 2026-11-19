/// A session service decorator that persists writes in the background.
library;

import 'dart:async';
import 'dart:math' as math;

import '../errors/session_not_found_error.dart';
import '../errors/stale_session_error.dart';
import '../events/event.dart';
import '../workflow/workflow.dart' show RetryConfig;
import 'base_session_service.dart';
import 'session.dart';
import 'session_write_buffer.dart';

/// Configuration for [BufferedSessionService].
class BufferedSessionServiceConfig {
  /// Creates a buffered session service configuration.
  BufferedSessionServiceConfig({
    this.retryConfig = const RetryConfig(maxAttempts: 1),
    this.maxWriteDelay = Duration.zero,
    this.maxBatchEvents = 50,
  }) {
    if (maxWriteDelay < Duration.zero) {
      throw ArgumentError.value(
        maxWriteDelay,
        'maxWriteDelay',
        'maxWriteDelay must not be negative.',
      );
    }
    if (maxBatchEvents < 1) {
      throw ArgumentError.value(
        maxBatchEvents,
        'maxBatchEvents',
        'maxBatchEvents must be at least 1.',
      );
    }
  }

  /// How a failed write is retried. Off by default (`maxAttempts: 1`), since a
  /// retry can store an event twice if its first attempt committed.
  /// [StaleSessionError] and [SessionNotFoundError] are never retried.
  final RetryConfig retryConfig;

  /// How long a session's first queued write waits for more events to join it.
  ///
  /// Applies when the wrapped service supports batched `appendEvents`.
  final Duration maxWriteDelay;

  /// The most events sent in one `appendEvents` call.
  final int maxBatchEvents;
}

/// A session service that writes events to another one in the background.
///
/// [appendEvent] updates the session and returns at once. A writer per session
/// sends the events to the wrapped service in order, and reads wait for the
/// writes they would see. When a write fails, the session's next
/// [appendEvent], [flushSession], or [deleteSession] throws
/// `SessionPersistenceError`.
class BufferedSessionService extends BaseSessionService {
  /// Creates a buffered session service wrapping [delegate].
  ///
  /// Closing this service leaves [delegate] open.
  /// Set [batchWrites] to explicitly override whether [delegate]'s
  /// `appendEvents` method is used for batching (defaults to
  /// `delegate.supportsBatchAppendEvents`).
  BufferedSessionService(
    BaseSessionService delegate, {
    BufferedSessionServiceConfig? config,
    bool? batchWrites,
    math.Random? random,
  }) : _delegate = delegate,
       _config = config ?? BufferedSessionServiceConfig(),
       _batchWrites = batchWrites ?? delegate.supportsBatchAppendEvents,
       _random = random ?? math.Random() {
    final Duration delay = _batchWrites ? _config.maxWriteDelay : Duration.zero;
    _buffer = SessionWriteBuffer(
      _persist,
      maxWriteDelay: delay,
      maxBatchEvents: _batchWrites ? _config.maxBatchEvents : 1,
    );
  }

  final BaseSessionService _delegate;
  final BufferedSessionServiceConfig _config;
  final bool _batchWrites;
  final math.Random _random;
  late final SessionWriteBuffer _buffer;

  /// The underlying session service delegate.
  BaseSessionService get delegate => _delegate;

  /// The effective configuration for this buffered service.
  BufferedSessionServiceConfig get config => _config;

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    await _buffer.awaitWritesSeenBy(SessionKey(appName, userId, sessionId ?? ''));
    return _delegate.createSession(
      appName: appName,
      userId: userId,
      state: state,
      sessionId: sessionId,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    await _buffer.awaitWritesSeenBy(SessionKey(appName, userId, sessionId));
    return _delegate.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    await _buffer.awaitWritesListedFor(appName, userId);
    return _delegate.listSessions(appName: appName, userId: userId);
  }

  @override
  Future<Map<String, Object?>> getUserState({
    required String appName,
    required String userId,
  }) async {
    await _buffer.awaitUserStateWrites(appName, userId);
    return _delegate.getUserState(appName: appName, userId: userId);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    await _buffer.flush(
      SessionKey(appName, userId, sessionId),
      _doNothing,
    );
    await _delegate.deleteSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    if (event.partial == true) {
      return event;
    }
    if (session.id.isEmpty) {
      throw ArgumentError('BufferedSessionService requires a session id.');
    }
    final Event snapshot = eventForPersistence(event);
    return _buffer.append(
      session,
      snapshot,
      () => _applyToLiveSession(session, event),
    );
  }

  Event _applyToLiveSession(Session session, Event event) {
    final Event appended = commitEventToSession(session: session, event: event);
    session.lastUpdateTime = appended.timestamp;
    return appended;
  }

  @override
  Future<void> flushSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError(
        'BufferedSessionService.flushSession requires a session id.',
      );
    }
    await _buffer.flush(
      SessionKey(appName, userId, sessionId),
      () => _delegate.flushSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      ),
    );
  }

  @override
  Future<void> flush() async {
    await _buffer.flushAll(_delegate.flush);
  }

  /// Flushes every session and stops the writers; leaves the delegate open.
  Future<void> aclose() async {
    await _buffer.aclose(_delegate.flush);
  }

  /// Alias for [aclose].
  Future<void> close() => aclose();

  Future<Object?> _persist(Session storeSession, List<Event> events) {
    return _withRetries(() async {
      // A failed attempt may have left events on the store session.
      storeSession.events.clear();
      if (_batchWrites) {
        await _delegate.appendEvents(session: storeSession, events: events);
      } else {
        await _delegate.appendEvent(session: storeSession, event: events.first);
      }
    });
  }

  Future<Object?> _withRetries(Future<void> Function() call) async {
    final RetryConfig retry = _config.retryConfig;
    int failedAttempts = 0;
    while (true) {
      Object failure;
      try {
        await call();
        return null;
      } on StaleSessionError catch (e) {
        return e;
      } on SessionNotFoundError catch (e) {
        return e;
      } catch (e) {
        failure = e;
      }
      failedAttempts += 1;
      if (!_shouldRetry(retry, failure, failedAttempts)) {
        return failure;
      }
      final Duration delay = _retryDelay(retry, failedAttempts, _random);
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
  }
}

bool _shouldRetry(RetryConfig retry, Object failure, int failedAttempts) {
  if (failedAttempts >= retry.maxAttempts) {
    return false;
  }
  final List<Object>? allowed = retry.exceptions;
  if (allowed == null) {
    return true;
  }
  final String runtimeName = failure.runtimeType.toString();
  for (final Object entry in allowed) {
    if (entry is Type && failure.runtimeType == entry) {
      return true;
    }
    if (entry is String && entry == runtimeName) {
      return true;
    }
  }
  return false;
}

Duration _retryDelay(
  RetryConfig retry,
  int failedAttempts,
  math.Random random,
) {
  final double initialSec =
      retry.initialDelay.inMicroseconds / Duration.microsecondsPerSecond;
  final double maxSec =
      retry.maxDelay.inMicroseconds / Duration.microsecondsPerSecond;
  if (initialSec <= 0) {
    return Duration.zero;
  }
  double delay =
      initialSec * math.pow(retry.backoffMultiplier, failedAttempts - 1);
  if (!delay.isFinite) {
    delay = maxSec;
  }
  if (retry.jitter > 0) {
    delay = math.min(delay, maxSec / (1.0 + retry.jitter));
    final double offset = (random.nextDouble() * 2.0 - 1.0) * retry.jitter * delay;
    delay += offset;
  }
  final double clamped = delay.clamp(0.0, maxSec);
  return Duration(
    microseconds: (clamped * Duration.microsecondsPerSecond).round(),
  );
}

Future<void> _doNothing() async {}
