import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Trace-state key-value container.
class TraceState {
  /// Creates trace state values.
  const TraceState([Map<String, String>? values])
    : values = values ?? const <String, String>{};

  /// Trace-state entries.
  final Map<String, String> values;
}

/// Trace flags for span context.
class TraceFlags {
  /// Creates trace flags with raw [value].
  const TraceFlags(this.value);

  /// Raw trace flags value.
  final int value;

  /// Sampled trace flag.
  static const TraceFlags sampled = TraceFlags(0x01);
}

/// Span context identifier fields.
class SpanContext {
  /// Creates a span context.
  const SpanContext({
    required this.traceId,
    required this.spanId,
    required this.isRemote,
    required this.traceFlags,
    required this.traceState,
  });

  /// Trace id as integer.
  final int traceId;

  /// Span id as integer.
  final int spanId;

  /// Whether this context is remote.
  final bool isRemote;

  /// Trace flags.
  final TraceFlags traceFlags;

  /// Trace state.
  final TraceState traceState;

  /// 32-character hexadecimal trace id.
  String get traceIdHex => traceId.toRadixString(16).padLeft(32, '0');

  /// 16-character hexadecimal span id.
  String get spanIdHex => spanId.toRadixString(16).padLeft(16, '0');
}

/// Readable span model used for export and retrieval.
class ReadableSpan {
  /// Creates a readable span.
  ReadableSpan({
    required this.name,
    required this.context,
    this.parent,
    Map<String, Object?>? attributes,
    this.startTimeUnixNano,
    this.endTimeUnixNano,
  }) : attributes = attributes ?? <String, Object?>{};

  /// Span name.
  final String name;

  /// Span context.
  final SpanContext context;

  /// Parent span context, if present.
  final SpanContext? parent;

  /// Span attributes.
  final Map<String, Object?> attributes;

  /// Span start time in Unix nanoseconds.
  final int? startTimeUnixNano;

  /// Span end time in Unix nanoseconds.
  final int? endTimeUnixNano;
}

/// Export result status.
enum SpanExportResult { success, failure }

/// Span exporter interface.
abstract class SpanExporter {
  /// Exports [spans] and returns export status.
  SpanExportResult export(List<ReadableSpan> spans);

  /// Shuts down exporter resources.
  void shutdown();

  /// Flushes buffered spans before timeout.
  bool forceFlush({int timeoutMillis = 30000});
}

/// SQLite-backed [SpanExporter] implementation.
class SqliteSpanExporter implements SpanExporter {
  /// Creates a SQLite span exporter storing data at [dbPath].
  SqliteSpanExporter({required this.dbPath}) : _storeFile = File(dbPath) {
    _ensureSchema();
  }

  /// SQLite database path.
  final String dbPath;
  final File _storeFile;
  late final sqlite.Database _database = sqlite.sqlite3.open(dbPath);

  void _ensureSchema() {
    final Directory parent = _storeFile.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS spans (
        span_id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL,
        parent_span_id TEXT,
        name TEXT NOT NULL,
        start_time_unix_nano INTEGER,
        end_time_unix_nano INTEGER,
        session_id TEXT,
        invocation_id TEXT,
        event_id TEXT,
        attributes_json TEXT NOT NULL
      )
    ''');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_spans_session_id ON spans(session_id)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_spans_trace_id ON spans(trace_id)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_spans_event_id ON spans(event_id)',
    );
  }

  String _serializeAttributes(Map<String, Object?> attributes) {
    try {
      return jsonEncode(_normalizeJsonValue(attributes));
    } catch (_) {
      return '{}';
    }
  }

  Map<String, Object?> _deserializeAttributes(Object? attributesJson) {
    if (attributesJson == null) {
      return <String, Object?>{};
    }
    try {
      final Object? decoded = attributesJson is String
          ? jsonDecode(attributesJson)
          : attributesJson;
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
      }
      return <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  @override
  SpanExportResult export(List<ReadableSpan> spans) {
    try {
      final sqlite.PreparedStatement statement = _database.prepare('''
        INSERT INTO spans (
          span_id,
          trace_id,
          parent_span_id,
          name,
          start_time_unix_nano,
          end_time_unix_nano,
          session_id,
          invocation_id,
          event_id,
          attributes_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(span_id) DO UPDATE SET
          trace_id = excluded.trace_id,
          parent_span_id = excluded.parent_span_id,
          name = excluded.name,
          start_time_unix_nano = excluded.start_time_unix_nano,
          end_time_unix_nano = excluded.end_time_unix_nano,
          session_id = excluded.session_id,
          invocation_id = excluded.invocation_id,
          event_id = excluded.event_id,
          attributes_json = excluded.attributes_json
      ''');
      for (final ReadableSpan span in spans) {
        final Map<String, Object?> attributes = Map<String, Object?>.from(
          span.attributes,
        );
        final Object? sessionId =
            attributes['gcp.vertex.agent.session_id'] ??
            attributes['gen_ai.conversation.id'];
        final Object? invocationId =
            attributes['gcp.vertex.agent.invocation_id'];
        final Object? eventId = attributes['gcp.vertex.agent.event_id'];
        statement.execute(<Object?>[
          span.context.spanIdHex,
          span.context.traceIdHex,
          span.parent?.spanIdHex,
          span.name,
          span.startTimeUnixNano,
          span.endTimeUnixNano,
          sessionId == null ? null : '$sessionId',
          invocationId == null ? null : '$invocationId',
          eventId == null ? null : '$eventId',
          _serializeAttributes(attributes),
        ]);
      }
      statement.close();
      return SpanExportResult.success;
    } catch (_) {
      return SpanExportResult.failure;
    }
  }

  @override
  void shutdown() {
    _database.close();
  }

  @override
  bool forceFlush({int timeoutMillis = 30000}) {
    return true;
  }

  ReadableSpan _rowToReadableSpan(sqlite.Row row) {
    final int traceId = int.parse('${row['trace_id']}', radix: 16);
    final int spanId = int.parse('${row['span_id']}', radix: 16);

    final SpanContext context = SpanContext(
      traceId: traceId,
      spanId: spanId,
      isRemote: false,
      traceFlags: TraceFlags.sampled,
      traceState: const TraceState(),
    );

    SpanContext? parent;
    final Object? parentSpanIdHex = row['parent_span_id'];
    if (parentSpanIdHex != null && '$parentSpanIdHex'.isNotEmpty) {
      parent = SpanContext(
        traceId: traceId,
        spanId: int.parse('$parentSpanIdHex', radix: 16),
        isRemote: false,
        traceFlags: TraceFlags.sampled,
        traceState: const TraceState(),
      );
    }

    return ReadableSpan(
      name: '${row['name'] ?? ''}',
      context: context,
      parent: parent,
      attributes: _deserializeAttributes(row['attributes_json']),
      startTimeUnixNano: row['start_time_unix_nano'] as int?,
      endTimeUnixNano: row['end_time_unix_nano'] as int?,
    );
  }

  /// Returns all spans in traces associated with [sessionId].
  List<ReadableSpan> getAllSpansForSession(String sessionId) {
    final sqlite.ResultSet rows = _database.select(
      '''
      SELECT
        span_id,
        trace_id,
        parent_span_id,
        name,
        start_time_unix_nano,
        end_time_unix_nano,
        attributes_json
      FROM spans
      WHERE trace_id IN (
        SELECT DISTINCT trace_id FROM spans WHERE session_id = ?
      )
      ORDER BY COALESCE(start_time_unix_nano, 0), span_id
    ''',
      <Object?>[sessionId],
    );

    return rows.map((sqlite.Row row) => _rowToReadableSpan(row)).toList();
  }

  /// Returns one trace row mapped by [eventId], if available.
  Map<String, Object?>? getTraceByEventId(String eventId) {
    final sqlite.ResultSet rows = _database.select(
      '''
      SELECT
        span_id,
        trace_id,
        parent_span_id,
        name,
        start_time_unix_nano,
        end_time_unix_nano,
        session_id,
        invocation_id,
        event_id,
        attributes_json
      FROM spans
      WHERE event_id = ?
      ORDER BY COALESCE(start_time_unix_nano, 0), span_id
      LIMIT 1
    ''',
      <Object?>[eventId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final sqlite.Row row = rows.first;
    return <String, Object?>{
      'name': '${row['name'] ?? ''}',
      'span_id': '${row['span_id'] ?? ''}',
      'trace_id': '${row['trace_id'] ?? ''}',
      'start_time': row['start_time_unix_nano'],
      'end_time': row['end_time_unix_nano'],
      'attributes': _deserializeAttributes(row['attributes_json']),
      'parent_span_id': row['parent_span_id'],
      'event_id': row['event_id'],
      'session_id': row['session_id'],
      'invocation_id': row['invocation_id'],
    };
  }

  Object? _normalizeJsonValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? nestedValue) =>
            MapEntry('$key', _normalizeJsonValue(nestedValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_normalizeJsonValue).toList();
    }
    return '<not serializable>';
  }
}
