import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// Summary of an agent skill returned by `list_skills` or `search_skills`.
@immutable
class AdkSkillSummary {
  /// Creates an [AdkSkillSummary].
  const AdkSkillSummary({
    required this.name,
    required this.description,
  });

  /// Unique name of the skill.
  final String name;

  /// Human-readable description of what the skill provides.
  final String description;
}

/// Dedicated card widget for rendering `SkillToolset` tool calls and responses (`list_skills`, `search_skills`, `load_skill`, `unload_skill`, `load_skill_resource`).
///
/// Mirrors the `skill-tool` component in `adk-web`.
class AdkSkillToolCard extends StatefulWidget {
  /// Creates an [AdkSkillToolCard].
  const AdkSkillToolCard({
    super.key,
    required this.toolName,
    this.toolArgs,
    this.toolResult,
    this.isRunning = false,
    this.initiallyExpanded = false,
    this.style,
    this.leadingIcon,
    this.trailingWidget,
    this.headerBuilder,
    this.skillItemBuilder,
    this.contentBuilder,
  });

  /// Name of the invoked skill tool.
  final String toolName;

  /// Arguments passed to the skill tool.
  final Map<String, dynamic>? toolArgs;

  /// Result payload returned by the skill tool.
  final dynamic toolResult;

  /// Whether the tool call is still executing.
  final bool isRunning;

  /// Whether details are expanded by default.
  final bool initiallyExpanded;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    String headerTitle,
    bool isExpanded,
    VoidCallback onToggle,
  )? headerBuilder;

  /// Optional custom builder for individual [AdkSkillSummary] items in list/search results.
  final Widget Function(BuildContext context, AdkSkillSummary skill)?
      skillItemBuilder;

  /// Optional custom builder to replace the expanded body content.
  final Widget Function(
    BuildContext context,
    String toolName,
    Map<String, dynamic>? toolArgs,
    dynamic toolResult,
  )? contentBuilder;

  /// Tool names handled by [AdkSkillToolCard].
  static const Set<String> supportedTools = <String>{
    'list_skills',
    'search_skills',
    'load_skill',
    'unload_skill',
    'load_skill_resource',
  };

  /// Whether [name] is a `SkillToolset` tool handled by [AdkSkillToolCard].
  static bool isSkillTool(String? name) =>
      name != null && supportedTools.contains(name);

  /// Parses `<available_skills>` XML or a list of skill maps into [AdkSkillSummary] items.
  static List<AdkSkillSummary> parseSkillsResult(Object? rawResponse) {
    if (rawResponse == null) {
      return const <AdkSkillSummary>[];
    }
    if (rawResponse is Map) {
      final Object? skillsList = rawResponse['skills'];
      if (skillsList is List) {
        return skillsList
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> item) => AdkSkillSummary(
                name: '${item['name'] ?? ''}'.trim(),
                description: '${item['description'] ?? ''}'.trim(),
              ),
            )
            .where((AdkSkillSummary s) => s.name.isNotEmpty)
            .toList();
      }
      final Object? resultStr = rawResponse['result'] ?? rawResponse['output'];
      if (resultStr is String) {
        return _parseAvailableSkillsXml(resultStr);
      }
    }
    if (rawResponse is String) {
      return _parseAvailableSkillsXml(rawResponse);
    }
    return const <AdkSkillSummary>[];
  }

  static List<AdkSkillSummary> _parseAvailableSkillsXml(String xml) {
    final List<AdkSkillSummary> skills = <AdkSkillSummary>[];
    final RegExp skillRegex = RegExp(
      r'<skill>[\s\S]*?<name>([\s\S]*?)<\/name>[\s\S]*?<description>([\s\S]*?)<\/description>[\s\S]*?<\/skill>',
    );
    for (final RegExpMatch match in skillRegex.allMatches(xml)) {
      skills.add(
        AdkSkillSummary(
          name: (match.group(1) ?? '').trim(),
          description: (match.group(2) ?? '').trim(),
        ),
      );
    }
    return skills;
  }

  @override
  State<AdkSkillToolCard> createState() => _AdkSkillToolCardState();
}

class _AdkSkillToolCardState extends State<AdkSkillToolCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _isExpanded = !_isExpanded);

  Map<String, dynamic> get _responseMap {
    final Object? res = widget.toolResult;
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return res.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  String? get _errorMessage {
    final Object? err = _responseMap['error'];
    if (err is String && err.trim().isNotEmpty) return err.trim();
    return null;
  }

  String get _skillName =>
      '${widget.toolArgs?['name'] ?? widget.toolArgs?['skill_name'] ?? _responseMap['skill_name'] ?? ''}'
          .trim();

  String get _resourcePath =>
      '${widget.toolArgs?['file_path'] ?? _responseMap['file_path'] ?? ''}'
          .trim();

  String get _searchQuery => '${widget.toolArgs?['query'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(widget.style) ?? widget.style;
    final String? error = _errorMessage;
    final bool hasError = error != null;
    final List<AdkSkillSummary> skills =
        AdkSkillToolCard.parseSkillsResult(widget.toolResult);

    final Color accentColor = hasError
        ? theme.colorScheme.error
        : (effectiveStyle?.accentColor ?? Colors.indigo.shade600);
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);
    final String titleText = _headerLabel(skills.length);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ??
                theme.colorScheme.surfaceContainerLow,
            borderRadius: radius,
            border: Border.all(
              color: hasError
                  ? theme.colorScheme.error.withValues(alpha: 0.5)
                  : (effectiveStyle?.borderColor ??
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.headerBuilder != null)
            widget.headerBuilder!(context, titleText, _isExpanded, _toggle)
          else
            InkWell(
              onTap: _toggle,
              borderRadius: radius,
              child: Container(
                color: effectiveStyle?.headerBackgroundColor,
                padding: effectiveStyle?.padding ??
                    const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 10.0,
                    ),
                child: Row(
                  children: <Widget>[
                    widget.leadingIcon ??
                        Icon(
                          _iconForTool(widget.toolName),
                          size: 16.0,
                          color: accentColor,
                        ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        titleText,
                        style: effectiveStyle?.titleStyle ??
                            theme.textTheme.labelMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: effectiveStyle?.textColor,
                            ),
                      ),
                    ),
                    if (widget.trailingWidget != null) ...<Widget>[
                      widget.trailingWidget!,
                      const SizedBox(width: 6.0),
                    ],
                    if (widget.isRunning)
                      const SizedBox(
                        width: 14.0,
                        height: 14.0,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      )
                    else
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18.0,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 10.0),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (_isExpanded && !hasError) ...<Widget>[
            const Divider(height: 1.0),
            Padding(
              padding: effectiveStyle?.padding ?? const EdgeInsets.all(12.0),
              child: widget.contentBuilder != null
                  ? widget.contentBuilder!(
                      context,
                      widget.toolName,
                      widget.toolArgs,
                      widget.toolResult,
                    )
                  : _buildExpandedContent(theme, effectiveStyle, skills),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForTool(String name) {
    switch (name) {
      case 'list_skills':
      case 'search_skills':
        return Icons.extension_outlined;
      case 'load_skill':
        return Icons.auto_stories_outlined;
      case 'load_skill_resource':
        return Icons.description_outlined;
      case 'unload_skill':
        return Icons.eject_outlined;
      default:
        return Icons.extension_outlined;
    }
  }

  String _headerLabel(int skillCount) {
    switch (widget.toolName) {
      case 'list_skills':
        return skillCount > 0
            ? 'Available Skills ($skillCount)'
            : 'List Available Skills';
      case 'search_skills':
        return _searchQuery.isNotEmpty
            ? 'Search Skills: "$_searchQuery" ($skillCount)'
            : 'Search Skills ($skillCount)';
      case 'load_skill':
        return _skillName.isNotEmpty
            ? 'Loaded Skill: $_skillName'
            : 'Load Skill';
      case 'unload_skill':
        return _skillName.isNotEmpty
            ? 'Unloaded Skill: $_skillName'
            : 'Unload Skill';
      case 'load_skill_resource':
        return _resourcePath.isNotEmpty
            ? 'Skill Resource: $_skillName/$_resourcePath'
            : 'Load Skill Resource';
      default:
        return widget.toolName;
    }
  }

  Widget _buildExpandedContent(
    ThemeData theme,
    AdkCardStyle? effectiveStyle,
    List<AdkSkillSummary> skills,
  ) {
    if (widget.toolName == 'list_skills' ||
        widget.toolName == 'search_skills') {
      if (skills.isEmpty) {
        return Text(
          'No skills found.',
          style: effectiveStyle?.bodyStyle ??
              theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: skills.map((AdkSkillSummary s) {
          if (widget.skillItemBuilder != null) {
            return widget.skillItemBuilder!(context, s);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: Text(
                    s.name,
                    style: effectiveStyle?.subtitleStyle ??
                        theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    s.description,
                    style: effectiveStyle?.bodyStyle ??
                        theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    if (widget.toolName == 'load_skill') {
      final String instructions = '${_responseMap['instructions'] ?? ''}'.trim();
      final Object? frontmatter = _responseMap['frontmatter'];
      final String? description = frontmatter is Map
          ? frontmatter['description']?.toString()
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (description != null && description.isNotEmpty) ...<Widget>[
            Text(
              description,
              style: effectiveStyle?.bodyStyle ??
                  theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8.0),
          ],
          if (instructions.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: SelectableText(
                instructions,
                style: effectiveStyle?.codeStyle ??
                    theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                    ),
              ),
            ),
        ],
      );
    }

    if (widget.toolName == 'load_skill_resource') {
      final String content = '${_responseMap['content'] ?? ''}'.trim();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: SelectableText(
          content.isEmpty ? 'Empty resource content.' : content,
          style: effectiveStyle?.codeStyle ??
              theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11.5,
              ),
        ),
      );
    }

    final Object? activeSkills = _responseMap['active_skills'];
    if (activeSkills is List && activeSkills.isNotEmpty) {
      return Wrap(
        spacing: 6.0,
        runSpacing: 4.0,
        children: activeSkills.map((Object? item) {
          return Chip(
            label: Text(
              '$item',
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            visualDensity: VisualDensity.compact,
          );
        }).toList(),
      );
    }

    return Text(
      '${widget.toolResult ?? widget.toolArgs ?? ''}',
      style: effectiveStyle?.codeStyle ??
          theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
    );
  }
}
