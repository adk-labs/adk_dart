import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

/// A developer inspector widget displaying all tools registered to an agent,
/// their descriptions, and their parameter schemas.
class AdkToolInspectorView extends StatelessWidget {
  /// Creates an [AdkToolInspectorView].
  const AdkToolInspectorView({
    super.key,
    required this.tools,
    this.title = 'Registered Tools',
  });

  /// The list of tools to inspect.
  final List<Object> tools;

  /// Header title.
  final String title;

  String _formatSchema(dynamic schema) {
    if (schema == null) return 'No parameters';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(schema);
    } catch (_) {
      return schema.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (tools.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.build_circle_outlined,
                size: 40.0,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8.0),
              Text(
                'No tools registered to this agent.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12.0),
      itemCount: tools.length,
      itemBuilder: (BuildContext context, int index) {
        final Object tool = tools[index];
        String name = 'Tool #${index + 1}';
        String description = '';
        dynamic parameters;

        if (tool is adk.BaseTool) {
          name = tool.name;
          description = tool.description;
          final decl = tool.getDeclaration();
          parameters = decl?.parameters;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ExpansionTile(
            leading: Icon(
              Icons.build_rounded,
              color: theme.colorScheme.primary,
              size: 20.0,
            ),
            title: Text(
              name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: description.isNotEmpty
                ? Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  )
                : null,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Parameter Schema:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: SelectableText(
                        _formatSchema(parameters),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
