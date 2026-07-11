/// LLM-backed event summarizer implementation.
library;

import '../events/event.dart';
import '../events/event_actions.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';
import 'base_events_summarizer.dart';

/// Summarizes event history into a compaction event using an LLM.
class LlmEventSummarizer extends BaseEventsSummarizer {
  /// Creates an LLM event summarizer.
  LlmEventSummarizer({required BaseLlm llm, String? promptTemplate})
    : _llm = llm,
      _promptTemplate = promptTemplate ?? _defaultPromptTemplate;

  static const String _defaultPromptTemplate =
      'The following is a conversation history between a user and an AI agent.'
      ' It may or may not start from a compacted history. Please identify and'
      ' reiterate the user request, summarize the context so far, focusing on'
      ' key decisions made and information obtained, as well as any unresolved'
      ' questions or tasks. '
      'CRITICAL INSTRUCTIONS: '
      '1. Explicitly identify and state the primary language used by the user '
      'at the top of your summary (e.g., "Conversation Language: English"). '
      '2. If the agent called any tools, accurately list the exact tool names '
      'used to maintain tool grounding. '
      'The rest of the summary should be concise and capture the'
      ' essence of the interaction.\n\n{conversation_history}';

  /// Tool call args and responses can be large (e.g. search results). Cap how
  /// much of each is rendered so compaction does not inflate the very context
  /// it exists to shrink.
  static const int _maxToolContentChars = 2000;

  final BaseLlm _llm;
  final String _promptTemplate;

  /// Formats [events] into prompt text, including thoughts and tool calls.
  ///
  /// Thoughts carry the agent's analysis of tool responses, and tool calls and
  /// responses carry the evidence retrieved so far, so all three are included.
  /// Thoughts emitted by a compaction event are skipped so a prior summary's
  /// reasoning does not leak into the next summary.
  String formatEventsForPrompt(List<Event> events) {
    final List<String> history = <String>[];
    for (final Event event in events) {
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      final bool isCompaction = event.actions.compaction != null;
      for (final Part part in content.parts) {
        final String? text = part.text;
        if (part.thought && text != null && text.isNotEmpty) {
          if (!isCompaction) {
            history.add('${event.author} (thought): $text');
          }
        } else if (text != null && text.isNotEmpty) {
          history.add('${event.author}: $text');
        }
        final FunctionCall? functionCall = part.functionCall;
        if (functionCall != null) {
          final String args = _truncate('${functionCall.args}');
          history.add(
            '${event.author} called tool: ${functionCall.name}($args)',
          );
        }
        final FunctionResponse? functionResponse = part.functionResponse;
        if (functionResponse != null) {
          final String response = _truncate('${functionResponse.response}');
          history.add(
            'Tool response from ${functionResponse.name}: $response',
          );
        }
      }
    }
    return history.join('\n');
  }

  /// Caps [text] at the tool-content limit, marking dropped characters.
  String _truncate(String text) {
    const int limit = _maxToolContentChars;
    if (text.length <= limit) {
      return text;
    }
    return '${text.substring(0, limit)}... '
        '[truncated ${text.length - limit} chars]';
  }

  /// Returns a summary compaction event for [events].
  @override
  Future<Event?> maybeSummarizeEvents({required List<Event> events}) async {
    if (events.isEmpty) {
      return null;
    }

    final String conversationHistory = formatEventsForPrompt(events);
    final String prompt = _promptTemplate.replaceFirst(
      '{conversation_history}',
      conversationHistory,
    );

    final LlmRequest llmRequest = LlmRequest(
      model: _llm.model,
      contents: <Content>[Content.userText(prompt)],
    );

    Content? summaryContent;
    Object? usageMetadata;
    await for (final LlmResponse response in _llm.generateContent(
      llmRequest,
      stream: false,
    )) {
      usageMetadata ??= response.usageMetadata;
      if (response.content != null) {
        summaryContent = response.content!.copyWith();
        break;
      }
    }

    if (summaryContent == null) {
      return null;
    }

    summaryContent = summaryContent.copyWith(role: 'model');

    final EventCompaction compaction = EventCompaction(
      startTimestamp: events.first.timestamp,
      endTimestamp: events.last.timestamp,
      compactedContent: summaryContent,
    );
    final EventActions actions = EventActions(compaction: compaction);

    return Event(
      author: 'user',
      actions: actions,
      invocationId: Event.newId(),
      usageMetadata: usageMetadata,
    );
  }
}
