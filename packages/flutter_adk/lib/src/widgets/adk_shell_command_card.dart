import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// Dedicated terminal card widget for rendering shell execution tools (`Execute`, `execute_bash`, `run_command`, `run_skill_script`).
///
/// Mirrors the `shell-command` component in `adk-web`.
class AdkShellCommandCard extends StatefulWidget {
  /// Creates an [AdkShellCommandCard].
  const AdkShellCommandCard({
    super.key,
    required this.toolName,
    this.toolArgs,
    this.toolResult,
    this.isRunning = false,
    this.initiallyExpanded = true,
    this.promptPrefix = r'$ ',
    this.style,
    this.stdoutStyle,
    this.stderrStyle,
    this.leadingIcon,
    this.trailingWidget,
    this.statusBadgeBuilder,
    this.headerBuilder,
    this.outputBuilder,
  });

  /// Name of the invoked shell execution tool.
  final String toolName;

  /// Arguments passed to the shell tool.
  final Map<String, dynamic>? toolArgs;

  /// Result payload returned by the shell tool.
  final dynamic toolResult;

  /// Whether the command is currently executing.
  final bool isRunning;

  /// Whether terminal output is expanded by default.
  final bool initiallyExpanded;

  /// Prefix string rendered before the command in the header (defaults to `r'$ '`).
  final String promptPrefix;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Custom text style for standard output lines.
  final TextStyle? stdoutStyle;

  /// Custom text style for standard error lines.
  final TextStyle? stderrStyle;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder for the exit-code or timeout status badge.
  final Widget Function(BuildContext context, int? exitCode, bool timedOut)?
      statusBadgeBuilder;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    String command,
    int? exitCode,
    bool timedOut,
    bool isExpanded,
    VoidCallback onToggle,
  )? headerBuilder;

  /// Optional custom builder to replace the terminal output section.
  final Widget Function(
    BuildContext context,
    String stdout,
    String stderr,
    int? exitCode,
  )? outputBuilder;

  /// Tool names handled by [AdkShellCommandCard].
  static const Set<String> supportedTools = <String>{
    'Execute',
    'execute_bash',
    'run_command',
    'run_skill_script',
  };

  /// Whether [name] is a shell command tool handled by [AdkShellCommandCard].
  static bool isShellTool(String? name) =>
      name != null && supportedTools.contains(name);

  static final RegExp _ansiPattern = RegExp(
    r'[\u001b\u009b][\[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]',
  );

  /// Strips ANSI terminal escape codes from [text].
  static String stripAnsi(String text) => text.replaceAll(_ansiPattern, '');

  @override
  State<AdkShellCommandCard> createState() => _AdkShellCommandCardState();
}

class _AdkShellCommandCardState extends State<AdkShellCommandCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _isExpanded = !_isExpanded);

  String get _commandString {
    final Map<String, dynamic>? args = widget.toolArgs;
    if (args == null) return widget.toolName;
    if (args['command'] is String) return (args['command'] as String).trim();
    if (args['file_path'] is String) {
      final String skill = '${args['skill_name'] ?? ''}'.trim();
      final String path = '${args['file_path']}'.trim();
      return skill.isNotEmpty ? '$skill/$path' : path;
    }
    return widget.toolName;
  }

  Map<String, dynamic> get _resMap {
    final Object? res = widget.toolResult;
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return res.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).terminalCardStyle?.merge(widget.style) ??
        widget.style;
    final Map<String, dynamic> res = _resMap;
    final String stdout = AdkShellCommandCard.stripAnsi(
      '${res['stdout'] ?? (widget.toolResult is String ? widget.toolResult : '')}'
          .trimRight(),
    );
    final String stderr = AdkShellCommandCard.stripAnsi(
      '${res['stderr'] ?? res['error'] ?? ''}'.trimRight(),
    );
    final int? exitCode = (res['exit_code'] ?? res['returncode']) is num
        ? ((res['exit_code'] ?? res['returncode']) as num).toInt()
        : null;
    final bool timedOut =
        res['timed_out'] == true || res['status'] == 'timeout';
    final bool hasError =
        timedOut || (exitCode != null && exitCode != 0) || res['error'] != null;

    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ?? const Color(0xFF1E1E24),
            borderRadius: radius,
            border: Border.all(
              color: hasError
                  ? theme.colorScheme.error.withValues(alpha: 0.7)
                  : (effectiveStyle?.borderColor ?? Colors.white24),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.headerBuilder != null)
            widget.headerBuilder!(
              context,
              _commandString,
              exitCode,
              timedOut,
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
                      vertical: 9.0,
                    ),
                child: Row(
                  children: <Widget>[
                    widget.leadingIcon ??
                        Icon(
                          Icons.terminal_rounded,
                          size: 16.0,
                          color: effectiveStyle?.accentColor ??
                              Colors.greenAccent,
                        ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        '${widget.promptPrefix}$_commandString',
                        style: effectiveStyle?.titleStyle ??
                            theme.textTheme.labelMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: effectiveStyle?.textColor ?? Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.statusBadgeBuilder != null)
                      widget.statusBadgeBuilder!(context, exitCode, timedOut)
                    else if (timedOut)
                      _buildStatusChip('TIMEOUT', Colors.orangeAccent)
                    else if (exitCode != null)
                      _buildStatusChip(
                        'exit $exitCode',
                        exitCode == 0 ? Colors.greenAccent : Colors.redAccent,
                      ),
                    if (widget.trailingWidget != null) ...<Widget>[
                      const SizedBox(width: 6.0),
                      widget.trailingWidget!,
                    ],
                    const SizedBox(width: 6.0),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18.0,
                      color: effectiveStyle?.textColor ?? Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          if (_isExpanded && (stdout.isNotEmpty || stderr.isNotEmpty)) ...<
            Widget
          >[
            const Divider(height: 1.0, color: Colors.white12),
            if (widget.outputBuilder != null)
              widget.outputBuilder!(context, stdout, stderr, exitCode)
            else
              Container(
                constraints: BoxConstraints(
                  maxHeight: effectiveStyle?.maxBodyHeight ?? 220.0,
                ),
                padding: const EdgeInsets.all(10.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (stdout.isNotEmpty)
                        SelectableText(
                          stdout,
                          style: widget.stdoutStyle ??
                              effectiveStyle?.codeStyle ??
                              const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: Color(0xFFE0E0E0),
                              ),
                        ),
                      if (stderr.isNotEmpty) ...<Widget>[
                        if (stdout.isNotEmpty) const SizedBox(height: 6.0),
                        SelectableText(
                          stderr,
                          style: widget.stderrStyle ??
                              const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: Colors.redAccent,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.0,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
