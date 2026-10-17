/// Supported UI and agent response languages for the example application.
library;

/// Supported languages in the example app.
enum AppLanguage {
  /// English language option.
  en,

  /// Korean language option.
  ko,

  /// Japanese language option.
  ja,

  /// Simplified Chinese language option.
  zh,
}

/// Extension methods for [AppLanguage] providing language code and localized labels.
extension AppLanguageX on AppLanguage {
  /// The two-letter ISO language code.
  String get code {
    switch (this) {
      case AppLanguage.en:
        return 'en';
      case AppLanguage.ko:
        return 'ko';
      case AppLanguage.ja:
        return 'ja';
      case AppLanguage.zh:
        return 'zh';
    }
  }

  /// The native display label of the language.
  String get nativeLabel {
    switch (this) {
      case AppLanguage.en:
        return 'English';
      case AppLanguage.ko:
        return '한국어';
      case AppLanguage.ja:
        return '日本語';
      case AppLanguage.zh:
        return '中文';
    }
  }
}

/// Resolves an [AppLanguage] from the given two-letter ISO [code].
AppLanguage appLanguageFromCode(String? code) {
  switch (code) {
    case 'ko':
      return AppLanguage.ko;
    case 'ja':
      return AppLanguage.ja;
    case 'zh':
      return AppLanguage.zh;
    case 'en':
    default:
      return AppLanguage.en;
  }
}

/// Returns a system prompt instruction specifying the desired response [language].
String responseLanguageInstruction(AppLanguage language) {
  switch (language) {
    case AppLanguage.en:
      return 'Respond in English.';
    case AppLanguage.ko:
      return 'Respond in Korean.';
    case AppLanguage.ja:
      return 'Respond in Japanese.';
    case AppLanguage.zh:
      return 'Respond in Simplified Chinese.';
  }
}
