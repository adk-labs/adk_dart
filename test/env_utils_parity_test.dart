import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('env utils parity', () {
    test('isEnvEnabled handles true/1 and false values', () {
      expect(
        isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'true'}),
        isTrue,
      );
      expect(
        isEnvEnabled('FLAG', environment: <String, String>{'FLAG': '1'}),
        isTrue,
      );
      expect(
        isEnvEnabled('FLAG', environment: <String, String>{'FLAG': 'false'}),
        isFalse,
      );
      expect(isEnvEnabled('FLAG', environment: <String, String>{}), isFalse);
      expect(
        isEnvEnabled(
          'FLAG',
          defaultValue: '1',
          environment: <String, String>{},
        ),
        isTrue,
      );
    });
  });
}
