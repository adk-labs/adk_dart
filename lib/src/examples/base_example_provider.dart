/// Base abstractions for query-driven few-shot example providers.
library;

import 'example.dart';

/// Base class for providers that return examples for a query.
abstract class BaseExampleProvider {
  /// Returns examples relevant to [query].
  List<Example> getExamples(String query);
}
