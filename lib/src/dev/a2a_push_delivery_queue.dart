import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

class A2aPushDeliveryPolicy {
  const A2aPushDeliveryPolicy({
    this.maxAttempts = 5,
    this.baseDelayMs = 1000,
    this.maxDelayMs = 60000,
    this.requestTimeoutMs = 10000,
  });

  final int maxAttempts;
  final int baseDelayMs;
  final int maxDelayMs;
  final int requestTimeoutMs;
}

class A2aPushDeliveryEntry {
  const A2aPushDeliveryEntry({
    required this.id,
    required this.appName,
    required this.taskId,
    required this.targetUrl,
    required this.headers,
    required this.authHeader,
    required this.task,
    required this.update,
    required this.attemptCount,
    required this.policy,
  });

  final int id;
  final String appName;
  final String taskId;
  final String targetUrl;
  final Map<String, String> headers;
  final String? authHeader;
  final Map<String, Object?> task;
  final Map<String, Object?> update;
  final int attemptCount;
  final A2aPushDeliveryPolicy policy;
}

class A2aPushDeliveryQueue {
  A2aPushDeliveryQueue._({required sqlite.Database database})
    : _database = database {
    _ensureSchema();
  }

  factory A2aPushDeliveryQueue.open({required String dbPath}) {
    final File file = File(dbPath);
    file.parent.createSync(recursive: true);
    return A2aPushDeliveryQueue._(database: sqlite.sqlite3.open(dbPath));
  }

  final sqlite.Database _database;
  bool _closed = false;

  void close() {
    if (_closed) {
      return;
    }
    _database.close();
    _closed = true;
  }

  void enqueue({
    required String appName,
    required String taskId,
    required String targetUrl,
    required Map<String, String> headers,
    required String? authHeader,
    required Map<String, Object?> task,
    required Map<String, Object?> update,
    required A2aPushDeliveryPolicy policy,
  }) {
    if (_closed) {
      return;
    }
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final sqlite.PreparedStatement statement = _database.prepare('''
      INSERT INTO a2a_push_delivery_queue (
        app_name,
        task_id,
        target_url,
        headers_json,
        auth_header,
        task_json,
        update_json,
        attempt_count,
        max_attempts,
        base_delay_ms,
        max_delay_ms,
        request_timeout_ms,
        next_attempt_at_ms,
        created_at_ms,
        last_error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, NULL)
    ''');
    try {
      statement.execute(<Object?>[
        appName,
        taskId,
        targetUrl,
        jsonEncode(headers),
        authHeader,
        jsonEncode(task),
        jsonEncode(update),
        policy.maxAttempts,
        policy.baseDelayMs,
        policy.maxDelayMs,
        policy.requestTimeoutMs,
        nowMs,
        nowMs,
      ]);
    } finally {
      statement.close();
    }
  }

  List<A2aPushDeliveryEntry> readDue({int limit = 64}) {
    if (_closed) {
      return const <A2aPushDeliveryEntry>[];
    }
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final sqlite.ResultSet rows = _database.select(
      '''
      SELECT
        id,
        app_name,
        task_id,
        target_url,
        headers_json,
        auth_header,
        task_json,
        update_json,
        attempt_count,
        max_attempts,
        base_delay_ms,
        max_delay_ms,
        request_timeout_ms
      FROM a2a_push_delivery_queue
      WHERE next_attempt_at_ms <= ?
      ORDER BY next_attempt_at_ms ASC, id ASC
      LIMIT ?
      ''',
      <Object?>[nowMs, limit],
    );

    return rows.map(_rowToEntry).toList(growable: false);
  }

  void markDelivered(int id) {
    if (_closed) {
      return;
    }
    _database.execute(
      'DELETE FROM a2a_push_delivery_queue WHERE id = ?',
      <Object?>[id],
    );
  }

  void markFailed(A2aPushDeliveryEntry entry, {required String error}) {
    if (_closed) {
      return;
    }
    final int nextAttemptCount = entry.attemptCount + 1;
    if (nextAttemptCount >= entry.policy.maxAttempts) {
      _database.execute(
        '''
        INSERT INTO a2a_push_delivery_dead_letter (
          app_name,
          task_id,
          target_url,
          headers_json,
          auth_header,
          task_json,
          update_json,
          attempt_count,
          max_attempts,
          base_delay_ms,
          max_delay_ms,
          request_timeout_ms,
          failed_at_ms,
          final_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          entry.appName,
          entry.taskId,
          entry.targetUrl,
          jsonEncode(entry.headers),
          entry.authHeader,
          jsonEncode(entry.task),
          jsonEncode(entry.update),
          nextAttemptCount,
          entry.policy.maxAttempts,
          entry.policy.baseDelayMs,
          entry.policy.maxDelayMs,
          entry.policy.requestTimeoutMs,
          DateTime.now().millisecondsSinceEpoch,
          error,
        ],
      );
      markDelivered(entry.id);
      return;
    }

    final int delayMs = _backoffDelayMs(
      baseDelayMs: entry.policy.baseDelayMs,
      maxDelayMs: entry.policy.maxDelayMs,
      attemptCount: nextAttemptCount,
    );
    final int nextAttemptAt = DateTime.now().millisecondsSinceEpoch + delayMs;
    _database.execute(
      '''
      UPDATE a2a_push_delivery_queue
      SET attempt_count = ?,
          next_attempt_at_ms = ?,
          last_error = ?
      WHERE id = ?
      ''',
      <Object?>[nextAttemptCount, nextAttemptAt, error, entry.id],
    );
  }

  int pendingCount() {
    if (_closed) {
      return 0;
    }
    final sqlite.ResultSet rows = _database.select(
      'SELECT COUNT(*) AS count FROM a2a_push_delivery_queue',
    );
    return rows.first['count'] as int? ?? 0;
  }

  int deadLetterCount() {
    if (_closed) {
      return 0;
    }
    final sqlite.ResultSet rows = _database.select(
      'SELECT COUNT(*) AS count FROM a2a_push_delivery_dead_letter',
    );
    return rows.first['count'] as int? ?? 0;
  }

  A2aPushDeliveryEntry _rowToEntry(sqlite.Row row) {
    return A2aPushDeliveryEntry(
      id: row['id'] as int,
      appName: row['app_name'] as String? ?? '',
      taskId: row['task_id'] as String? ?? '',
      targetUrl: row['target_url'] as String? ?? '',
      headers: _decodeHeaders(row['headers_json']),
      authHeader: row['auth_header'] as String?,
      task: _decodeObjectMap(row['task_json']),
      update: _decodeObjectMap(row['update_json']),
      attemptCount: row['attempt_count'] as int? ?? 0,
      policy: A2aPushDeliveryPolicy(
        maxAttempts: row['max_attempts'] as int? ?? 5,
        baseDelayMs: row['base_delay_ms'] as int? ?? 1000,
        maxDelayMs: row['max_delay_ms'] as int? ?? 60000,
        requestTimeoutMs: row['request_timeout_ms'] as int? ?? 10000,
      ),
    );
  }

  Map<String, String> _decodeHeaders(Object? value) {
    final Map<String, Object?> decoded = _decodeObjectMap(value);
    final Map<String, String> headers = <String, String>{};
    decoded.forEach((String key, Object? value) {
      final String normalizedKey = key.trim();
      final String normalizedValue = '$value'.trim();
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) {
        return;
      }
      headers[normalizedKey] = normalizedValue;
    });
    return headers;
  }

  Map<String, Object?> _decodeObjectMap(Object? raw) {
    if (raw is Map) {
      return raw.map((Object? key, Object? value) => MapEntry('$key', value));
    }
    if (raw is! String || raw.trim().isEmpty) {
      return <String, Object?>{};
    }
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map) {
        return <String, Object?>{};
      }
      return parsed.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    } catch (_) {
      return <String, Object?>{};
    }
  }

  int _backoffDelayMs({
    required int baseDelayMs,
    required int maxDelayMs,
    required int attemptCount,
  }) {
    final int shift = attemptCount < 30 ? attemptCount : 30;
    final int factor = 1 << shift;
    final int candidate = baseDelayMs * factor;
    return candidate > maxDelayMs ? maxDelayMs : candidate;
  }

  void _ensureSchema() {
    _database.execute('''
      CREATE TABLE IF NOT EXISTS a2a_push_delivery_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_name TEXT NOT NULL,
        task_id TEXT NOT NULL,
        target_url TEXT NOT NULL,
        headers_json TEXT NOT NULL,
        auth_header TEXT,
        task_json TEXT NOT NULL,
        update_json TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        max_attempts INTEGER NOT NULL,
        base_delay_ms INTEGER NOT NULL,
        max_delay_ms INTEGER NOT NULL,
        request_timeout_ms INTEGER NOT NULL,
        next_attempt_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        last_error TEXT
      )
    ''');
    _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_a2a_push_delivery_due
      ON a2a_push_delivery_queue (next_attempt_at_ms, id)
      ''');

    _database.execute('''
      CREATE TABLE IF NOT EXISTS a2a_push_delivery_dead_letter (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_name TEXT NOT NULL,
        task_id TEXT NOT NULL,
        target_url TEXT NOT NULL,
        headers_json TEXT NOT NULL,
        auth_header TEXT,
        task_json TEXT NOT NULL,
        update_json TEXT NOT NULL,
        attempt_count INTEGER NOT NULL,
        max_attempts INTEGER NOT NULL,
        base_delay_ms INTEGER NOT NULL,
        max_delay_ms INTEGER NOT NULL,
        request_timeout_ms INTEGER NOT NULL,
        failed_at_ms INTEGER NOT NULL,
        final_error TEXT
      )
    ''');
  }
}
