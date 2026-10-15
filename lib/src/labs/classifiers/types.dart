/// Question, answer, and response models shared by ADK classifiers.
library;

/// Base class for typed questions answered by a classifier.
sealed class ClassifierQuestion {
  /// Creates a classifier question with optional [instructions].
  const ClassifierQuestion({this.instructions});

  /// Discriminator identifying the question kind (`choice`, `binary`, `score`).
  String get type;

  /// Optional instructions describing what to decide or rate.
  final String? instructions;

  /// Serializes this question to a JSON-compatible map.
  Map<String, Object?> toJson();

  /// Deserializes a [ClassifierQuestion] from a JSON map using its `type`.
  factory ClassifierQuestion.fromJson(Map<String, Object?> json) {
    final Object? rawType = json['type'];
    switch (rawType) {
      case 'choice':
        return Choice.fromJson(json);
      case 'binary':
        return Binary.fromJson(json);
      case 'score':
        return Score.fromJson(json);
      default:
        throw ArgumentError.value(
          rawType,
          'type',
          'Unsupported classifier question type.',
        );
    }
  }
}

/// Alias matching upstream Python's `Question` type alias.
typedef Question = ClassifierQuestion;

/// Question that asks a classifier to pick one of N labels.
final class Choice extends ClassifierQuestion {
  /// Creates a [Choice] question with at least two [criteria] labels.
  ///
  /// Throws an [ArgumentError] when [criteria] has fewer than 2 entries.
  Choice({super.instructions, required Map<String, Object?> criteria})
    : criteria = Map<String, Object?>.unmodifiable(criteria) {
    if (this.criteria.length < 2) {
      throw ArgumentError.value(
        criteria,
        'criteria',
        'Choice criteria must contain at least 2 labels.',
      );
    }
  }

  /// Deserializes a [Choice] question from [json].
  factory Choice.fromJson(Map<String, Object?> json) {
    final Object? rawCriteria = json['criteria'];
    if (rawCriteria is! Map) {
      throw ArgumentError.value(
        rawCriteria,
        'criteria',
        'Choice criteria must be a Map.',
      );
    }
    return Choice(
      instructions: json['instructions'] as String?,
      criteria: <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in rawCriteria.entries)
          '${entry.key}': entry.value,
      },
    );
  }

  @override
  String get type => 'choice';

  /// Maps each candidate label to an optional description of when it applies.
  final Map<String, Object?> criteria;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      if (instructions != null) 'instructions': instructions,
      'criteria': Map<String, Object?>.from(criteria),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Choice &&
        other.instructions == instructions &&
        _mapEquals(other.criteria, criteria);
  }

  @override
  int get hashCode => Object.hash(type, instructions, _mapHash(criteria));
}

/// Question that asks for the calibrated probability that a statement is true.
final class Binary extends ClassifierQuestion {
  /// Creates a [Binary] yes/no question.
  const Binary({super.instructions, this.criteria});

  /// Deserializes a [Binary] question from [json].
  factory Binary.fromJson(Map<String, Object?> json) {
    return Binary(
      instructions: json['instructions'] as String?,
      criteria: json['criteria'],
    );
  }

  @override
  String get type => 'binary';

  /// Optional description of what counts as `true`.
  final Object? criteria;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      if (instructions != null) 'instructions': instructions,
      if (criteria != null) 'criteria': criteria,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Binary &&
        other.instructions == instructions &&
        _deepEquals(other.criteria, criteria);
  }

  @override
  int get hashCode => Object.hash(type, instructions, _deepHash(criteria));
}

/// Question that places the input on an ordered rubric starting at level 0.
final class Score extends ClassifierQuestion {
  /// Creates a [Score] question with at least two ordered [criteria] levels.
  ///
  /// Throws an [ArgumentError] when [criteria] has fewer than 2 entries.
  Score({super.instructions, required List<Object?> criteria})
    : criteria = List<Object?>.unmodifiable(criteria) {
    if (this.criteria.length < 2) {
      throw ArgumentError.value(
        criteria,
        'criteria',
        'Score criteria must contain at least 2 levels.',
      );
    }
  }

  /// Deserializes a [Score] question from [json].
  factory Score.fromJson(Map<String, Object?> json) {
    final Object? rawCriteria = json['criteria'];
    if (rawCriteria is! List) {
      throw ArgumentError.value(
        rawCriteria,
        'criteria',
        'Score criteria must be a List.',
      );
    }
    return Score(
      instructions: json['instructions'] as String?,
      criteria: List<Object?>.from(rawCriteria),
    );
  }

  @override
  String get type => 'score';

  /// One description per rubric level, starting at level 0.
  final List<Object?> criteria;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      if (instructions != null) 'instructions': instructions,
      'criteria': List<Object?>.from(criteria),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Score &&
        other.instructions == instructions &&
        _listEquals(other.criteria, criteria);
  }

  @override
  int get hashCode => Object.hash(type, instructions, _listHash(criteria));
}

/// Base class for typed answers returned by a classifier.
sealed class ClassifierAnswer {
  /// Creates a classifier answer with optional provider [confidence].
  ///
  /// Throws an [ArgumentError] if [confidence] is outside `[0.0, 1.0]`.
  ClassifierAnswer({this.confidence}) {
    if (confidence != null) {
      _validateProbability(confidence!, 'confidence');
    }
  }

  /// Discriminator identifying the answer kind (`choice`, `binary`, `score`).
  String get type;

  /// Provider's confidence in the answer, in `[0.0, 1.0]`, when reported.
  final double? confidence;

  /// Serializes this answer to a JSON-compatible map.
  Map<String, Object?> toJson();

  /// Deserializes a [ClassifierAnswer] from a JSON map using its `type`.
  factory ClassifierAnswer.fromJson(Map<String, Object?> json) {
    final Object? rawType = json['type'];
    switch (rawType) {
      case 'choice':
        return ChoiceAnswer.fromJson(json);
      case 'binary':
        return BinaryAnswer.fromJson(json);
      case 'score':
        return ScoreAnswer.fromJson(json);
      default:
        throw ArgumentError.value(
          rawType,
          'type',
          'Unsupported classifier answer type.',
        );
    }
  }
}

/// Alias matching upstream Python's `Answer` type alias.
typedef Answer = ClassifierAnswer;

/// Answer to a [Choice] question.
final class ChoiceAnswer extends ClassifierAnswer {
  /// Creates a [ChoiceAnswer] with the winning [choice] and label [probabilities].
  ///
  /// Throws an [ArgumentError] if any probability or [confidence] is outside
  /// `[0.0, 1.0]`.
  ChoiceAnswer({
    required this.choice,
    required Map<String, double> probabilities,
    super.confidence,
  }) : probabilities = Map<String, double>.unmodifiable(probabilities) {
    for (final MapEntry<String, double> entry in this.probabilities.entries) {
      _validateProbability(entry.value, 'probabilities[${entry.key}]');
    }
  }

  /// Deserializes a [ChoiceAnswer] from [json].
  factory ChoiceAnswer.fromJson(Map<String, Object?> json) {
    final Object? rawChoice = json['choice'];
    final Object? rawProbabilities = json['probabilities'];
    if (rawChoice is! String) {
      throw ArgumentError.value(rawChoice, 'choice', 'choice must be a String.');
    }
    if (rawProbabilities is! Map) {
      throw ArgumentError.value(
        rawProbabilities,
        'probabilities',
        'probabilities must be a Map.',
      );
    }
    return ChoiceAnswer(
      choice: rawChoice,
      probabilities: <String, double>{
        for (final MapEntry<Object?, Object?> entry in rawProbabilities.entries)
          '${entry.key}': _toDouble(entry.value, 'probabilities[${entry.key}]'),
      },
      confidence: json['confidence'] == null
          ? null
          : _toDouble(json['confidence'], 'confidence'),
    );
  }

  @override
  String get type => 'choice';

  /// The most likely label.
  final String choice;

  /// Probability assigned to each candidate label.
  final Map<String, double> probabilities;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      'choice': choice,
      'probabilities': Map<String, double>.from(probabilities),
      'confidence': confidence,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ChoiceAnswer &&
        other.choice == choice &&
        other.confidence == confidence &&
        _mapEquals(other.probabilities, probabilities);
  }

  @override
  int get hashCode =>
      Object.hash(type, choice, confidence, _mapHash(probabilities));
}

/// Answer to a [Binary] question.
final class BinaryAnswer extends ClassifierAnswer {
  /// Creates a [BinaryAnswer] with calibrated [probability].
  ///
  /// Throws an [ArgumentError] if [probability] or [confidence] is outside
  /// `[0.0, 1.0]`.
  BinaryAnswer({required this.probability, super.confidence}) {
    _validateProbability(probability, 'probability');
  }

  /// Deserializes a [BinaryAnswer] from [json].
  factory BinaryAnswer.fromJson(Map<String, Object?> json) {
    return BinaryAnswer(
      probability: _toDouble(json['probability'], 'probability'),
      confidence: json['confidence'] == null
          ? null
          : _toDouble(json['confidence'], 'confidence'),
    );
  }

  @override
  String get type => 'binary';

  /// Calibrated probability that the statement is `true`.
  final double probability;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      'probability': probability,
      'confidence': confidence,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BinaryAnswer &&
        other.probability == probability &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(type, probability, confidence);
}

/// Answer to a [Score] question.
final class ScoreAnswer extends ClassifierAnswer {
  /// Creates a [ScoreAnswer] with expected [score] and level [probabilities].
  ///
  /// Throws an [ArgumentError] if any probability or [confidence] is outside
  /// `[0.0, 1.0]`.
  ScoreAnswer({
    required this.score,
    required Map<int, double> probabilities,
    super.confidence,
  }) : probabilities = Map<int, double>.unmodifiable(probabilities) {
    for (final MapEntry<int, double> entry in this.probabilities.entries) {
      _validateProbability(entry.value, 'probabilities[${entry.key}]');
    }
  }

  /// Deserializes a [ScoreAnswer] from [json].
  factory ScoreAnswer.fromJson(Map<String, Object?> json) {
    final Object? rawProbabilities = json['probabilities'];
    if (rawProbabilities is! Map) {
      throw ArgumentError.value(
        rawProbabilities,
        'probabilities',
        'probabilities must be a Map.',
      );
    }
    return ScoreAnswer(
      score: _toDouble(json['score'], 'score'),
      probabilities: <int, double>{
        for (final MapEntry<Object?, Object?> entry in rawProbabilities.entries)
          _toInt(entry.key, 'probabilities key'): _toDouble(
            entry.value,
            'probabilities[${entry.key}]',
          ),
      },
      confidence: json['confidence'] == null
          ? null
          : _toDouble(json['confidence'], 'confidence'),
    );
  }

  @override
  String get type => 'score';

  /// Expected rubric level weighted by [probabilities].
  final double score;

  /// Probability assigned to each rubric level.
  final Map<int, double> probabilities;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      'score': score,
      'probabilities': <String, double>{
        for (final MapEntry<int, double> entry in probabilities.entries)
          '${entry.key}': entry.value,
      },
      'confidence': confidence,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ScoreAnswer &&
        other.score == score &&
        other.confidence == confidence &&
        _mapEquals(other.probabilities, probabilities);
  }

  @override
  int get hashCode =>
      Object.hash(type, score, confidence, _mapHash(probabilities));
}

/// Answers returned from a single classifier call.
class ClassifierResponse {
  /// Creates a [ClassifierResponse] mapping question names to [answers].
  ClassifierResponse({
    required Map<String, ClassifierAnswer> answers,
    this.modelVersion,
  }) : answers = Map<String, ClassifierAnswer>.unmodifiable(answers);

  /// Deserializes a [ClassifierResponse] from [json].
  factory ClassifierResponse.fromJson(Map<String, Object?> json) {
    final Object? rawAnswers = json['answers'];
    if (rawAnswers is! Map) {
      throw ArgumentError.value(
        rawAnswers,
        'answers',
        'answers must be a Map.',
      );
    }
    return ClassifierResponse(
      answers: <String, ClassifierAnswer>{
        for (final MapEntry<Object?, Object?> entry in rawAnswers.entries)
          '${entry.key}': entry.value is ClassifierAnswer
              ? entry.value as ClassifierAnswer
              : ClassifierAnswer.fromJson(
                  <String, Object?>{
                    for (final MapEntry<Object?, Object?> item
                        in (entry.value as Map).entries)
                      '${item.key}': item.value,
                  },
                ),
      },
      modelVersion:
          (json['model_version'] ?? json['modelVersion']) as String?,
    );
  }

  /// Maps each question name to its corresponding [ClassifierAnswer].
  final Map<String, ClassifierAnswer> answers;

  /// Optional model version reported by the classifier provider.
  final String? modelVersion;

  /// Serializes this response to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'answers': <String, Object?>{
        for (final MapEntry<String, ClassifierAnswer> entry in answers.entries)
          entry.key: entry.value.toJson(),
      },
      'model_version': modelVersion,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ClassifierResponse &&
        other.modelVersion == modelVersion &&
        _mapEquals(other.answers, answers);
  }

  @override
  int get hashCode => Object.hash(modelVersion, _mapHash(answers));
}

void _validateProbability(double value, String name) {
  if (value.isNaN || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      name,
      '$name must be between 0.0 and 1.0 inclusive.',
    );
  }
}

double _toDouble(Object? value, String name) {
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError.value(value, name, '$name must be a number.');
}

int _toInt(Object? value, String name) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    final int? parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw ArgumentError.value(value, name, '$name must be an integer.');
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    return _mapEquals(a, b);
  }
  if (a is List && b is List) {
    return _listEquals(a, b);
  }
  return a == b;
}

bool _mapEquals(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<Object?, Object?> entry in a.entries) {
    if (!b.containsKey(entry.key) ||
        !_deepEquals(b[entry.key], entry.value)) {
      return false;
    }
  }
  return true;
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i += 1) {
    if (!_deepEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

int _deepHash(Object? value) {
  if (value is Map) {
    return _mapHash(value);
  }
  if (value is List) {
    return _listHash(value);
  }
  return value.hashCode;
}

int _mapHash(Map<Object?, Object?> map) {
  int hash = 0;
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    hash ^= Object.hash(entry.key, _deepHash(entry.value));
  }
  return hash;
}

int _listHash(List<Object?> list) {
  return Object.hashAll(list.map(_deepHash));
}
