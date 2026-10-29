import 'package:flutter/material.dart';

/// Reusable visual style configuration for ADK cards, badges, banners, and meters.
@immutable
class AdkCardStyle {
  /// Creates an [AdkCardStyle].
  const AdkCardStyle({
    this.backgroundColor,
    this.headerBackgroundColor,
    this.borderColor,
    this.accentColor,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.margin,
    this.elevation,
    this.decoration,
    this.titleStyle,
    this.subtitleStyle,
    this.bodyStyle,
    this.codeStyle,
    this.maxBodyHeight,
  });

  /// Container background color.
  final Color? backgroundColor;

  /// Optional header row background color.
  final Color? headerBackgroundColor;

  /// Border stroke color.
  final Color? borderColor;

  /// Primary accent color for icons, indicators, and badges.
  final Color? accentColor;

  /// Default foreground text color.
  final Color? textColor;

  /// Corner radius of the card or badge container.
  final BorderRadius? borderRadius;

  /// Internal content padding.
  final EdgeInsetsGeometry? padding;

  /// External margin around the card or badge.
  final EdgeInsetsGeometry? margin;

  /// Optional Material elevation when rendered inside a [Card].
  final double? elevation;

  /// Full [BoxDecoration] override for the container.
  final BoxDecoration? decoration;

  /// Text style for card titles or headers.
  final TextStyle? titleStyle;

  /// Text style for secondary labels, chips, or subtitles.
  final TextStyle? subtitleStyle;

  /// Text style for body text.
  final TextStyle? bodyStyle;

  /// Monospace text style for code, diff lines, or terminal output.
  final TextStyle? codeStyle;

  /// Maximum scrollable height for expandable card bodies.
  final double? maxBodyHeight;

  /// Creates a copy of this [AdkCardStyle] with updated properties.
  AdkCardStyle copyWith({
    Color? backgroundColor,
    Color? headerBackgroundColor,
    Color? borderColor,
    Color? accentColor,
    Color? textColor,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? elevation,
    BoxDecoration? decoration,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
    TextStyle? bodyStyle,
    TextStyle? codeStyle,
    double? maxBodyHeight,
  }) {
    return AdkCardStyle(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      headerBackgroundColor:
          headerBackgroundColor ?? this.headerBackgroundColor,
      borderColor: borderColor ?? this.borderColor,
      accentColor: accentColor ?? this.accentColor,
      textColor: textColor ?? this.textColor,
      borderRadius: borderRadius ?? this.borderRadius,
      padding: padding ?? this.padding,
      margin: margin ?? this.margin,
      elevation: elevation ?? this.elevation,
      decoration: decoration ?? this.decoration,
      titleStyle: titleStyle ?? this.titleStyle,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      bodyStyle: bodyStyle ?? this.bodyStyle,
      codeStyle: codeStyle ?? this.codeStyle,
      maxBodyHeight: maxBodyHeight ?? this.maxBodyHeight,
    );
  }

  /// Merges [other] on top of this [AdkCardStyle].
  AdkCardStyle merge(AdkCardStyle? other) {
    if (other == null) return this;
    return copyWith(
      backgroundColor: other.backgroundColor,
      headerBackgroundColor: other.headerBackgroundColor,
      borderColor: other.borderColor,
      accentColor: other.accentColor,
      textColor: other.textColor,
      borderRadius: other.borderRadius,
      padding: other.padding,
      margin: other.margin,
      elevation: other.elevation,
      decoration: other.decoration,
      titleStyle: other.titleStyle,
      subtitleStyle: other.subtitleStyle,
      bodyStyle: other.bodyStyle,
      codeStyle: other.codeStyle,
      maxBodyHeight: other.maxBodyHeight,
    );
  }
}

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
    this.cardStyle,
    this.terminalCardStyle,
    this.usageBadgeStyle,
    this.compactionCardStyle,
    this.contextMeterStyle,
  });

  /// Derives default theme properties from the current Flutter [ThemeData].
  factory AdkChatThemeData.fromTheme(ThemeData theme) {
    return AdkChatThemeData(
      userBubbleColor: theme.colorScheme.primary,
      modelBubbleColor: theme.colorScheme.surfaceContainerHighest,
      toolBubbleColor: theme.colorScheme.surfaceContainerLow,
      systemBubbleColor:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      errorBubbleColor:
          theme.colorScheme.errorContainer.withValues(alpha: 0.7),
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

  /// Default style applied to tool, file, skill, web, computer, and evaluation cards.
  final AdkCardStyle? cardStyle;

  /// Default style applied to shell command and code execution terminal cards.
  final AdkCardStyle? terminalCardStyle;

  /// Default style applied to `AdkTokenUsageBadge` and `AdkUsageMonitorCard`.
  final AdkCardStyle? usageBadgeStyle;

  /// Default style applied to `AdkCompactionSummaryCard`.
  final AdkCardStyle? compactionCardStyle;

  /// Default style applied to `AdkContextWindowMeter`.
  final AdkCardStyle? contextMeterStyle;

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
    AdkCardStyle? cardStyle,
    AdkCardStyle? terminalCardStyle,
    AdkCardStyle? usageBadgeStyle,
    AdkCardStyle? compactionCardStyle,
    AdkCardStyle? contextMeterStyle,
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
      suggestionBackgroundColor:
          suggestionBackgroundColor ?? this.suggestionBackgroundColor,
      suggestionTextColor: suggestionTextColor ?? this.suggestionTextColor,
      suggestionBorderRadius:
          suggestionBorderRadius ?? this.suggestionBorderRadius,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      appBarBackgroundColor:
          appBarBackgroundColor ?? this.appBarBackgroundColor,
      appBarTextStyle: appBarTextStyle ?? this.appBarTextStyle,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showAvatars: showAvatars ?? this.showAvatars,
      cardStyle: cardStyle ?? this.cardStyle,
      terminalCardStyle: terminalCardStyle ?? this.terminalCardStyle,
      usageBadgeStyle: usageBadgeStyle ?? this.usageBadgeStyle,
      compactionCardStyle: compactionCardStyle ?? this.compactionCardStyle,
      contextMeterStyle: contextMeterStyle ?? this.contextMeterStyle,
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

  /// The active [AdkChatThemeData] provided to descendants.
  final AdkChatThemeData data;

  /// Retrieves the closest [AdkChatThemeData] from the widget tree, or `null` if none is found.
  static AdkChatThemeData? maybeOf(BuildContext context) {
    final AdkTheme? inherited =
        context.dependOnInheritedWidgetOfExactType<AdkTheme>();
    return inherited?.data;
  }

  /// Retrieves the closest [AdkChatThemeData] from the widget tree, or derives
  /// a default theme from [Theme.of].
  static AdkChatThemeData of(BuildContext context) {
    return maybeOf(context) ?? AdkChatThemeData.fromTheme(Theme.of(context));
  }

  @override
  bool updateShouldNotify(AdkTheme oldWidget) => data != oldWidget.data;
}
