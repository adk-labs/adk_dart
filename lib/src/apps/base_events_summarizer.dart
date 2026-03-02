/// Event summarization abstraction used by app compaction.
library;

import '../events/event.dart';

/// Base interface for event summarizers.
abstract class BaseEventsSummarizer {
  /// Optionally summarizes [events], returning `null` when unchanged.
  Future<Event?> maybeSummarizeEvents({required List<Event> events});
}
