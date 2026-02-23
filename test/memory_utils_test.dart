import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  test('formatTimestamp returns ISO-8601 local timestamp', () {
    final String expected = DateTime.fromMillisecondsSinceEpoch(
      0,
    ).toIso8601String();
    final String formatted = formatTimestamp(0);
    expect(formatted, expected);
  });

  test('formatTimestamp preserves sub-second precision', () {
    final String formatted = formatTimestamp(1700000000.123);
    expect(formatted, contains('2023'));
    expect(formatted, endsWith('123'));
  });
}
