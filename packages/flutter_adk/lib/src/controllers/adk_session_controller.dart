import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/adk_session_info.dart';
import '../storage/adk_storage.dart';

/// A reactive controller for managing conversation sessions, history lists, and storage synchronization.
class AdkSessionController extends ChangeNotifier {
  /// Creates an [AdkSessionController].
  AdkSessionController({
    required this.storage,
    this.appName = 'flutter_adk_app',
    this.userId = 'user_default',
    String? initialSessionId,
  }) : _activeSessionId = initialSessionId;

  /// Key-value persistence storage.
  final AdkKeyValueStorage storage;

  /// Application namespace.
  final String appName;

  /// Active user namespace.
  final String userId;

  final List<AdkSessionInfo> _sessions = <AdkSessionInfo>[];
  String? _activeSessionId;
  bool _isLoading = false;
  String _searchQuery = '';

  /// List of all loaded sessions.
  List<AdkSessionInfo> get sessions => List<AdkSessionInfo>.unmodifiable(_sessions);

  /// Filtered sessions matching [_searchQuery].
  List<AdkSessionInfo> get filteredSessions {
    if (_searchQuery.isEmpty) return sessions;
    final String q = _searchQuery.toLowerCase();
    return _sessions.where((AdkSessionInfo s) => s.title.toLowerCase().contains(q)).toList();
  }

  /// ID of the currently active session.
  String? get activeSessionId => _activeSessionId;

  /// Currently active [AdkSessionInfo], if found.
  AdkSessionInfo? get activeSession {
    if (_activeSessionId == null) return null;
    final int idx = _sessions.indexWhere((AdkSessionInfo s) => s.id == _activeSessionId);
    return idx >= 0 ? _sessions[idx] : null;
  }

  /// Whether sessions are currently being loaded from storage.
  bool get isLoading => _isLoading;

  String _buildKeyPrefix() => 'adk_session_${appName}_${userId}_';

  /// Loads all sessions belonging to this user from storage.
  Future<void> loadAllSessions() async {
    _isLoading = true;
    notifyListeners();

    try {
      final String prefix = _buildKeyPrefix();
      final List<String> keys = await storage.getKeys(prefix: prefix);
      _sessions.clear();

      for (final String k in keys) {
        final String? jsonStr = await storage.read(k);
        if (jsonStr == null || jsonStr.isEmpty) continue;

        try {
          final Map<String, dynamic> map = json.decode(jsonStr) as Map<String, dynamic>;
          final String sid = map['id']?.toString() ?? k.replaceFirst(prefix, '');
          final List<dynamic> events = map['events'] as List<dynamic>? ?? <dynamic>[];
          final String title = map['title']?.toString() ?? 'Chat Session ($sid)';
          final DateTime updatedAt = map['updatedAt'] != null
              ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
              : DateTime.now();

          _sessions.add(
            AdkSessionInfo(
              id: sid,
              title: title,
              messageCount: events.length,
              updatedAt: updatedAt,
            ),
          );
        } catch (_) {}
      }

      // Sort newest first
      _sessions.sort((a, b) {
        final DateTime aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      if (_activeSessionId == null && _sessions.isNotEmpty) {
        _activeSessionId = _sessions.first.id;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a new session and sets it as active.
  Future<AdkSessionInfo> createNewSession({String? title, String? sessionId}) async {
    final String sid = sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    final String sessionTitle = title ?? 'New Chat';
    final DateTime now = DateTime.now();

    final AdkSessionInfo newSession = AdkSessionInfo(
      id: sid,
      title: sessionTitle,
      messageCount: 0,
      updatedAt: now,
    );

    _sessions.insert(0, newSession);
    _activeSessionId = sid;

    // Persist empty session envelope
    final String key = '${_buildKeyPrefix()}$sid';
    final Map<String, dynamic> data = <String, dynamic>{
      'id': sid,
      'title': sessionTitle,
      'updatedAt': now.toIso8601String(),
      'events': <dynamic>[],
    };
    await storage.write(key, json.encode(data));

    notifyListeners();
    return newSession;
  }

  /// Switches active session to [sessionId].
  void switchSession(String sessionId) {
    if (_activeSessionId != sessionId) {
      _activeSessionId = sessionId;
      notifyListeners();
    }
  }

  /// Updates title of an existing session.
  Future<void> updateSessionTitle(String sessionId, String newTitle) async {
    final int idx = _sessions.indexWhere((AdkSessionInfo s) => s.id == sessionId);
    if (idx >= 0) {
      _sessions[idx] = _sessions[idx].copyWith(title: newTitle);

      final String key = '${_buildKeyPrefix()}$sessionId';
      final String? existing = await storage.read(key);
      if (existing != null) {
        try {
          final Map<String, dynamic> map = json.decode(existing) as Map<String, dynamic>;
          map['title'] = newTitle;
          await storage.write(key, json.encode(map));
        } catch (_) {}
      }

      notifyListeners();
    }
  }

  /// Deletes a session from storage and local list.
  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((AdkSessionInfo s) => s.id == sessionId);
    final String key = '${_buildKeyPrefix()}$sessionId';
    await storage.delete(key);

    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }
    notifyListeners();
  }

  /// Clears all sessions for this user.
  Future<void> clearAllSessions() async {
    final String prefix = _buildKeyPrefix();
    final List<String> keys = await storage.getKeys(prefix: prefix);
    for (final String k in keys) {
      await storage.delete(k);
    }
    _sessions.clear();
    _activeSessionId = null;
    notifyListeners();
  }

  /// Sets search filter query.
  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    notifyListeners();
  }
}
