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
    this.orientation = Axis.horizontal,
    this.nodeWidth = 140.0,
    this.nodeHeight,
    this.cardElevation = 2.0,
    this.borderRadius,
    this.cardMargin,
    this.cardPadding,
    this.completedColor,
    this.runningColor,
    this.failedColor,
    this.skippedColor,
    this.pendingColor,
    this.activeBorderColor,
    this.nodeBuilder,
    this.edgeBuilder,
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

  /// Layout orientation of the node graph (horizontal or vertical).
  final Axis orientation;

  /// Fixed width for default node cards.
  final double nodeWidth;

  /// Optional fixed height for default node cards.
  final double? nodeHeight;

  /// Elevation shadow of the outer card.
  final double cardElevation;

  /// Border radius of the outer card.
  final BorderRadius? borderRadius;

  /// Margin around the outer card.
  final EdgeInsetsGeometry? cardMargin;

  /// Inner padding inside the outer card.
  final EdgeInsetsGeometry? cardPadding;

  /// Custom color override for [AdkGraphNodeStatus.completed].
  final Color? completedColor;

  /// Custom color override for [AdkGraphNodeStatus.running].
  final Color? runningColor;

  /// Custom color override for [AdkGraphNodeStatus.failed].
  final Color? failedColor;

  /// Custom color override for [AdkGraphNodeStatus.skipped].
  final Color? skippedColor;

  /// Custom color override for [AdkGraphNodeStatus.pending].
  final Color? pendingColor;

  /// Custom highlight border color for the active node.
  final Color? activeBorderColor;

  /// Custom builder for node widgets.
  final Widget Function(
    BuildContext context,
    AdkGraphNode node,
    bool isActive,
    AdkGraphNodeStatus status,
    VoidCallback? onTap,
  )? nodeBuilder;

  /// Custom builder for connecting edge connectors.
  final Widget Function(
    BuildContext context,
    AdkGraphEdge? edge,
    bool isLast,
  )? edgeBuilder;

  Color _statusColor(ThemeData theme, AdkGraphNodeStatus status) {
    switch (status) {
      case AdkGraphNodeStatus.completed:
        return completedColor ?? Colors.green.shade600;
      case AdkGraphNodeStatus.running:
        return runningColor ?? theme.colorScheme.primary;
      case AdkGraphNodeStatus.failed:
        return failedColor ?? theme.colorScheme.error;
      case AdkGraphNodeStatus.skipped:
        return skippedColor ?? theme.colorScheme.outline;
      case AdkGraphNodeStatus.pending:
        return pendingColor ?? theme.colorScheme.outlineVariant;
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

    final Widget nodeContent = SingleChildScrollView(
      scrollDirection: orientation,
      child: orientation == Axis.horizontal
          ? Row(children: _buildNodeItems(context, theme, colorScheme))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildNodeItems(context, theme, colorScheme),
            ),
    );

    return Card(
      margin: cardMargin ?? const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(16.0),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: cardPadding ?? const EdgeInsets.all(16.0),
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
            nodeContent,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNodeItems(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return List<Widget>.generate(nodes.length, (int index) {
      final AdkGraphNode node = nodes[index];
      final bool isLast = index == nodes.length - 1;
      final bool isActive = node.id == activeNodeId ||
          node.status == AdkGraphNodeStatus.running;

      final AdkGraphEdge? edge = !isLast
          ? edges.firstWhere(
              (AdkGraphEdge e) =>
                  e.fromId == node.id && e.toId == nodes[index + 1].id,
              orElse: () => AdkGraphEdge(fromId: node.id, toId: ''),
            )
          : null;

      final Color statusCol = _statusColor(theme, node.status);
      final VoidCallback? tapCallback = onNodeTap != null
          ? () => onNodeTap!(node)
          : null;

      final Widget nodeWidget = nodeBuilder != null
          ? nodeBuilder!(context, node, isActive, node.status, tapCallback)
          : InkWell(
              onTap: tapCallback,
              borderRadius: BorderRadius.circular(12.0),
              child: Container(
                width: nodeWidth,
                height: nodeHeight,
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: isActive
                      ? (activeBorderColor ?? colorScheme.primary).withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: isActive ? (activeBorderColor ?? colorScheme.primary) : statusCol,
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
            );

      final Widget connectorWidget = edgeBuilder != null
          ? edgeBuilder!(context, edge, isLast)
          : (!isLast
              ? (orientation == Axis.horizontal
                  ? Padding(
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
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(width: 20.0),
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 16.0,
                            color: colorScheme.outline,
                          ),
                          if (edge != null &&
                              edge.label != null &&
                              edge.label!.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 6.0),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                                vertical: 1.0,
                              ),
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
                          ],
                        ],
                      ),
                    ))
              : const SizedBox.shrink());

      return orientation == Axis.horizontal
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                nodeWidget,
                connectorWidget,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                nodeWidget,
                connectorWidget,
              ],
            );
    });
  }
}
