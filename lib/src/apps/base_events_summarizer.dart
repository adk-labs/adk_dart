import '../events/event.dart';

abstract class BaseEventsSummarizer {
  Future<Event?> maybeSummarizeEvents({required List<Event> events});
}
