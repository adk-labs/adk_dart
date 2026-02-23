import '../events/event.dart';
import '../events/event_actions.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';
import 'base_events_summarizer.dart';

class LlmEventSummarizer extends BaseEventsSummarizer {
  LlmEventSummarizer({required BaseLlm llm, String? promptTemplate})
    : _llm = llm,
      _promptTemplate = promptTemplate ?? _defaultPromptTemplate;

  static const String _defaultPromptTemplate =
      'The following is a conversation history between a user and an AI '
      'agent. Please summarize the conversation, focusing on key '
      'information and decisions made, as well as any unresolved '
      'questions or tasks. The summary should be concise and capture the '
      'essence of the interaction.\n\n{conversation_history}';

  final BaseLlm _llm;
  final String _promptTemplate;

  String formatEventsForPrompt(List<Event> events) {
    final List<String> history = <String>[];
    for (final Event event in events) {
      final Content? content = event.content;
      if (content == null) {
        continue;
      }
      for (final Part part in content.parts) {
        final String? text = part.text;
        if (text != null && text.isNotEmpty) {
          history.add('${event.author}: $text');
        }
      }
    }
    return history.join('\n');
  }

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
    await for (final LlmResponse response in _llm.generateContent(
      llmRequest,
      stream: false,
    )) {
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

    return Event(author: 'user', actions: actions, invocationId: Event.newId());
  }
}
