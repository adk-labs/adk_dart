import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

final class _Sqlite3Handle extends Opaque {}

final class _Sqlite3Statement extends Opaque {}

const int _sqliteOk = 0;
const int _sqliteRow = 100;
const int _sqliteDone = 101;

const int _sqliteInteger = 1;
const int _sqliteFloat = 2;
const int _sqliteText = 3;
const int _sqliteBlob = 4;
const int _sqliteNull = 5;

const int _sqliteOpenReadOnly = 0x00000001;
const int _sqliteOpenReadWrite = 0x00000002;
const int _sqliteOpenCreate = 0x00000004;
const int _sqliteOpenUri = 0x00000040;
const int _sqliteOpenFullMutex = 0x00010000;

class ResolvedSqliteDbUrl {
  const ResolvedSqliteDbUrl({
    required this.storePath,
    required this.connectPath,
    required this.connectUri,
    required this.readOnly,
    required this.inMemory,
  });

  final String storePath;
  final String connectPath;
  final bool connectUri;
  final bool readOnly;
  final bool inMemory;
}

ResolvedSqliteDbUrl resolveSqliteDbUrl(
  String dbUrl, {
  String argumentName = 'dbUrl',
}) {
  final String normalized = dbUrl.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(dbUrl, argumentName, 'must not be empty.');
  }

  if (normalized == ':memory:') {
    return const ResolvedSqliteDbUrl(
      storePath: ':memory:',
      connectPath: ':memory:',
      connectUri: false,
      readOnly: false,
      inMemory: true,
    );
  }

  if (!normalized.contains('://')) {
    return ResolvedSqliteDbUrl(
      storePath: normalized,
      connectPath: normalized,
      connectUri: normalized.startsWith('file:'),
      readOnly: false,
      inMemory: _isInMemoryStorePath(normalized),
    );
  }

  if (!normalized.startsWith('sqlite:') &&
      !normalized.startsWith('sqlite+aiosqlite:')) {
    throw ArgumentError.value(
      dbUrl,
      argumentName,
      'Only sqlite URLs are supported.',
    );
  }

  final String sanitizedInput = _escapeInvalidPercents(normalized);
  final Uri uri;
  try {
    uri = Uri.parse(sanitizedInput);
  } on FormatException catch (e) {
    throw ArgumentError.value(
      dbUrl,
      argumentName,
      'Invalid sqlite URL: ${e.message}',
    );
  }

  final String rawPath = _extractRawSqlitePath(sanitizedInput);
  final String path = _resolveSqliteUriPath(rawPath, dbUrl, argumentName);

  final Map<String, List<String>> query = _parseQueryParameters(uri.query);
  return _buildResolvedStorePath(
    path: path,
    query: query,
    dbUrl: dbUrl,
    argumentName: argumentName,
  );
}

class SqliteMigrationDatabase {
  SqliteMigrationDatabase._({
    required _SqliteBindings bindings,
    required Pointer<_Sqlite3Handle> handle,
    required String displayPath,
  }) : _bindings = bindings,
       _handle = handle,
       _displayPath = displayPath;

  factory SqliteMigrationDatabase.open({
    required String connectPath,
    required String displayPath,
    required bool uri,
    required bool readOnly,
  }) {
    final _SqliteBindings bindings = _SqliteBindings.instance;
    final Pointer<Pointer<_Sqlite3Handle>> dbOut = _NativeMemory.allocate(
      sizeOf<Pointer<_Sqlite3Handle>>(),
    ).cast<Pointer<_Sqlite3Handle>>();
    dbOut.value = nullptr;

    final _NativeString path = _NativeString.fromDart(connectPath);
    final int flags =
        (readOnly
            ? _sqliteOpenReadOnly
            : (_sqliteOpenReadWrite | _sqliteOpenCreate)) |
        (uri ? _sqliteOpenUri : 0) |
        _sqliteOpenFullMutex;

    final int resultCode;
    try {
      resultCode = bindings.sqlite3OpenV2(
        path.pointer,
        dbOut,
        flags,
        nullptr.cast<Uint8>(),
      );
    } finally {
      path.dispose();
    }

    final Pointer<_Sqlite3Handle> handle = dbOut.value;
    _NativeMemory.free(dbOut.cast<Void>());

    if (resultCode != _sqliteOk) {
      String message = 'Failed to open SQLite database.';
      if (handle != nullptr) {
        message = _decodeCString(bindings.sqlite3Errmsg(handle));
        bindings.sqlite3CloseV2(handle);
      }
      throw FileSystemException(
        'SQLite open error ($resultCode): $message',
        displayPath,
      );
    }

    return SqliteMigrationDatabase._(
      bindings: bindings,
      handle: handle,
      displayPath: displayPath,
    );
  }

  final _SqliteBindings _bindings;
  final Pointer<_Sqlite3Handle> _handle;
  final String _displayPath;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _bindings.sqlite3CloseV2(_handle);
    _disposed = true;
  }

  void execute(String sql, [List<Object?> params = const <Object?>[]]) {
    _ensureOpen();
    final _PreparedStatement statement = _prepare(sql);
    try {
      _bindParameters(statement, params);
      int stepCode = _bindings.sqlite3Step(statement.handle);
      while (stepCode == _sqliteRow) {
        stepCode = _bindings.sqlite3Step(statement.handle);
      }
      if (stepCode != _sqliteDone) {
        _throwSqliteError(operation: 'execute', code: stepCode);
      }
    } finally {
      statement.dispose();
    }
  }

  List<Map<String, Object?>> query(
    String sql, [
    List<Object?> params = const <Object?>[],
  ]) {
    _ensureOpen();
    final _PreparedStatement statement = _prepare(sql);
    try {
      _bindParameters(statement, params);
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      while (true) {
        final int stepCode = _bindings.sqlite3Step(statement.handle);
        if (stepCode == _sqliteDone) {
          break;
        }
        if (stepCode != _sqliteRow) {
          _throwSqliteError(operation: 'query', code: stepCode);
        }

        final int columnCount = _bindings.sqlite3ColumnCount(statement.handle);
        final Map<String, Object?> row = <String, Object?>{};
        for (int index = 0; index < columnCount; index += 1) {
          final String name = _decodeCString(
            _bindings.sqlite3ColumnName(statement.handle, index),
          );
          row[name] = _readColumn(statement.handle, index);
        }
        rows.add(row);
      }
      return rows;
    } finally {
      statement.dispose();
    }
  }

  void runTransaction(void Function() action) {
    execute('BEGIN');
    bool committed = false;
    try {
      action();
      execute('COMMIT');
      committed = true;
    } finally {
      if (!committed) {
        try {
          execute('ROLLBACK');
        } catch (_) {}
      }
    }
  }

  bool hasTable(String tableName) {
    final List<Map<String, Object?>> rows = query(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      <Object?>[tableName],
    );
    return rows.isNotEmpty;
  }

  Set<String> tableColumns(String tableName) {
    final List<Map<String, Object?>> rows = query(
      'PRAGMA table_info($tableName)',
    );
    return rows
        .map((Map<String, Object?> row) => '${row['name'] ?? ''}')
        .where((String name) => name.isNotEmpty)
        .toSet();
  }

  _PreparedStatement _prepare(String sql) {
    final _NativeString sqlString = _NativeString.fromDart(sql);
    final Pointer<Pointer<_Sqlite3Statement>> stmtOut = _NativeMemory.allocate(
      sizeOf<Pointer<_Sqlite3Statement>>(),
    ).cast<Pointer<_Sqlite3Statement>>();
    stmtOut.value = nullptr;

    final int resultCode;
    try {
      resultCode = _bindings.sqlite3PrepareV2(
        _handle,
        sqlString.pointer,
        -1,
        stmtOut,
        nullptr.cast<Pointer<Uint8>>(),
      );
    } finally {
      sqlString.dispose();
    }

    final Pointer<_Sqlite3Statement> statement = stmtOut.value;
    _NativeMemory.free(stmtOut.cast<Void>());

    if (resultCode != _sqliteOk) {
      if (statement != nullptr) {
        _bindings.sqlite3Finalize(statement);
      }
      _throwSqliteError(operation: 'prepare', code: resultCode);
    }

    return _PreparedStatement(_bindings, statement);
  }

  void _bindParameters(_PreparedStatement statement, List<Object?> params) {
    for (int index = 0; index < params.length; index += 1) {
      final int parameterIndex = index + 1;
      final Object? value = params[index];

      int resultCode;
      if (value == null) {
        resultCode = _bindings.sqlite3BindNull(
          statement.handle,
          parameterIndex,
        );
      } else if (value is bool) {
        resultCode = _bindings.sqlite3BindInt(
          statement.handle,
          parameterIndex,
          value ? 1 : 0,
        );
      } else if (value is int) {
        resultCode = _bindings.sqlite3BindInt64(
          statement.handle,
          parameterIndex,
          value,
        );
      } else if (value is double) {
        resultCode = _bindings.sqlite3BindDouble(
          statement.handle,
          parameterIndex,
          value,
        );
      } else if (value is num) {
        resultCode = _bindings.sqlite3BindDouble(
          statement.handle,
          parameterIndex,
          value.toDouble(),
        );
      } else if (value is Uint8List) {
        // Fallback: bind blobs as base64 text to keep migration code simple.
        final String encoded = base64.encode(value);
        final _NativeString textValue = _NativeString.fromDart(encoded);
        statement.registerOwnedString(textValue);
        resultCode = _bindings.sqlite3BindText(
          statement.handle,
          parameterIndex,
          textValue.pointer,
          -1,
          nullptr.cast<NativeFunction<_SqliteDestructorNative>>(),
        );
      } else {
        final _NativeString textValue = _NativeString.fromDart('$value');
        statement.registerOwnedString(textValue);
        resultCode = _bindings.sqlite3BindText(
          statement.handle,
          parameterIndex,
          textValue.pointer,
          -1,
          nullptr.cast<NativeFunction<_SqliteDestructorNative>>(),
        );
      }

      if (resultCode != _sqliteOk) {
        _throwSqliteError(operation: 'bind', code: resultCode);
      }
    }
  }

  Object? _readColumn(Pointer<_Sqlite3Statement> statement, int index) {
    final int type = _bindings.sqlite3ColumnType(statement, index);
    switch (type) {
      case _sqliteNull:
        return null;
      case _sqliteInteger:
        return _bindings.sqlite3ColumnInt64(statement, index);
      case _sqliteFloat:
        return _bindings.sqlite3ColumnDouble(statement, index);
      case _sqliteText:
        return _decodeCString(_bindings.sqlite3ColumnText(statement, index));
      case _sqliteBlob:
        final int length = _bindings.sqlite3ColumnBytes(statement, index);
        if (length <= 0) {
          return Uint8List(0);
        }
        final Pointer<Void> blobPointer = _bindings.sqlite3ColumnBlob(
          statement,
          index,
        );
        if (blobPointer == nullptr) {
          return Uint8List(0);
        }
        return Uint8List.fromList(
          blobPointer.cast<Uint8>().asTypedList(length),
        );
      default:
        return null;
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('SQLite database connection is already closed.');
    }
  }

  Never _throwSqliteError({required String operation, required int code}) {
    final String message = _decodeCString(_bindings.sqlite3Errmsg(_handle));
    throw FileSystemException(
      'SQLite $operation error ($code): $message',
      _displayPath,
    );
  }
}

ResolvedSqliteDbUrl _buildResolvedStorePath({
  required String path,
  required Map<String, List<String>> query,
  required String dbUrl,
  required String argumentName,
}) {
  if (path.isEmpty) {
    throw ArgumentError.value(
      dbUrl,
      argumentName,
      'SQLite URL must include a file path.',
    );
  }

  final bool readOnly = _parseSqliteReadOnlyMode(query);
  final bool inMemory =
      _isInMemoryStorePath(path) || _parseSqliteInMemoryMode(query);
  final String connectQuery = _buildSqliteConnectionQuery(query);

  if (connectQuery.isNotEmpty) {
    return ResolvedSqliteDbUrl(
      storePath: path,
      connectPath: 'file:$path?$connectQuery',
      connectUri: true,
      readOnly: readOnly,
      inMemory: inMemory,
    );
  }

  return ResolvedSqliteDbUrl(
    storePath: path,
    connectPath: path,
    connectUri: path.startsWith('file:'),
    readOnly: readOnly,
    inMemory: inMemory,
  );
}

String _resolveSqliteUriPath(
  String rawPath,
  String dbUrl,
  String argumentName,
) {
  String path = Uri.decodeComponent(rawPath);
  if (path == ':memory:' || path == '/:memory:') {
    return ':memory:';
  }
  if (path.isEmpty || path == '/') {
    throw ArgumentError.value(
      dbUrl,
      argumentName,
      'SQLite URL must include a file path.',
    );
  }

  if (path.startsWith('//')) {
    path = path.substring(1);
  } else if (path.startsWith('/')) {
    path = path.substring(1);
  }

  if (path.isEmpty) {
    throw ArgumentError.value(
      dbUrl,
      argumentName,
      'SQLite URL must include a file path.',
    );
  }
  return path;
}

String _extractRawSqlitePath(String sqliteUrl) {
  final int schemeSeparator = sqliteUrl.indexOf('://');
  if (schemeSeparator < 0) {
    return '';
  }

  String rest = sqliteUrl.substring(schemeSeparator + 3);
  final int queryIndex = rest.indexOf('?');
  final int fragmentIndex = rest.indexOf('#');
  int end = rest.length;
  if (queryIndex >= 0 && queryIndex < end) {
    end = queryIndex;
  }
  if (fragmentIndex >= 0 && fragmentIndex < end) {
    end = fragmentIndex;
  }
  rest = rest.substring(0, end);
  if (rest.isEmpty) {
    return '';
  }

  if (!rest.startsWith('/')) {
    if (rest == ':memory:') {
      return ':memory:';
    }
    final int slash = rest.indexOf('/');
    if (slash < 0) {
      return '';
    }
    return rest.substring(slash);
  }

  return rest;
}

bool _parseSqliteReadOnlyMode(Map<String, List<String>> query) {
  final List<String> modeValues = query['mode'] ?? <String>[];
  for (final String rawMode in modeValues) {
    if (rawMode.trim().toLowerCase() == 'ro') {
      return true;
    }
  }
  return false;
}

bool _parseSqliteInMemoryMode(Map<String, List<String>> query) {
  final List<String> modeValues = query['mode'] ?? <String>[];
  for (final String rawMode in modeValues) {
    if (rawMode.trim().toLowerCase() == 'memory') {
      return true;
    }
  }
  return false;
}

bool _isInMemoryStorePath(String path) {
  final String normalized = path.trim().toLowerCase();
  return normalized == ':memory:' || normalized == 'file::memory:';
}

Map<String, List<String>> _parseQueryParameters(String query) {
  if (query.isEmpty) {
    return <String, List<String>>{};
  }

  final Map<String, List<String>> parsed = <String, List<String>>{};
  for (final String pair in query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final int separator = pair.indexOf('=');
    final String keyPart = separator < 0 ? pair : pair.substring(0, separator);
    final String valuePart = separator < 0 ? '' : pair.substring(separator + 1);
    final String key = Uri.decodeQueryComponent(keyPart);
    final String value = Uri.decodeQueryComponent(valuePart);
    parsed.putIfAbsent(key, () => <String>[]).add(value);
  }
  return parsed;
}

String _buildSqliteConnectionQuery(Map<String, List<String>> query) {
  if (query.isEmpty) {
    return '';
  }

  final List<String> encodedPairs = <String>[];
  query.forEach((String key, List<String> values) {
    if (values.isEmpty) {
      return;
    }
    for (final String value in values) {
      encodedPairs.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
      );
    }
  });
  return encodedPairs.join('&');
}

String _escapeInvalidPercents(String input) {
  final StringBuffer escaped = StringBuffer();
  for (int index = 0; index < input.length; index += 1) {
    final String char = input[index];
    if (char != '%') {
      escaped.write(char);
      continue;
    }
    if (index + 2 < input.length &&
        _isHexDigit(input.codeUnitAt(index + 1)) &&
        _isHexDigit(input.codeUnitAt(index + 2))) {
      escaped.write(char);
      continue;
    }
    escaped.write('%25');
  }
  return escaped.toString();
}

bool _isHexDigit(int codeUnit) {
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 70) ||
      (codeUnit >= 97 && codeUnit <= 102);
}

class _PreparedStatement {
  _PreparedStatement(this._bindings, this.handle);

  final _SqliteBindings _bindings;
  final Pointer<_Sqlite3Statement> handle;
  final List<_NativeString> _ownedStrings = <_NativeString>[];
  bool _disposed = false;

  void registerOwnedString(_NativeString value) {
    _ownedStrings.add(value);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _bindings.sqlite3Finalize(handle);
    for (final _NativeString string in _ownedStrings) {
      string.dispose();
    }
    _ownedStrings.clear();
    _disposed = true;
  }
}

class _SqliteBindings {
  _SqliteBindings._(DynamicLibrary library)
    : sqlite3OpenV2 = library
          .lookupFunction<_SqliteOpenV2Native, _SqliteOpenV2Dart>(
            'sqlite3_open_v2',
          ),
      sqlite3CloseV2 = library
          .lookupFunction<_SqliteCloseV2Native, _SqliteCloseV2Dart>(
            'sqlite3_close_v2',
          ),
      sqlite3Errmsg = library
          .lookupFunction<_SqliteErrmsgNative, _SqliteErrmsgDart>(
            'sqlite3_errmsg',
          ),
      sqlite3PrepareV2 = library
          .lookupFunction<_SqlitePrepareV2Native, _SqlitePrepareV2Dart>(
            'sqlite3_prepare_v2',
          ),
      sqlite3Step = library.lookupFunction<_SqliteStepNative, _SqliteStepDart>(
        'sqlite3_step',
      ),
      sqlite3Finalize = library
          .lookupFunction<_SqliteFinalizeNative, _SqliteFinalizeDart>(
            'sqlite3_finalize',
          ),
      sqlite3BindNull = library
          .lookupFunction<_SqliteBindNullNative, _SqliteBindNullDart>(
            'sqlite3_bind_null',
          ),
      sqlite3BindInt = library
          .lookupFunction<_SqliteBindIntNative, _SqliteBindIntDart>(
            'sqlite3_bind_int',
          ),
      sqlite3BindInt64 = library
          .lookupFunction<_SqliteBindInt64Native, _SqliteBindInt64Dart>(
            'sqlite3_bind_int64',
          ),
      sqlite3BindDouble = library
          .lookupFunction<_SqliteBindDoubleNative, _SqliteBindDoubleDart>(
            'sqlite3_bind_double',
          ),
      sqlite3BindText = library
          .lookupFunction<_SqliteBindTextNative, _SqliteBindTextDart>(
            'sqlite3_bind_text',
          ),
      sqlite3ColumnCount = library
          .lookupFunction<_SqliteColumnCountNative, _SqliteColumnCountDart>(
            'sqlite3_column_count',
          ),
      sqlite3ColumnName = library
          .lookupFunction<_SqliteColumnNameNative, _SqliteColumnNameDart>(
            'sqlite3_column_name',
          ),
      sqlite3ColumnType = library
          .lookupFunction<_SqliteColumnTypeNative, _SqliteColumnTypeDart>(
            'sqlite3_column_type',
          ),
      sqlite3ColumnInt64 = library
          .lookupFunction<_SqliteColumnInt64Native, _SqliteColumnInt64Dart>(
            'sqlite3_column_int64',
          ),
      sqlite3ColumnDouble = library
          .lookupFunction<_SqliteColumnDoubleNative, _SqliteColumnDoubleDart>(
            'sqlite3_column_double',
          ),
      sqlite3ColumnText = library
          .lookupFunction<_SqliteColumnTextNative, _SqliteColumnTextDart>(
            'sqlite3_column_text',
          ),
      sqlite3ColumnBlob = library
          .lookupFunction<_SqliteColumnBlobNative, _SqliteColumnBlobDart>(
            'sqlite3_column_blob',
          ),
      sqlite3ColumnBytes = library
          .lookupFunction<_SqliteColumnBytesNative, _SqliteColumnBytesDart>(
            'sqlite3_column_bytes',
          );

  static final _SqliteBindings instance = _SqliteBindings._(
    _openSqliteLibrary(),
  );

  final _SqliteOpenV2Dart sqlite3OpenV2;
  final _SqliteCloseV2Dart sqlite3CloseV2;
  final _SqliteErrmsgDart sqlite3Errmsg;
  final _SqlitePrepareV2Dart sqlite3PrepareV2;
  final _SqliteStepDart sqlite3Step;
  final _SqliteFinalizeDart sqlite3Finalize;
  final _SqliteBindNullDart sqlite3BindNull;
  final _SqliteBindIntDart sqlite3BindInt;
  final _SqliteBindInt64Dart sqlite3BindInt64;
  final _SqliteBindDoubleDart sqlite3BindDouble;
  final _SqliteBindTextDart sqlite3BindText;
  final _SqliteColumnCountDart sqlite3ColumnCount;
  final _SqliteColumnNameDart sqlite3ColumnName;
  final _SqliteColumnTypeDart sqlite3ColumnType;
  final _SqliteColumnInt64Dart sqlite3ColumnInt64;
  final _SqliteColumnDoubleDart sqlite3ColumnDouble;
  final _SqliteColumnTextDart sqlite3ColumnText;
  final _SqliteColumnBlobDart sqlite3ColumnBlob;
  final _SqliteColumnBytesDart sqlite3ColumnBytes;
}

class _NativeMemory {
  static final DynamicLibrary _library = _openCLibrary();

  static final Pointer<Void> Function(int) _malloc = _library
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');

  static final void Function(Pointer<Void>) _free = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');

  static Pointer<Void> allocate(int byteCount) {
    final Pointer<Void> pointer = _malloc(byteCount);
    if (pointer == nullptr) {
      throw StateError('Native allocation failed.');
    }
    return pointer;
  }

  static void free(Pointer<Void> pointer) {
    if (pointer == nullptr) {
      return;
    }
    _free(pointer);
  }
}

class _NativeString {
  _NativeString._(this.pointer);

  final Pointer<Uint8> pointer;

  factory _NativeString.fromDart(String value) {
    final List<int> bytes = utf8.encode(value);
    final Pointer<Uint8> buffer = _NativeMemory.allocate(
      bytes.length + 1,
    ).cast<Uint8>();
    final Uint8List nativeBytes = buffer.asTypedList(bytes.length + 1);
    nativeBytes.setRange(0, bytes.length, bytes);
    nativeBytes[bytes.length] = 0;
    return _NativeString._(buffer);
  }

  void dispose() {
    _NativeMemory.free(pointer.cast<Void>());
  }
}

String _decodeCString(Pointer<Uint8> pointer) {
  if (pointer == nullptr) {
    return '';
  }

  int length = 0;
  while (pointer[length] != 0) {
    length += 1;
  }

  if (length == 0) {
    return '';
  }

  return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
}

DynamicLibrary _openSqliteLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('/usr/lib/libsqlite3.dylib');
  }
  if (Platform.isLinux) {
    try {
      return DynamicLibrary.open('libsqlite3.so.0');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so');
    }
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('sqlite3.dll');
  }
  return DynamicLibrary.process();
}

DynamicLibrary _openCLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libc.so.6');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('msvcrt.dll');
  }
  return DynamicLibrary.process();
}

typedef _SqliteDestructorNative = Void Function(Pointer<Void>);

typedef _SqliteOpenV2Native =
    Int32 Function(
      Pointer<Uint8> filename,
      Pointer<Pointer<_Sqlite3Handle>> db,
      Int32 flags,
      Pointer<Uint8> vfs,
    );

typedef _SqliteOpenV2Dart =
    int Function(
      Pointer<Uint8> filename,
      Pointer<Pointer<_Sqlite3Handle>> db,
      int flags,
      Pointer<Uint8> vfs,
    );

typedef _SqliteCloseV2Native = Int32 Function(Pointer<_Sqlite3Handle> db);
typedef _SqliteCloseV2Dart = int Function(Pointer<_Sqlite3Handle> db);

typedef _SqliteErrmsgNative =
    Pointer<Uint8> Function(Pointer<_Sqlite3Handle> db);
typedef _SqliteErrmsgDart = Pointer<Uint8> Function(Pointer<_Sqlite3Handle> db);

typedef _SqlitePrepareV2Native =
    Int32 Function(
      Pointer<_Sqlite3Handle> db,
      Pointer<Uint8> sql,
      Int32 byteCount,
      Pointer<Pointer<_Sqlite3Statement>> statement,
      Pointer<Pointer<Uint8>> tail,
    );

typedef _SqlitePrepareV2Dart =
    int Function(
      Pointer<_Sqlite3Handle> db,
      Pointer<Uint8> sql,
      int byteCount,
      Pointer<Pointer<_Sqlite3Statement>> statement,
      Pointer<Pointer<Uint8>> tail,
    );

typedef _SqliteStepNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement);
typedef _SqliteStepDart = int Function(Pointer<_Sqlite3Statement> statement);

typedef _SqliteFinalizeNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement);
typedef _SqliteFinalizeDart =
    int Function(Pointer<_Sqlite3Statement> statement);

typedef _SqliteBindNullNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement, Int32 index);
typedef _SqliteBindNullDart =
    int Function(Pointer<_Sqlite3Statement> statement, int index);

typedef _SqliteBindIntNative =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Int32 value,
    );
typedef _SqliteBindIntDart =
    int Function(Pointer<_Sqlite3Statement> statement, int index, int value);

typedef _SqliteBindInt64Native =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Int64 value,
    );
typedef _SqliteBindInt64Dart =
    int Function(Pointer<_Sqlite3Statement> statement, int index, int value);

typedef _SqliteBindDoubleNative =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Double value,
    );
typedef _SqliteBindDoubleDart =
    int Function(Pointer<_Sqlite3Statement> statement, int index, double value);

typedef _SqliteBindTextNative =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Pointer<Uint8> value,
      Int32 length,
      Pointer<NativeFunction<_SqliteDestructorNative>> destructor,
    );

typedef _SqliteBindTextDart =
    int Function(
      Pointer<_Sqlite3Statement> statement,
      int index,
      Pointer<Uint8> value,
      int length,
      Pointer<NativeFunction<_SqliteDestructorNative>> destructor,
    );

typedef _SqliteColumnCountNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement);
typedef _SqliteColumnCountDart =
    int Function(Pointer<_Sqlite3Statement> statement);

typedef _SqliteColumnNameNative =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnNameDart =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnTypeNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnTypeDart =
    int Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnInt64Native =
    Int64 Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnInt64Dart =
    int Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnDoubleNative =
    Double Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnDoubleDart =
    double Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnTextNative =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnTextDart =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnBlobNative =
    Pointer<Void> Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnBlobDart =
    Pointer<Void> Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnBytesNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnBytesDart =
    int Function(Pointer<_Sqlite3Statement> statement, int column);
