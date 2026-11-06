/// Telemetry configuration, exporters, and tracing helpers.
library;

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

/// OpenTelemetry span kind classification.
enum SpanKind {
  /// Default internal operation.
  internal('INTERNAL'),

  /// Server-side request handling.
  server('SERVER'),

  /// Outgoing client request.
  client('CLIENT'),

  /// Asynchronous message producer.
  producer('PRODUCER'),

  /// Asynchronous message consumer.
  consumer('CONSUMER');

  const SpanKind(this.wireName);

  /// Uppercase OpenTelemetry wire representation.
  final String wireName;

  /// Resolves a [SpanKind] from its [wireName], defaulting to [SpanKind.internal].
  static SpanKind fromWireName(String? value) {
    final String normalized = (value ?? '').trim().toUpperCase();
    for (final SpanKind kind in SpanKind.values) {
      if (kind.wireName == normalized) {
        return kind;
      }
    }
    return SpanKind.internal;
  }
}

/// OpenTelemetry span status code classification.
enum StatusCode {
  /// Default unset status.
  unset('UNSET'),

  /// Operation completed successfully.
  ok('OK'),

  /// Operation encountered an error.
  error('ERROR');

  const StatusCode(this.wireName);

  /// Uppercase OpenTelemetry wire representation.
  final String wireName;

  /// Resolves a [StatusCode] from its [wireName], defaulting to [StatusCode.unset].
  static StatusCode fromWireName(String? value) {
    final String normalized = (value ?? '').trim().toUpperCase();
    for (final StatusCode code in StatusCode.values) {
      if (code.wireName == normalized) {
        return code;
      }
    }
    return StatusCode.unset;
  }
}

/// OpenTelemetry span status consisting of a [statusCode] and optional [description].
class SpanStatus {
  /// Creates a span status.
  const SpanStatus({
    this.statusCode = StatusCode.unset,
    this.description,
  });

  /// Default unset span status.
  static const SpanStatus unset = SpanStatus();

  /// Status code (`UNSET`, `OK`, or `ERROR`).
  final StatusCode statusCode;

  /// Optional human-readable description (typically set for [StatusCode.error]).
  final String? description;

  /// Whether this status represents the default unset state.
  bool get isUnset =>
      statusCode == StatusCode.unset &&
      (description == null || description!.isEmpty);
}

/// Event recorded during a span's lifetime.
class SpanEvent {
  /// Creates a span event.
  SpanEvent({
    required this.name,
    Map<String, Object?>? attributes,
    this.timestampUnixNano,
  }) : attributes = attributes ?? <String, Object?>{};

  /// Event name.
  final String name;

  /// Event attributes.
  final Map<String, Object?> attributes;

  /// Event timestamp in Unix nanoseconds.
  final int? timestampUnixNano;

  /// Timestamp alias matching OpenTelemetry Python `Event.timestamp`.
  int? get timestamp => timestampUnixNano;
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
    this.kind = SpanKind.internal,
    this.status = SpanStatus.unset,
    List<SpanEvent>? events,
  }) : attributes = attributes ?? <String, Object?>{},
       events = events ?? const <SpanEvent>[];

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

  /// OpenTelemetry span kind.
  final SpanKind kind;

  /// OpenTelemetry span status.
  final SpanStatus status;

  /// Events recorded on this span.
  final List<SpanEvent> events;
}

/// Export result status.
enum SpanExportResult {
  /// Spans were exported and persisted without error.
  success,

  /// Exporting or persisting spans failed.
  failure,
}

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
        attributes_json TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'INTERNAL',
        status_code TEXT NOT NULL DEFAULT 'UNSET',
        status_description TEXT,
        events_json TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    final sqlite.ResultSet versionRows = _database.select(
      'PRAGMA user_version;',
    );
    final int userVersion = versionRows.isEmpty
        ? 0
        : (versionRows.first.values.first as int? ?? 0);
    if (userVersion < 2) {
      final sqlite.ResultSet columns = _database.select(
        'PRAGMA table_info(spans);',
      );
      final Set<String> existingColumns = columns
          .map((sqlite.Row row) => '${row['name'] ?? ''}')
          .toSet();
      if (!existingColumns.contains('kind')) {
        _database.execute(
          "ALTER TABLE spans ADD COLUMN kind TEXT NOT NULL DEFAULT 'INTERNAL'",
        );
      }
      if (!existingColumns.contains('status_code')) {
        _database.execute(
          "ALTER TABLE spans ADD COLUMN status_code TEXT NOT NULL DEFAULT 'UNSET'",
        );
      }
      if (!existingColumns.contains('status_description')) {
        _database.execute(
          'ALTER TABLE spans ADD COLUMN status_description TEXT',
        );
      }
      if (!existingColumns.contains('events_json')) {
        _database.execute(
          "ALTER TABLE spans ADD COLUMN events_json TEXT NOT NULL DEFAULT '[]'",
        );
      }
      _database.execute('PRAGMA user_version = 2');
    }
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

  String _serializeEvents(List<SpanEvent> events) {
    if (events.isEmpty) {
      return '[]';
    }
    try {
      final List<Map<String, Object?>> payload = events
          .map(
            (SpanEvent event) => <String, Object?>{
              'name': event.name,
              'timestamp': event.timestampUnixNano,
              'attributes': _normalizeJsonValue(event.attributes),
            },
          )
          .toList(growable: false);
      return jsonEncode(payload);
    } catch (_) {
      return '[]';
    }
  }

  List<SpanEvent> _deserializeEvents(Object? eventsJson) {
    if (eventsJson == null) {
      return const <SpanEvent>[];
    }
    try {
      final Object? decoded = eventsJson is String
          ? jsonDecode(eventsJson)
          : eventsJson;
      if (decoded is! List) {
        return const <SpanEvent>[];
      }
      final List<SpanEvent> result = <SpanEvent>[];
      for (final Object? entry in decoded) {
        if (entry is! Map) {
          continue;
        }
        final Object? rawName = entry['name'];
        final Object? rawTimestamp =
            entry['timestamp'] ?? entry['timestamp_unix_nano'];
        final Object? rawAttributes = entry['attributes'];
        result.add(
          SpanEvent(
            name: '${rawName ?? ''}',
            timestampUnixNano: rawTimestamp is num
                ? rawTimestamp.toInt()
                : (rawTimestamp is String ? int.tryParse(rawTimestamp) : null),
            attributes: _deserializeAttributes(rawAttributes),
          ),
        );
      }
      return List<SpanEvent>.unmodifiable(result);
    } catch (_) {
      return const <SpanEvent>[];
    }
  }

  SpanStatus _deserializeStatus(Object? rawCode, Object? rawDescription) {
    final StatusCode code = StatusCode.fromWireName(rawCode as String?);
    final String? description = rawDescription is String ? rawDescription : null;
    if (code == StatusCode.unset &&
        (description == null || description.isEmpty)) {
      return SpanStatus.unset;
    }
    return SpanStatus(statusCode: code, description: description);
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
          attributes_json,
          kind,
          status_code,
          status_description,
          events_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(span_id) DO UPDATE SET
          trace_id = excluded.trace_id,
          parent_span_id = excluded.parent_span_id,
          name = excluded.name,
          start_time_unix_nano = excluded.start_time_unix_nano,
          end_time_unix_nano = excluded.end_time_unix_nano,
          session_id = excluded.session_id,
          invocation_id = excluded.invocation_id,
          event_id = excluded.event_id,
          attributes_json = excluded.attributes_json,
          kind = excluded.kind,
          status_code = excluded.status_code,
          status_description = excluded.status_description,
          events_json = excluded.events_json
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
          span.kind.wireName,
          span.status.statusCode.wireName,
          span.status.description,
          _serializeEvents(span.events),
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
      kind: SpanKind.fromWireName(row['kind'] as String?),
      status: _deserializeStatus(
        row['status_code'],
        row['status_description'],
      ),
      events: _deserializeEvents(row['events_json']),
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
        session_id,
        attributes_json,
        kind,
        status_code,
        status_description,
        events_json
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
        attributes_json,
        status_code,
        status_description,
        events_json
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
    final SpanStatus status = _deserializeStatus(
      row['status_code'],
      row['status_description'],
    );
    final List<SpanEvent> events = _deserializeEvents(row['events_json']);
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
      if (!status.isUnset)
        'status': <String, Object?>{
          'status_code': status.statusCode.wireName,
          if (status.description != null) 'description': status.description,
        },
      if (events.isNotEmpty)
        'events': events
            .map(
              (SpanEvent event) => <String, Object?>{
                'name': event.name,
                'timestamp': event.timestampUnixNano,
                'attributes': event.attributes,
              },
            )
            .toList(growable: false),
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
