import 'common.dart';

/// Rubric body content used by LLM-as-judge criteria.
class RubricContent {
  /// Creates rubric content.
  RubricContent({this.textProperty});

  /// Natural-language rubric text.
  final String? textProperty;

  /// Decodes rubric content from JSON.
  factory RubricContent.fromJson(EvalJson json) {
    return RubricContent(
      textProperty:
          asNullableString(json['textProperty']) ??
          asNullableString(json['text_property']),
    );
  }

  /// Encodes this rubric content for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      if (textProperty != null) 'text_property': textProperty,
    };
  }
}

/// One rubric definition that can be applied during evaluation.
class Rubric {
  /// Creates a rubric definition.
  Rubric({
    required this.rubricId,
    required this.rubricContent,
    this.description,
    this.type,
  });

  /// Stable rubric identifier.
  final String rubricId;

  /// Rubric body content.
  final RubricContent rubricContent;

  /// Optional rubric description.
  final String? description;

  /// Optional rubric type discriminator.
  final String? type;

  /// Decodes a rubric from JSON.
  factory Rubric.fromJson(EvalJson json) {
    final EvalJson rubricContentJson = asEvalJson(
      json['rubricContent'] ?? json['rubric_content'],
    );
    return Rubric(
      rubricId:
          asNullableString(json['rubricId']) ??
          asNullableString(json['rubric_id']) ??
          '',
      rubricContent: RubricContent.fromJson(rubricContentJson),
      description: asNullableString(json['description']),
      type: asNullableString(json['type']),
    );
  }

  /// Encodes this rubric for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'rubric_id': rubricId,
      'rubric_content': rubricContent.toJson(),
      if (description != null) 'description': description,
      if (type != null) 'type': type,
    };
  }
}

/// Score assigned to one rubric for a single evaluation result.
class RubricScore {
  /// Creates a rubric score record.
  RubricScore({required this.rubricId, this.rationale, this.score});

  /// Rubric identifier.
  final String rubricId;

  /// Optional explanation for the score.
  final String? rationale;

  /// Numeric rubric score.
  final double? score;

  /// Decodes a rubric score from JSON.
  factory RubricScore.fromJson(EvalJson json) {
    return RubricScore(
      rubricId:
          asNullableString(json['rubricId']) ??
          asNullableString(json['rubric_id']) ??
          '',
      rationale: asNullableString(json['rationale']),
      score: asNullableDouble(json['score']),
    );
  }

  /// Encodes this rubric score for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'rubric_id': rubricId,
      if (rationale != null) 'rationale': rationale,
      if (score != null) 'score': score,
    };
  }
}
