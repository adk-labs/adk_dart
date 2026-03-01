import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_adk_example/domain/models/custom_agent_config.dart';

abstract class CustomAgentConfigRepository {
  Future<CustomAgentConfig> load();

  Future<void> save(CustomAgentConfig config);
}

class SharedPreferencesCustomAgentConfigRepository
    implements CustomAgentConfigRepository {
  static const String _prefKey = 'flutter_adk_example_custom_agent_config_v1';

  @override
  Future<CustomAgentConfig> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefKey);
      if (raw == null || raw.trim().isEmpty) {
        return CustomAgentConfig.defaults();
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return CustomAgentConfig.defaults();
      }
      return CustomAgentConfig.fromJson(
        decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
    } catch (_) {
      return CustomAgentConfig.defaults();
    }
  }

  @override
  Future<void> save(CustomAgentConfig config) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(config.toJson()));
    } catch (_) {
      // Keep running with in-memory state when persistence fails.
    }
  }
}
