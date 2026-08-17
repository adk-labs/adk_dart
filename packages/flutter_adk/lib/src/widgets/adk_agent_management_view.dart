import 'package:flutter/material.dart';

import '../controllers/adk_agent_manager_controller.dart';
import '../models/adk_agent_metadata.dart';
import '../theme/adk_theme.dart';

/// A turnkey administrative dashboard and inspector widget for managing, observing, and toggling AI agents.
class AdkAgentManagementView extends StatefulWidget {
  /// Creates an [AdkAgentManagementView].
  const AdkAgentManagementView({
    super.key,
    required this.controller,
    this.onAgentSelected,
    this.theme,
    this.title = 'AI Agent Fleet Manager',
    this.showMetricsHeader = true,
    this.agentCardBuilder,
    this.headerBuilder,
    this.emptyStateBuilder,
  });

  /// The agent manager controller.
  final AdkAgentManagerController controller;

  /// Callback when an agent card is tapped.
  final ValueChanged<AdkAgentMetadata>? onAgentSelected;

  /// Optional theme styling configuration.
  final AdkChatThemeData? theme;

  /// Title shown in the header.
  final String title;

  /// Whether to display top telemetry summary cards.
  final bool showMetricsHeader;

  /// Optional custom builder for agent cards.
  final Widget Function(
    BuildContext context,
    AdkAgentMetadata agent,
    ValueChanged<bool> onToggle,
    VoidCallback onInspect,
  )? agentCardBuilder;

  /// Optional custom builder for header.
  final Widget Function(BuildContext context)? headerBuilder;

  /// Optional custom builder for empty state.
  final Widget Function(BuildContext context)? emptyStateBuilder;

  @override
  State<AdkAgentManagementView> createState() => _AdkAgentManagementViewState();
}

class _AdkAgentManagementViewState extends State<AdkAgentManagementView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _showAgentInspector(AdkAgentMetadata agent) {
    final ThemeData theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, ScrollController scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20.0),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36.0,
                    height: 4.0,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.smart_toy, color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            agent.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'ID: ${agent.id} • Model: ${agent.model}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                const Divider(),
                const SizedBox(height: 8.0),
                Text(
                  'System Instruction / Prompt',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6.0),
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: SelectableText(
                    agent.instruction.isNotEmpty
                        ? agent.instruction
                        : 'No static instructions provided.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16.0),
                Text(
                  'Capabilities & Telemetry',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8.0),
                Wrap(
                  spacing: 12.0,
                  runSpacing: 8.0,
                  children: <Widget>[
                    _buildMetricChip(theme, 'Tools Registered', '${agent.toolsCount}'),
                    _buildMetricChip(theme, 'Sub-Agents', '${agent.subAgentsCount}'),
                    _buildMetricChip(theme, 'Total Turns', '${agent.metrics.totalInvocations}'),
                    _buildMetricChip(theme, 'Total Tokens', '${agent.metrics.totalTokens}'),
                    _buildMetricChip(
                      theme,
                      'Avg Latency',
                      '${agent.metrics.avgLatencyMs.toStringAsFixed(0)} ms',
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMetricChip(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 10.0, color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AdkAgentMetadata> agents = widget.controller.filteredAgents;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Column(
        children: <Widget>[
          if (widget.headerBuilder != null)
            widget.headerBuilder!(context)
          else if (widget.showMetricsHeader)
            _buildFleetSummary(theme),
          // Search & Filter Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search agents by name, role, or model...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          widget.controller.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(vertical: 0.0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (String text) => widget.controller.setSearchQuery(text),
            ),
          ),
          // Tags filter bar
          if (widget.controller.allTags.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: <Widget>[
                  FilterChip(
                    label: const Text('All'),
                    selected: widget.controller.selectedTag == null,
                    onSelected: (_) => widget.controller.setTagFilter(null),
                  ),
                  const SizedBox(width: 6.0),
                  ...widget.controller.allTags.map((String t) {
                    final bool isSel = widget.controller.selectedTag == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(t),
                        selected: isSel,
                        onSelected: (bool val) => widget.controller.setTagFilter(val ? t : null),
                      ),
                    );
                  }),
                ],
              ),
            ),
          // Agent Cards List
          Expanded(
            child: agents.isEmpty
                ? (widget.emptyStateBuilder != null
                    ? widget.emptyStateBuilder!(context)
                    : _buildEmptyState(theme))
                : ListView.separated(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: agents.length,
                    separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 12.0),
                    itemBuilder: (BuildContext context, int index) {
                      final AdkAgentMetadata agent = agents[index];
                      if (widget.agentCardBuilder != null) {
                        return widget.agentCardBuilder!(
                          context,
                          agent,
                          (bool val) => widget.controller.toggleAgent(agent.id, val),
                          () => _showAgentInspector(agent),
                        );
                      }
                      return _buildDefaultAgentCard(theme, agent);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetSummary(ThemeData theme) {
    final int total = widget.controller.agents.length;
    final int enabled = widget.controller.enabledAgents.length;
    final int totalTurns = widget.controller.agents
        .fold(0, (int acc, AdkAgentMetadata a) => acc + a.metrics.totalInvocations);
    final int totalTokens = widget.controller.agents
        .fold(0, (int acc, AdkAgentMetadata a) => acc + a.metrics.totalTokens);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _buildSummaryItem('Fleet Size', '$enabled / $total active'),
          _buildSummaryItem('Total Turns', '$totalTurns'),
          _buildSummaryItem('Total Tokens', '$totalTokens'),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0)),
        Text(label, style: const TextStyle(fontSize: 11.0, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.smart_toy_outlined, size: 48.0, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12.0),
          Text('No agents found', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4.0),
          Text(
            'Register agents using AdkAgentManagerController',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAgentCard(ThemeData theme, AdkAgentMetadata agent) {
    final Color statusColor = switch (agent.status) {
      .idle => Colors.green,
      .busy => Colors.orange,
      .disabled => Colors.grey,
      .error => theme.colorScheme.error,
    };

    final bool isActive = agent.id == widget.controller.activeAgentId;

    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isActive ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8.0,
                  height: 8.0,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    agent.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: agent.isEnabled,
                  onChanged: (bool val) => widget.controller.toggleAgent(agent.id, val),
                ),
              ],
            ),
            if (agent.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4.0),
              Text(
                agent.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10.0),
            Wrap(
              spacing: 6.0,
              runSpacing: 4.0,
              children: <Widget>[
                _buildBadge(theme, 'Model: ${agent.model}'),
                _buildBadge(theme, '${agent.toolsCount} Tools'),
                if (agent.subAgentsCount > 0)
                  _buildBadge(theme, '${agent.subAgentsCount} Sub-Agents'),
                _buildBadge(theme, '${agent.metrics.totalInvocations} turns'),
              ],
            ),
            const SizedBox(height: 10.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16.0),
                  label: const Text('Inspect'),
                  onPressed: () => _showAgentInspector(agent),
                ),
                const SizedBox(width: 8.0),
                FilledButton.tonal(
                  onPressed: agent.isEnabled
                      ? () {
                          widget.controller.setActiveAgent(agent.id);
                          widget.onAgentSelected?.call(agent);
                        }
                      : null,
                  child: Text(isActive ? 'Active' : 'Select'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.0, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
