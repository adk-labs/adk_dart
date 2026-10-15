/// Workflow node that routes execution using a [BaseClassifier].
library;

import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../features/_feature_registry.dart';
import '../../types/content.dart';
import '../../workflow/workflow.dart';
import 'base_classifier.dart';
import 'types.dart';

const String _questionName = 'route';

/// Workflow node that classifies its input and routes to the resulting label.
///
/// A [ClassifierNode] asks [classifier] a single [Choice] or [Binary]
/// [question] about its `nodeInput` and emits the answer as the workflow
/// route: the chosen label for a [Choice] question, or `true` / `false` for a
/// [Binary] question based on [threshold]. Its output is the unchanged
/// `nodeInput`, so downstream nodes receive the original value.
///
/// ```dart
/// final triageNode = ClassifierNode(
///   name: 'triage',
///   classifier: myClassifier,
///   question: Choice(
///     instructions: 'Route this support ticket.',
///     criteria: <String, Object?>{
///       'billing': 'Invoices, charges, or refunds',
///       'technical': 'Bugs or outages',
///     },
///   ),
///   answerKey: 'triage_answer',
/// );
/// ```
class ClassifierNode extends BaseNode {
  /// Creates a [ClassifierNode] that routes on [question] answered by [classifier].
  ///
  /// Throws a [StateError] when [FeatureName.classifier] is disabled, or an
  /// [ArgumentError] when [question] is not a [Choice] or [Binary], when
  /// [threshold] is outside `[0.0, 1.0]`, or when [threshold] is explicitly
  /// provided for a [Choice] question.
  ClassifierNode({
    required super.name,
    required this.classifier,
    required this.question,
    double? threshold,
    this.answerKey,
    super.description,
    super.dependsOn,
    super.rerunOnResume,
    super.waitForOutput,
    super.retryConfig,
    super.timeout,
  }) : threshold = threshold ?? 0.5 {
    if (!isFeatureEnabled(FeatureName.classifier)) {
      throw StateError(
        'Feature ${FeatureName.classifier} (${FeatureName.classifier.value}) is not enabled.',
      );
    }
    if (question is! Choice && question is! Binary) {
      throw ArgumentError.value(
        question,
        'question',
        'ClassifierNode question must be Choice or Binary, not ${question.type}.',
      );
    }
    if (this.threshold.isNaN || this.threshold < 0.0 || this.threshold > 1.0) {
      throw ArgumentError.value(
        this.threshold,
        'threshold',
        'threshold must be between 0.0 and 1.0 inclusive.',
      );
    }
    if (threshold != null && question is Choice) {
      throw ArgumentError(
        'threshold is only applicable to Binary questions, not Choice.',
      );
    }
  }

  /// Classifier that answers [question].
  final BaseClassifier classifier;

  /// Question whose answer determines the outgoing route.
  final ClassifierQuestion question;

  /// Probability threshold at or above which a [Binary] question routes `true`.
  final double threshold;

  /// Optional session state key under which the serialized answer is stored.
  final String? answerKey;

  /// Set of possible routes emitted by this node.
  Set<Object?> get routes {
    final ClassifierQuestion q = question;
    if (q is Choice) {
      return Set<Object?>.unmodifiable(q.criteria.keys);
    }
    return const <Object?>{true, false};
  }

  /// Computes the outgoing route value for [answer].
  ///
  /// Throws a [WorkflowDataError] when [answer] does not match [question] or
  /// chooses an unknown label.
  Object routeFor(ClassifierAnswer answer) {
    final ClassifierQuestion q = question;
    if (q is Choice && answer is ChoiceAnswer) {
      if (!q.criteria.containsKey(answer.choice)) {
        final List<String> sortedRoutes =
            routes.map((Object? r) => '$r').toList()..sort();
        throw WorkflowDataError(
          'Classifier for node "$name" chose "${answer.choice}", '
          'which is not one of its labels: $sortedRoutes.',
        );
      }
      return answer.choice;
    }
    if (q is Binary && answer is BinaryAnswer) {
      return answer.probability >= threshold;
    }
    throw WorkflowDataError(
      'Classifier for node "$name" returned a ${answer.type} answer '
      'to a ${question.type} question.',
    );
  }

  @override
  void validateOutgoingEdges(List<Edge> edges) {
    final Set<Object?> edgeRoutes = <Object?>{};
    bool hasUnroutedEdge = false;
    for (final Edge edge in edges) {
      if (edge.route == null) {
        hasUnroutedEdge = true;
        continue;
      }
      if (edge.route is Iterable && edge.route is! String) {
        edgeRoutes.addAll(edge.route as Iterable<Object?>);
      } else {
        edgeRoutes.add(edge.route);
      }
    }
    if (edgeRoutes.isEmpty) {
      return;
    }

    final Set<Object?> knownRoutes = routes;
    final List<String> unknown = edgeRoutes
        .where((Object? r) => !knownRoutes.contains(r) && r != DEFAULT_ROUTE)
        .map((Object? r) => '$r')
        .toList()
      ..sort();
    if (unknown.isNotEmpty) {
      final List<String> sortedKnown =
          knownRoutes.map((Object? r) => '$r').toList()..sort();
      throw GraphValidationError(
        'Graph validation failed. ClassifierNode "$name" has edges '
        'for routes it never emits: $unknown. Its routes are $sortedKnown.',
      );
    }

    final List<String> missing = knownRoutes
        .where((Object? r) => !edgeRoutes.contains(r))
        .map((Object? r) => '$r')
        .toList()
      ..sort();
    if (missing.isNotEmpty &&
        !edgeRoutes.contains(DEFAULT_ROUTE) &&
        !hasUnroutedEdge) {
      throw GraphValidationError(
        'Graph validation failed. ClassifierNode "$name" has no edge '
        'for routes $missing, so the branch would end when the '
        'classifier picks one. Add an edge for each, or a DEFAULT_ROUTE '
        'or unrouted edge.',
      );
    }
  }

  /// Executes classification on [nodeInput] and returns the routing [Event].
  Future<Event> execute(WorkflowContext context, Object? nodeInput) async {
    if (nodeInput == null) {
      throw WorkflowDataError(
        "ClassifierNode '$name' requires a non-None input.",
      );
    }
    Object classifierInput = nodeInput;
    if (nodeInput is! Content &&
        nodeInput is! String &&
        nodeInput is! num &&
        nodeInput is! bool &&
        nodeInput is! Map &&
        nodeInput is! List) {
      try {
        final Object? json = (nodeInput as dynamic).toJson();
        if (json != null) {
          classifierInput = json;
        }
      } catch (_) {
        // Keep original nodeInput when it does not expose toJson().
      }
    }
    final ClassifierResponse response = await classifier.classify(
      input: classifierInput,
      questions: <String, ClassifierQuestion>{_questionName: question},
    );
    final ClassifierAnswer? answer = response.answers[_questionName];
    if (answer == null) {
      throw WorkflowDataError(
        'Classifier for node "$name" returned no answer.',
      );
    }
    final Object route = routeFor(answer);
    final Map<String, Object?> stateUpdates = <String, Object?>{};
    if (answerKey != null) {
      final Map<String, Object?> serialized = answer.toJson();
      context.state[answerKey!] = serialized;
      stateUpdates[answerKey!] = serialized;
    }
    return Event(
      invocationId: context.invocationContext?.invocationId ?? '',
      author: name,
      output: nodeInput,
      actions: EventActions(route: route, stateDelta: stateUpdates),
    );
  }

  @override
  Future<Event> run(WorkflowContext context, Object? nodeInput) {
    return execute(context, nodeInput);
  }
}
