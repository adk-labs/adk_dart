import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

/// Data model representing an AI Agent Persona.
@immutable
class AdkPersona {
  /// Creates an [AdkPersona].
  const AdkPersona({
    required this.id,
    required this.name,
    required this.description,
    this.agent,
    this.icon = Icons.smart_toy_outlined,
    this.avatarUrl,
    this.accentColor,
    this.suggestedPrompts = const <String>[],
    this.metadata = const <String, dynamic>{},
  });

  /// Unique identifier for this persona.
  final String id;

  /// Display name of the AI persona.
  final String name;

  /// Short summary description of what this agent does.
  final String description;

  /// ADK Agent instance associated with this persona.
  final adk.BaseAgent? agent;

  /// Icon representing this persona.
  final IconData icon;

  /// Optional network image avatar URL.
  final String? avatarUrl;

  /// Theme accent color for this persona card.
  final Color? accentColor;

  /// Initial prompt suggestion chips for this persona.
  final List<String> suggestedPrompts;

  /// Extra custom metadata tags.
  final Map<String, dynamic> metadata;
}

/// A responsive Grid / Carousel card selector for picking from multiple AI agent personas.
class AdkAgentPersonaSelector extends StatelessWidget {
  /// Creates an [AdkAgentPersonaSelector].
  const AdkAgentPersonaSelector({
    super.key,
    required this.personas,
    required this.onPersonaSelected,
    this.selectedPersonaId,
    this.isGrid = true,
    this.crossAxisCount = 2,
    this.padding = const EdgeInsets.all(12.0),
    this.cardBuilder,
    this.header,
  });

  /// The list of AI personas to display.
  final List<AdkPersona> personas;

  /// Callback when a persona card is tapped.
  final ValueChanged<AdkPersona> onPersonaSelected;

  /// Currently selected persona ID, if any.
  final String? selectedPersonaId;

  /// Whether to render in a grid layout (true) or horizontal carousel (false).
  final bool isGrid;

  /// Number of columns when in grid mode.
  final int crossAxisCount;

  /// Padding around the selector.
  final EdgeInsetsGeometry padding;

  /// Optional builder to override the card rendering.
  final Widget Function(BuildContext context, AdkPersona persona, bool isSelected, VoidCallback onSelect)? cardBuilder;

  /// Optional header widget placed above the selector.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (personas.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget content = isGrid
        ? GridView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            padding: padding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12.0,
              mainAxisSpacing: 12.0,
              childAspectRatio: 1.15,
            ),
            itemCount: personas.length,
            itemBuilder: (BuildContext context, int index) {
              final AdkPersona persona = personas[index];
              final bool isSelected = persona.id == selectedPersonaId;
              if (cardBuilder != null) {
                return cardBuilder!(
                  context,
                  persona,
                  isSelected,
                  () => onPersonaSelected(persona),
                );
              }
              return _buildDefaultCard(context, persona, isSelected);
            },
          )
        : SizedBox(
            height: 140.0,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: padding,
              itemCount: personas.length,
              separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 12.0),
              itemBuilder: (BuildContext context, int index) {
                final AdkPersona persona = personas[index];
                final bool isSelected = persona.id == selectedPersonaId;
                if (cardBuilder != null) {
                  return cardBuilder!(
                    context,
                    persona,
                    isSelected,
                    () => onPersonaSelected(persona),
                  );
                }
                return SizedBox(
                  width: 180.0,
                  child: _buildDefaultCard(context, persona, isSelected),
                );
              },
            ),
          );

    if (header != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          header!,
          content,
        ],
      );
    }

    return content;
  }

  Widget _buildDefaultCard(BuildContext context, AdkPersona persona, bool isSelected) {
    final ThemeData theme = Theme.of(context);
    final Color accent = persona.accentColor ?? theme.colorScheme.primary;

    return InkWell(
      onTap: () => onPersonaSelected(persona),
      borderRadius: BorderRadius.circular(16.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isSelected
                ? accent
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: <BoxShadow>[
            if (isSelected)
              BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 8.0,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16.0,
                  backgroundColor: accent.withValues(alpha: 0.2),
                  child: Icon(persona.icon, size: 18.0, color: accent),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle, size: 18.0, color: accent),
              ],
            ),
            const Spacer(),
            Text(
              persona.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              persona.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
