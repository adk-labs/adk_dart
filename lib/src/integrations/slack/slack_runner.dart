/// Slack integration surface for running ADK agents in Slack conversations.
library;

import '../../events/event.dart';
import '../../runners/runner.dart';
import '../../types/content.dart';

/// Callback used to respond into a Slack thread.
typedef SlackSay =
    Future<Map<String, Object?>> Function({
      required String text,
      String? threadTs,
    });

/// Handler invoked for one Slack event.
typedef SlackEventHandler =
    Future<void> Function(Map<String, Object?> event, SlackSay say);

/// Minimal Slack API surface needed by [SlackRunner].
abstract class SlackApiClient {
  /// Updates a previously sent message.
  Future<void> chatUpdate({
    required String channel,
    required String ts,
    required String text,
  });

  /// Deletes a previously sent message.
  Future<void> chatDelete({required String channel, required String ts});
}

/// Minimal Slack app surface needed by [SlackRunner].
abstract class SlackAppAdapter {
  /// Slack Web API client.
  SlackApiClient get client;

  /// Registers one handler for a Slack event name.
  void onEvent(String eventName, SlackEventHandler handler);
}

/// Socket mode handler abstraction used by [SlackRunner.start].
abstract class SlackSocketModeHandler {
  /// Starts the socket mode event loop.
  Future<void> start();
}

/// Factory for creating socket mode handlers.
typedef SlackSocketModeHandlerFactory =
    SlackSocketModeHandler Function(SlackAppAdapter app, String appToken);

/// Runner that bridges Slack events into an ADK [Runner].
class SlackRunner {
  /// Creates a Slack runner bound to [runner] and [slackApp].
  SlackRunner(this.runner, this.slackApp, {this.socketModeHandlerFactory}) {
    _setupHandlers();
  }

  /// ADK runner used to execute the root agent.
  final Runner runner;

  /// Slack app adapter used to register event handlers.
  final SlackAppAdapter slackApp;

  /// Optional factory used to start Slack Socket Mode.
  final SlackSocketModeHandlerFactory? socketModeHandlerFactory;

  void _setupHandlers() {
    slackApp.onEvent('app_mention', (Map<String, Object?> event, SlackSay say) {
      return handleMessage(event, say);
    });
    slackApp.onEvent('message', (
      Map<String, Object?> event,
      SlackSay say,
    ) async {
      if (!shouldHandleMessageEvent(event)) {
        return;
      }
      await handleMessage(event, say);
    });
  }

  /// Whether [event] should be handled as an incoming user message.
  static bool shouldHandleMessageEvent(Map<String, Object?> event) {
    if (event['bot_id'] != null || event['bot_profile'] != null) {
      return false;
    }
    final bool isDirectMessage = '${event['channel_type'] ?? ''}' == 'im';
    final bool inThread = event['thread_ts'] != null;
    return isDirectMessage || inThread;
  }

  /// Handles one Slack message or app mention event.
  Future<void> handleMessage(Map<String, Object?> event, SlackSay say) async {
    final String text = '${event['text'] ?? ''}'.trim();
    final String userId = '${event['user'] ?? ''}'.trim();
    final String channelId = '${event['channel'] ?? ''}'.trim();
    final String threadTs = '${event['thread_ts'] ?? event['ts'] ?? ''}'.trim();

    if (text.isEmpty || userId.isEmpty || channelId.isEmpty) {
      return;
    }

    final String sessionId = threadTs.isEmpty
        ? channelId
        : '$channelId-$threadTs';
    String? thinkingTs;
    try {
      final Map<String, Object?> thinkingResponse = await say(
        text: '_Thinking..._',
        threadTs: threadTs.isEmpty ? null : threadTs,
      );
      final Object? responseTs = thinkingResponse['ts'];
      if (responseTs is String && responseTs.isNotEmpty) {
        thinkingTs = responseTs;
      }

      await for (final Event event in runner.runAsync(
        userId: userId,
        sessionId: sessionId,
        newMessage: Content.userText(text),
      )) {
        final Content? content = event.content;
        if (content == null || content.parts.isEmpty) {
          continue;
        }
        for (final Part part in content.parts) {
          final String messageText = (part.text ?? '').trim();
          if (messageText.isEmpty) {
            continue;
          }
          if (thinkingTs != null) {
            await slackApp.client.chatUpdate(
              channel: channelId,
              ts: thinkingTs,
              text: messageText,
            );
            thinkingTs = null;
          } else {
            await say(
              text: messageText,
              threadTs: threadTs.isEmpty ? null : threadTs,
            );
          }
        }
      }

      if (thinkingTs != null) {
        await slackApp.client.chatDelete(channel: channelId, ts: thinkingTs);
      }
    } catch (error) {
      final String errorMessage = 'Sorry, I encountered an error: $error';
      if (thinkingTs != null) {
        await slackApp.client.chatUpdate(
          channel: channelId,
          ts: thinkingTs,
          text: errorMessage,
        );
      } else {
        await say(
          text: errorMessage,
          threadTs: threadTs.isEmpty ? null : threadTs,
        );
      }
    }
  }

  /// Starts Slack Socket Mode using [appToken].
  Future<void> start(String appToken) async {
    final SlackSocketModeHandlerFactory? factory = socketModeHandlerFactory;
    if (factory == null) {
      throw UnsupportedError(
        'Slack socket mode is not configured. Provide '
        '`socketModeHandlerFactory` when creating SlackRunner.',
      );
    }
    await factory(slackApp, appToken).start();
  }
}
