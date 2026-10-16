import 'package:flutter/material.dart';

/// A chip badge indicating that a message or reasoning step was escalated to
/// an advisor model (via `ModelConsultTool` or `ForceEscalationPlugin`).
class AdkModelConsultBadge extends StatelessWidget {
  /// Creates an [AdkModelConsultBadge].
  const AdkModelConsultBadge({
    super.key,
    required this.advisorModel,
    this.escalationReason,
    this.turnCount,
    this.turnBudget,
    this.onTap,
  });

  /// The model name consulted (e.g., `'gemini-2.5-pro'`).
  final String advisorModel;

  /// High-level rationale for why escalation was triggered.
  final String? escalationReason;

  /// Number of turns used so far in this consultation budget.
  final int? turnCount;

  /// Maximum allowed turns allocated for consultation.
  final int? turnBudget;

  /// Callback when user taps the badge.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final String budgetLabel = (turnCount != null && turnBudget != null)
        ? ' ($turnCount/$turnBudget)'
        : '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: colorScheme.secondary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.psychology_outlined,
              size: 16.0,
              color: colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 6.0),
            Text(
              'Consulted: $advisorModel$budgetLabel',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            if (escalationReason != null && escalationReason!.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4.0),
              Tooltip(
                message: escalationReason!,
                child: Icon(
                  Icons.info_outline,
                  size: 14.0,
                  color: colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A collapsible card displaying full advisor consultation details, escalation
/// rationales, and remaining turn/session budgets.
class AdkEscalationCard extends StatefulWidget {
  /// Creates an [AdkEscalationCard].
  const AdkEscalationCard({
    super.key,
    required this.advisorModel,
    required this.escalationReason,
    this.consultationOutput,
    this.turnCount = 1,
    this.turnBudget = 3,
    this.sessionCount = 1,
    this.sessionBudget = 10,
    this.initiallyExpanded = false,
  });

  /// Model consulted.
  final String advisorModel;

  /// Trigger reason.
  final String escalationReason;

  /// Summary response or output produced by the advisor model.
  final String? consultationOutput;

  /// Turns consumed.
  final int turnCount;

  /// Turn budget cap.
  final int turnBudget;

  /// Session consultations consumed.
  final int sessionCount;

  /// Session consultation budget cap.
  final int sessionBudget;

  /// Whether the card is initially expanded.
  final bool initiallyExpanded;

  @override
  State<AdkEscalationCard> createState() => _AdkEscalationCardState();
}

class _AdkEscalationCardState extends State<AdkEscalationCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final double turnProgress = widget.turnBudget > 0
        ? (widget.turnCount / widget.turnBudget).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      elevation: 1.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: colorScheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12.0),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 14.0,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 16.0,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Model Escalation: ${widget.advisorModel}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.escalationReason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...<Widget>[
            const Divider(height: 1.0),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Turn Budget: ${widget.turnCount} / ${widget.turnBudget}',
                              style: theme.textTheme.labelSmall,
                            ),
                            const SizedBox(height: 4.0),
                            LinearProgressIndicator(
                              value: turnProgress,
                              minHeight: 4.0,
                              borderRadius: BorderRadius.circular(2.0),
                              color: colorScheme.secondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Text(
                        'Session: ${widget.sessionCount}/${widget.sessionBudget}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  if (widget.consultationOutput != null &&
                      widget.consultationOutput!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12.0),
                    Text(
                      'Advisor Response:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: SelectableText(
                        widget.consultationOutput!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
