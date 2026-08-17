import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

import '../widgets/adk_agent_logger_view.dart';

/// A reactive controller for buffering, filtering, searching, and exporting AI Agent I/O logs and telemetry.
class AdkAgentLoggerController extends ChangeNotifier {
  /// Creates an [AdkAgentLoggerController].
  AdkAgentLoggerController({
    this.maxLogEntries = 500,
    List<AdkAgentLogEntry>? initialLogs,
  }) : _logs = initialLogs != null ? List<AdkAgentLogEntry>.from(initialLogs) : <AdkAgentLogEntry>[];

  /// Maximum number of log entries to retain in memory.
  final int maxLogEntries;

  final List<AdkAgentLogEntry> _logs;
  AdkLogCategory _selectedCategory = .all;
  String _searchQuery = '';
  bool _autoScroll = true;

  /// Unmodifiable list of all buffered logs.
  List<AdkAgentLogEntry> get logs => List<AdkAgentLogEntry>.unmodifiable(_logs);

  /// Currently active category filter.
  AdkLogCategory get selectedCategory => _selectedCategory;

  /// Current search query string.
  String get searchQuery => _searchQuery;

  /// Whether auto-scrolling to newest logs is active.
  bool get autoScroll => _autoScroll;

  /// Filtered logs matching [selectedCategory] and [searchQuery].
  List<AdkAgentLogEntry> get filteredLogs {
    return _logs.where((AdkAgentLogEntry entry) {
      if (_selectedCategory != .all && entry.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final String q = _searchQuery.toLowerCase();
        final bool matchesTitle = entry.title.toLowerCase().contains(q);
        final bool matchesAgent = entry.agentName.toLowerCase().contains(q);
        final bool matchesPayload = entry.payload?.toString().toLowerCase().contains(q) ?? false;
        return matchesTitle || matchesAgent || matchesPayload;
      }
      return true;
    }).toList();
  }

  /// Appends a new [AdkAgentLogEntry] to the buffer.
  void addLog(AdkAgentLogEntry entry) {
    if (_logs.length >= maxLogEntries) {
      _logs.removeAt(0);
    }
    _logs.add(entry);
    notifyListeners();
  }

  /// Records an ADK runtime [adk.Event] as a structured log entry.
  void recordEvent(adk.Event event) {
    final String author = event.author.isNotEmpty ? event.author : 'agent';
    final content = event.content;
    String title = 'Event ($author)';
    dynamic payload = <String, dynamic>{'invocationId': event.invocationId, 'branch': event.branch};
    AdkLogCategory category = .modelResponse;

    if (content != null) {
      for (final part in content.parts) {
        if (part.functionCall != null) {
          title = 'Tool Call: ${part.functionCall!.name}';
          payload = part.functionCall!.args;
          category = .toolCall;
          break;
        } else if (part.functionResponse != null) {
          title = 'Tool Response: ${part.functionResponse!.name}';
          payload = part.functionResponse!.response;
          category = .toolCall;
          break;
        } else if (part.text != null && part.text!.isNotEmpty) {
          final isUser = content.role == 'user' || author == 'user';
          title = isUser ? 'User Prompt' : 'Model Response';
          payload = <String, dynamic>{'text': part.text};
          category = isUser ? .userInput : .modelResponse;
        }
      }
    }

    addLog(
      AdkAgentLogEntry(
        id: 'evt_${event.id}_${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        agentName: author,
        category: category,
        title: title,
        payload: payload,
      ),
    );
  }

  /// Changes the active category filter.
  void setCategory(AdkLogCategory category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  /// Updates the text search query filter.
  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    notifyListeners();
  }

  /// Toggles the auto-scroll setting.
  void toggleAutoScroll() {
    _autoScroll = !_autoScroll;
    notifyListeners();
  }

  /// Clears all buffered log entries.
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Exports the log buffer as a formatted JSON string.
  String exportJson({bool pretty = true}) {
    final List<Map<String, dynamic>> list = _logs.map((AdkAgentLogEntry entry) {
      return <String, dynamic>{
        'id': entry.id,
        'timestamp': entry.timestamp.toIso8601String(),
        'agentName': entry.agentName,
        'category': entry.category.name,
        'title': entry.title,
        'subtitle': entry.subtitle,
        'payload': entry.payload,
        'durationMs': entry.durationMs,
        'tokenCount': entry.tokenCount,
        'isError': entry.isError,
      };
    }).toList();

    if (pretty) {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(list);
    }
    return json.encode(list);
  }
}
