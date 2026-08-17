import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget for displaying structured output data (JSON / Map / List) with
/// formatted syntax styling, copy-to-clipboard, and key-value inspectability.
class AdkStructuredDataView extends StatelessWidget {
  /// Creates an [AdkStructuredDataView].
  const AdkStructuredDataView({
    super.key,
    required this.data,
    this.title = 'Structured Output',
    this.showCard = true,
    this.showCopyButton = true,
  });

  /// The structured payload. Can be a [Map], [List], or a raw JSON string.
  final dynamic data;

  /// Header title.
  final String title;

  /// Whether to enclose within a styled Material Card.
  final bool showCard;

  /// Whether to display a copy button.
  final bool showCopyButton;

  String _formatJson() {
    if (data == null) return 'null';
    if (data is String) {
      try {
        final decoded = jsonDecode(data as String);
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(decoded);
      } catch (_) {
        return data as String;
      }
    }
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String formattedText = _formatJson();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.data_object_rounded,
                    size: 18.0,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (showCopyButton)
                IconButton(
                  icon: const Icon(Icons.copy, size: 16.0),
                  tooltip: 'Copy JSON',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: formattedText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied structured JSON to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1.0),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: showCard
                ? const BorderRadius.vertical(bottom: Radius.circular(12.0))
                : BorderRadius.circular(8.0),
          ),
          child: SelectableText(
            formattedText,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 12.0,
              height: 1.4,
            ),
          ),
        ),
      ],
    );

    if (!showCard) {
      return content;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: content,
    );
  }
}
