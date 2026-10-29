import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// Dedicated card widget for rendering `load_web_page` tool calls and responses.
///
/// Mirrors the `web-page` component in `adk-web`.
class AdkWebPageCard extends StatefulWidget {
  /// Creates an [AdkWebPageCard].
  const AdkWebPageCard({
    super.key,
    required this.toolName,
    this.toolArgs,
    this.toolResult,
    this.isRunning = false,
    this.initiallyExpanded = false,
    this.onUrlTap,
    this.style,
    this.leadingIcon,
    this.trailingWidget,
    this.domainBadgeBuilder,
    this.headerBuilder,
    this.contentBuilder,
  });

  /// Name of the web page tool (`load_web_page`).
  final String toolName;

  /// Arguments passed to the web page tool.
  final Map<String, dynamic>? toolArgs;

  /// Result returned by the web page tool.
  final dynamic toolResult;

  /// Whether the web page fetch is still in progress.
  final bool isRunning;

  /// Whether the fetched page content preview is expanded by default.
  final bool initiallyExpanded;

  /// Optional callback invoked when the URL chip is tapped.
  final void Function(String url)? onUrlTap;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder for the domain chip badge.
  final Widget Function(BuildContext context, String domain)?
      domainBadgeBuilder;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    String url,
    String domain,
    bool failed,
    bool isExpanded,
    VoidCallback onToggle,
  )? headerBuilder;

  /// Optional custom builder to replace the expanded page text body.
  final Widget Function(BuildContext context, String content, bool failed)?
      contentBuilder;

  /// Tool names handled by [AdkWebPageCard].
  static const Set<String> supportedTools = <String>{
    'load_web_page',
    'fetch_web_page',
  };

  /// Whether [name] is a web page tool handled by [AdkWebPageCard].
  static bool isWebPageTool(String? name) =>
      name != null && supportedTools.contains(name);

  @override
  State<AdkWebPageCard> createState() => _AdkWebPageCardState();
}

class _AdkWebPageCardState extends State<AdkWebPageCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _isExpanded = !_isExpanded);

  String get _url =>
      '${widget.toolArgs?['url'] ?? widget.toolArgs?['uri'] ?? ''}'.trim();

  String get _domain {
    if (_url.isEmpty) return '';
    final Uri? parsed = Uri.tryParse(_url);
    return parsed?.host ?? _url;
  }

  String get _content {
    final Object? res = widget.toolResult;
    if (res is Map) {
      return '${res['result'] ?? res['content'] ?? res['text'] ?? ''}'.trim();
    }
    if (res is String) {
      return res.trim();
    }
    return '';
  }

  bool get _isFailed =>
      _content.startsWith('Failed to fetch url:') ||
      (widget.toolResult is Map &&
          (widget.toolResult as Map)['error'] != null);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(widget.style) ?? widget.style;
    final bool failed = _isFailed;
    final String content = _content;
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ??
                theme.colorScheme.surfaceContainerLow,
            borderRadius: radius,
            border: Border.all(
              color: failed
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
              _url,
              _domain,
              failed,
              _isExpanded,
              _toggle,
            )
          else
            InkWell(
              onTap: content.isNotEmpty
                  ? _toggle
                  : (widget.onUrlTap != null && _url.isNotEmpty
                        ? () => widget.onUrlTap!(_url)
                        : null),
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
                          failed
                              ? Icons.public_off_rounded
                              : Icons.language_rounded,
                          size: 16.0,
                          color: failed
                              ? theme.colorScheme.error
                              : (effectiveStyle?.accentColor ??
                                  theme.colorScheme.primary),
                        ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        _url.isNotEmpty ? _url : widget.toolName,
                        style: effectiveStyle?.titleStyle ??
                            theme.textTheme.labelMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: effectiveStyle?.textColor,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_domain.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 6.0),
                      if (widget.domainBadgeBuilder != null)
                        widget.domainBadgeBuilder!(context, _domain)
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            _domain,
                            style: effectiveStyle?.subtitleStyle ??
                                theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10.0,
                                  color:
                                      theme.colorScheme.onSecondaryContainer,
                                ),
                          ),
                        ),
                    ],
                    if (widget.trailingWidget != null) ...<Widget>[
                      const SizedBox(width: 4.0),
                      widget.trailingWidget!,
                    ],
                    if (content.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 4.0),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18.0,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_isExpanded && content.isNotEmpty) ...<Widget>[
            const Divider(height: 1.0),
            if (widget.contentBuilder != null)
              widget.contentBuilder!(context, content, failed)
            else
              Container(
                constraints: BoxConstraints(
                  maxHeight: effectiveStyle?.maxBodyHeight ?? 200.0,
                ),
                padding: const EdgeInsets.all(10.0),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: effectiveStyle?.bodyStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          color: failed
                              ? theme.colorScheme.error
                              : (effectiveStyle?.textColor ??
                                  theme.colorScheme.onSurfaceVariant),
                        ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
