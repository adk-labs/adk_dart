import 'package:flutter/material.dart';

/// Node execution status for [AdkWorkflowProgressIndicator].
enum AdkWorkflowNodeStatus {
  /// Node has not started yet.
  pending,

  /// Node is currently executing.
  running,

  /// Node has completed successfully.
  completed,

  /// Node failed with an error.
  failed,
}

/// A single step item representing a workflow node.
class AdkWorkflowStep {
  /// Creates an [AdkWorkflowStep].
  const AdkWorkflowStep({
    required this.name,
    this.status = AdkWorkflowNodeStatus.pending,
    this.description,
  });

  /// Name or identifier of the node.
  final String name;

  /// Current execution status.
  final AdkWorkflowNodeStatus status;

  /// Optional description.
  final String? description;
}

/// A horizontal or vertical timeline progress indicator for ADK 2.0 Workflows.
class AdkWorkflowProgressIndicator extends StatelessWidget {
  /// Creates an [AdkWorkflowProgressIndicator].
  const AdkWorkflowProgressIndicator({
    super.key,
    required this.steps,
    this.isVertical = false,
  });

  /// List of workflow steps.
  final List<AdkWorkflowStep> steps;

  /// Whether to render in vertical orientation.
  final bool isVertical;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);

    if (isVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(steps.length, (int index) {
          final AdkWorkflowStep step = steps[index];
          final bool isLast = index == steps.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    _buildStatusIcon(theme, step.status),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2.0,
                          color: _getLineColor(theme, step.status),
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          step.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: step.status == AdkWorkflowNodeStatus.running
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (step.description != null)
                          Text(
                            step.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(steps.length, (int index) {
            final AdkWorkflowStep step = steps[index];
            final bool isLast = index == steps.length - 1;

            return Row(
              children: <Widget>[
                _buildStatusIcon(theme, step.status),
                const SizedBox(width: 6.0),
                Text(
                  step.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: step.status == AdkWorkflowNodeStatus.running
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 24.0,
                    height: 2.0,
                    color: _getLineColor(theme, step.status),
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme, AdkWorkflowNodeStatus status) {
    switch (status) {
      case AdkWorkflowNodeStatus.running:
        return SizedBox(
          width: 16.0,
          height: 16.0,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: theme.colorScheme.primary,
          ),
        );
      case AdkWorkflowNodeStatus.completed:
        return Icon(
          Icons.check_circle,
          size: 18.0,
          color: theme.colorScheme.primary,
        );
      case AdkWorkflowNodeStatus.failed:
        return Icon(
          Icons.cancel,
          size: 18.0,
          color: theme.colorScheme.error,
        );
      case AdkWorkflowNodeStatus.pending:
        return Icon(
          Icons.radio_button_unchecked,
          size: 18.0,
          color: theme.colorScheme.outlineVariant,
        );
    }
  }

  Color _getLineColor(ThemeData theme, AdkWorkflowNodeStatus status) {
    return status == AdkWorkflowNodeStatus.completed
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.5);
  }
}
