import 'dart:convert';
import 'dart:io';

class TraceState {
  const TraceState([Map<String, String>? values])
    : values = values ?? const <String, String>{};

  final Map<String, String> values;
}

class TraceFlags {
  const TraceFlags(this.value);

  final int value;

  static const TraceFlags sampled = TraceFlags(0x01);
}

class SpanContext {
  const SpanContext({
    required this.traceId,
    required this.spanId,
    required this.isRemote,
    required this.traceFlags,
    required this.traceState,
  });

  final int traceId;
  final int spanId;
  final bool isRemote;
  final TraceFlags traceFlags;
  final TraceState traceState;

  String get traceIdHex => traceId.toRadixString(16).padLeft(32, '0');
  String get spanIdHex => spanId.toRadixString(16).padLeft(16, '0');
}

class ReadableSpan {
  ReadableSpan({
    required this.name,
    required this.context,
    this.parent,
    Map<String, Object?>? attributes,
    this.startTimeUnixNano,
    this.endTimeUnixNano,
  }) : attributes = attributes ?? <String, Object?>{};

  final String name;
  final SpanContext context;
  final SpanContext? parent;
  final Map<String, Object?> attributes;
  final int? startTimeUnixNano;
  final int? endTimeUnixNano;
}

enum SpanExportResult { success, failure }

abstract class SpanExporter {
  SpanExportResult export(List<ReadableSpan> spans);

  void shutdown();

  bool forceFlush({int timeoutMillis = 30000});
}

class SqliteSpanExporter implements SpanExporter {
  SqliteSpanExporter({required this.dbPath}) : _storeFile = File(dbPath) {
    _ensureSchema();
  }

  final String dbPath;
  final File _storeFile;

  void _ensureSchema() {
    final Directory? parent = _storeFile.parent;
    if (parent != null && !parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    if (!_storeFile.existsSync()) {
      _storeFile.writeAsStringSync('[]');
    }
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
      final List<Map<String, Object?>> rows = _loadRows();
      final Map<String, Map<String, Object?>> rowsBySpanId =
          <String, Map<String, Object?>>{};
      for (final Map<String, Object?> row in rows) {
        final Object? spanId = row['span_id'];
        if (spanId != null) {
          rowsBySpanId['$spanId'] = row;
        }
      }

      for (final ReadableSpan span in spans) {
        final Map<String, Object?> attributes = Map<String, Object?>.from(
          span.attributes,
        );
        final Object? sessionId =
            attributes['gcp.vertex.agent.session_id'] ??
            attributes['gen_ai.conversation.id'];
        final Object? invocationId =
            attributes['gcp.vertex.agent.invocation_id'];

        rowsBySpanId[span.context.spanIdHex] = <String, Object?>{
          'span_id': span.context.spanIdHex,
          'trace_id': span.context.traceIdHex,
          'parent_span_id': span.parent?.spanIdHex,
          'name': span.name,
          'start_time_unix_nano': span.startTimeUnixNano,
          'end_time_unix_nano': span.endTimeUnixNano,
          'session_id': sessionId == null ? null : '$sessionId',
          'invocation_id': invocationId == null ? null : '$invocationId',
          'attributes_json': _serializeAttributes(attributes),
        };
      }

      _saveRows(rowsBySpanId.values.toList());
      return SpanExportResult.success;
    } catch (_) {
      return SpanExportResult.failure;
    }
  }

  @override
  void shutdown() {
    // No persistent connection is held in this Dart implementation.
  }

  @override
  bool forceFlush({int timeoutMillis = 30000}) {
    return true;
  }

  List<Map<String, Object?>> _loadRows() {
    _ensureSchema();
    final String raw = _storeFile.readAsStringSync();
    if (raw.trim().isEmpty) {
      return <Map<String, Object?>>[];
    }

    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <Map<String, Object?>>[];
    }

    return decoded
        .whereType<Map>()
        .map(
          (Map row) =>
              row.map((Object? key, Object? value) => MapEntry('$key', value)),
        )
        .toList();
  }

  void _saveRows(List<Map<String, Object?>> rows) {
    rows.sort((Map<String, Object?> a, Map<String, Object?> b) {
      final int left = _asInt(a['start_time_unix_nano']);
      final int right = _asInt(b['start_time_unix_nano']);
      return left.compareTo(right);
    });
    _storeFile.writeAsStringSync(jsonEncode(rows));
  }

  List<Map<String, Object?>> _query(
    bool Function(Map<String, Object?> row) predicate,
  ) {
    return _loadRows().where(predicate).toList();
  }

  ReadableSpan _rowToReadableSpan(Map<String, Object?> row) {
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

  List<ReadableSpan> getAllSpansForSession(String sessionId) {
    final List<Map<String, Object?>> traceRows = _query(
      (Map<String, Object?> row) => row['session_id'] == sessionId,
    );
    final Set<String> traceIds = traceRows
        .map((Map<String, Object?> row) => row['trace_id'])
        .where((Object? traceId) => traceId != null)
        .map((Object? traceId) => '$traceId')
        .toSet();

    if (traceIds.isEmpty) {
      return <ReadableSpan>[];
    }

    final List<Map<String, Object?>> rows = _query(
      (Map<String, Object?> row) => traceIds.contains('${row['trace_id']}'),
    );
    rows.sort((Map<String, Object?> a, Map<String, Object?> b) {
      final int left = _asInt(a['start_time_unix_nano']);
      final int right = _asInt(b['start_time_unix_nano']);
      return left.compareTo(right);
    });

    return rows
        .map((Map<String, Object?> row) => _rowToReadableSpan(row))
        .toList();
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
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
