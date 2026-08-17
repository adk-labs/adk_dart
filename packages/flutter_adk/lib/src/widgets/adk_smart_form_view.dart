import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import '../models/adk_chat_message.dart';
import '../theme/adk_theme.dart';
import 'adk_chat_view.dart';

/// Data model representing a single field in an [AdkSmartFormView].
@immutable
class AdkFormField {
  /// Creates an [AdkFormField].
  const AdkFormField({
    required this.key,
    required this.label,
    this.value,
    this.hint,
    this.isRequired = true,
  });

  /// Unique field key (e.g. `user_name`, `booking_date`, `guests_count`).
  final String key;

  /// Human-readable label for this field.
  final String label;

  /// Current extracted value.
  final String? value;

  /// Hint placeholder if unfilled.
  final String? hint;

  /// Whether this field must be filled before submission.
  final bool isRequired;

  /// Whether this field has a non-empty value.
  bool get isFilled => value != null && value!.trim().isNotEmpty;

  /// Copies this [AdkFormField] with optional updated values.
  AdkFormField copyWith({
    String? key,
    String? label,
    String? value,
    String? hint,
    bool? isRequired,
  }) {
    return AdkFormField(
      key: key ?? this.key,
      label: label ?? this.label,
      value: value ?? this.value,
      hint: hint ?? this.hint,
      isRequired: isRequired ?? this.isRequired,
    );
  }
}

/// A turnkey conversational smart form view where an AI agent auto-populates form fields through dialogue.
class AdkSmartFormView extends StatefulWidget {
  /// Creates an [AdkSmartFormView].
  const AdkSmartFormView({
    super.key,
    required this.agent,
    required this.fields,
    required this.onSubmit,
    this.controller,
    this.theme,
    this.formTitle = 'Application Form',
    this.submitButtonLabel = 'Submit Form',
    this.fieldRowBuilder,
    this.formCardBuilder,
    this.submitButtonBuilder,
  });

  /// The agent guiding the user to fill out the form.
  final adk.BaseAgent agent;

  /// Initial list of fields to collect.
  final List<AdkFormField> fields;

  /// Callback when all required fields are filled and user submits.
  final ValueChanged<Map<String, String>> onSubmit;

  /// Optional preconfigured controller.
  final AdkChatController? controller;

  /// Optional theme styling.
  final AdkChatThemeData? theme;

  /// Title for the form summary card.
  final String formTitle;

  /// Label for the submit button.
  final String submitButtonLabel;

  /// Custom builder for an individual field row.
  final Widget Function(BuildContext context, AdkFormField field, VoidCallback onEdit)? fieldRowBuilder;

  /// Custom builder for the entire form fields container.
  final Widget Function(BuildContext context, List<AdkFormField> fields, VoidCallback onSubmit)? formCardBuilder;

  /// Custom builder for the submit button.
  final Widget Function(BuildContext context, bool isReady, VoidCallback onSubmit)? submitButtonBuilder;

  @override
  State<AdkSmartFormView> createState() => _AdkSmartFormViewState();
}

class _AdkSmartFormViewState extends State<AdkSmartFormView> {
  late final AdkChatController _controller;
  late final bool _ownsController;
  late List<AdkFormField> _currentFields;

  @override
  void initState() {
    super.initState();
    _currentFields = List<AdkFormField>.from(widget.fields);
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = AdkChatController(agent: widget.agent);
      _ownsController = true;
    }

    _controller.addListener(_onChatUpdate);
  }

  void _onChatUpdate() {
    // Scan for tool calls or structured updates that match field keys
    for (final AdkChatMessage msg in _controller.messages) {
      if (msg.isTool && msg.toolArgs != null) {
        final Map<String, dynamic> args = msg.toolArgs!;
        setState(() {
          for (int i = 0; i < _currentFields.length; i++) {
            final String k = _currentFields[i].key;
            if (args.containsKey(k) && args[k] != null) {
              _currentFields[i] = _currentFields[i].copyWith(value: args[k].toString());
            }
          }
        });
      }
    }
  }

  bool get _isFormReady => _currentFields.where((AdkFormField f) => f.isRequired).every((AdkFormField f) => f.isFilled);

  void _submit() {
    final Map<String, String> data = <String, String>{};
    for (final AdkFormField f in _currentFields) {
      if (f.value != null) {
        data[f.key] = f.value!;
      }
    }
    widget.onSubmit(data);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChatUpdate);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData flutterTheme = Theme.of(context);
    final AdkChatThemeData adkTheme = widget.theme ?? AdkTheme.of(context);

    return Column(
      children: <Widget>[
        // Form Summary Card
        if (widget.formCardBuilder != null)
          widget.formCardBuilder!(context, _currentFields, _submit)
        else
          _buildDefaultFormCard(flutterTheme),
        // Chat Interface
        Expanded(
          child: AdkChatView(
            controller: _controller,
            theme: adkTheme,
            showAppBar: false,
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultFormCard(ThemeData theme) {
    final int filledCount = _currentFields.where((AdkFormField f) => f.isFilled).length;
    final double progress = _currentFields.isEmpty ? 1.0 : filledCount / _currentFields.length;

    return Container(
      margin: const EdgeInsets.all(12.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.assignment_outlined, size: 20.0, color: theme.colorScheme.primary),
              const SizedBox(width: 8.0),
              Text(
                widget.formTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '$filledCount / ${_currentFields.length} completed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6.0,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: progress >= 1.0 ? Colors.green : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 6.0,
            children: _currentFields.map((AdkFormField field) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: field.isFilled
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      field.isFilled ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 12.0,
                      color: field.isFilled ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      '${field.label}: ',
                      style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      field.value ?? (field.hint ?? 'Pending'),
                      style: TextStyle(
                        fontSize: 11.0,
                        color: field.isFilled ? theme.colorScheme.onSurface : theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (_isFormReady) ...<Widget>[
            const SizedBox(height: 10.0),
            SizedBox(
              width: double.infinity,
              child: widget.submitButtonBuilder != null
                  ? widget.submitButtonBuilder!(context, _isFormReady, _submit)
                  : FilledButton.icon(
                      icon: const Icon(Icons.send_rounded, size: 16.0),
                      label: Text(widget.submitButtonLabel),
                      onPressed: _submit,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
