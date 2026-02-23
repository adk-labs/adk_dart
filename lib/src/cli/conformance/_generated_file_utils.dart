import 'dart:convert';
import 'dart:io';

import 'test_case.dart';

Future<void> writeTestCasesToFile(
  String filePath,
  List<ConformanceTestCase> testCases,
) async {
  final File file = File(filePath);
  file.parent.createSync(recursive: true);
  final List<Map<String, Object?>> json = testCases
      .map((ConformanceTestCase testCase) {
        return <String, Object?>{
          'name': testCase.name,
          'turns': testCase.turns
              .map(
                (ConformanceTurn turn) => <String, Object?>{
                  'user_text': turn.userText,
                  'expected_reply_contains': turn.expectedReplyContains,
                },
              )
              .toList(growable: false),
        };
      })
      .toList(growable: false);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}

Future<List<ConformanceTestCase>> readTestCasesFromFile(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    return <ConformanceTestCase>[];
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! List) {
    throw const FormatException(
      'Conformance test file must contain a JSON list.',
    );
  }

  return decoded
      .whereType<Map>()
      .map((Map item) {
        final Map<String, Object?> map = item.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final List<ConformanceTurn> turns =
            (map['turns'] as List?)
                ?.whereType<Map>()
                .map((Map turnItem) {
                  final Map<String, Object?> turnMap = turnItem.map(
                    (Object? key, Object? value) => MapEntry('$key', value),
                  );
                  return ConformanceTurn(
                    userText: '${turnMap['user_text'] ?? ''}',
                    expectedReplyContains:
                        '${turnMap['expected_reply_contains'] ?? ''}',
                  );
                })
                .toList(growable: false) ??
            <ConformanceTurn>[];
        return ConformanceTestCase(name: '${map['name'] ?? ''}', turns: turns);
      })
      .toList(growable: false);
}
