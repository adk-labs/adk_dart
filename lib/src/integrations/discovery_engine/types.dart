/// Data types shared by the Discovery Engine CheckGrounding integration.
library;

/// A piece of evidence that a grounding check verifies an answer against.
class FactChunk {
  /// Creates a fact chunk.
  FactChunk({
    required this.text,
    this.title,
    this.link,
    Map<String, String>? attributes,
  }) : attributes = Map<String, String>.unmodifiable(
         attributes ?? const <String, String>{},
       );

  /// The evidence text.
  final String text;

  /// Optional title, used for citation attribution.
  final String? title;

  /// Optional source URI, used for citation attribution.
  final String? link;

  /// Optional key-value metadata, returned with citations.
  final Map<String, String> attributes;

  /// Serializes this fact chunk to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    if (title != null) 'title': title,
    if (link != null) 'link': link,
    if (attributes.isNotEmpty) 'attributes': Map<String, String>.from(attributes),
  };

  /// Deserializes a [FactChunk] from JSON.
  factory FactChunk.fromJson(Map<String, Object?> json) {
    final Object? rawAttrs = json['attributes'];
    final Map<String, String> attrs = <String, String>{};
    if (rawAttrs is Map) {
      rawAttrs.forEach((Object? key, Object? value) {
        if (key != null && value != null) {
          attrs['$key'] = '$value';
        }
      });
    }
    return FactChunk(
      text: '${json['text'] ?? ''}',
      title: json['title'] as String?,
      link: json['link'] as String?,
      attributes: attrs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FactChunk) return false;
    if (text != other.text ||
        title != other.title ||
        link != other.link ||
        attributes.length != other.attributes.length) {
      return false;
    }
    for (final MapEntry<String, String> entry in attributes.entries) {
      if (other.attributes[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, title, link, Object.hashAllUnordered(
    attributes.entries.map(
      (MapEntry<String, String> e) => Object.hash(e.key, e.value),
    ),
  ));
}

/// Capacity limits that a grounding backend enforces.
///
/// The defaults match the Discovery Engine CheckGrounding API.
class GroundingLimits {
  /// Creates grounding capacity limits.
  GroundingLimits({this.maxFacts = 200}) {
    if (maxFacts <= 0) {
      throw ArgumentError.value(
        maxFacts,
        'maxFacts',
        'maxFacts must be greater than 0.',
      );
    }
  }

  /// Maximum number of fact chunks evaluated per check.
  final int maxFacts;

  @override
  bool operator ==(Object other) =>
      other is GroundingLimits && other.maxFacts == maxFacts;

  @override
  int get hashCode => maxFacts.hashCode;
}

/// Outcome of a single grounding check.
enum GroundingStatus {
  /// The check ran and returned grounding metadata.
  ok('ok'),

  /// Skipped because there were no fact chunks to ground against.
  skippedNoFacts('skipped_no_facts'),

  /// Skipped because the answer had no non-whitespace text.
  skippedEmpty('skipped_empty'),

  /// The backend rejected the answer for exceeding its token limit.
  rejectedTooLong('rejected_too_long'),

  /// The backend call failed for any other reason.
  apiError('api_error');

  /// Creates a grounding status with its wire [value].
  const GroundingStatus(this.value);

  /// String value matching upstream Python `GroundingStatus`.
  final String value;
}

/// Outcome of a grounding check and the signals it produced.
class GroundingResult {
  /// Creates a grounding check result.
  const GroundingResult({
    required this.status,
    required this.numFactsEvaluated,
    this.metadata,
    this.supportScore,
    this.numClaims,
    this.error,
  });

  /// Outcome of the check.
  final GroundingStatus status;

  /// Number of fact chunks sent to the backend.
  final int numFactsEvaluated;

  /// Citation metadata (`grounding_chunks`, `grounding_supports`).
  ///
  /// Set only when [status] is [GroundingStatus.ok].
  final Map<String, Object?>? metadata;

  /// Answer-level support score, when the backend returned one.
  final double? supportScore;

  /// Number of claims in the answer that required a grounding check.
  final int? numClaims;

  /// Error message for [GroundingStatus.rejectedTooLong] and
  /// [GroundingStatus.apiError].
  final String? error;

  /// Serializes this result to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.value,
    'num_facts_evaluated': numFactsEvaluated,
    if (metadata != null) 'metadata': metadata,
    if (supportScore != null) 'support_score': supportScore,
    if (numClaims != null) 'num_claims': numClaims,
    if (error != null) 'error': error,
  };
}
