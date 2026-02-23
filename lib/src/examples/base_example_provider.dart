import 'example.dart';

/// Base class for providers that return examples for a query.
abstract class BaseExampleProvider {
  List<Example> getExamples(String query);
}
