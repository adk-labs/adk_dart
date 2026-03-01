import 'package:flutter_adk_example/domain/models/app_language.dart';

class AppSettings {
  const AppSettings({
    required this.apiKey,
    required this.mcpUrl,
    required this.mcpBearerToken,
    required this.language,
    required this.debugLogsEnabled,
  });

  final String apiKey;
  final String mcpUrl;
  final String mcpBearerToken;
  final AppLanguage language;
  final bool debugLogsEnabled;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  AppSettings copyWith({
    String? apiKey,
    String? mcpUrl,
    String? mcpBearerToken,
    AppLanguage? language,
    bool? debugLogsEnabled,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      mcpUrl: mcpUrl ?? this.mcpUrl,
      mcpBearerToken: mcpBearerToken ?? this.mcpBearerToken,
      language: language ?? this.language,
      debugLogsEnabled: debugLogsEnabled ?? this.debugLogsEnabled,
    );
  }
}
