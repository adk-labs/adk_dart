import 'package:flutter/material.dart';
import '../models/adk_session_info.dart';

export '../models/adk_session_info.dart';

/// Legacy alias for [AdkSessionInfo].
typedef AdkSessionItem = AdkSessionInfo;

/// A sidebar drawer widget displaying the user's past conversation sessions.
class AdkSessionDrawer extends StatelessWidget {
  /// Creates an [AdkSessionDrawer].
  const AdkSessionDrawer({
    super.key,
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionSelected,
    required this.onNewSession,
    this.onDeleteSession,
    this.title = 'Conversations',
    this.headerWidget,
  });

  /// List of session items to display.
  final List<AdkSessionInfo> sessions;

  /// ID of the currently active session.
  final String activeSessionId;

  /// Callback when a session is selected.
  final ValueChanged<AdkSessionInfo> onSessionSelected;

  /// Callback when the "New Chat" button is tapped.
  final VoidCallback onNewSession;

  /// Optional callback when a session is deleted.
  final ValueChanged<AdkSessionInfo>? onDeleteSession;

  /// Header title.
  final String title;

  /// Optional custom header widget.
  final Widget? headerWidget;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (headerWidget != null)
              headerWidget!
            else
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_comment_outlined),
                      tooltip: 'New Chat',
                      onPressed: onNewSession,
                    ),
                  ],
                ),
              ),
            const Divider(height: 1.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: FilledButton.tonalIcon(
                onPressed: onNewSession,
                icon: const Icon(Icons.add, size: 18.0),
                label: const Text('New Chat'),
              ),
            ),
            Expanded(
              child: sessions.isEmpty
                  ? Center(
                      child: Text(
                        'No previous sessions',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (BuildContext context, int index) {
                        final AdkSessionInfo session = sessions[index];
                        final bool isSelected = session.id == activeSessionId;

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                          leading: Icon(
                            isSelected ? Icons.chat_bubble : Icons.chat_bubble_outline,
                            size: 20.0,
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: session.lastMessagePreview != null && session.lastMessagePreview!.isNotEmpty
                              ? Text(
                                  session.lastMessagePreview!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                )
                              : null,
                          trailing: onDeleteSession != null
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18.0),
                                  tooltip: 'Delete',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => onDeleteSession!(session),
                                )
                              : null,
                          onTap: () => onSessionSelected(session),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
