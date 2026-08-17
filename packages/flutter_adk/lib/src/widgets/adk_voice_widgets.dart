import 'package:flutter/material.dart';

/// An animated audio waveform visualizer that reacts to audio streaming.
class AdkAudioWaveVisualizer extends StatefulWidget {
  /// Creates an [AdkAudioWaveVisualizer].
  const AdkAudioWaveVisualizer({
    super.key,
    this.barCount = 5,
    this.color,
    this.height = 24.0,
    this.isActive = true,
  });

  /// Number of waveform bars.
  final int barCount;

  /// Bar color.
  final Color? color;

  /// Maximum visualizer height.
  final double height;

  /// Whether the animation is currently active.
  final bool isActive;

  @override
  State<AdkAudioWaveVisualizer> createState() => _AdkAudioWaveVisualizerState();
}

class _AdkAudioWaveVisualizerState extends State<AdkAudioWaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AdkAudioWaveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
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
    final Color barColor =
        widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.barCount, (int index) {
              final double phase = (index * 0.25) % 1.0;
              final double progress = (_controller.value + phase) % 1.0;
              final double factor = widget.isActive
                  ? (0.2 + 0.8 * (1.0 - (progress - 0.5).abs() * 2))
                  : 0.2;

              return Container(
                width: 3.0,
                height: widget.height * factor,
                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// A voice microphone action button for triggering real-time speech / Gemini Live interactions.
class AdkVoiceMicButton extends StatelessWidget {
  /// Creates an [AdkVoiceMicButton].
  const AdkVoiceMicButton({
    super.key,
    required this.isListening,
    required this.onPressed,
    this.activeColor,
    this.inactiveColor,
    this.size = 48.0,
  });

  /// Whether voice listening is currently active.
  final bool isListening;

  /// Callback when the microphone button is pressed.
  final VoidCallback onPressed;

  /// Background color when active/recording.
  final Color? activeColor;

  /// Background color when idle.
  final Color? inactiveColor;

  /// Button diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color bg = isListening
        ? (activeColor ?? theme.colorScheme.error)
        : (inactiveColor ?? theme.colorScheme.primaryContainer);

    final Color fg = isListening
        ? theme.colorScheme.onError
        : theme.colorScheme.onPrimaryContainer;

    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
        ),
        icon: isListening
            ? const Icon(Icons.mic, size: 22.0)
            : const Icon(Icons.mic_none, size: 22.0),
        tooltip: isListening ? 'Stop listening' : 'Start voice input',
        onPressed: onPressed,
      ),
    );
  }
}
