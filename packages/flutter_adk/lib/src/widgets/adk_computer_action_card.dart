import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// Dedicated card widget for rendering `ComputerUseToolset` actions and browser screenshots.
///
/// Mirrors the `computer-action` component in `adk-web`, including coordinate reticle overlays.
class AdkComputerActionCard extends StatelessWidget {
  /// Creates an [AdkComputerActionCard].
  const AdkComputerActionCard({
    super.key,
    required this.toolName,
    this.toolArgs,
    this.toolResult,
    this.isRunning = false,
    this.style,
    this.leadingIcon,
    this.trailingWidget,
    this.headerBuilder,
    this.coordinateBadgeBuilder,
    this.screenshotBuilder,
  });

  /// Name of the invoked computer-use tool.
  final String toolName;

  /// Arguments passed to the computer-use tool (for example `x`, `y`, `text`, `url`).
  final Map<String, dynamic>? toolArgs;

  /// Result returned by the computer-use tool, optionally containing a screenshot image.
  final dynamic toolResult;

  /// Whether the computer-use action is currently executing.
  final bool isRunning;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    String actionLabel,
    ({int x, int y})? coordinates,
  )? headerBuilder;

  /// Optional custom builder for the `(x, y)` coordinate badge.
  final Widget Function(BuildContext context, int x, int y)?
      coordinateBadgeBuilder;

  /// Optional custom builder for rendering the screenshot image bytes.
  final Widget Function(
    BuildContext context,
    Uint8List screenshotBytes,
    ({int x, int y})? coordinates,
  )? screenshotBuilder;

  /// Tool names handled by [AdkComputerActionCard].
  static const Set<String> supportedTools = <String>{
    'computer',
    'click_at',
    'move',
    'mouse_move',
    'mouse_down',
    'mouse_up',
    'context_click',
    'double_click',
    'double_click_at',
    'triple_click',
    'middle_click_coordinate',
    'drag_and_drop',
    'scroll_at',
    'type_text_at',
    'key_press',
    'key_up',
    'wait_5_seconds',
    'go_back',
    'go_forward',
    'search',
    'navigate',
    'key_combination',
    ' hover_at',
    'hover_at',
    'open_web_browser',
    'take_screenshot',
  };

  /// Whether [name] is a `ComputerUseToolset` tool handled by [AdkComputerActionCard].
  static bool isComputerActionTool(String? name) =>
      name != null && supportedTools.contains(name);

  ({int x, int y})? get _coordinates {
    final Map<String, dynamic>? args = toolArgs;
    if (args == null) return null;
    if (args['coordinate'] is List && (args['coordinate'] as List).length == 2) {
      final List<Object?> coord = (args['coordinate'] as List).cast<Object?>();
      if (coord[0] is num && coord[1] is num) {
        return (x: (coord[0] as num).toInt(), y: (coord[1] as num).toInt());
      }
    }
    if (args['x'] is num && args['y'] is num) {
      return (x: (args['x'] as num).toInt(), y: (args['y'] as num).toInt());
    }
    return null;
  }

  String? get _url {
    final Object? res = toolResult;
    if (res is Map && res['url'] is String) {
      return res['url'] as String;
    }
    if (toolArgs?['url'] is String) {
      return toolArgs!['url'] as String;
    }
    return null;
  }

  Uint8List? get _screenshotBytes {
    final Object? res = toolResult;
    if (res is! Map) return null;
    final Object? img = res['image'];
    if (img is Map && img['data'] is String) {
      try {
        return base64Decode(img['data'] as String);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(style) ?? style;
    final ({int x, int y})? coords = _coordinates;
    final String? url = _url;
    final Uint8List? screenshot = _screenshotBytes;
    final String? typedText = toolArgs?['text']?.toString();
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      padding: effectiveStyle?.padding ?? const EdgeInsets.all(12.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ??
                theme.colorScheme.surfaceContainerLow,
            borderRadius: radius,
            border: Border.all(
              color: effectiveStyle?.borderColor ??
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (headerBuilder != null)
            headerBuilder!(context, _labelForAction(), coords)
          else
            Row(
              children: <Widget>[
                leadingIcon ??
                    Icon(
                      _iconForAction(toolName),
                      size: 16.0,
                      color: effectiveStyle?.accentColor ??
                          theme.colorScheme.primary,
                    ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    _labelForAction(),
                    style: effectiveStyle?.titleStyle ??
                        theme.textTheme.labelMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: effectiveStyle?.textColor,
                        ),
                  ),
                ),
                if (coords != null)
                  if (coordinateBadgeBuilder != null)
                    coordinateBadgeBuilder!(context, coords.x, coords.y)
                  else
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
                        '(${coords.x}, ${coords.y})',
                        style: effectiveStyle?.subtitleStyle ??
                            theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                if (trailingWidget != null) ...<Widget>[
                  const SizedBox(width: 6.0),
                  trailingWidget!,
                ],
              ],
            ),
          if (typedText != null && typedText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6.0),
            Text(
              'Input: "$typedText"',
              style: effectiveStyle?.codeStyle ??
                  theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          ],
          if (url != null && url.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6.0),
            Row(
              children: <Widget>[
                Icon(
                  Icons.link_rounded,
                  size: 14.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4.0),
                Expanded(
                  child: Text(
                    url,
                    style: effectiveStyle?.subtitleStyle ??
                        theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (screenshot != null) ...<Widget>[
            const SizedBox(height: 8.0),
            if (screenshotBuilder != null)
              screenshotBuilder!(context, screenshot, coords)
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.memory(
                  screenshot,
                  height: effectiveStyle?.maxBodyHeight ?? 180.0,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ],
      ),
    );
  }

  IconData _iconForAction(String name) {
    if (name.contains('click')) return Icons.ads_click_rounded;
    if (name.contains('type') || name.contains('key')) {
      return Icons.keyboard_alt_outlined;
    }
    if (name.contains('scroll')) return Icons.swap_vert_rounded;
    if (name.contains('navigate') || name.contains('browser')) {
      return Icons.open_in_browser_rounded;
    }
    return Icons.desktop_windows_outlined;
  }

  String _labelForAction() {
    final String? subAction = toolArgs?['action']?.toString();
    if (toolName == 'computer' && subAction != null && subAction.isNotEmpty) {
      return 'computer: $subAction';
    }
    return toolName;
  }
}
