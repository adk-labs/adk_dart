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
  });

  /// Whether barge-in interruption is currently active.
  final bool isBargeIn;

  /// Display text for the badge.
  final String label;

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

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16.0),
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
              Icons.bolt_rounded,
              size: 16.0,
              color: colorScheme.error,
            ),
            const SizedBox(width: 4.0),
            Text(
              widget.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onErrorContainer,
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

    return Container(
      margin: const EdgeInsets.all(12.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28.0),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
        border: Border.all(
          color: isBargeIn
              ? colorScheme.error.withValues(alpha: 0.5)
              : (isListening || isSpeaking
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          AdkVoiceMicButton(
            isListening: isListening,
            size: 40.0,
            onPressed: onMicToggle ?? () {},
          ),
          const SizedBox(width: 12.0),
          AdkAudioWaveVisualizer(
            isActive: isListening || isSpeaking,
            height: 20.0,
            barCount: 5,
            color: isBargeIn
                ? colorScheme.error
                : (isSpeaking ? colorScheme.secondary : colorScheme.primary),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      _resolveStatus(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isBargeIn
                            ? colorScheme.error
                            : (isSpeaking ? colorScheme.secondary : colorScheme.primary),
                      ),
                    ),
                    if (isBargeIn) ...<Widget>[
                      const SizedBox(width: 8.0),
                      const AdkLiveBargeInIndicator(isBargeIn: true),
                    ],
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
          if (onDisconnect != null) ...<Widget>[
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
