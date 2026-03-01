import 'package:flutter_adk_example/domain/models/custom_agent_config.dart';

enum UserExampleArchitecture { single, team, sequential, parallel, loop }

extension UserExampleArchitectureX on UserExampleArchitecture {
  String get labelKey {
    switch (this) {
      case UserExampleArchitecture.single:
        return 'user_example.arch.single';
      case UserExampleArchitecture.team:
        return 'user_example.arch.team';
      case UserExampleArchitecture.sequential:
        return 'user_example.arch.sequential';
      case UserExampleArchitecture.parallel:
        return 'user_example.arch.parallel';
      case UserExampleArchitecture.loop:
        return 'user_example.arch.loop';
    }
  }
}

class UserExampleConfig {
  const UserExampleConfig({
    required this.id,
    required this.title,
    required this.summary,
    required this.initialAssistantMessage,
    required this.inputHint,
    required this.architecture,
    required this.agents,
    required this.entryAgentIndex,
    required this.connections,
    required this.prompts,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory UserExampleConfig.defaults({String? id}) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return UserExampleConfig(
      id:
          id ??
          'user_example_${DateTime.now().microsecondsSinceEpoch.toString()}',
      title: 'My Example',
      summary: 'User-defined example with custom agent topology.',
      initialAssistantMessage:
          'This is your custom example. Ask a question to run your configured agents.',
      inputHint: 'Ask your custom example...',
      architecture: UserExampleArchitecture.single,
      agents: <CustomAgentConfig>[CustomAgentConfig.defaults()],
      entryAgentIndex: 0,
      connections: const <UserExampleConnection>[],
      prompts: const <String>[
        'What can you do?',
        'Solve this using your configured tools.',
        'If tools are missing, explain what to configure.',
      ],
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  final String id;
  final String title;
  final String summary;
  final String initialAssistantMessage;
  final String inputHint;
  final UserExampleArchitecture architecture;
  final List<CustomAgentConfig> agents;
  final int entryAgentIndex;
  final List<UserExampleConnection> connections;
  final List<String> prompts;
  final int createdAtMs;
  final int updatedAtMs;

  UserExampleConfig copyWith({
    String? id,
    String? title,
    String? summary,
    String? initialAssistantMessage,
    String? inputHint,
    UserExampleArchitecture? architecture,
    List<CustomAgentConfig>? agents,
    int? entryAgentIndex,
    List<UserExampleConnection>? connections,
    List<String>? prompts,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return UserExampleConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      initialAssistantMessage:
          initialAssistantMessage ?? this.initialAssistantMessage,
      inputHint: inputHint ?? this.inputHint,
      architecture: architecture ?? this.architecture,
      agents: agents ?? this.agents,
      entryAgentIndex: entryAgentIndex ?? this.entryAgentIndex,
      connections: connections ?? this.connections,
      prompts: prompts ?? this.prompts,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'summary': summary,
      'initialAssistantMessage': initialAssistantMessage,
      'inputHint': inputHint,
      'architecture': architecture.name,
      'agents': agents.map((CustomAgentConfig it) => it.toJson()).toList(),
      'entryAgentIndex': entryAgentIndex,
      'connections': connections
          .map((UserExampleConnection item) => item.toJson())
          .toList(),
      'prompts': prompts,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  factory UserExampleConfig.fromJson(Map<String, Object?> json) {
    final UserExampleConfig fallback = UserExampleConfig.defaults(
      id: (json['id'] as String?)?.trim(),
    );
    final List<CustomAgentConfig> agents =
        ((json['agents'] as List?) ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> item) => CustomAgentConfig.fromJson(
                item.map(
                  (Object? key, Object? value) =>
                      MapEntry(key.toString(), value),
                ),
              ),
            )
            .toList();
    final List<String> prompts =
        ((json['prompts'] as List?) ?? const <Object?>[])
            .whereType<Object?>()
            .map((Object? item) => item?.toString() ?? '')
            .where((String item) => item.trim().isNotEmpty)
            .toList();
    final List<UserExampleConnection> connections =
        ((json['connections'] as List?) ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> item) => UserExampleConnection.fromJson(
                item.map(
                  (Object? key, Object? value) =>
                      MapEntry(key.toString(), value),
                ),
              ),
            )
            .toList(growable: false);

    return UserExampleConfig(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : fallback.id,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : fallback.title,
      summary: (json['summary'] as String?)?.trim().isNotEmpty == true
          ? (json['summary'] as String).trim()
          : fallback.summary,
      initialAssistantMessage:
          (json['initialAssistantMessage'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['initialAssistantMessage'] as String).trim()
          : fallback.initialAssistantMessage,
      inputHint: (json['inputHint'] as String?)?.trim().isNotEmpty == true
          ? (json['inputHint'] as String).trim()
          : fallback.inputHint,
      architecture: _parseArchitecture(
        (json['architecture'] as String?) ?? fallback.architecture.name,
      ),
      agents: agents.isEmpty ? fallback.agents : agents,
      entryAgentIndex: json['entryAgentIndex'] is int
          ? json['entryAgentIndex'] as int
          : fallback.entryAgentIndex,
      connections: connections,
      prompts: prompts.isEmpty ? fallback.prompts : prompts,
      createdAtMs: json['createdAtMs'] is int
          ? json['createdAtMs'] as int
          : fallback.createdAtMs,
      updatedAtMs: json['updatedAtMs'] is int
          ? json['updatedAtMs'] as int
          : fallback.updatedAtMs,
    );
  }

  static UserExampleArchitecture _parseArchitecture(String raw) {
    final String normalized = raw.trim().toLowerCase();
    for (final UserExampleArchitecture arch in UserExampleArchitecture.values) {
      if (arch.name == normalized) {
        return arch;
      }
    }
    return UserExampleArchitecture.single;
  }
}

class UserExampleConnection {
  const UserExampleConnection({
    required this.fromIndex,
    required this.toIndex,
    required this.condition,
  });

  final int fromIndex;
  final int toIndex;
  final String condition;

  UserExampleConnection copyWith({
    int? fromIndex,
    int? toIndex,
    String? condition,
  }) {
    return UserExampleConnection(
      fromIndex: fromIndex ?? this.fromIndex,
      toIndex: toIndex ?? this.toIndex,
      condition: condition ?? this.condition,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fromIndex': fromIndex,
      'toIndex': toIndex,
      'condition': condition,
    };
  }

  factory UserExampleConnection.fromJson(Map<String, Object?> json) {
    return UserExampleConnection(
      fromIndex: json['fromIndex'] is int ? json['fromIndex'] as int : 0,
      toIndex: json['toIndex'] is int ? json['toIndex'] as int : 0,
      condition: (json['condition'] as String?)?.trim() ?? '',
    );
  }
}
