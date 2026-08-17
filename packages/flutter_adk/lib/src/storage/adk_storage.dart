import 'dart:async';

/// A lightweight key-value storage interface for ADK Flutter apps.
///
/// Implement this interface or wrap your favorite storage library
/// (e.g. `shared_preferences`, `flutter_secure_storage`, `hive`, `sqflite`).
abstract class AdkKeyValueStorage {
  /// Reads a string value for [key], or returns `null` if not found.
  FutureOr<String?> read(String key);

  /// Writes a string [value] for [key].
  FutureOr<void> write(String key, String value);

  /// Deletes the entry for [key].
  FutureOr<void> delete(String key);

  /// Returns all keys matching an optional [prefix].
  FutureOr<List<String>> getKeys({String prefix = ''});
}

/// In-memory implementation of [AdkKeyValueStorage].
class AdkMemoryStorage implements AdkKeyValueStorage {
  final Map<String, String> _store = <String, String>{};

  @override
  String? read(String key) => _store[key];

  @override
  void write(String key, String value) => _store[key] = value;

  @override
  void delete(String key) => _store.remove(key);

  @override
  List<String> getKeys({String prefix = ''}) {
    if (prefix.isEmpty) {
      return _store.keys.toList();
    }
    return _store.keys.where((String k) => k.startsWith(prefix)).toList();
  }
}

/// Adapter allowing developers to construct an [AdkKeyValueStorage]
/// from simple callbacks without subclassing.
class AdkCustomStorage implements AdkKeyValueStorage {
  /// Creates an [AdkCustomStorage] with delegate callbacks.
  AdkCustomStorage({
    required FutureOr<String?> Function(String key) read,
    required FutureOr<void> Function(String key, String value) write,
    required FutureOr<void> Function(String key) delete,
    required FutureOr<List<String>> Function({String prefix}) getKeys,
  })  : _read = read,
        _write = write,
        _delete = delete,
        _getKeys = getKeys;

  final FutureOr<String?> Function(String key) _read;
  final FutureOr<void> Function(String key, String value) _write;
  final FutureOr<void> Function(String key) _delete;
  final FutureOr<List<String>> Function({String prefix}) _getKeys;

  @override
  FutureOr<String?> read(String key) => _read(key);

  @override
  FutureOr<void> write(String key, String value) => _write(key, value);

  @override
  FutureOr<void> delete(String key) => _delete(key);

  @override
  FutureOr<List<String>> getKeys({String prefix = ''}) => _getKeys(prefix: prefix);
}
