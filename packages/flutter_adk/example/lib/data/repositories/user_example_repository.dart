import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_adk_example/domain/models/user_example_config.dart';

abstract class UserExampleRepository {
  Future<List<UserExampleConfig>> loadAll();

  Future<void> saveAll(List<UserExampleConfig> examples);
}

class SharedPreferencesUserExampleRepository implements UserExampleRepository {
  static const String _prefKey = 'flutter_adk_example_user_examples_v1';

  @override
  Future<List<UserExampleConfig>> loadAll() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefKey);
      if (raw == null || raw.trim().isEmpty) {
        return <UserExampleConfig>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <UserExampleConfig>[];
      }
      final List<UserExampleConfig> items = decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) => UserExampleConfig.fromJson(
              item.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList();
      items.sort(
        (UserExampleConfig a, UserExampleConfig b) =>
            b.updatedAtMs.compareTo(a.updatedAtMs),
      );
      return items;
    } catch (_) {
      return <UserExampleConfig>[];
    }
  }

  @override
  Future<void> saveAll(List<UserExampleConfig> examples) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<Map<String, Object?>> json = examples
          .map((UserExampleConfig item) => item.toJson())
          .toList(growable: false);
      await prefs.setString(_prefKey, jsonEncode(json));
    } catch (_) {
      // Keep app usable even if persistence fails.
    }
  }
}
