enum UserExampleConnectionDslType { always, intent, contains, unknown }

class UserExampleConnectionDsl {
  const UserExampleConnectionDsl({
    required this.type,
    required this.raw,
    required this.value,
  });

  final UserExampleConnectionDslType type;
  final String raw;
  final String value;

  bool get isValid => type != UserExampleConnectionDslType.unknown;

  String get normalizedExpression {
    switch (type) {
      case UserExampleConnectionDslType.always:
        return 'always';
      case UserExampleConnectionDslType.intent:
        return 'intent:$value';
      case UserExampleConnectionDslType.contains:
        return 'contains:$value';
      case UserExampleConnectionDslType.unknown:
        return raw.trim();
    }
  }

  static const Set<String> supportedIntents = <String>{
    'greeting',
    'farewell',
    'weather',
    'time',
    'capital',
    'billing',
    'support',
    'payment',
    'refund',
    'login',
    'technical',
    'general',
  };

  static UserExampleConnectionDsl parse(String input) {
    final String raw = input.trim();
    if (raw.isEmpty) {
      return const UserExampleConnectionDsl(
        type: UserExampleConnectionDslType.always,
        raw: '',
        value: '',
      );
    }
    final String lower = raw.toLowerCase();
    if (lower == 'always') {
      return UserExampleConnectionDsl(
        type: UserExampleConnectionDslType.always,
        raw: raw,
        value: '',
      );
    }
    if (lower.startsWith('intent:')) {
      final String value = raw.substring('intent:'.length).trim().toLowerCase();
      if (value.isNotEmpty && supportedIntents.contains(value)) {
        return UserExampleConnectionDsl(
          type: UserExampleConnectionDslType.intent,
          raw: raw,
          value: value,
        );
      }
      return UserExampleConnectionDsl(
        type: UserExampleConnectionDslType.unknown,
        raw: raw,
        value: value,
      );
    }
    if (lower.startsWith('contains:')) {
      final String value = raw.substring('contains:'.length).trim();
      if (value.isNotEmpty) {
        return UserExampleConnectionDsl(
          type: UserExampleConnectionDslType.contains,
          raw: raw,
          value: value,
        );
      }
      return UserExampleConnectionDsl(
        type: UserExampleConnectionDslType.unknown,
        raw: raw,
        value: value,
      );
    }
    return UserExampleConnectionDsl(
      type: UserExampleConnectionDslType.unknown,
      raw: raw,
      value: raw,
    );
  }
}
