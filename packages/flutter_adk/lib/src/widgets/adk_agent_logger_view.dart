import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents a single I/O log entry recorded during agent execution.
class AdkAgentLogEntry {
  /// Creates an [AdkAgentLogEntry].
  AdkAgentLogEntry({
    required this.id,
    required this.timestamp,
    required this.agentName,
    required this.category,
    required this.title,
    this.subtitle,
    this.payload,
    this.durationMs,
    this.tokenCount,
    this.isError = false,
  });

  /// Unique log entry ID.
  final String id;

  /// Log creation timestamp.
  final DateTime timestamp;

  /// Name of the agent producing or receiving this event.
  final String agentName;

  /// Category filter for the log entry.
  final AdkLogCategory category;

  /// Short headline title.
  final String title;

  /// Optional subtitle or snippet.
  final String? subtitle;

  /// Detailed payload (Map, List, string, or json-serializable object).
  final dynamic payload;

  /// Latency in milliseconds if applicable.
  final int? durationMs;

  /// Token usage if applicable.
  final int? tokenCount;

  /// Whether this entry represents a failure or error.
  final bool isError;
}

/// Category filter options for [AdkAgentLogEntry].
enum AdkLogCategory {
  /// All logs.
  all,

  /// User inputs and prompt events.
  userInput,

  /// Model generation and LLM responses.
  modelResponse,

  /// Tool execution invocations and tool outputs.
  toolCall,

  /// Session and state changes.
  stateUpdate,

  /// Errors and exceptions.
  error,
}

/// A developer logger widget for inspecting input, output, tool calls, and state changes
/// of ADK agents in real-time.
class AdkAgentLoggerView extends StatefulWidget {
  /// Creates an [AdkAgentLoggerView].
  const AdkAgentLoggerView({
    super.key,
    required this.logs,
    this.onClearLogs,
    this.title = 'Agent I/O Logger',
    this.showHeader = true,
  });

  /// The list of log entries to display.
  final List<AdkAgentLogEntry> logs;

  /// Optional callback to clear the logs.
  final VoidCallback? onClearLogs;

  /// Header title.
  final String title;

  /// Whether to show the top header bar.
  final bool showHeader;

  @override
  State<AdkAgentLoggerView> createState() => _AdkAgentLoggerViewState();
}

class _AdkAgentLoggerViewState extends State<AdkAgentLoggerView> {
  AdkLogCategory _selectedCategory = .all;
  String _searchQuery = '';
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void didUpdateWidget(AdkAgentLoggerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.logs.length > oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<AdkAgentLogEntry> get _filteredLogs {
    return widget.logs.where((AdkAgentLogEntry log) {
      if (_selectedCategory != .all &&
          log.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final String q = _searchQuery.toLowerCase();
        final bool matchesTitle = log.title.toLowerCase().contains(q);
        final bool matchesAgent = log.agentName.toLowerCase().contains(q);
        final bool matchesSub =
            log.subtitle?.toLowerCase().contains(q) ?? false;
        return matchesTitle || matchesAgent || matchesSub;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AdkAgentLogEntry> displayLogs = _filteredLogs;

    return Column(
      children: <Widget>[
        if (widget.showHeader) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.terminal_rounded,
                  size: 20.0,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8.0),
                Text(
                  widget.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _autoScroll ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
                    size: 18.0,
                    color: _autoScroll ? theme.colorScheme.primary : null,
                  ),
                  tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll paused',
                  onPressed: () => setState(() => _autoScroll = !_autoScroll),
                ),
                if (widget.onClearLogs != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18.0),
                    tooltip: 'Clear logs',
                    onPressed: widget.onClearLogs,
                  ),
              ],
            ),
          ),
        ],
        _buildFilterBar(theme),
        Expanded(
          child: displayLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40.0,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        'No agent logs recorded yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  itemCount: displayLogs.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _AdkLogEntryTile(entry: displayLogs[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 36.0,
            child: TextField(
              onChanged: (String val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Filter logs by text or agent...',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                prefixIcon: const Icon(Icons.search, size: 16.0),
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6.0),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AdkLogCategory.values.map((AdkLogCategory cat) {
                final bool isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: FilterChip(
                    label: Text(_getCategoryLabel(cat)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _getCategoryLabel(AdkLogCategory category) {
    switch (category) {
      case .all:
        return 'All';
      case .userInput:
        return 'User Inputs';
      case .modelResponse:
        return 'Model LLM';
      case .toolCall:
        return 'Tool Calls';
      case .stateUpdate:
        return 'State Deltas';
      case .error:
        return 'Errors';
    }
  }
}

class _AdkLogEntryTile extends StatefulWidget {
  const _AdkLogEntryTile({required this.entry});

  final AdkAgentLogEntry entry;

  @override
  State<_AdkLogEntryTile> createState() => _AdkLogEntryTileState();
}

class _AdkLogEntryTileState extends State<_AdkLogEntryTile> {
  bool _expanded = false;

  String _formatPayload(dynamic payload) {
    if (payload == null) return 'null';
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(payload);
    } catch (_) {
      return payload.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkAgentLogEntry entry = widget.entry;

    final IconData icon = _getCategoryIcon(entry.category);
    final Color color = _getCategoryColor(theme, entry.category, entry.isError);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: entry.isError
              ? theme.colorScheme.error.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 16.0, color: color),
                  const SizedBox(width: 8.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      entry.agentName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (entry.durationMs != null) ...<Widget>[
                    Text(
                      '${entry.durationMs}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10.0,
                      ),
                    ),
                    const SizedBox(width: 6.0),
                  ],
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...<Widget>[
            const Divider(height: 1.0),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (entry.subtitle != null) ...<Widget>[
                    Text(
                      entry.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Payload:',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14.0),
                        tooltip: 'Copy JSON payload',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _formatPayload(entry.payload)),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Payload copied to clipboard'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6.0),
                    ),
                    child: SelectableText(
                      _formatPayload(entry.payload),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getCategoryIcon(AdkLogCategory category) {
    switch (category) {
      case .userInput:
        return Icons.person_outline;
      case .modelResponse:
        return Icons.auto_awesome;
      case .toolCall:
        return Icons.build_circle_outlined;
      case .stateUpdate:
        return Icons.data_object;
      case .error:
        return Icons.error_outline;
      case .all:
        return Icons.list_alt;
    }
  }

  Color _getCategoryColor(ThemeData theme, AdkLogCategory category, bool isError) {
    if (isError) return theme.colorScheme.error;
    switch (category) {
      case .userInput:
        return theme.colorScheme.primary;
      case .modelResponse:
        return theme.colorScheme.secondary;
      case .toolCall:
        return theme.colorScheme.tertiary;
      case .stateUpdate:
        return Colors.teal;
      case .error:
        return theme.colorScheme.error;
      case .all:
        return theme.colorScheme.onSurface;
    }
  }
}
