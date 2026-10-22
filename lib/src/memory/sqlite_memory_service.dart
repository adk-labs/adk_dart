/// SQLite-backed memory service implementation with FTS5 full-text search.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../events/event.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import '_utils.dart';
import 'base_memory_service.dart';
import 'memory_entry.dart';

const String _unknownSessionId = '__unknown_session__';
const String _schemaVersion = '1';

const String _createMetadataTableSql = '''
CREATE TABLE IF NOT EXISTS adk_memory_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''';

const String _createMemoryEventsTableSql = '''
CREATE TABLE IF NOT EXISTS memory_events (
  app_name TEXT NOT NULL,
  user_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  author TEXT,
  event_timestamp REAL NOT NULL,
  content_json TEXT NOT NULL,
  search_text TEXT NOT NULL,
  custom_metadata_json TEXT,
  PRIMARY KEY (app_name, user_id, session_id, event_id)
);
''';

const String _createMemoryEventsLookupIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_memory_events_lookup
ON memory_events (app_name, user_id, event_timestamp DESC);
''';

const String _createMemoryEventsFtsTableSql = '''
CREATE VIRTUAL TABLE IF NOT EXISTS memory_events_fts USING fts5(
  search_text,
  app_name UNINDEXED,
  user_id UNINDEXED,
  session_id UNINDEXED,
  event_id UNINDEXED,
  tokenize='unicode61'
);
''';

const String _createMemoryEntriesTableSql = '''
CREATE TABLE IF NOT EXISTS memory_entries (
  app_name TEXT NOT NULL,
  user_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  author TEXT,
  event_timestamp REAL NOT NULL,
  content_json TEXT NOT NULL,
  search_text TEXT NOT NULL,
  custom_metadata_json TEXT,
  PRIMARY KEY (app_name, user_id, session_id, event_id)
);
''';

const String _createMemoryEntriesLookupIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_memory_entries_lookup
ON memory_entries (app_name, user_id, event_timestamp DESC);
''';

const String _createMemoryEntriesFtsTableSql = '''
CREATE VIRTUAL TABLE IF NOT EXISTS memory_entries_fts USING fts5(
  search_text,
  app_name UNINDEXED,
  user_id UNINDEXED,
  session_id UNINDEXED,
  event_id UNINDEXED,
  tokenize='unicode61'
);
''';

final RegExp _tokenRegex = RegExp(
  r'[0-9a-z_\u00a0-\uffff]+',
  caseSensitive: false,
  unicode: true,
);

final RegExp _whitespaceRegex = RegExp(r'\s+');

bool _isAlphaOrDigitRune(int rune) {
  if ((rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A)) {
    return true;
  }
  if (rune < 0xA0) {
    return false;
  }
  // Latin Extended, Greek, Cyrillic, CJK, Hangul, Hiragana, Katakana, etc.
  if ((rune >= 0x00C0 && rune <= 0x02AF) ||
      (rune >= 0x0370 && rune <= 0x052F) ||
      (rune >= 0x0530 && rune <= 0x1FFF) ||
      (rune >= 0x2C00 && rune <= 0x2DFF) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x3400 && rune <= 0x9FFF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0xF900 && rune <= 0xFAFF)) {
    return true;
  }
  return false;
}

bool _isLatinRune(int rune) {
  if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
    return true;
  }
  if ((rune >= 0x00C0 && rune <= 0x024F) ||
      (rune >= 0x1E00 && rune <= 0x1EFF)) {
    return true;
  }
  return false;
}

String _splitScriptRuns(String text) {
  if (text.isEmpty) {
    return text;
  }
  final StringBuffer out = StringBuffer();
  bool? prevLatin;
  for (final int rune in text.runes) {
    if (_isAlphaOrDigitRune(rune) && !(rune >= 0x30 && rune <= 0x39)) {
      final bool currLatin = _isLatinRune(rune);
      if (prevLatin != null && currLatin != prevLatin) {
        out.write(' ');
      }
      prevLatin = currLatin;
    } else {
      prevLatin = null;
    }
    out.writeCharCode(rune);
  }
  return out.toString();
}

String _normalizeText(String text, {int maxBytes = 262144}) {
  if (text.isEmpty) {
    return '';
  }
  String normalized = unorm.nfc(text);
  normalized = _splitScriptRuns(normalized);
  normalized = normalized.toLowerCase();
  normalized = normalized.replaceAll(_whitespaceRegex, ' ').trim();
  final Uint8List encoded = utf8.encode(normalized);
  if (encoded.length > maxBytes) {
    normalized = utf8.decode(
      encoded.sublist(0, maxBytes),
      allowMalformed: true,
    );
    // If the last character is U+FFFD due to mid-character UTF-8 slice, strip it.
    if (normalized.endsWith('\uFFFD')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
  }
  return normalized;
}

List<String> _extractTokens(String text) {
  if (text.isEmpty) {
    return const <String>[];
  }
  final List<String> tokens = <String>[];
  for (final RegExpMatch match in _tokenRegex.allMatches(text)) {
    final String? token = match.group(0);
    if (token == null || token.isEmpty) {
      continue;
    }
    if (token.length > 1 || token.codeUnitAt(0) > 127) {
      tokens.add(token);
    }
  }
  return tokens;
}

String _extractPartsText(List<Part> parts) {
  if (parts.isEmpty) {
    return '';
  }
  final List<String> texts = <String>[];
  for (final Part part in parts) {
    final String? text = part.text;
    if (text == null || text.isEmpty || part.thought) {
      continue;
    }
    final String cleaned = text.replaceAll('\n', ' ').trim();
    if (cleaned.isNotEmpty) {
      texts.add(cleaned);
    }
  }
  return texts.join(' ');
}

String _extractEventText(Event event) {
  final Content? content = event.content;
  if (content == null || content.parts.isEmpty) {
    return '';
  }
  return _extractPartsText(content.parts);
}

({String path, bool isUri}) _parseDbPath(String dbPath) {
  final String trimmed = dbPath.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('db_path must be set.');
  }
  if (trimmed == ':memory:') {
    return (path: ':memory:', isUri: false);
  }
  if (trimmed.startsWith('sqlite')) {
    final int colonIndex = trimmed.indexOf(':');
    if (colonIndex < 0) {
      throw ArgumentError('Unsupported database URL scheme in $dbPath');
    }
    final String scheme = trimmed.substring(0, colonIndex).toLowerCase();
    if (scheme != 'sqlite' && scheme != 'sqlite+aiosqlite') {
      throw ArgumentError('Unsupported database URL scheme in $dbPath');
    }
    final String rest = trimmed.substring(colonIndex + 1);
    String rawPath = rest;
    String query = '';
    final int qIndex = rawPath.indexOf('?');
    if (qIndex >= 0) {
      query = rawPath.substring(qIndex + 1);
      rawPath = rawPath.substring(0, qIndex);
    }
    if (rawPath.startsWith('//')) {
      final String afterSlashes = rawPath.substring(2);
      final int slashIdx = afterSlashes.indexOf('/');
      if (slashIdx < 0) {
        if (afterSlashes.isNotEmpty && afterSlashes != 'localhost') {
          throw ArgumentError('SQLite does not support remote hosts: $dbPath');
        }
        rawPath = '';
      } else {
        final String host = afterSlashes.substring(0, slashIdx);
        if (host.isNotEmpty && host != 'localhost') {
          throw ArgumentError('SQLite does not support remote hosts: $dbPath');
        }
        rawPath = afterSlashes.substring(slashIdx);
      }
    }
    rawPath = Uri.decodeComponent(rawPath);
    if (rawPath.startsWith('/') && !rawPath.startsWith('//')) {
      rawPath = rawPath.substring(1);
    } else if (rawPath.startsWith('//')) {
      rawPath = rawPath.substring(1);
    }
    if (rawPath.isEmpty) {
      if (query.isNotEmpty) {
        return (path: 'file:?$query', isUri: true);
      }
      return (path: ':memory:', isUri: false);
    }
    if (rawPath == ':memory:') {
      if (query.isNotEmpty) {
        return (path: 'file::memory:?$query', isUri: true);
      }
      return (path: ':memory:', isUri: false);
    }
    if (query.isNotEmpty) {
      return (path: 'file:$rawPath?$query', isUri: true);
    }
    return (path: rawPath, isUri: false);
  }
  return (path: trimmed, isUri: false);
}

/// A persistent memory service backed by SQLite with optional FTS5 search.
///
/// Events and memories are stored per `(appName, userId)` scope and indexed for
/// full-text retrieval via SQLite FTS5 when supported by the host SQLite build,
/// with automatic fallback to `LIKE` token matching when FTS5 is unavailable.
///
/// ```dart
/// final memoryService = SqliteMemoryService(':memory:');
/// await memoryService.addEventsToMemory(
///   appName: 'my_app',
///   userId: 'user_1',
///   sessionId: 'session_1',
///   events: [
///     Event(
///       invocationId: 'inv_1',
///       author: 'user',
///       content: Content.userText('I prefer dark mode in all editors.'),
///     ),
///   ],
/// );
/// final results = await memoryService.searchMemory(
///   appName: 'my_app',
///   userId: 'user_1',
///   query: 'dark mode',
/// );
/// await memoryService.close();
/// ```
class SqliteMemoryService extends BaseMemoryService {
  /// Creates a SQLite-backed memory service storing data at [dbPath].
  ///
  /// Pass `':memory:'` for an in-memory database, a filesystem path, or a
  /// `sqlite:///...` URI.
  ///
  /// [fts] controls full-text search indexing (`'auto'`, `'on'`, or `'off'`).
  /// [maxEventBytes] bounds the UTF-8 byte length of normalized search text.
  /// [maxResults] caps the number of memories returned by [searchMemory].
  SqliteMemoryService(
    String dbPath, {
    String fts = 'auto',
    int maxEventBytes = 262144,
    int maxResults = 50,
  }) : _ftsMode = fts,
       _maxEventBytes = maxEventBytes,
       _maxResults = maxResults {
    final ({String path, bool isUri}) parsed = _parseDbPath(dbPath);
    String resolvedPath = parsed.path;
    final bool isUri = parsed.isUri;

    if (resolvedPath != ':memory:' && !isUri) {
      final File file = File(resolvedPath).absolute;
      resolvedPath = file.path;
      if (Directory(resolvedPath).existsSync()) {
        throw ArgumentError('db_path $resolvedPath is a directory.');
      }
      file.parent.createSync(recursive: true);
    }

    if (!const <String>{'auto', 'on', 'off'}.contains(fts)) {
      throw ArgumentError("fts must be 'auto', 'on', or 'off', got $fts");
    }
    if (maxEventBytes <= 0) {
      throw ArgumentError('max_event_bytes must be > 0.');
    }
    if (maxResults <= 0) {
      throw ArgumentError('max_results must be > 0.');
    }

    _dbPath = resolvedPath;
    _isUri = isUri;
    _ftsEnabled = fts != 'off';
  }

  /// Creates an in-memory SQLite memory service.
  factory SqliteMemoryService.inMemory({
    String fts = 'auto',
    int maxEventBytes = 262144,
    int maxResults = 50,
  }) {
    return SqliteMemoryService(
      ':memory:',
      fts: fts,
      maxEventBytes: maxEventBytes,
      maxResults: maxResults,
    );
  }

  late final String _dbPath;
  late final bool _isUri;
  final String _ftsMode;
  final int _maxEventBytes;
  final int _maxResults;
  late bool _ftsEnabled;

  sqlite3.Database? _db;
  bool _initialized = false;
  bool _closed = false;

  /// Resolved SQLite database path or URI.
  String get dbPath => _dbPath;

  /// Configured FTS mode (`'auto'`, `'on'`, or `'off'`).
  String get ftsMode => _ftsMode;

  /// Whether FTS5 indexing and querying are currently active.
  bool get isFtsEnabled => _ftsEnabled;

  /// Maximum UTF-8 byte length of normalized event search text.
  int get maxEventBytes => _maxEventBytes;

  /// Maximum number of search results returned per query.
  int get maxResults => _maxResults;

  /// Builds a sanitized FTS5 `MATCH` query from [query] tokens.
  ///
  /// Each extracted token has embedded double quotes doubled and is wrapped in
  /// double quotes, then joined with `OR`.
  static String buildFtsQuery(String query, {int maxBytes = 262144}) {
    final String normalized = _normalizeText(query, maxBytes: maxBytes);
    final List<String> tokens = _extractTokens(normalized);
    if (tokens.isEmpty) {
      return '';
    }
    return tokens
        .map((String token) => '"${token.replaceAll('"', '""')}"')
        .join(' OR ');
  }

  sqlite3.Database _openDatabase() {
    if (_closed) {
      throw StateError('SqliteMemoryService has already been closed.');
    }
    final sqlite3.Database? existing = _db;
    if (existing != null) {
      return existing;
    }
    final sqlite3.Database db;
    if (_dbPath == ':memory:') {
      db = sqlite3.sqlite3.openInMemory();
    } else {
      db = sqlite3.sqlite3.open(_dbPath, uri: _isUri);
    }
    _configureConnection(db);
    _db = db;
    return db;
  }

  void _configureConnection(sqlite3.Database db) {
    db.execute('PRAGMA busy_timeout=3000;');
    try {
      db.execute('PRAGMA journal_mode=WAL;');
    } on sqlite3.SqliteException {
      // Read-only or special in-memory modes may reject WAL; safe to ignore.
    }
    try {
      db.execute('PRAGMA synchronous=NORMAL;');
    } on sqlite3.SqliteException {
      // Safe to ignore on read-only connections.
    }
  }

  void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    final sqlite3.Database db = _openDatabase();

    // Check existing schema version before writing on potentially read-only DBs.
    final sqlite3.ResultSet tableCheck = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='adk_memory_metadata'",
    );
    if (tableCheck.isNotEmpty) {
      final sqlite3.ResultSet rows = db.select(
        "SELECT value FROM adk_memory_metadata WHERE key = 'schema_version'",
      );
      if (rows.isNotEmpty) {
        final String version = '${rows.first['value']}';
        if (version != _schemaVersion) {
          throw StateError(
            "Unsupported SqliteMemoryService schema_version '$version'. Expected '$_schemaVersion'.",
          );
        }
      }
    }

    try {
      db.execute(_createMetadataTableSql);
      db.execute(
        "INSERT OR IGNORE INTO adk_memory_metadata (key, value) VALUES ('schema_version', ?)",
        <Object?>[_schemaVersion],
      );
      final sqlite3.ResultSet rows = db.select(
        "SELECT value FROM adk_memory_metadata WHERE key = 'schema_version'",
      );
      if (rows.isNotEmpty) {
        final String version = '${rows.first['value']}';
        if (version != _schemaVersion) {
          throw StateError(
            "Unsupported SqliteMemoryService schema_version '$version'. Expected '$_schemaVersion'.",
          );
        }
      }
      db.execute(_createMemoryEventsTableSql);
      db.execute(_createMemoryEventsLookupIndexSql);
      db.execute(_createMemoryEntriesTableSql);
      db.execute(_createMemoryEntriesLookupIndexSql);

      if (_ftsMode != 'off') {
        try {
          db.execute(_createMemoryEventsFtsTableSql);
          db.execute(_createMemoryEntriesFtsTableSql);
          _ftsEnabled = true;
        } on sqlite3.SqliteException catch (error) {
          if (_ftsMode == 'on') {
            rethrow;
          }
          developer.log(
            'FTS5 is not available in SQLite, falling back to LIKE search: $error',
            name: 'adk_dart.sqlite_memory_service',
          );
          _ftsEnabled = false;
        }
      } else {
        _ftsEnabled = false;
      }
    } on sqlite3.SqliteException catch (error) {
      final String msg = error.message.toLowerCase();
      if (!msg.contains('readonly')) {
        rethrow;
      }
      if (_ftsMode != 'off') {
        final sqlite3.ResultSet ftsCheck = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND (name='memory_events_fts' OR name='memory_entries_fts')",
        );
        if (ftsCheck.isNotEmpty) {
          _ftsEnabled = true;
        } else if (_ftsMode == 'on') {
          throw sqlite3.SqliteException(
            extendedResultCode: error.extendedResultCode,
            message:
                'FTS5 is set to "on", but FTS table does not exist in read-only database.',
          );
        } else {
          _ftsEnabled = false;
        }
      } else {
        _ftsEnabled = false;
      }
    }

    _initialized = true;
  }

  @override
  Future<void> addSessionToMemory(
    Session session, {
    Map<String, Object?>? customMetadata,
  }) async {
    await addEventsToMemory(
      appName: session.appName,
      userId: session.userId,
      sessionId: session.id,
      events: session.events,
      customMetadata: customMetadata,
    );
  }

  @override
  Future<void> addEventsToMemory({
    required String appName,
    required String userId,
    required List<Event> events,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    _ensureInitialized();
    final String effectiveSessionId = sessionId ?? _unknownSessionId;
    final String customMetadataJson = _encodeCustomMetadata(customMetadata);
    final sqlite3.Database db = _openDatabase();

    db.execute('BEGIN IMMEDIATE');
    try {
      for (final Event event in events) {
        final String rawText = _extractEventText(event);
        if (rawText.isEmpty) {
          continue;
        }
        final String searchText = _normalizeText(
          rawText,
          maxBytes: _maxEventBytes,
        );
        if (searchText.isEmpty) {
          continue;
        }

        final String contentJson = jsonEncode(_contentToJson(event.content));
        final String author = event.author;
        final double eventTimestamp = event.timestamp;

        String eventId = event.id;
        if (eventId.isEmpty) {
          final String payload = '$author:$eventTimestamp:$contentJson';
          eventId = sha256
              .convert(utf8.encode(payload))
              .toString()
              .substring(0, 32);
        }

        _upsertRecord(
          db: db,
          appName: appName,
          userId: userId,
          sessionId: effectiveSessionId,
          eventId: eventId,
          author: author,
          eventTimestamp: eventTimestamp,
          contentJson: contentJson,
          searchText: searchText,
          customMetadataJson: customMetadataJson,
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> addMemory({
    required String appName,
    required String userId,
    required List<MemoryEntry> memories,
    Map<String, Object?>? customMetadata,
  }) async {
    _ensureInitialized();
    final sqlite3.Database db = _openDatabase();

    db.execute('BEGIN IMMEDIATE');
    try {
      for (final MemoryEntry memory in memories) {
        final String rawText = _extractPartsText(memory.content.parts);
        if (rawText.isEmpty) {
          continue;
        }
        final String searchText = _normalizeText(
          rawText,
          maxBytes: _maxEventBytes,
        );
        if (searchText.isEmpty) {
          continue;
        }

        final Map<String, Object?> mergedMeta = <String, Object?>{
          ...memory.customMetadata,
          ...?customMetadata,
        };
        final String effectiveSessionId =
            mergedMeta['session_id'] is String &&
                (mergedMeta['session_id'] as String).isNotEmpty
            ? mergedMeta['session_id'] as String
            : _unknownSessionId;

        final String contentJson = jsonEncode(_contentToJson(memory.content));
        final String? author = memory.author;
        final double eventTimestamp = _parseTimestampToSeconds(
          memory.timestamp,
        );

        String eventId =
            memory.id ??
            (mergedMeta['event_id'] is String
                ? mergedMeta['event_id'] as String
                : '');
        if (eventId.isEmpty) {
          final String payload =
              '${author ?? ''}:$eventTimestamp:$contentJson';
          eventId = sha256
              .convert(utf8.encode(payload))
              .toString()
              .substring(0, 32);
        }

        final String customMetadataJson = _encodeCustomMetadata(mergedMeta);

        _upsertRecord(
          db: db,
          appName: appName,
          userId: userId,
          sessionId: effectiveSessionId,
          eventId: eventId,
          author: author,
          eventTimestamp: eventTimestamp,
          contentJson: contentJson,
          searchText: searchText,
          customMetadataJson: customMetadataJson,
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> deleteMemory({
    required String appName,
    required String userId,
    String? memoryId,
  }) async {
    _ensureInitialized();
    final sqlite3.Database db = _openDatabase();
    db.execute('BEGIN IMMEDIATE');
    try {
      if (memoryId != null && memoryId.isNotEmpty) {
        db.execute(
          'DELETE FROM memory_events WHERE app_name = ? AND user_id = ? AND event_id = ?',
          <Object?>[appName, userId, memoryId],
        );
        db.execute(
          'DELETE FROM memory_entries WHERE app_name = ? AND user_id = ? AND event_id = ?',
          <Object?>[appName, userId, memoryId],
        );
        if (_ftsEnabled) {
          db.execute(
            'DELETE FROM memory_events_fts WHERE app_name = ? AND user_id = ? AND event_id = ?',
            <Object?>[appName, userId, memoryId],
          );
          db.execute(
            'DELETE FROM memory_entries_fts WHERE app_name = ? AND user_id = ? AND event_id = ?',
            <Object?>[appName, userId, memoryId],
          );
        }
      } else {
        db.execute(
          'DELETE FROM memory_events WHERE app_name = ? AND user_id = ?',
          <Object?>[appName, userId],
        );
        db.execute(
          'DELETE FROM memory_entries WHERE app_name = ? AND user_id = ?',
          <Object?>[appName, userId],
        );
        if (_ftsEnabled) {
          db.execute(
            'DELETE FROM memory_events_fts WHERE app_name = ? AND user_id = ?',
            <Object?>[appName, userId],
          );
          db.execute(
            'DELETE FROM memory_entries_fts WHERE app_name = ? AND user_id = ?',
            <Object?>[appName, userId],
          );
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<SearchMemoryResponse> searchMemory({
    required String appName,
    required String userId,
    required String query,
  }) async {
    _ensureInitialized();
    final String normalizedQuery = _normalizeText(
      query,
      maxBytes: _maxEventBytes,
    );
    final List<String> tokens = _extractTokens(normalizedQuery);
    if (tokens.isEmpty) {
      return SearchMemoryResponse();
    }

    final sqlite3.Database db = _openDatabase();
    List<sqlite3.Row> rows = const <sqlite3.Row>[];
    bool ftsFailed = false;

    if (_ftsEnabled) {
      final String ftsQuery = tokens
          .map((String token) => '"${token.replaceAll('"', '""')}"')
          .join(' OR ');
      const String sql = '''
        SELECT e.session_id, e.event_id, e.author, e.event_timestamp, e.content_json, e.custom_metadata_json
        FROM memory_events_fts f
        JOIN memory_events e
          ON f.app_name = e.app_name
         AND f.user_id = e.user_id
         AND f.session_id = e.session_id
         AND f.event_id = e.event_id
        WHERE f.memory_events_fts MATCH ?
          AND f.app_name = ?
          AND f.user_id = ?
        ORDER BY bm25(memory_events_fts) ASC, e.event_timestamp DESC, e.rowid DESC
        LIMIT ?
      ''';
      try {
        rows = db.select(sql, <Object?>[
          ftsQuery,
          appName,
          userId,
          _maxResults,
        ]);
      } on sqlite3.SqliteException catch (error) {
        if (_ftsMode == 'on') {
          rethrow;
        }
        developer.log(
          'FTS5 query failed, falling back to LIKE search: $error',
          name: 'adk_dart.sqlite_memory_service',
        );
        ftsFailed = true;
      }
    }

    if (!_ftsEnabled || ftsFailed) {
      final List<String> likeClauses = List<String>.filled(
        tokens.length,
        r"search_text LIKE ? ESCAPE '\'",
      );
      final String whereLikes = likeClauses.join(' OR ');
      final String sql = '''
        SELECT session_id, event_id, author, event_timestamp, content_json, custom_metadata_json
        FROM memory_events
        WHERE app_name = ?
          AND user_id = ?
          AND ($whereLikes)
        ORDER BY event_timestamp DESC, rowid DESC
        LIMIT ?
      ''';
      final List<Object?> params = <Object?>[appName, userId];
      for (final String token in tokens) {
        final String escaped = token
            .replaceAll(r'\', r'\\')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_');
        params.add('%$escaped%');
      }
      params.add(_maxResults);
      rows = db.select(sql, params);
    }

    final List<MemoryEntry> memories = <MemoryEntry>[];
    for (final sqlite3.Row row in rows) {
      final String sessionId = '${row['session_id'] ?? _unknownSessionId}';
      final String eventId = '${row['event_id'] ?? ''}';
      final String? author = row['author'] as String?;
      final Object? rawTimestamp = row['event_timestamp'];
      final double eventTimestamp = rawTimestamp is num
          ? rawTimestamp.toDouble()
          : double.tryParse('$rawTimestamp') ?? 0.0;
      final String contentJson = '${row['content_json'] ?? '{}'}';
      final String? customMetaJson = row['custom_metadata_json'] as String?;

      Content content;
      try {
        final Object? decoded = jsonDecode(contentJson);
        if (decoded is Map<String, Object?>) {
          content = _contentFromJson(decoded);
        } else if (decoded is Map) {
          content = _contentFromJson(
            decoded.map((Object? k, Object? v) => MapEntry('$k', v)),
          );
        } else {
          continue;
        }
      } catch (error) {
        developer.log(
          'Failed to parse content_json for event $eventId: $error',
          name: 'adk_dart.sqlite_memory_service',
        );
        continue;
      }

      final Map<String, Object?> customMetadata = <String, Object?>{
        'session_id': sessionId,
        'event_id': eventId,
      };
      if (customMetaJson != null && customMetaJson.isNotEmpty) {
        try {
          final Object? parsedMeta = jsonDecode(customMetaJson);
          if (parsedMeta is Map) {
            parsedMeta.forEach((Object? key, Object? value) {
              if (key is String) {
                customMetadata[key] = value;
              }
            });
          }
        } catch (error) {
          developer.log(
            'Failed to parse custom_metadata_json for event $eventId: $error',
            name: 'adk_dart.sqlite_memory_service',
          );
        }
      }

      memories.add(
        MemoryEntry(
          content: content,
          author: author,
          timestamp: formatTimestamp(eventTimestamp),
          customMetadata: customMetadata,
          id: eventId,
        ),
      );
    }

    return SearchMemoryResponse(memories: memories);
  }

  /// Closes the underlying SQLite database connection.
  Future<void> close() async {
    final sqlite3.Database? db = _db;
    _db = null;
    _closed = true;
    db?.close();
  }

  void _upsertRecord({
    required sqlite3.Database db,
    required String appName,
    required String userId,
    required String sessionId,
    required String eventId,
    required String? author,
    required double eventTimestamp,
    required String contentJson,
    required String searchText,
    required String customMetadataJson,
  }) {
    final List<Object?> params = <Object?>[
      appName,
      userId,
      sessionId,
      eventId,
      author,
      eventTimestamp,
      contentJson,
      searchText,
      customMetadataJson,
    ];

    db.execute('''
      INSERT INTO memory_events (
        app_name, user_id, session_id, event_id, author, event_timestamp, content_json, search_text, custom_metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (app_name, user_id, session_id, event_id) DO UPDATE SET
        author = excluded.author,
        event_timestamp = excluded.event_timestamp,
        content_json = excluded.content_json,
        search_text = excluded.search_text,
        custom_metadata_json = excluded.custom_metadata_json
      ''', params);

    db.execute('''
      INSERT INTO memory_entries (
        app_name, user_id, session_id, event_id, author, event_timestamp, content_json, search_text, custom_metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (app_name, user_id, session_id, event_id) DO UPDATE SET
        author = excluded.author,
        event_timestamp = excluded.event_timestamp,
        content_json = excluded.content_json,
        search_text = excluded.search_text,
        custom_metadata_json = excluded.custom_metadata_json
      ''', params);

    if (_ftsEnabled) {
      db.execute(
        '''
        DELETE FROM memory_events_fts
        WHERE app_name = ? AND user_id = ? AND session_id = ? AND event_id = ?
        ''',
        <Object?>[appName, userId, sessionId, eventId],
      );
      db.execute(
        '''
        INSERT INTO memory_events_fts (search_text, app_name, user_id, session_id, event_id)
        VALUES (?, ?, ?, ?, ?)
        ''',
        <Object?>[searchText, appName, userId, sessionId, eventId],
      );

      db.execute(
        '''
        DELETE FROM memory_entries_fts
        WHERE app_name = ? AND user_id = ? AND session_id = ? AND event_id = ?
        ''',
        <Object?>[appName, userId, sessionId, eventId],
      );
      db.execute(
        '''
        INSERT INTO memory_entries_fts (search_text, app_name, user_id, session_id, event_id)
        VALUES (?, ?, ?, ?, ?)
        ''',
        <Object?>[searchText, appName, userId, sessionId, eventId],
      );
    }
  }
}

String _encodeCustomMetadata(Map<String, Object?>? customMetadata) {
  try {
    return jsonEncode(customMetadata ?? const <String, Object?>{});
  } catch (error) {
    throw ArgumentError('custom_metadata must be JSON-serializable: $error');
  }
}

double _parseTimestampToSeconds(String? timestamp) {
  if (timestamp == null || timestamp.trim().isEmpty) {
    return DateTime.now().millisecondsSinceEpoch / 1000.0;
  }
  final double? asNumber = double.tryParse(timestamp.trim());
  if (asNumber != null) {
    return asNumber;
  }
  final DateTime? parsed = DateTime.tryParse(timestamp.trim());
  if (parsed != null) {
    return parsed.millisecondsSinceEpoch / 1000.0;
  }
  return DateTime.now().millisecondsSinceEpoch / 1000.0;
}

Map<String, Object?> _contentToJson(Content? content) {
  if (content == null) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map(_partToJson).toList(growable: false),
  };
}

Map<String, Object?> _partToJson(Part part) {
  final Map<String, Object?> json = <String, Object?>{};
  if (part.text != null) {
    json['text'] = part.text;
  }
  if (part.thought) {
    json['thought'] = true;
  }
  if (part.thoughtSignature != null) {
    json['thought_signature'] = base64Encode(part.thoughtSignature!);
  }
  if (part.functionCall != null) {
    json['function_call'] = <String, Object?>{
      'name': part.functionCall!.name,
      'args': part.functionCall!.args,
      if (part.functionCall!.id != null) 'id': part.functionCall!.id,
    };
  }
  if (part.functionResponse != null) {
    json['function_response'] = <String, Object?>{
      'name': part.functionResponse!.name,
      'response': part.functionResponse!.response,
      if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
    };
  }
  if (part.inlineData != null) {
    json['inline_data'] = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      if (part.inlineData!.displayName != null)
        'display_name': part.inlineData!.displayName,
    };
  }
  if (part.fileData != null) {
    json['file_data'] = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      if (part.fileData!.mimeType != null) 'mime_type': part.fileData!.mimeType,
      if (part.fileData!.displayName != null)
        'display_name': part.fileData!.displayName,
    };
  }
  return json;
}

Content _contentFromJson(Map<String, Object?> json) {
  final String? role = json['role'] as String?;
  final Object? rawParts = json['parts'];
  final List<Part> parts = <Part>[];
  if (rawParts is List) {
    for (final Object? item in rawParts) {
      if (item is Map) {
        parts.add(
          _partFromJson(
            item.map<String, Object?>((Object? k, Object? v) => MapEntry('$k', v)),
          ),
        );
      }
    }
  }
  return Content(role: role, parts: parts);
}

Part _partFromJson(Map<String, Object?> json) {
  final String? text = json['text'] as String?;
  final bool thought = json['thought'] == true;
  final Object? rawSig = json['thought_signature'] ?? json['thoughtSignature'];
  List<int>? thoughtSignature;
  if (rawSig is String && rawSig.isNotEmpty) {
    try {
      thoughtSignature = base64Decode(rawSig);
    } catch (_) {
      thoughtSignature = utf8.encode(rawSig);
    }
  } else if (rawSig is List<int>) {
    thoughtSignature = rawSig;
  }

  FunctionCall? functionCall;
  final Object? rawFc = json['function_call'] ?? json['functionCall'];
  if (rawFc is Map) {
    final Object? rawArgs = rawFc['args'];
    functionCall = FunctionCall(
      name: '${rawFc['name'] ?? ''}',
      args: rawArgs is Map
          ? rawArgs.map<String, dynamic>((Object? k, Object? v) => MapEntry('$k', v))
          : <String, dynamic>{},
      id: rawFc['id'] as String?,
    );
  }

  FunctionResponse? functionResponse;
  final Object? rawFr = json['function_response'] ?? json['functionResponse'];
  if (rawFr is Map) {
    final Object? rawResp = rawFr['response'];
    functionResponse = FunctionResponse(
      name: '${rawFr['name'] ?? ''}',
      response: rawResp is Map
          ? rawResp.map<String, dynamic>((Object? k, Object? v) => MapEntry('$k', v))
          : <String, dynamic>{},
      id: rawFr['id'] as String?,
    );
  }

  InlineData? inlineData;
  final Object? rawInline = json['inline_data'] ?? json['inlineData'];
  if (rawInline is Map) {
    final Object? rawData = rawInline['data'];
    List<int> bytes = const <int>[];
    if (rawData is String && rawData.isNotEmpty) {
      try {
        bytes = base64Decode(rawData);
      } catch (_) {
        bytes = utf8.encode(rawData);
      }
    } else if (rawData is List<int>) {
      bytes = rawData;
    }
    inlineData = InlineData(
      mimeType: '${rawInline['mime_type'] ?? rawInline['mimeType'] ?? ''}',
      data: bytes,
      displayName:
          (rawInline['display_name'] ?? rawInline['displayName']) as String?,
    );
  }

  FileData? fileData;
  final Object? rawFile = json['file_data'] ?? json['fileData'];
  if (rawFile is Map) {
    fileData = FileData(
      fileUri: '${rawFile['file_uri'] ?? rawFile['fileUri'] ?? ''}',
      mimeType: (rawFile['mime_type'] ?? rawFile['mimeType']) as String?,
      displayName:
          (rawFile['display_name'] ?? rawFile['displayName']) as String?,
    );
  }

  return Part(
    text: text,
    thought: thought,
    thoughtSignature: thoughtSignature,
    functionCall: functionCall,
    functionResponse: functionResponse,
    inlineData: inlineData,
    fileData: fileData,
  );
}
