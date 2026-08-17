import 'package:flutter/material.dart';

/// A session history item model for [AdkSessionDrawer].
class AdkSessionItem {
  /// Creates an [AdkSessionItem].
  const AdkSessionItem({
    required this.id,
    required this.title,
    this.lastActiveTime,
    this.messageCount = 0,
  });

  /// Unique session identifier.
  final String id;

  /// Human-readable title of the conversation.
  final String title;

  /// Timestamp of the last interaction.
  final DateTime? lastActiveTime;

  /// Total message count in this session.
  final int messageCount;
}

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
  final List<AdkSessionItem> sessions;

  /// ID of the currently active session.
  final String activeSessionId;

  /// Callback when a session is selected.
  final ValueChanged<String> onSessionSelected;

  /// Callback when the "New Chat" button is tapped.
  final VoidCallback onNewSession;

  /// Optional callback when a session is deleted.
  final ValueChanged<String>? onDeleteSession;

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
          children: <Widget>[
            headerWidget ??
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
                        tooltip: 'New Conversation',
                        onPressed: onNewSession,
                      ),
                    ],
                  ),
                ),
            const Divider(height: 1.0),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: FilledButton.tonalIcon(
                onPressed: onNewSession,
                icon: const Icon(Icons.add, size: 18.0),
                label: const Text('New Chat'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(42.0),
                ),
              ),
            ),
            Expanded(
              child: sessions.isEmpty
                  ? Center(
                      child: Text(
                        'No previous chats',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (BuildContext context, int index) {
                        final AdkSessionItem session = sessions[index];
                        final bool isSelected = session.id == activeSessionId;

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor:
                              theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                          leading: Icon(
                            isSelected
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                            size: 20.0,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: onDeleteSession != null
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18.0),
                                  tooltip: 'Delete',
                                  onPressed: () => onDeleteSession!(session.id),
                                )
                              : null,
                          onTap: () {
                            onSessionSelected(session.id);
                            Navigator.of(context).maybePop();
                          },
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
