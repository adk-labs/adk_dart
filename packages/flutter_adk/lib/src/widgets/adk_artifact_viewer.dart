import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Data model representing an artifact generated or manipulated during an ADK session.
@immutable
class AdkArtifactItem {
  /// Creates an [AdkArtifactItem].
  const AdkArtifactItem({
    required this.name,
    this.content,
    this.mimeType,
    this.version,
    this.sizeBytes,
    this.metadata = const <String, dynamic>{},
  });

  /// The unique name / filename of the artifact (e.g. `report.md`, `chart.json`).
  final String name;

  /// String content of the artifact if text-based.
  final String? content;

  /// MIME type of the artifact (e.g. `text/markdown`, `application/json`).
  final String? mimeType;

  /// Version string or revision number.
  final String? version;

  /// Size of the artifact in bytes.
  final int? sizeBytes;

  /// Custom metadata map.
  final Map<String, dynamic> metadata;

  /// Guesses whether the artifact is code or structured data based on name.
  bool get isCodeOrJson {
    final lower = name.toLowerCase();
    return lower.endsWith('.dart') ||
        lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.py') ||
        lower.endsWith('.html');
  }

  /// Guesses whether the artifact is markdown.
  bool get isMarkdown => name.toLowerCase().endsWith('.md');
}

/// A compact card widget representing a generated artifact with quick actions.
class AdkArtifactCard extends StatelessWidget {
  /// Creates an [AdkArtifactCard].
  const AdkArtifactCard({
    super.key,
    required this.artifact,
    this.onTap,
    this.onDownload,
  });

  /// The artifact represented by this card.
  final AdkArtifactItem artifact;

  /// Callback when user taps the card to preview or view the artifact.
  final VoidCallback? onTap;

  /// Optional callback to download/export the artifact.
  final VoidCallback? onDownload;

  IconData _getIcon() {
    final lower = artifact.name.toLowerCase();
    if (lower.endsWith('.md')) return Icons.description_outlined;
    if (lower.endsWith('.json') || lower.endsWith('.dart') || lower.endsWith('.py')) {
      return Icons.code_rounded;
    }
    if (lower.endsWith('.csv') || lower.endsWith('.xlsx')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(10.0),
        onTap: onTap ??
            () {
              if (artifact.content != null) {
                showDialog<void>(
                  context: context,
                  builder: (BuildContext ctx) => AdkArtifactViewer(artifact: artifact),
                );
              }
            },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Icon(
                  _getIcon(),
                  size: 20.0,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      artifact.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: <Widget>[
                        if (artifact.version != null)
                          Text(
                            'v${artifact.version} • ',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (artifact.sizeBytes != null)
                          Text(
                            _formatSize(artifact.sizeBytes),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDownload != null)
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 18.0),
                  onPressed: onDownload,
                  tooltip: 'Download',
                )
              else
                const Icon(Icons.chevron_right, size: 18.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full dialog or container viewer for inspecting artifact content, with copy and preview features.
class AdkArtifactViewer extends StatefulWidget {
  /// Creates an [AdkArtifactViewer].
  const AdkArtifactViewer({
    super.key,
    required this.artifact,
    this.onSave,
  });

  /// The artifact to view.
  final AdkArtifactItem artifact;

  /// Optional callback to save/export.
  final VoidCallback? onSave;

  @override
  State<AdkArtifactViewer> createState() => _AdkArtifactViewerState();
}

class _AdkArtifactViewerState extends State<AdkArtifactViewer> {
  bool _copied = false;

  void _copyContent() async {
    final String content = widget.artifact.content ?? '';
    if (mounted) setState(() => _copied = true);
    await Clipboard.setData(ClipboardData(text: content));
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String content = widget.artifact.content ?? 'No content available.';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700.0,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // App Bar / Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: <Widget>[
                  Icon(Icons.article_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.artifact.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.artifact.mimeType != null)
                          Text(
                            widget.artifact.mimeType!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _copied ? Icons.check : Icons.copy_rounded,
                      color: _copied ? Colors.green : null,
                      size: 20.0,
                    ),
                    tooltip: 'Copy to Clipboard',
                    onPressed: _copyContent,
                  ),
                  if (widget.onSave != null)
                    IconButton(
                      icon: const Icon(Icons.save_alt_rounded, size: 20.0),
                      tooltip: 'Save Artifact',
                      onPressed: widget.onSave,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20.0),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1.0),

            // Content Area
            Expanded(
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: widget.artifact.isCodeOrJson ? 'monospace' : null,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
