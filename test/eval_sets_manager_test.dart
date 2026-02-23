import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryEvalSetsManager', () {
    test('supports create/add/update/delete flow', () async {
      final InMemoryEvalSetsManager manager = InMemoryEvalSetsManager();
      final EvalSet created = await manager.createEvalSet('app', 'set1');
      expect(created.evalSetId, 'set1');

      final EvalCase case1 = EvalCase(
        evalId: 'case1',
        input: 'hello',
        expectedOutput: 'world',
      );
      await manager.addEvalCase('app', 'set1', case1);
      expect(
        (await manager.getEvalCase('app', 'set1', 'case1'))?.input,
        'hello',
      );

      final EvalCase updated = EvalCase(
        evalId: 'case1',
        input: 'updated',
        expectedOutput: 'output',
      );
      await manager.updateEvalCase('app', 'set1', updated);
      expect(
        (await manager.getEvalCase('app', 'set1', 'case1'))?.input,
        'updated',
      );

      await manager.deleteEvalCase('app', 'set1', 'case1');
      expect(await manager.getEvalCase('app', 'set1', 'case1'), isNull);
      expect(await manager.listEvalSets('app'), contains('set1'));
    });
  });

  group('LocalEvalSetsManager', () {
    test('persists eval sets and reloads from disk', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_eval_sets_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final LocalEvalSetsManager manager = LocalEvalSetsManager(dir.path);
      await manager.createEvalSet('app', 'set1');
      await manager.addEvalCase(
        'app',
        'set1',
        EvalCase(evalId: 'case1', input: 'input', expectedOutput: 'output'),
      );

      final EvalSet? loaded = await manager.getEvalSet('app', 'set1');
      expect(loaded, isNotNull);
      expect(loaded!.evalCases, hasLength(1));
      expect(loaded.evalCases.first.evalId, 'case1');
      expect(await manager.listEvalSets('app'), contains('set1'));
    });

    test('loads legacy evalset json list format', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_eval_sets_legacy_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final Directory appDir = Directory('${dir.path}/app');
      await appDir.create(recursive: true);
      final File file = File('${appDir.path}/legacy.evalset.json');
      await file.writeAsString(
        jsonEncode(<Object?>[
          <String, Object?>{
            'name': 'legacy_case',
            'data': <Object?>[
              <String, Object?>{'query': 'Q1', 'reference': 'A1'},
            ],
            'initial_session': <String, Object?>{
              'app_name': 'app',
              'user_id': 'user',
              'state': <String, Object?>{'x': 1},
            },
          },
        ]),
      );

      final LocalEvalSetsManager manager = LocalEvalSetsManager(dir.path);
      final EvalSet? loaded = await manager.getEvalSet('app', 'legacy');
      expect(loaded, isNotNull);
      expect(loaded!.evalCases, hasLength(1));
      expect(loaded.evalCases.first.evalId, 'legacy_case');
      expect(loaded.evalCases.first.input, 'Q1');
      expect(loaded.evalCases.first.expectedOutput, 'A1');
      expect(loaded.evalCases.first.sessionInput, isNotNull);
    });
  });
}
