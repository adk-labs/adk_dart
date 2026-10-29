import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// Type of a line in a unified file diff.
enum AdkDiffLineType {
  /// Unchanged surrounding line.
  context,

  /// Newly added line (`+`).
  added,

  /// Deleted line (`-`).
  removed,
}

/// A single diff line with old/new line numbers and text content.
@immutable
class AdkDiffLine {
  /// Creates an [AdkDiffLine].
  const AdkDiffLine({
    required this.type,
    required this.content,
    this.oldLineNum,
    this.newLineNum,
  });

  /// Classification of this diff line.
  final AdkDiffLineType type;

  /// Raw line text.
  final String content;

  /// 1-based line number in the original text, if applicable.
  final int? oldLineNum;

  /// 1-based line number in the modified text, if applicable.
  final int? newLineNum;
}

/// Dedicated card widget for rendering `EnvironmentToolset` file operations (`EditFile`, `WriteFile`, `ReadFile`).
///
/// Mirrors the `file-edit` component in `adk-web` with line-by-line unified diff and line-numbered viewer.
class AdkFileEditCard extends StatefulWidget {
  /// Creates an [AdkFileEditCard].
  const AdkFileEditCard({
    super.key,
    required this.toolName,
    this.toolArgs,
    this.toolResult,
    this.isRunning = false,
    this.initiallyExpanded = true,
    this.style,
    this.addedBackgroundColor,
    this.addedTextColor,
    this.removedBackgroundColor,
    this.removedTextColor,
    this.leadingIcon,
    this.trailingWidget,
    this.headerBuilder,
    this.diffLineBuilder,
    this.readContentBuilder,
  });

  /// Name of the file tool (`EditFile`, `WriteFile`, `ReadFile`).
  final String toolName;

  /// Arguments passed to the file tool.
  final Map<String, dynamic>? toolArgs;

  /// Result returned by the file tool.
  final dynamic toolResult;

  /// Whether the file tool call is currently running.
  final bool isRunning;

  /// Whether the diff or file content body is initially expanded.
  final bool initiallyExpanded;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Custom background color for added (`+`) diff lines.
  final Color? addedBackgroundColor;

  /// Custom text color for added (`+`) diff lines.
  final Color? addedTextColor;

  /// Custom background color for removed (`-`) diff lines.
  final Color? removedBackgroundColor;

  /// Custom text color for removed (`-`) diff lines.
  final Color? removedTextColor;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    String filePath,
    int addedCount,
    int removedCount,
    bool isExpanded,
    VoidCallback onToggle,
  )? headerBuilder;

  /// Optional custom builder for each [AdkDiffLine] in `EditFile` / `WriteFile`.
  final Widget Function(BuildContext context, AdkDiffLine line)?
      diffLineBuilder;

  /// Optional custom builder for `ReadFile` content.
  final Widget Function(BuildContext context, String filePath, String content)?
      readContentBuilder;

  /// Tool names handled by [AdkFileEditCard].
  static const Set<String> supportedTools = <String>{
    'EditFile',
    'WriteFile',
    'ReadFile',
    'edit_file',
    'write_file',
    'read_file',
  };

  /// Whether [name] is a file tool handled by [AdkFileEditCard].
  static bool isFileTool(String? name) =>
      name != null && supportedTools.contains(name);

  /// Computes a line-by-line diff between [oldStr] and [newStr].
  static List<AdkDiffLine> computeDiff(String oldStr, String newStr) {
    final List<String> oldLines =
        oldStr.isEmpty ? const <String>[] : oldStr.split('\n');
    final List<String> newLines =
        newStr.isEmpty ? const <String>[] : newStr.split('\n');
    final int m = oldLines.length;
    final int n = newLines.length;

    if (m * n > 250000) {
      return <AdkDiffLine>[
        for (int i = 0; i < m; i++)
          AdkDiffLine(
            type: AdkDiffLineType.removed,
            content: oldLines[i],
            oldLineNum: i + 1,
          ),
        for (int j = 0; j < n; j++)
          AdkDiffLine(
            type: AdkDiffLineType.added,
            content: newLines[j],
            newLineNum: j + 1,
          ),
      ];
    }

    final List<List<int>> dp = List<List<int>>.generate(
      m + 1,
      (_) => List<int>.filled(n + 1, 0),
    );
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (oldLines[i - 1] == newLines[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }

    final List<AdkDiffLine> reversed = <AdkDiffLine>[];
    int i = m;
    int j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1]) {
        reversed.add(
          AdkDiffLine(
            type: AdkDiffLineType.context,
            content: oldLines[i - 1],
            oldLineNum: i,
            newLineNum: j,
          ),
        );
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        reversed.add(
          AdkDiffLine(
            type: AdkDiffLineType.added,
            content: newLines[j - 1],
            newLineNum: j,
          ),
        );
        j--;
      } else {
        reversed.add(
          AdkDiffLine(
            type: AdkDiffLineType.removed,
            content: oldLines[i - 1],
            oldLineNum: i,
          ),
        );
        i--;
      }
    }
    return reversed.reversed.toList();
  }

  @override
  State<AdkFileEditCard> createState() => _AdkFileEditCardState();
}

class _AdkFileEditCardState extends State<AdkFileEditCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _isExpanded = !_isExpanded);

  String get _filePath =>
      '${widget.toolArgs?['path'] ?? widget.toolArgs?['file_path'] ?? ''}'
          .trim();

  bool get _isReadTool =>
      widget.toolName == 'ReadFile' || widget.toolName == 'read_file';

  String? get _errorMessage {
    final Object? res = widget.toolResult;
    if (res is Map) {
      if (res['status'] == 'error') {
        return (res['message'] ?? res['error'] ?? 'File operation failed')
            .toString();
      }
      if (res['error'] is String && (res['error'] as String).isNotEmpty) {
        return res['error'] as String;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(widget.style) ?? widget.style;
    final String? error = _errorMessage;
    final bool hasError = error != null;

    final String oldStr = '${widget.toolArgs?['old_string'] ?? ''}';
    final String newStr =
        '${widget.toolArgs?['new_string'] ?? widget.toolArgs?['content'] ?? ''}';
    final List<AdkDiffLine> diffLines = _isReadTool
        ? const <AdkDiffLine>[]
        : AdkFileEditCard.computeDiff(oldStr, newStr);
    final int addedCount = diffLines
        .where((AdkDiffLine l) => l.type == AdkDiffLineType.added)
        .length;
    final int removedCount = diffLines
        .where((AdkDiffLine l) => l.type == AdkDiffLineType.removed)
        .length;

    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);
    final String displayPath =
        _filePath.isNotEmpty ? _filePath : widget.toolName;

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
            widget.headerBuilder!(
              context,
              displayPath,
              addedCount,
              removedCount,
              _isExpanded,
              _toggle,
            )
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
                          _isReadTool
                              ? Icons.menu_book_outlined
                              : Icons.edit_document,
                          size: 16.0,
                          color: hasError
                              ? theme.colorScheme.error
                              : (effectiveStyle?.accentColor ??
                                  theme.colorScheme.primary),
                        ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        displayPath,
                        style: effectiveStyle?.titleStyle ??
                            theme.textTheme.labelMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: effectiveStyle?.textColor,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_isReadTool &&
                        (addedCount > 0 || removedCount > 0)) ...<Widget>[
                      if (addedCount > 0)
                        Text(
                          '+$addedCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: widget.addedTextColor ?? Colors.green.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (addedCount > 0 && removedCount > 0)
                        const SizedBox(width: 6.0),
                      if (removedCount > 0)
                        Text(
                          '-$removedCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: widget.removedTextColor ??
                                theme.colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(width: 8.0),
                    ],
                    if (widget.trailingWidget != null) ...<Widget>[
                      widget.trailingWidget!,
                      const SizedBox(width: 6.0),
                    ],
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
            if (_isReadTool)
              _buildReadContent(theme, effectiveStyle)
            else
              _buildDiffContent(theme, effectiveStyle, diffLines),
          ],
        ],
      ),
    );
  }

  Widget _buildReadContent(ThemeData theme, AdkCardStyle? effectiveStyle) {
    final Object? res = widget.toolResult;
    String content = '';
    if (res is Map) {
      content = '${res['content'] ?? res['result'] ?? ''}'.trimRight();
    } else if (res is String) {
      content = res.trimRight();
    }
    if (widget.readContentBuilder != null) {
      return widget.readContentBuilder!(context, _filePath, content);
    }
    if (content.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          'Read file $_filePath',
          style: effectiveStyle?.codeStyle ??
              theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(
        maxHeight: effectiveStyle?.maxBodyHeight ?? 240.0,
      ),
      padding: const EdgeInsets.all(10.0),
      child: SingleChildScrollView(
        child: SelectableText(
          content,
          style: effectiveStyle?.codeStyle ??
              theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11.5,
              ),
        ),
      ),
    );
  }

  Widget _buildDiffContent(
    ThemeData theme,
    AdkCardStyle? effectiveStyle,
    List<AdkDiffLine> diffLines,
  ) {
    if (diffLines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: BoxConstraints(
        maxHeight: effectiveStyle?.maxBodyHeight ?? 260.0,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: diffLines.map((AdkDiffLine line) {
            if (widget.diffLineBuilder != null) {
              return widget.diffLineBuilder!(context, line);
            }
            final Color? bgColor;
            final Color textColor;
            final String prefix;
            switch (line.type) {
              case AdkDiffLineType.added:
                bgColor = widget.addedBackgroundColor ??
                    Colors.green.withValues(alpha: 0.14);
                textColor = widget.addedTextColor ?? Colors.green.shade800;
                prefix = '+';
              case AdkDiffLineType.removed:
                bgColor = widget.removedBackgroundColor ??
                    theme.colorScheme.error.withValues(alpha: 0.14);
                textColor =
                    widget.removedTextColor ?? theme.colorScheme.error;
                prefix = '-';
              case AdkDiffLineType.context:
                bgColor = null;
                textColor = effectiveStyle?.textColor ??
                    theme.colorScheme.onSurfaceVariant;
                prefix = ' ';
            }
            return Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 1.5,
              ),
              child: Text(
                '$prefix ${line.content}',
                style: (effectiveStyle?.codeStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                        ))
                    ?.copyWith(color: textColor),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
