import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/adk_core.dart' as core;
import 'package:test/test.dart';

void main() {
  group('NodePathBuilder parity', () {
    test('fromString returns empty path when string is empty', () {
      final NodePathBuilder path = NodePathBuilder.fromString('');

      expect(path.toString(), '');
      expect(path.segments, isEmpty);
    });

    test('fromString parses single and multiple segments', () {
      expect(NodePathBuilder.fromString('wf@1').toString(), 'wf@1');
      expect(
        NodePathBuilder.fromString('wf@1/node@2').toString(),
        'wf@1/node@2',
      );
    });

    test('string representation joins segments with slash', () {
      final NodePathBuilder path = NodePathBuilder(<String>['wf@1', 'node@2']);

      expect(path.toString(), 'wf@1/node@2');
    });

    test('equality compares path segments', () {
      expect(
        NodePathBuilder(<String>['wf@1', 'node@2']),
        NodePathBuilder(<String>['wf@1', 'node@2']),
      );
      expect(
        NodePathBuilder(<String>['wf@1', 'node@1']),
        isNot(NodePathBuilder(<String>['wf@1', 'node@2'])),
      );
      expect(NodePathBuilder(<String>['wf@1']), isNot('wf@1'));
    });

    test('nodeName returns leaf name without run id', () {
      expect(NodePathBuilder.fromString('wf@1/node@2').nodeName, 'node');
      expect(NodePathBuilder.fromString('wf@1/node').nodeName, 'node');
      expect(NodePathBuilder.fromString('').nodeName, '');
    });

    test('leafSegment returns full leaf segment', () {
      expect(NodePathBuilder.fromString('wf@1/node@2').leafSegment, 'node@2');
      expect(NodePathBuilder.fromString('').leafSegment, '');
    });

    test('runId returns leaf run id when present', () {
      expect(NodePathBuilder.fromString('wf@1/node@2').runId, '2');
      expect(NodePathBuilder.fromString('wf@1/node').runId, isNull);
      expect(NodePathBuilder.fromString('wf@1/node@').runId, '');
      expect(NodePathBuilder.fromString('').runId, isNull);
    });

    test('parent returns prefix path', () {
      final NodePathBuilder? parent = NodePathBuilder.fromString(
        'wf@1/node@2',
      ).parent;

      expect(parent, isNotNull);
      expect(parent.toString(), 'wf@1');
      expect(NodePathBuilder.fromString('wf@1').parent, isNull);
      expect(NodePathBuilder.fromString('').parent, isNull);
    });

    test('append adds segment with or without run id', () {
      final NodePathBuilder path = NodePathBuilder.fromString('wf@1');

      expect(path.append('node', '2').toString(), 'wf@1/node@2');
      expect(path.append('node').toString(), 'wf@1/node');
    });

    test('isDescendantOf checks strict ancestry', () {
      final NodePathBuilder ancestor = NodePathBuilder.fromString('wf@1');

      expect(
        NodePathBuilder.fromString('wf@1/node@2').isDescendantOf(ancestor),
        isTrue,
      );
      expect(
        NodePathBuilder.fromString(
          'wf@1/inner@1/node@2',
        ).isDescendantOf(ancestor),
        isTrue,
      );
      expect(ancestor.isDescendantOf(ancestor), isFalse);
      expect(
        NodePathBuilder.fromString('other@1/node@2').isDescendantOf(ancestor),
        isFalse,
      );
    });

    test('isDirectChildOf checks one-segment ancestry', () {
      final NodePathBuilder parent = NodePathBuilder.fromString('wf@1');

      expect(
        NodePathBuilder.fromString('wf@1/node@2').isDirectChildOf(parent),
        isTrue,
      );
      expect(
        NodePathBuilder.fromString(
          'wf@1/inner@1/node@2',
        ).isDirectChildOf(parent),
        isFalse,
      );
    });

    test('getDirectChild returns child path toward descendant', () {
      final NodePathBuilder parent = NodePathBuilder.fromString('wf@1');
      final NodePathBuilder descendant = NodePathBuilder.fromString(
        'wf@1/inner@1/node@2',
      );

      expect(parent.getDirectChild(descendant), isA<NodePathBuilder>());
      expect(parent.getDirectChild(descendant).toString(), 'wf@1/inner@1');
    });

    test('getDirectChild rejects unrelated or non-descendant paths', () {
      final NodePathBuilder parent = NodePathBuilder.fromString('wf@1');

      expect(
        () =>
            parent.getDirectChild(NodePathBuilder.fromString('other@1/node@2')),
        throwsArgumentError,
      );
      expect(() => parent.getDirectChild(parent), throwsArgumentError);
    });

    test('is exported through the Web-safe core entrypoint', () {
      final core.NodePathBuilder path = core.NodePathBuilder.fromString('wf@1');

      expect(path.append('node', '2').toString(), 'wf@1/node@2');
    });
  });
}
