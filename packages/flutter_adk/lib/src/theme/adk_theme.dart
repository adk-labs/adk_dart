import 'package:flutter/material.dart';

/// Theming configuration for ADK Flutter UI components and chat views.
@immutable
class AdkChatThemeData {
  /// Creates an [AdkChatThemeData].
  const AdkChatThemeData({
    this.userBubbleColor,
    this.modelBubbleColor,
    this.toolBubbleColor,
    this.systemBubbleColor,
    this.errorBubbleColor,
    this.userTextColor,
    this.modelTextColor,
    this.userTextStyle,
    this.modelTextStyle,
    this.toolTextStyle,
    this.authorTextStyle,
    this.timestampTextStyle,
    this.borderRadius,
    this.userBorderRadius,
    this.modelBorderRadius,
    this.bubblePadding,
    this.bubbleMargin,
    this.maxWidthFactor = 0.82,
    this.inputBackgroundColor,
    this.inputBorderRadius,
    this.inputTextStyle,
    this.inputHintStyle,
    this.inputPadding,
    this.sendButtonColor,
    this.sendButtonIconColor,
    this.sendButtonIcon,
    this.suggestionBackgroundColor,
    this.suggestionTextColor,
    this.suggestionBorderRadius,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.appBarTextStyle,
    this.showTimestamp = false,
    this.showAvatars = false,
  });

  /// Derives default theme properties from the current Flutter [ThemeData].
  factory AdkChatThemeData.fromTheme(ThemeData theme) {
    return AdkChatThemeData(
      userBubbleColor: theme.colorScheme.primary,
      modelBubbleColor: theme.colorScheme.surfaceContainerHighest,
      toolBubbleColor: theme.colorScheme.surfaceContainerLow,
      systemBubbleColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      errorBubbleColor: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
      userTextColor: theme.colorScheme.onPrimary,
      modelTextColor: theme.colorScheme.onSurface,
      inputBackgroundColor: theme.colorScheme.surfaceContainerHigh,
      sendButtonColor: theme.colorScheme.primary,
      sendButtonIconColor: theme.colorScheme.onPrimary,
      suggestionBackgroundColor: theme.colorScheme.surfaceContainerLow,
      suggestionTextColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      appBarBackgroundColor: theme.colorScheme.surface,
    );
  }

  /// Background color for user message bubbles.
  final Color? userBubbleColor;

  /// Background color for AI agent / model message bubbles.
  final Color? modelBubbleColor;

  /// Background color for tool call cards.
  final Color? toolBubbleColor;

  /// Background color for system notifications.
  final Color? systemBubbleColor;

  /// Background color for error messages.
  final Color? errorBubbleColor;

  /// Text color for user message bubbles.
  final Color? userTextColor;

  /// Text color for model message bubbles.
  final Color? modelTextColor;

  /// Text style for user messages.
  final TextStyle? userTextStyle;

  /// Text style for model messages.
  final TextStyle? modelTextStyle;

  /// Text style for tool execution text.
  final TextStyle? toolTextStyle;

  /// Text style for author / agent name headers.
  final TextStyle? authorTextStyle;

  /// Text style for timestamps.
  final TextStyle? timestampTextStyle;

  /// Default corner radius for message bubbles.
  final BorderRadius? borderRadius;

  /// Specific corner radius for user bubbles.
  final BorderRadius? userBorderRadius;

  /// Specific corner radius for model bubbles.
  final BorderRadius? modelBorderRadius;

  /// Internal padding for message bubbles.
  final EdgeInsetsGeometry? bubblePadding;

  /// External margin around message bubbles.
  final EdgeInsetsGeometry? bubbleMargin;

  /// Max width of message bubbles relative to screen width (0.0 to 1.0).
  final double maxWidthFactor;

  /// Background color for the text input box.
  final Color? inputBackgroundColor;

  /// Corner radius for the text input container.
  final BorderRadius? inputBorderRadius;

  /// Text style for typed input text.
  final TextStyle? inputTextStyle;

  /// Text style for input placeholder hint.
  final TextStyle? inputHintStyle;

  /// Padding inside the input bar.
  final EdgeInsetsGeometry? inputPadding;

  /// Background color for the send button.
  final Color? sendButtonColor;

  /// Icon color for the send button.
  final Color? sendButtonIconColor;

  /// Custom icon for the send button.
  final IconData? sendButtonIcon;

  /// Background color for suggestion chips.
  final Color? suggestionBackgroundColor;

  /// Text color for suggestion chips.
  final Color? suggestionTextColor;

  /// Corner radius for suggestion chips.
  final BorderRadius? suggestionBorderRadius;

  /// Overall background color for the chat view.
  final Color? backgroundColor;

  /// AppBar background color if shown.
  final Color? appBarBackgroundColor;

  /// Text style for AppBar title.
  final TextStyle? appBarTextStyle;

  /// Whether to display message timestamps.
  final bool showTimestamp;

  /// Whether to display avatars next to messages.
  final bool showAvatars;

  /// Creates a copy of this [AdkChatThemeData] with updated fields.
  AdkChatThemeData copyWith({
    Color? userBubbleColor,
    Color? modelBubbleColor,
    Color? toolBubbleColor,
    Color? systemBubbleColor,
    Color? errorBubbleColor,
    Color? userTextColor,
    Color? modelTextColor,
    TextStyle? userTextStyle,
    TextStyle? modelTextStyle,
    TextStyle? toolTextStyle,
    TextStyle? authorTextStyle,
    TextStyle? timestampTextStyle,
    BorderRadius? borderRadius,
    BorderRadius? userBorderRadius,
    BorderRadius? modelBorderRadius,
    EdgeInsetsGeometry? bubblePadding,
    EdgeInsetsGeometry? bubbleMargin,
    double? maxWidthFactor,
    Color? inputBackgroundColor,
    BorderRadius? inputBorderRadius,
    TextStyle? inputTextStyle,
    TextStyle? inputHintStyle,
    EdgeInsetsGeometry? inputPadding,
    Color? sendButtonColor,
    Color? sendButtonIconColor,
    IconData? sendButtonIcon,
    Color? suggestionBackgroundColor,
    Color? suggestionTextColor,
    BorderRadius? suggestionBorderRadius,
    Color? backgroundColor,
    Color? appBarBackgroundColor,
    TextStyle? appBarTextStyle,
    bool? showTimestamp,
    bool? showAvatars,
  }) {
    return AdkChatThemeData(
      userBubbleColor: userBubbleColor ?? this.userBubbleColor,
      modelBubbleColor: modelBubbleColor ?? this.modelBubbleColor,
      toolBubbleColor: toolBubbleColor ?? this.toolBubbleColor,
      systemBubbleColor: systemBubbleColor ?? this.systemBubbleColor,
      errorBubbleColor: errorBubbleColor ?? this.errorBubbleColor,
      userTextColor: userTextColor ?? this.userTextColor,
      modelTextColor: modelTextColor ?? this.modelTextColor,
      userTextStyle: userTextStyle ?? this.userTextStyle,
      modelTextStyle: modelTextStyle ?? this.modelTextStyle,
      toolTextStyle: toolTextStyle ?? this.toolTextStyle,
      authorTextStyle: authorTextStyle ?? this.authorTextStyle,
      timestampTextStyle: timestampTextStyle ?? this.timestampTextStyle,
      borderRadius: borderRadius ?? this.borderRadius,
      userBorderRadius: userBorderRadius ?? this.userBorderRadius,
      modelBorderRadius: modelBorderRadius ?? this.modelBorderRadius,
      bubblePadding: bubblePadding ?? this.bubblePadding,
      bubbleMargin: bubbleMargin ?? this.bubbleMargin,
      maxWidthFactor: maxWidthFactor ?? this.maxWidthFactor,
      inputBackgroundColor: inputBackgroundColor ?? this.inputBackgroundColor,
      inputBorderRadius: inputBorderRadius ?? this.inputBorderRadius,
      inputTextStyle: inputTextStyle ?? this.inputTextStyle,
      inputHintStyle: inputHintStyle ?? this.inputHintStyle,
      inputPadding: inputPadding ?? this.inputPadding,
      sendButtonColor: sendButtonColor ?? this.sendButtonColor,
      sendButtonIconColor: sendButtonIconColor ?? this.sendButtonIconColor,
      sendButtonIcon: sendButtonIcon ?? this.sendButtonIcon,
      suggestionBackgroundColor: suggestionBackgroundColor ?? this.suggestionBackgroundColor,
      suggestionTextColor: suggestionTextColor ?? this.suggestionTextColor,
      suggestionBorderRadius: suggestionBorderRadius ?? this.suggestionBorderRadius,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      appBarBackgroundColor: appBarBackgroundColor ?? this.appBarBackgroundColor,
      appBarTextStyle: appBarTextStyle ?? this.appBarTextStyle,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showAvatars: showAvatars ?? this.showAvatars,
    );
  }
}

/// An [InheritedWidget] that provides [AdkChatThemeData] down the widget tree.
class AdkTheme extends InheritedWidget {
  /// Creates an [AdkTheme].
  const AdkTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// The [AdkChatThemeData] provided by this widget.
  final AdkChatThemeData data;

  /// Retrieves the closest [AdkChatThemeData] from the widget tree, or derives one from [Theme.of].
  static AdkChatThemeData of(BuildContext context) {
    final AdkTheme? inherited = context.dependOnInheritedWidgetOfExactType<AdkTheme>();
    if (inherited != null) {
      return inherited.data;
    }
    return AdkChatThemeData.fromTheme(Theme.of(context));
  }

  /// Retrieves the closest [AdkChatThemeData], or null if not found.
  static AdkChatThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdkTheme>()?.data;
  }

  @override
  bool updateShouldNotify(AdkTheme oldWidget) => data != oldWidget.data;
}
