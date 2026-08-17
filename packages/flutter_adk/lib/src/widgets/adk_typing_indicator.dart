import 'package:flutter/material.dart';

/// An animated typing / thinking indicator displayed while an agent generates responses.
class AdkTypingIndicator extends StatefulWidget {
  /// Creates an [AdkTypingIndicator].
  const AdkTypingIndicator({
    super.key,
    this.dotColor,
    this.dotSize = 6.0,
    this.spacing = 4.0,
  });

  /// Color of the animated dots.
  final Color? dotColor;

  /// Diameter of each dot.
  final double dotSize;

  /// Space between dots.
  final double spacing;

  @override
  State<AdkTypingIndicator> createState() => _AdkTypingIndicatorState();
}

class _AdkTypingIndicatorState extends State<AdkTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.dotColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.7);

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (int index) {
            final double offset = (index * 0.2);
            final double progress = (_controller.value - offset) % 1.0;
            final double scale = 0.5 + 0.5 * (1.0 - (progress - 0.5).abs() * 2);

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
              child: Transform.scale(
                scale: scale.clamp(0.4, 1.0),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
