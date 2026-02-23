import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('utils parity batch', () {
    test('withAclosing closes resource after callback', () async {
      bool closed = false;
      final String result = await withAclosing<String, String>(
        'resource',
        (String _) async {
          closed = true;
        },
        (String resource) async {
          expect(resource, 'resource');
          return 'ok';
        },
      );
      expect(result, 'ok');
      expect(closed, isTrue);
    });

    test('workingInProgress blocks unless bypass env is enabled', () {
      expect(
        () => workingInProgress.check('MyFeature'),
        throwsA(isA<StateError>()),
      );

      expect(
        () => workingInProgress.check(
          'MyFeature',
          environment: <String, String>{'ADK_ALLOW_WIP_FEATURES': 'true'},
        ),
        returnsNormally,
      );
    });

    test('experimental emits warning message and supports suppress env', () {
      String? warning;
      experimental.check(
        'MyExperimentalApi',
        onWarning: (String message) => warning = message,
      );
      expect(warning, contains('[EXPERIMENTAL] MyExperimentalApi'));

      warning = null;
      experimental.check(
        'MyExperimentalApi',
        environment: <String, String>{
          'ADK_SUPPRESS_EXPERIMENTAL_FEATURE_WARNINGS': '1',
        },
        onWarning: (String message) => warning = message,
      );
      expect(warning, isNull);
    });

    test('loadYamlFile parses yaml mappings and lists', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_yaml_load_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final File file = File('${dir.path}/sample.yaml');
      await file.writeAsString('''
name: root
enabled: true
items:
  - one
  - key: value
''');

      final Object? loaded = loadYamlFile(file.path);
      expect(loaded, isA<Map>());
      final Map map = loaded as Map;
      expect(map['name'], 'root');
      expect(map['enabled'], true);
      expect(map['items'], isA<List>());
    });

    test('dumpPydanticToYaml writes and round-trips map data', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_yaml_dump_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final File file = File('${dir.path}/out.yaml');

      dumpPydanticToYaml(
        <String, Object?>{
          'name': 'root',
          'description': 'line1\nline2',
          'enabled': true,
        },
        file.path,
        sortKeys: true,
      );

      final String raw = await file.readAsString();
      expect(raw, contains('description: |'));
      expect(raw, contains('line1'));
      expect(raw, contains('line2'));
    });

    test('version constant matches python baseline', () {
      expect(adkVersion, '1.25.1');
    });
  });
}
