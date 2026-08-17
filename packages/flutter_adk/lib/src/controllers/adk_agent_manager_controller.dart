import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

import '../models/adk_agent_metadata.dart';

/// A centralized reactive controller for managing, toggling, observing, and hot-swapping multiple AI agents.
class AdkAgentManagerController extends ChangeNotifier {
  /// Creates an [AdkAgentManagerController].
  AdkAgentManagerController({
    List<adk.BaseAgent>? initialAgents,
  }) {
    if (initialAgents != null) {
      for (final adk.BaseAgent a in initialAgents) {
        registerAgent(a);
      }
    }
  }

  final Map<String, AdkAgentMetadata> _agents = <String, AdkAgentMetadata>{};
  String? _activeAgentId;
  String _searchQuery = '';
  String? _selectedTag;

  /// Unmodifiable list of all registered agents.
  List<AdkAgentMetadata> get agents => List<AdkAgentMetadata>.unmodifiable(_agents.values);

  /// List of only currently enabled agents.
  List<AdkAgentMetadata> get enabledAgents =>
      _agents.values.where((AdkAgentMetadata a) => a.isEnabled).toList();

  /// ID of the currently active primary agent.
  String? get activeAgentId => _activeAgentId;

  /// Currently active [AdkAgentMetadata], if set.
  AdkAgentMetadata? get activeAgent =>
      _activeAgentId != null ? _agents[_activeAgentId] : (_agents.isNotEmpty ? _agents.values.first : null);

  /// Current search query filter.
  String get searchQuery => _searchQuery;

  /// Currently selected category tag filter.
  String? get selectedTag => _selectedTag;

  /// Filtered list of agents matching [searchQuery] and [selectedTag].
  List<AdkAgentMetadata> get filteredAgents {
    return _agents.values.where((AdkAgentMetadata meta) {
      if (_selectedTag != null && !meta.tags.contains(_selectedTag)) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final String q = _searchQuery.toLowerCase();
        final bool matchesName = meta.name.toLowerCase().contains(q);
        final bool matchesDesc = meta.description.toLowerCase().contains(q);
        final bool matchesModel = meta.model.toLowerCase().contains(q);
        return matchesName || matchesDesc || matchesModel;
      }
      return true;
    }).toList();
  }

  /// All unique tags present across registered agents.
  List<String> get allTags {
    final Set<String> tagSet = <String>{};
    for (final AdkAgentMetadata a in _agents.values) {
      tagSet.addAll(a.tags);
    }
    return tagSet.toList()..sort();
  }

  /// Registers an ADK agent into the central registry.
  AdkAgentMetadata registerAgent(
    adk.BaseAgent agent, {
    String? id,
    String? name,
    String? description,
    String? model,
    String? instruction,
    List<String> tags = const <String>[],
  }) {
    final String agentId = id ?? agent.name;
    final String displayName = name ?? agent.name;

    int toolsCount = 0;
    int subAgentsCount = 0;
    String detectedModel = model ?? 'gemini-3.7-flash';
    String detectedInstruction = instruction ?? '';

    if (agent is adk.LlmAgent) {
      toolsCount = agent.tools.length;
      subAgentsCount = agent.subAgents.length;
      detectedModel = model ?? agent.model.toString();
      detectedInstruction = instruction ?? agent.instruction.toString();
    }

    final AdkAgentMetadata metadata = AdkAgentMetadata(
      id: agentId,
      name: displayName,
      agent: agent,
      description: description ?? agent.description,
      model: detectedModel,
      instruction: detectedInstruction,
      toolsCount: toolsCount,
      subAgentsCount: subAgentsCount,
      tags: tags,
    );

    _agents[agentId] = metadata;
    _activeAgentId ??= agentId;

    notifyListeners();
    return metadata;
  }

  /// Unregisters an agent by its ID.
  void unregisterAgent(String id) {
    _agents.remove(id);
    if (_activeAgentId == id) {
      _activeAgentId = _agents.isNotEmpty ? _agents.keys.first : null;
    }
    notifyListeners();
  }

  /// Toggles an agent's enabled state (ON/OFF).
  void toggleAgent(String id, bool isEnabled) {
    if (_agents.containsKey(id)) {
      _agents[id] = _agents[id]!.copyWith(
        isEnabled: isEnabled,
        status: isEnabled ? .idle : .disabled,
      );
      notifyListeners();
    }
  }

  /// Sets the primary active agent.
  void setActiveAgent(String id) {
    if (_agents.containsKey(id) && _activeAgentId != id) {
      _activeAgentId = id;
      notifyListeners();
    }
  }

  /// Updates the operational status of an agent.
  void setAgentStatus(String id, AdkAgentStatus status) {
    if (_agents.containsKey(id)) {
      _agents[id] = _agents[id]!.copyWith(status: status);
      notifyListeners();
    }
  }

  /// Records an execution turn telemetry entry for an agent.
  void recordInvocation(
    String id, {
    required int tokens,
    required double latencyMs,
    bool isError = false,
  }) {
    if (_agents.containsKey(id)) {
      final AdkAgentMetadata current = _agents[id]!;
      final AdkAgentMetrics m = current.metrics;

      final AdkAgentMetrics updatedMetrics = m.copyWith(
        totalInvocations: m.totalInvocations + 1,
        totalTokens: m.totalTokens + tokens,
        errorCount: isError ? m.errorCount + 1 : m.errorCount,
        totalLatencyMs: m.totalLatencyMs + latencyMs,
        lastActiveAt: DateTime.now(),
      );

      _agents[id] = current.copyWith(
        metrics: updatedMetrics,
        status: isError ? .error : .idle,
      );
      notifyListeners();
    }
  }

  /// Hot-swaps the system instructions for an agent in the registry.
  void updateInstruction(String id, String newInstruction) {
    if (_agents.containsKey(id)) {
      _agents[id] = _agents[id]!.copyWith(instruction: newInstruction);
      notifyListeners();
    }
  }

  /// Sets the search query filter.
  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    notifyListeners();
  }

  /// Sets the category tag filter.
  void setTagFilter(String? tag) {
    _selectedTag = tag;
    notifyListeners();
  }

  /// Retrieves an agent's metadata by ID.
  AdkAgentMetadata? getAgent(String id) => _agents[id];

  /// Clears all registered agents.
  void clearAll() {
    _agents.clear();
    _activeAgentId = null;
    notifyListeners();
  }
}
