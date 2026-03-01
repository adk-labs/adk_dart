import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PersistedChatMessage {
  const PersistedChatMessage({
    required this.isUser,
    required this.text,
    this.author,
    required this.timestampMs,
  });

  final bool isUser;
  final String text;
  final String? author;
  final int timestampMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'isUser': isUser,
      'text': text,
      'author': author,
      'timestampMs': timestampMs,
    };
  }

  factory PersistedChatMessage.fromJson(Map<String, Object?> json) {
    return PersistedChatMessage(
      isUser: json['isUser'] == true,
      text: (json['text'] as String?) ?? '',
      author: json['author'] as String?,
      timestampMs:
          (json['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class PersistedChatSession {
  const PersistedChatSession({
    required this.sessionId,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.messages,
  });

  final String sessionId;
  final int createdAtMs;
  final int updatedAtMs;
  final List<PersistedChatMessage> messages;

  PersistedChatSession copyWith({
    String? sessionId,
    int? createdAtMs,
    int? updatedAtMs,
    List<PersistedChatMessage>? messages,
  }) {
    return PersistedChatSession(
      sessionId: sessionId ?? this.sessionId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      messages: messages ?? this.messages,
    );
  }

  String get preview {
    for (final PersistedChatMessage message in messages.reversed) {
      final String trimmed = message.text.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'messages': messages
          .map((PersistedChatMessage message) => message.toJson())
          .toList(growable: false),
    };
  }

  factory PersistedChatSession.fromJson(Map<String, Object?> json) {
    final List<Object?> rawMessages =
        (json['messages'] as List<Object?>?) ?? const <Object?>[];
    return PersistedChatSession(
      sessionId: (json['sessionId'] as String?) ?? 'session_unknown',
      createdAtMs:
          (json['createdAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      updatedAtMs:
          (json['updatedAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      messages: rawMessages
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) => PersistedChatMessage.fromJson(
              item.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

abstract class ChatHistoryStore {
  Future<List<PersistedChatSession>> loadSessions({required String exampleId});

  Future<void> upsertSession({
    required String exampleId,
    required PersistedChatSession session,
  });
}

class SharedPreferencesChatHistoryStore implements ChatHistoryStore {
  static const String _sessionsKeyPrefix =
      'flutter_adk_example_chat_sessions_v1_';
  static const int _maxSessionsPerExample = 30;

  @override
  Future<List<PersistedChatSession>> loadSessions({
    required String exampleId,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_keyForExample(exampleId));
      if (raw == null || raw.trim().isEmpty) {
        return <PersistedChatSession>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <PersistedChatSession>[];
      }

      final List<PersistedChatSession> sessions = decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) => PersistedChatSession.fromJson(
              item.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false);
      sessions.sort(
        (PersistedChatSession a, PersistedChatSession b) =>
            b.updatedAtMs.compareTo(a.updatedAtMs),
      );
      return sessions;
    } catch (_) {
      return <PersistedChatSession>[];
    }
  }

  @override
  Future<void> upsertSession({
    required String exampleId,
    required PersistedChatSession session,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<PersistedChatSession> sessions = await loadSessions(
        exampleId: exampleId,
      );
      final int existingIndex = sessions.indexWhere(
        (PersistedChatSession item) => item.sessionId == session.sessionId,
      );
      if (existingIndex >= 0) {
        sessions[existingIndex] = session;
      } else {
        sessions.add(session);
      }

      sessions.sort(
        (PersistedChatSession a, PersistedChatSession b) =>
            b.updatedAtMs.compareTo(a.updatedAtMs),
      );

      final List<PersistedChatSession> limited = sessions
          .take(_maxSessionsPerExample)
          .toList(growable: false);
      final String payload = jsonEncode(
        limited
            .map((PersistedChatSession item) => item.toJson())
            .toList(growable: false),
      );
      await prefs.setString(_keyForExample(exampleId), payload);
    } catch (_) {
      // Keep app running even when persistence is unavailable.
    }
  }

  String _keyForExample(String exampleId) => '$_sessionsKeyPrefix$exampleId';
}
