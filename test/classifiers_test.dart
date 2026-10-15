import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeClassifier extends BaseClassifier {
  _FakeClassifier(this.response) : super(model: 'fake-classifier');

  final ClassifierResponse response;

  @override
  Future<ClassifierResponse> classify({
    required Object input,
    required Map<String, ClassifierQuestion> questions,
  }) async {
    return response;
  }
}

void main() {
  group('Classifiers and ClassifierNode', () {
    test('Choice question validates criteria length >= 2', () {
      expect(
        () => Choice(criteria: const {'a': 'A'}),
        throwsArgumentError,
      );
      final valid = Choice(criteria: const {'a': 'Option A', 'b': 'Option B'});
      expect(valid.type, equals('choice'));
      expect(valid.criteria.length, equals(2));
    });

    test('Score question validates criteria length >= 2', () {
      expect(
        () => Score(criteria: const ['poor']),
        throwsArgumentError,
      );
      final valid = Score(criteria: const ['poor', 'good']);
      expect(valid.type, equals('score'));
    });

    test('ClassifierNode validates question and route for Choice', () {
      final question = Choice(criteria: const {'refund': 'Refund', 'support': 'Support'});
      final classifier = _FakeClassifier(
        ClassifierResponse(
          answers: {
            'route': ChoiceAnswer(
              choice: 'refund',
              probabilities: {'refund': 0.9, 'support': 0.1},
              confidence: 0.9,
            ),
          },
        ),
      );

      final node = ClassifierNode(
        name: 'triage',
        classifier: classifier,
        question: question,
      );

      expect(node.routes, equals({'refund', 'support'}));
      expect(
        node.routeFor(
          ChoiceAnswer(
            choice: 'refund',
            probabilities: {'refund': 0.9, 'support': 0.1},
          ),
        ),
        equals('refund'),
      );
    });

    test('ClassifierNode throws when threshold is used with Choice', () {
      final question = Choice(criteria: const {'a': 'A', 'b': 'B'});
      final classifier = _FakeClassifier(ClassifierResponse(answers: {}));

      expect(
        () => ClassifierNode(
          name: 'invalid',
          classifier: classifier,
          question: question,
          threshold: 0.8,
        ),
        throwsArgumentError,
      );
    });

    test('ClassifierNode routes binary questions using threshold', () {
      final question = Binary(instructions: 'Is spam?');
      final classifier = _FakeClassifier(ClassifierResponse(answers: {}));

      final node = ClassifierNode(
        name: 'spam_check',
        classifier: classifier,
        question: question,
        threshold: 0.7,
      );

      expect(node.routes, equals({true, false}));
      expect(
        node.routeFor(BinaryAnswer(probability: 0.8)),
        isTrue,
      );
      expect(
        node.routeFor(BinaryAnswer(probability: 0.5)),
        isFalse,
      );
    });
  });
}
