import 'package:flutter/material.dart';
import 'adk_voice_widgets.dart';

/// An animated badge indicating that the agent was interrupted by user speech
/// (barge-in event).
class AdkLiveBargeInIndicator extends StatefulWidget {
  /// Creates an [AdkLiveBargeInIndicator].
  const AdkLiveBargeInIndicator({
    super.key,
    required this.isBargeIn,
    this.label = 'Agent Interrupted',
    this.backgroundColor,
    this.textColor,
    this.iconColor,
    this.icon,
    this.borderRadius,
    this.padding,
  });

  /// Whether barge-in interruption is currently active.
  final bool isBargeIn;

  /// Display text for the badge.
  final String label;

  /// Custom background color.
  final Color? backgroundColor;

  /// Custom text color.
  final Color? textColor;

  /// Custom icon color.
  final Color? iconColor;

  /// Custom icon.
  final IconData? icon;

  /// Custom border radius.
  final BorderRadius? borderRadius;

  /// Custom padding.
  final EdgeInsetsGeometry? padding;

  @override
  State<AdkLiveBargeInIndicator> createState() => _AdkLiveBargeInIndicatorState();
}

class _AdkLiveBargeInIndicatorState extends State<AdkLiveBargeInIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    if (widget.isBargeIn) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AdkLiveBargeInIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBargeIn != oldWidget.isBargeIn) {
      if (widget.isBargeIn) {
        _controller.forward(from: 0.0);
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final Color effectiveBg = widget.backgroundColor ?? colorScheme.errorContainer;
    final Color effectiveFg = widget.textColor ?? colorScheme.onErrorContainer;
    final Color effectiveIcon = widget.iconColor ?? colorScheme.error;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
          border: Border.all(
            color: colorScheme.error.withValues(alpha: 0.6),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colorScheme.error.withValues(alpha: 0.2),
              blurRadius: 6.0,
              offset: const Offset(0.0, 2.0),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              widget.icon ?? Icons.bolt_rounded,
              size: 16.0,
              color: effectiveIcon,
            ),
            const SizedBox(width: 4.0),
            Text(
              widget.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: effectiveFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A floating or docked real-time speech interaction bar for `CascadeLive` and
/// Gemini Live bidirectional streaming conversations.
class AdkCascadeLiveBar extends StatelessWidget {
  /// Creates an [AdkCascadeLiveBar].
  const AdkCascadeLiveBar({
    super.key,
    required this.isListening,
    this.isSpeaking = false,
    this.isBargeIn = false,
    this.partialTranscript,
    this.onMicToggle,
    this.onDisconnect,
    this.statusText,
    this.backgroundColor,
    this.visualizerColor,
    this.bargeInColor,
    this.elevation,
    this.margin,
    this.padding,
    this.borderRadius,
    this.customLeading,
    this.customTrailing,
    this.waveVisualizerBuilder,
  });

  /// Whether user microphone input is currently open and transmitting.
  final bool isListening;

  /// Whether the agent is currently producing audio speech output.
  final bool isSpeaking;

  /// Whether user speech interrupted model playback.
  final bool isBargeIn;

  /// Real-time live transcription string from STT.
  final String? partialTranscript;

  /// Callback when user taps the microphone toggle button.
  final VoidCallback? onMicToggle;

  /// Callback when user taps the disconnect / end live call button.
  final VoidCallback? onDisconnect;

  /// Custom status label to override default status text.
  final String? statusText;

  /// Custom background color of the bar container.
  final Color? backgroundColor;

  /// Custom color override for the waveform visualizer bars.
  final Color? visualizerColor;

  /// Custom color override when barge-in interrupt occurs.
  final Color? bargeInColor;

  /// Custom elevation shadow for the container.
  final double? elevation;

  /// Custom outer margin.
  final EdgeInsetsGeometry? margin;

  /// Custom inner padding.
  final EdgeInsetsGeometry? padding;

  /// Custom border radius.
  final BorderRadius? borderRadius;

  /// Custom widget replacing the default microphone button.
  final Widget? customLeading;

  /// Custom widget replacing the default disconnect button.
  final Widget? customTrailing;

  /// Custom builder for the audio wave visualizer.
  final Widget Function(
    BuildContext context,
    bool isActive,
    bool isSpeaking,
    bool isBargeIn,
  )? waveVisualizerBuilder;

  String _resolveStatus() {
    if (statusText != null) return statusText!;
    if (isBargeIn) return 'User speaking...';
    if (isSpeaking) return 'Agent speaking...';
    if (isListening) return 'Listening...';
    return 'Live paused';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final Color effectiveBargeIn = bargeInColor ?? colorScheme.error;
    final Color effectiveVisualizer = visualizerColor ??
        (isBargeIn
            ? effectiveBargeIn
            : (isSpeaking ? colorScheme.secondary : colorScheme.primary));

    return Container(
      margin: margin ?? const EdgeInsets.all(12.0),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surfaceContainerHigh,
        borderRadius: borderRadius ?? BorderRadius.circular(28.0),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: elevation != null ? (elevation! * 0.03).clamp(0.05, 0.3) : 0.12),
            blurRadius: elevation ?? 10.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
        border: Border.all(
          color: isBargeIn
              ? effectiveBargeIn.withValues(alpha: 0.5)
              : (isListening || isSpeaking
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (customLeading != null)
            customLeading!
          else
            AdkVoiceMicButton(
              isListening: isListening,
              size: 40.0,
              onPressed: onMicToggle ?? () {},
            ),
          const SizedBox(width: 12.0),
          if (waveVisualizerBuilder != null)
            waveVisualizerBuilder!(context, isListening || isSpeaking, isSpeaking, isBargeIn)
          else
            AdkAudioWaveVisualizer(
              isActive: isListening || isSpeaking,
              height: 20.0,
              barCount: 5,
              color: effectiveVisualizer,
            ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.0,
                  children: <Widget>[
                    Text(
                      _resolveStatus(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isBargeIn
                            ? effectiveBargeIn
                            : (isSpeaking ? colorScheme.secondary : colorScheme.primary),
                      ),
                    ),
                    if (isBargeIn)
                      AdkLiveBargeInIndicator(
                        isBargeIn: true,
                        backgroundColor: bargeInColor?.withValues(alpha: 0.2),
                        iconColor: bargeInColor,
                      ),
                  ],
                ),
                if (partialTranscript != null && partialTranscript!.isNotEmpty)
                  Text(
                    partialTranscript!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (customTrailing != null)
            customTrailing!
          else if (onDisconnect != null) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.call_end_rounded),
              color: colorScheme.error,
              tooltip: 'End Live Session',
              onPressed: onDisconnect,
            ),
          ],
        ],
      ),
    );
  }
}
