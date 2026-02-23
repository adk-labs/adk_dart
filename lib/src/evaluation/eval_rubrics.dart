import 'common.dart';

class RubricContent {
  RubricContent({this.textProperty});

  final String? textProperty;

  factory RubricContent.fromJson(EvalJson json) {
    return RubricContent(
      textProperty:
          asNullableString(json['textProperty']) ??
          asNullableString(json['text_property']),
    );
  }

  EvalJson toJson() {
    return <String, Object?>{
      if (textProperty != null) 'text_property': textProperty,
    };
  }
}

class Rubric {
  Rubric({
    required this.rubricId,
    required this.rubricContent,
    this.description,
    this.type,
  });

  final String rubricId;
  final RubricContent rubricContent;
  final String? description;
  final String? type;

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

  EvalJson toJson() {
    return <String, Object?>{
      'rubric_id': rubricId,
      'rubric_content': rubricContent.toJson(),
      if (description != null) 'description': description,
      if (type != null) 'type': type,
    };
  }
}

class RubricScore {
  RubricScore({required this.rubricId, this.rationale, this.score});

  final String rubricId;
  final String? rationale;
  final double? score;

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

  EvalJson toJson() {
    return <String, Object?>{
      'rubric_id': rubricId,
      if (rationale != null) 'rationale': rationale,
      if (score != null) 'score': score,
    };
  }
}
