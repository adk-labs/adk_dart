/// Per-session writers, ordering and failure reports for BufferedSessionService.
///
/// Everything here runs on one Dart isolate event loop. Code between two
/// awaits runs without interruption, so the buffer needs no lock.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import '../errors/session_persistence_error.dart';
import '../errors/stale_session_error.dart';
import '../events/event.dart';
import 'session.dart';
import 'state.dart';

/// How many sessions keep a failure to report before the oldest is forgotten.
const int maxUnreportedFailures = 1024;

/// Identifies one session.
class SessionKey {
  /// Creates a session key.
  const SessionKey(this.appName, this.userId, this.sessionId);

  /// Application name.
  final String appName;

  /// User identifier.
  final String userId;

  /// Session identifier.
  final String sessionId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SessionKey &&
            other.appName == appName &&
            other.userId == userId &&
            other.sessionId == sessionId);
  }

  @override
  int get hashCode => Object.hash(appName, userId, sessionId);

  @override
  String toString() => 'SessionKey($appName, $userId, $sessionId)';
}

/// State shared across sessions: `app:` state (`userId == null`) or `user:`.
class _Scope {
  const _Scope(this.appName, this.userId);

  final String appName;
  final String? userId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is _Scope &&
            other.appName == appName &&
            other.userId == userId);
  }

  @override
  int get hashCode => Object.hash(appName, userId);
}

typedef _Version = (int, String?, double, String?);

/// Returns the shared scopes that a change to [stateKeys] touches.
List<_Scope> _changedScopes(SessionKey key, Iterable<String> stateKeys) {
  final List<String> keys = stateKeys.toList(growable: false);
  final List<_Scope> scopes = <_Scope>[];
  if (keys.any((String k) => k.startsWith(State.userPrefix))) {
    scopes.add(_Scope(key.appName, key.userId));
  }
  if (keys.any((String k) => k.startsWith(State.appPrefix))) {
    scopes.add(_Scope(key.appName, null));
  }
  return scopes;
}

bool _sees(SessionKey key, _Scope scope) {
  return scope.appName == key.appName &&
      (scope.userId == null || scope.userId == key.userId);
}

/// Writes events, in order and all or none, through a store session.
///
/// Returns the error that stopped them once retries ran out, or `null`.
typedef PersistFn =
    Future<Object?> Function(Session storeSession, List<Event> events);

class _Write {
  _Write({
    required this.key,
    required this.event,
    required this.scopes,
    required List<_Write> after,
    required this.writer,
    required this.storeSession,
    required this.liveSession,
  }) : after = List<_Write>.unmodifiable(after);

  final SessionKey key;
  final Event event;
  final List<_Scope> scopes;
  List<_Write> after;
  final _SessionWriter writer;
  Session? storeSession;
  Session? liveSession;

  final Completer<Object?> _result = Completer<Object?>();
  Object? _failure;

  bool get done => _result.isCompleted;

  Object? get failure => _failure;

  Future<void> join() async {
    await _result.future;
  }

  void release() {
    after = const <_Write>[];
    storeSession = null;
    liveSession = null;
  }

  void complete(Object? failure) {
    if (!_result.isCompleted) {
      _failure = failure;
      _result.complete(failure);
    }
    release();
  }
}

class _SessionWriter {
  _SessionWriter(this.key, this._buffer);

  final SessionKey key;
  final SessionWriteBuffer _buffer;
  final Queue<_Write> _queue = Queue<_Write>();
  List<_Write> _current = <_Write>[];
  _Write? lastWrite;
  bool _taskRunning = false;
  Timer? _timer;
  bool _stopping = false;
  Object? _failure;
  final Map<int, (Session, Object)> _failedChains = <int, (Session, Object)>{};
  final Map<_Version, Session> _chains = <_Version, Session>{};

  Object? chainFailure(Session? storeSession) {
    if (_failure != null) {
      return _failure;
    }
    if (storeSession == null) {
      return null;
    }
    final (Session, Object)? entry =
        _failedChains[identityHashCode(storeSession)];
    if (entry != null && identical(entry.$1, storeSession)) {
      return entry.$2;
    }
    return null;
  }

  Session storeSessionFor(Session liveSession) {
    final Session? storeSession = _chains[_versionOf(liveSession)];
    if (storeSession != null) {
      return storeSession;
    }
    return _newStoreSession(liveSession);
  }

  _Write write(
    Event event, {
    required List<_Scope> scopes,
    required List<_Write> after,
    required Session storeSession,
    required Session liveSession,
    required _Version versionBefore,
  }) {
    final _Write write = _Write(
      key: key,
      event: event,
      scopes: scopes,
      after: after,
      writer: this,
      storeSession: storeSession,
      liveSession: liveSession,
    );
    if (identical(_chains[versionBefore], storeSession)) {
      _chains.remove(versionBefore);
    }
    _chains[_versionOf(liveSession)] = storeSession;
    lastWrite = write;
    _queue.add(write);
    final Object? failure = chainFailure(storeSession);
    if (failure != null && write.liveSession != null) {
      _buffer.markFailedLiveSession(write.liveSession!, failure);
    }
    _schedule();
    return write;
  }

  void flushNow() {
    _start();
  }

  void stop(Object error) {
    _stopping = true;
    _cancelTimer();
    if (_taskRunning) {
      return;
    }
    if (_queue.isNotEmpty) {
      _fail(error);
      _start();
    }
  }

  bool get failed => _failure != null;

  bool get isSending => _taskRunning;

  List<_Write> pendingWrites() => <_Write>[..._current, ..._queue];

  void _schedule() {
    if (_taskRunning) {
      return;
    }
    final Duration delay = _buffer.maxWriteDelay;
    final bool hasFailedWrite =
        _queue.isNotEmpty && chainFailure(_queue.last.storeSession) != null;
    if (_failure != null || hasFailedWrite || delay <= Duration.zero) {
      _start();
    } else {
      _timer ??= Timer(delay, _start);
    }
  }

  void _start() {
    _cancelTimer();
    if (_taskRunning) {
      return;
    }
    if (_queue.isNotEmpty) {
      _startTask();
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTask() {
    _taskRunning = true;
    final Future<void> task = _sendQueued();
    _buffer._trackTask(task, this);
    task.whenComplete(() {
      _taskRunning = false;
      _buffer._untrackTask(task);
    });
  }

  void _fail(Object failure) {
    _failure ??= failure;
    for (final _Write write in pendingWrites()) {
      if (write.liveSession != null) {
        _buffer.markFailedLiveSession(write.liveSession!, _failure!);
      }
    }
  }

  void _failChain(Session? storeSession, Object failure) {
    if (storeSession == null) {
      _fail(failure);
      return;
    }
    final int sid = identityHashCode(storeSession);
    final (Session, Object)? existing = _failedChains[sid];
    final Object effectiveFailure;
    if (existing == null || !identical(existing.$1, storeSession)) {
      _failedChains[sid] = (storeSession, failure);
      effectiveFailure = failure;
    } else {
      effectiveFailure = existing.$2;
    }
    for (final _Write write in pendingWrites()) {
      if (identical(write.storeSession, storeSession) &&
          write.liveSession != null) {
        _buffer.markFailedLiveSession(write.liveSession!, effectiveFailure);
      }
    }
  }

  Future<void> _sendQueued() async {
    // Yield once so synchronous consecutive appends in the same microtask turn
    // can coalesce into a single batch when maxBatchEvents > 1 and delay == 0.
    await Future<void>.delayed(Duration.zero);
    try {
      if (_stopping) {
        await _dropPending();
        return;
      }
      while (_queue.isNotEmpty) {
        final List<_Write> batch = _current = _nextBatch();
        await _waitForEarlierSharedStateWrites(batch);
        Object? batchFailure = chainFailure(batch[0].storeSession);
        batchFailure ??= await _persist(batch);
        if (batchFailure != null) {
          if (batchFailure is StaleSessionError) {
            _failChain(batch[0].storeSession, batchFailure);
          } else {
            _fail(batchFailure);
          }
        }
        _current = <_Write>[];
        for (final _Write write in batch) {
          _complete(write, batchFailure);
        }
      }
    } catch (e) {
      _stopping = true;
      _fail(e);
      await _dropPending();
    }
  }

  List<_Write> _nextBatch() {
    final List<_Write> batch = <_Write>[_queue.removeFirst()];
    final Set<_Write> inBatch = Set<_Write>.identity()..add(batch[0]);
    while (_queue.isNotEmpty && batch.length < _buffer.maxBatchEvents) {
      final _Write next = _queue.first;
      final bool sameChain = identical(next.storeSession, batch[0].storeSession);
      final bool depsReady = next.after.every(
        (_Write earlier) => earlier.done || inBatch.contains(earlier),
      );
      if (!sameChain || !depsReady) {
        break;
      }
      _queue.removeFirst();
      batch.add(next);
      inBatch.add(next);
    }
    return batch;
  }

  Future<Object?> _persist(List<_Write> batch) async {
    final Session? storeSession = batch[0].storeSession;
    if (storeSession == null) {
      return StateError('The write was abandoned.');
    }
    final Object? failure = await _buffer.persist(
      storeSession,
      <Event>[for (final _Write w in batch) w.event],
    );
    final Set<String> batchIds = <String>{
      for (final _Write w in batch) w.event.id,
    };
    final List<Event> merged = <Event>[
      for (final Event e in storeSession.events)
        if (!batchIds.contains(e.id)) e,
    ];
    storeSession.events.clear();
    if (failure != null) {
      developer.log(
        'A buffered session write failed; later ones are dropped '
        '(${failure.runtimeType}).',
        name: 'adk_dart.sessions',
      );
    } else {
      if (merged.isNotEmpty) {
        _mergeIntoLiveSession(batch, storeSession, merged);
      }
      _syncLiveSession(batch.last, storeSession);
    }
    return failure;
  }

  void _mergeIntoLiveSession(
    List<_Write> batch,
    Session storeSession,
    List<Event> merged,
  ) {
    final Session? live = batch.last.liveSession;
    if (live == null) {
      return;
    }
    final _Version versionBefore = _versionOf(live);
    final Set<String> known = <String>{for (final Event e in live.events) e.id};
    final List<Event> newEvents = <Event>[
      for (final Event e in merged)
        if (!known.contains(e.id)) e,
    ];
    int at = live.events.indexWhere((Event e) => e.id == batch.first.event.id);
    if (at < 0) {
      at = live.events.length;
    }
    live.events.insertAll(at, newEvents);
    final Set<String> queuedKeys = <String>{
      for (final _Write w in _queue)
        if (identical(w.liveSession, live)) ...w.event.actions.stateDelta.keys,
    };
    storeSession.state.forEach((String k, Object? v) {
      if (!k.startsWith(State.tempPrefix) && !queuedKeys.contains(k)) {
        live.state[k] = _deepCopyValue(v);
      }
    });
    if (identical(_chains[versionBefore], storeSession)) {
      _chains.remove(versionBefore);
      _chains[_versionOf(live)] = storeSession;
    }
  }

  void _syncLiveSession(_Write last, Session storeSession) {
    final Session? live = last.liveSession;
    if (live == null ||
        _queue.any((_Write w) => identical(w.liveSession, live))) {
      return;
    }
    final _Version versionBefore = _versionOf(live);
    _copyVersion(storeSession, live);
    if (identical(_chains[versionBefore], storeSession)) {
      _chains.remove(versionBefore);
      _chains[_versionOf(live)] = storeSession;
    }
  }

  Future<void> _waitForEarlierSharedStateWrites(List<_Write> batch) async {
    final Set<_Write> inBatch = Set<_Write>.identity()..addAll(batch);
    final List<_Write> earlierWrites = <_Write>[];
    for (final _Write write in batch) {
      for (final _Write earlier in write.after) {
        if (!inBatch.contains(earlier) && !earlier.done) {
          earlierWrites.add(earlier);
        }
      }
    }
    for (final _Write earlier in earlierWrites) {
      earlier.writer.flushNow();
    }
    for (final _Write earlier in earlierWrites) {
      await earlier.join();
    }
  }

  Future<void> _dropPending() async {
    _cancelTimer();
    while (_current.isNotEmpty || _queue.isNotEmpty) {
      if (_current.isEmpty) {
        _current = <_Write>[_queue.removeFirst()];
      }
      final _Write write = _current[0];
      for (final _Write earlier in write.after) {
        while (!earlier.done) {
          if (earlier.writer.isSending) {
            earlier.writer.flushNow();
          } else {
            earlier.writer.stop(_failure ?? StateError('Writer stopped.'));
          }
          await earlier.join();
        }
      }
      _current.removeAt(0);
      _complete(write, _failure);
    }
  }

  void _complete(_Write write, Object? failure) {
    _buffer._beforeComplete(this, write, failure);
    write.complete(failure);
  }
}

_Version _versionOf(Session session) {
  final String? lastEventId = session.events.isNotEmpty
      ? session.events.last.id
      : null;
  return (
    session.events.length,
    lastEventId,
    session.lastUpdateTime,
    session.storageUpdateMarker,
  );
}

void _copyVersion(Session source, Session target) {
  target.lastUpdateTime = source.lastUpdateTime;
  target.storageUpdateMarker = source.storageUpdateMarker;
}

Session _newStoreSession(Session live) {
  final Session storeSession = Session(
    id: live.id,
    appName: live.appName,
    userId: live.userId,
    state: <String, Object?>{
      for (final MapEntry<String, Object?> entry in live.state.entries)
        if (!entry.key.startsWith(State.tempPrefix))
          entry.key: _deepCopyValue(entry.value),
    },
    lastUpdateTime: live.lastUpdateTime,
    storageUpdateMarker: live.storageUpdateMarker,
  );
  _copyVersion(live, storeSession);
  return storeSession;
}

/// Buffers the writes of many sessions until the store has them.
class SessionWriteBuffer {
  /// Creates a session write buffer.
  SessionWriteBuffer(
    this.persist, {
    this.maxWriteDelay = Duration.zero,
    this.maxBatchEvents = 1,
    int maxUnreportedFailures = maxUnreportedFailures,
  }) : _maxUnreportedFailures = maxUnreportedFailures;

  /// Persistence callback invoked for each batch of events.
  final PersistFn persist;

  /// How long a session's first queued write waits for more events to join it.
  final Duration maxWriteDelay;

  /// Maximum number of events sent in one persistence call.
  final int maxBatchEvents;

  final int _maxUnreportedFailures;
  bool _isClosed = false;
  Completer<void>? _closed;
  final Map<SessionKey, _SessionWriter> _writers =
      <SessionKey, _SessionWriter>{};
  final Map<Future<void>, _SessionWriter> _tasks =
      <Future<void>, _SessionWriter>{};
  final Map<_Scope, _Write> _lastWriteByScope = <_Scope, _Write>{};
  final LinkedHashMap<SessionKey, Object> _failures =
      LinkedHashMap<SessionKey, Object>();
  final Set<SessionKey> _failuresRaisedByFlushAll = <SessionKey>{};
  final Expando<Object> _failedLiveSessions = Expando<Object>(
    'failedLiveSessions',
  );

  /// Applies an event with [apply] and queues the write of [snapshot].
  Event append(Session session, Event snapshot, Event Function() apply) {
    if (_isClosed) {
      throw StateError('BufferedSessionService is closed.');
    }
    final SessionKey key = SessionKey(
      session.appName,
      session.userId,
      session.id,
    );
    if (_failures[key] is! StaleSessionError) {
      _reportFailure(key);
    }
    _checkLiveSession(session);
    _SessionWriter? writer = _writers[key];
    final _Version versionBefore = _versionOf(session);
    final Session storeSession = writer != null
        ? writer.storeSessionFor(session)
        : _newStoreSession(session);
    if (writer != null) {
      final Object? chainFail = writer.chainFailure(storeSession);
      if (chainFail != null) {
        markFailedLiveSession(session, chainFail);
        _checkLiveSession(session);
      }
    }
    final Event appended = apply();
    final List<_Scope> scopes = _changedScopes(
      key,
      snapshot.actions.stateDelta.keys,
    );
    writer ??= _writers[key] = _SessionWriter(key, this);
    final List<_Write> after = <_Write>[
      for (final _Scope scope in scopes)
        if (_lastWriteByScope.containsKey(scope)) _lastWriteByScope[scope]!,
    ];
    final _Write write = writer.write(
      snapshot,
      scopes: scopes,
      after: after,
      storeSession: storeSession,
      liveSession: session,
      versionBefore: versionBefore,
    );
    for (final _Scope scope in scopes) {
      _lastWriteByScope[scope] = write;
    }
    return appended;
  }

  /// Waits for the session's writes and the writes to the scopes it sees.
  Future<void> awaitWritesSeenBy(SessionKey key) async {
    final _SessionWriter? writer = _writers[key];
    final List<_Write?> writes = <_Write?>[
      if (writer != null) writer.lastWrite,
      for (final MapEntry<_Scope, _Write> entry in _lastWriteByScope.entries)
        if (_sees(key, entry.key)) entry.value,
    ];
    await _awaitWrites(writes);
  }

  /// Waits for the writes a listing would see.
  Future<void> awaitWritesListedFor(String appName, String? userId) async {
    final List<_Write?> writes = <_Write?>[
      for (final MapEntry<SessionKey, _SessionWriter> entry in _writers.entries)
        if (entry.key.appName == appName &&
            (userId == null || userId == entry.key.userId))
          entry.value.lastWrite,
      for (final MapEntry<_Scope, _Write> entry in _lastWriteByScope.entries)
        if (entry.key.appName == appName &&
            (userId == null ||
                entry.key.userId == null ||
                entry.key.userId == userId))
          entry.value,
    ];
    await _awaitWrites(writes);
  }

  /// Waits for the writes that change the user's `user:` state.
  Future<void> awaitUserStateWrites(String appName, String userId) async {
    final _Write? write = _lastWriteByScope[_Scope(appName, userId)];
    await _awaitWrites(<_Write?>[write]);
  }

  /// Waits for the session's writes, runs [beforeReport], then reports errors.
  Future<void> flush(
    SessionKey key,
    Future<void> Function() beforeReport,
  ) async {
    final _SessionWriter? writer = _writers[key];
    final _Write? waited = writer?.lastWrite;
    Object? waitedFailure;
    if (waited != null) {
      await _awaitWrites(<_Write?>[waited]);
      waitedFailure = waited.failure;
    }
    await beforeReport();
    _reportFailure(key, waitedFailure: waitedFailure);
  }

  /// Waits for every write, runs [beforeReport], then reports failures.
  Future<void> flushAll(Future<void> Function() beforeReport) async {
    await _awaitWrites(<_Write?>[
      for (final _SessionWriter w in _writers.values) w.lastWrite,
    ]);
    await beforeReport();
    final List<SessionKey> keys = <SessionKey>[
      for (final SessionKey key in _failures.keys)
        if (!_failuresRaisedByFlushAll.contains(key)) key,
    ];
    if (keys.isEmpty) {
      return;
    }
    _failuresRaisedByFlushAll.addAll(keys);
    final List<Object> causes = <Object>[
      for (final SessionKey key in keys) _failures[key]!,
    ];
    final List<String> notes = <String>[
      for (final Object cause in causes.skip(1))
        'Another session failed with ${cause.runtimeType}: $cause',
    ];
    throw SessionPersistenceError(
      'Buffered writes of ${causes.length} session(s) could not be persisted.',
      cause: causes.first,
      notes: notes,
    );
  }

  /// Rejects later appends, flushes, then waits for writers to finish.
  Future<void> aclose(Future<void> Function() beforeReport) async {
    if (_closed != null) {
      await _closed!.future;
      await _stopWriters();
      return;
    }
    _isClosed = true;
    _closed = Completer<void>();
    try {
      await flushAll(beforeReport);
    } finally {
      try {
        await _stopWriters();
      } finally {
        if (!_closed!.isCompleted) {
          _closed!.complete();
        }
      }
    }
  }

  void _trackTask(Future<void> task, _SessionWriter writer) {
    _tasks[task] = writer;
  }

  void _untrackTask(Future<void> task) {
    _tasks.remove(task);
  }

  Future<void> _stopWriters() async {
    while (_tasks.isNotEmpty) {
      final List<Future<void>> tasks = _tasks.keys.toList(growable: false);
      await Future.wait<void>(tasks);
    }
  }

  Future<void> _awaitWrites(List<_Write?> writes) async {
    final List<_Write> pending = <_Write>[
      for (final _Write? w in writes)
        if (w != null && !w.done) w,
    ];
    for (final _Write w in pending) {
      w.writer.flushNow();
    }
    for (final _Write w in pending) {
      await w.join();
    }
  }

  void _beforeComplete(_SessionWriter writer, _Write write, Object? failure) {
    for (final _Scope scope in write.scopes) {
      if (identical(_lastWriteByScope[scope], write)) {
        _lastWriteByScope.remove(scope);
      }
    }
    if (failure != null && write.liveSession != null) {
      markFailedLiveSession(write.liveSession!, failure);
    }
    if (!identical(_writers[writer.key], writer)) {
      return;
    }
    if (identical(writer.lastWrite, write)) {
      _writers.remove(writer.key);
    }
    if (failure != null) {
      _recordFailure(writer.key, failure);
    }
  }

  void _recordFailure(SessionKey key, Object failure) {
    final Object? existing = _failures[key];
    if (existing != null) {
      if (existing is StaleSessionError && failure is! StaleSessionError) {
        _failures[key] = failure;
        _failuresRaisedByFlushAll.remove(key);
      }
      return;
    }
    _failures[key] = failure;
    if (_failures.length > _maxUnreportedFailures) {
      _retire(_failures.keys.first);
      developer.log(
        'Forgot the oldest unreported buffered-write failure; its session '
        'will not report it.',
        name: 'adk_dart.sessions',
      );
    }
  }

  /// Rejects later appends to [session], which holds a dropped event.
  void markFailedLiveSession(Session session, Object failure) {
    _failedLiveSessions[session] ??= failure;
  }

  void _checkLiveSession(Session session) {
    final Object? failure = _failedLiveSessions[session];
    if (failure != null) {
      final SessionKey key = SessionKey(
        session.appName,
        session.userId,
        session.id,
      );
      if (identical(_failures[key], failure)) {
        _retire(key);
      }
      throw SessionPersistenceError(
        'This session object holds an event whose buffered write could not '
        'be persisted. Read the session again before appending to it.',
        cause: failure,
      );
    }
  }

  void _reportFailure(SessionKey key, {Object? waitedFailure}) {
    final Object? failure = _failures[key];
    if (failure != null) {
      _retire(key);
    }
    final Object? cause = failure ?? waitedFailure;
    if (cause != null) {
      throw SessionPersistenceError(
        'A buffered write of this session could not be persisted. Read the '
        'session again before appending to it.',
        cause: cause,
      );
    }
  }

  void _retire(SessionKey key) {
    final _SessionWriter? writer = _writers[key];
    if (writer != null && writer.failed) {
      _writers.remove(key);
    }
    _failures.remove(key);
    _failuresRaisedByFlushAll.remove(key);
  }
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _deepCopyValue(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final Object? item in value) _deepCopyValue(item)];
  }
  if (value is Set) {
    return <Object?>{for (final Object? item in value) _deepCopyValue(item)};
  }
  return value;
}
