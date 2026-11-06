/// Base classifier contract for answering typed probability questions.
library;

import 'dart:async';

import '../../features/_feature_registry.dart';
import '../../utils/client_labels_utils.dart';
import 'types.dart';

/// Stateless model that answers typed questions with probability distributions.
///
/// Unlike a `BaseLlm`, a classifier does not generate free-form text, stream,
/// or invoke tools. It accepts an input and a map of [Choice], [Binary], or
/// [Score] questions, and returns a [ClassifierResponse] containing a
/// probability distribution for each question.
///
/// ```dart
/// class FixedBinaryClassifier extends BaseClassifier {
///   FixedBinaryClassifier() : super(model: 'fixed-binary');
///
///   @override
///   Future<ClassifierResponse> classify({
///     required Object input,
///     required Map<String, ClassifierQuestion> questions,
///   }) async {
///     return ClassifierResponse(
///       modelVersion: model,
///       answers: <String, ClassifierAnswer>{
///         for (final String key in questions.keys)
///           key: BinaryAnswer(probability: 0.8),
///       },
///     );
///   }
/// }
/// ```
abstract class BaseClassifier {
  /// Creates a classifier backed by [model].
  ///
  /// Throws a [StateError] when [FeatureName.classifier] is disabled.
  BaseClassifier({required this.model}) {
    if (!isFeatureEnabled(FeatureName.classifier)) {
      throw StateError(
        'Feature ${FeatureName.classifier} (${FeatureName.classifier.value}) is not enabled.',
      );
    }
  }

  /// Names the classifier in the client label of the requests it sends.
  String get clientLabelKind => 'custom';

  /// Provider's model name.
  String model;

  /// Labels requests sent inside [action] as coming from this classifier.
  ///
  /// Keeps the outer label instead when one is already set, such as during an
  /// evaluation run.
  Future<T> runWithClientLabelContext<T>(FutureOr<T> Function() action) async {
    final String label = classifierClientLabel(clientLabelKind);
    Future<T> runner() async => await action();
    try {
      return await clientLabelContext<Future<T>>(label, runner);
    } on ArgumentError {
      return await runner();
    }
  }

  /// Answers every question in [questions] against [input].
  Future<ClassifierResponse> classify({
    required Object input,
    required Map<String, ClassifierQuestion> questions,
  });
}
