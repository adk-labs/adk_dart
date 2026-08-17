import 'package:flutter/material.dart';

/// A breadcrumb / badge widget displaying the active agent in a multi-agent hierarchy.
class AdkAgentHierarchyBadge extends StatelessWidget {
  /// Creates an [AdkAgentHierarchyBadge].
  const AdkAgentHierarchyBadge({
    super.key,
    required this.agentPath,
    this.backgroundColor,
    this.textColor,
    this.icon = Icons.hub_outlined,
  });

  /// The active hierarchy path (e.g. `['Coordinator', 'Researcher', 'PythonCoder']`).
  final List<String> agentPath;

  /// Custom background color.
  final Color? backgroundColor;

  /// Custom text color.
  final Color? textColor;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (agentPath.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final Color bg = backgroundColor ??
        theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7);
    final Color fg = textColor ?? theme.colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14.0, color: fg),
          const SizedBox(width: 6.0),
          for (int i = 0; i < agentPath.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Icon(
                  Icons.chevron_right,
                  size: 14.0,
                  color: fg.withValues(alpha: 0.6),
                ),
              ),
            Text(
              agentPath[i],
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight:
                    i == agentPath.length - 1 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
