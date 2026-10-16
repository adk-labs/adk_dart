import 'package:flutter/material.dart';

/// Execution lifecycle state for an ADK Workflow graph node.
enum AdkGraphNodeStatus {
  /// Node has not started.
  pending,

  /// Node is currently executing.
  running,

  /// Node successfully finished execution.
  completed,

  /// Node execution failed with an error.
  failed,

  /// Node was bypassed or skipped due to branch routing.
  skipped,
}

/// A node representation inside an [AdkWorkflowGraphView].
class AdkGraphNode {
  /// Creates an [AdkGraphNode].
  const AdkGraphNode({
    required this.id,
    required this.label,
    this.status = AdkGraphNodeStatus.pending,
    this.subtitle,
    this.icon,
  });

  /// Unique node identifier.
  final String id;

  /// Display title.
  final String label;

  /// Current execution status.
  final AdkGraphNodeStatus status;

  /// Optional descriptive subtitle.
  final String? subtitle;

  /// Optional icon.
  final IconData? icon;
}

/// A directed edge connecting two workflow nodes.
class AdkGraphEdge {
  /// Creates an [AdkGraphEdge].
  const AdkGraphEdge({
    required this.fromId,
    required this.toId,
    this.label,
  });

  /// Source node ID.
  final String fromId;

  /// Destination node ID.
  final String toId;

  /// Optional routing condition or branch label.
  final String? label;
}

/// An interactive flowchart and graph viewer for ADK `Workflow` and `EdgesBuilder`
/// pipelines.
class AdkWorkflowGraphView extends StatelessWidget {
  /// Creates an [AdkWorkflowGraphView].
  const AdkWorkflowGraphView({
    super.key,
    required this.nodes,
    this.edges = const <AdkGraphEdge>[],
    this.onNodeTap,
    this.activeNodeId,
    this.title = 'Workflow Execution Graph',
  });

  /// The list of nodes in topological or sequential order.
  final List<AdkGraphNode> nodes;

  /// The directed edges linking nodes together.
  final List<AdkGraphEdge> edges;

  /// Callback when a node is tapped.
  final void Function(AdkGraphNode node)? onNodeTap;

  /// ID of the currently highlighted or active node.
  final String? activeNodeId;

  /// Header title for the graph viewer.
  final String title;

  Color _statusColor(ThemeData theme, AdkGraphNodeStatus status) {
    switch (status) {
      case AdkGraphNodeStatus.completed:
        return Colors.green.shade600;
      case AdkGraphNodeStatus.running:
        return theme.colorScheme.primary;
      case AdkGraphNodeStatus.failed:
        return theme.colorScheme.error;
      case AdkGraphNodeStatus.skipped:
        return theme.colorScheme.outline;
      case AdkGraphNodeStatus.pending:
        return theme.colorScheme.outlineVariant;
    }
  }

  IconData _statusIcon(AdkGraphNodeStatus status, IconData? customIcon) {
    if (customIcon != null) return customIcon;
    switch (status) {
      case AdkGraphNodeStatus.completed:
        return Icons.check_circle_rounded;
      case AdkGraphNodeStatus.running:
        return Icons.play_circle_fill_rounded;
      case AdkGraphNodeStatus.failed:
        return Icons.error_rounded;
      case AdkGraphNodeStatus.skipped:
        return Icons.skip_next_rounded;
      case AdkGraphNodeStatus.pending:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.hub_outlined, color: colorScheme.primary, size: 20.0),
                const SizedBox(width: 8.0),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(nodes.length, (int index) {
                  final AdkGraphNode node = nodes[index];
                  final bool isLast = index == nodes.length - 1;
                  final bool isActive = node.id == activeNodeId ||
                      node.status == AdkGraphNodeStatus.running;

                  // Find edge linking this node to next node if sequential
                  final AdkGraphEdge? edge = !isLast
                      ? edges.firstWhere(
                          (AdkGraphEdge e) =>
                              e.fromId == node.id && e.toId == nodes[index + 1].id,
                          orElse: () => AdkGraphEdge(fromId: node.id, toId: ''),
                        )
                      : null;

                  final Color statusCol = _statusColor(theme, node.status);

                  return Row(
                    children: <Widget>[
                      InkWell(
                        onTap: () => onNodeTap?.call(node),
                        borderRadius: BorderRadius.circular(12.0),
                        child: Container(
                          width: 140.0,
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: isActive
                                ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isActive ? colorScheme.primary : statusCol,
                              width: isActive ? 2.0 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(
                                    _statusIcon(node.status, node.icon),
                                    size: 16.0,
                                    color: statusCol,
                                  ),
                                  const SizedBox(width: 6.0),
                                  Expanded(
                                    child: Text(
                                      node.label,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (node.subtitle != null) ...<Widget>[
                                const SizedBox(height: 4.0),
                                Text(
                                  node.subtitle!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withValues(alpha: 0.7),
                                    fontSize: 10.0,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (!isLast) ...<Widget>[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (edge != null &&
                                  edge.label != null &&
                                  edge.label!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6.0,
                                    vertical: 1.0,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 2.0),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: Text(
                                    edge.label!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16.0,
                                color: colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
