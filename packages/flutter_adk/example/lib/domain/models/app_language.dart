enum AppLanguage { en, ko, ja, zh }

extension AppLanguageX on AppLanguage {
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
