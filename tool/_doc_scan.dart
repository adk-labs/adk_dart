import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';

class Issue {
  Issue(this.path, this.line, this.kind, this.name);
  final String path;
  final int line;
  final String kind;
  final String name;

  @override
  String toString() => '$path:$line [$kind] $name';
}

bool _isPublic(String name) => !name.startsWith('_');

bool _hasDocs(AnnotatedNode node) => node.documentationComment != null;

bool _hasOverride(AnnotatedNode node) {
  for (final Annotation annotation in node.metadata) {
    final String name = annotation.name.name;
    if (name == 'override') return true;
  }
  return false;
}

void main(List<String> args) {
  final String targetPath = args.isEmpty ? 'lib/src' : args.first;
  final Directory root = Directory(targetPath);
  if (!root.existsSync()) {
    stderr.writeln('Target directory does not exist: $targetPath');
    exitCode = 2;
    return;
  }
  final List<Issue> issues = <Issue>[];

  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final String path = entity.path;
    final String content = entity.readAsStringSync();
    final parsed = parseString(
      content: content,
      path: path,
      throwIfDiagnostics: false,
    );
    final CompilationUnit unit = parsed.unit;
    final LineInfo lineInfo = parsed.lineInfo;

    for (final CompilationUnitMember member in unit.declarations) {
      if (member is ClassDeclaration) {
        final String name = member.name.lexeme;
        final bool classPublic = _isPublic(name);
        if (classPublic && !_hasDocs(member)) {
          issues.add(Issue(path, lineInfo.getLocation(member.name.offset).lineNumber, 'class', name));
        }
        if (classPublic) for (final ClassMember cm in member.members) {
          if (cm is FieldDeclaration) {
            for (final VariableDeclaration v in cm.fields.variables) {
              final String n = v.name.lexeme;
              if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
                issues.add(Issue(path, lineInfo.getLocation(v.name.offset).lineNumber, 'field', '$name.$n'));
              }
            }
          } else if (cm is MethodDeclaration) {
            final String n = cm.name.lexeme;
            if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
              issues.add(Issue(path, lineInfo.getLocation(cm.name.offset).lineNumber, 'method', '$name.$n'));
            }
          } else if (cm is ConstructorDeclaration) {
            final String n = cm.name?.lexeme ?? member.name.lexeme;
            if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
              issues.add(Issue(path, lineInfo.getLocation(cm.offset).lineNumber, 'ctor', '$name.$n'));
            }
          }
        }
      } else if (member is MixinDeclaration) {
        final String name = member.name.lexeme;
        final bool mixinPublic = _isPublic(name);
        if (mixinPublic && !_hasDocs(member)) {
          issues.add(Issue(path, lineInfo.getLocation(member.name.offset).lineNumber, 'mixin', name));
        }
        if (mixinPublic) for (final ClassMember cm in member.members) {
          if (cm is FieldDeclaration) {
            for (final VariableDeclaration v in cm.fields.variables) {
              final String n = v.name.lexeme;
              if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
                issues.add(Issue(path, lineInfo.getLocation(v.name.offset).lineNumber, 'field', '$name.$n'));
              }
            }
          } else if (cm is MethodDeclaration) {
            final String n = cm.name.lexeme;
            if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
              issues.add(Issue(path, lineInfo.getLocation(cm.name.offset).lineNumber, 'method', '$name.$n'));
            }
          }
        }
      } else if (member is EnumDeclaration) {
        final String name = member.name.lexeme;
        if (_isPublic(name) && !_hasDocs(member)) {
          issues.add(Issue(path, lineInfo.getLocation(member.name.offset).lineNumber, 'enum', name));
        }
      } else if (member is ExtensionDeclaration) {
        final String? extName = member.name?.lexeme;
        if (extName != null && _isPublic(extName) && !_hasDocs(member)) {
          issues.add(Issue(path, lineInfo.getLocation(member.name!.offset).lineNumber, 'extension', extName));
        }
      } else if (member is FunctionDeclaration) {
        final String name = member.name.lexeme;
        if (_isPublic(name) && !_hasDocs(member)) {
          issues.add(Issue(path, lineInfo.getLocation(member.name.offset).lineNumber, 'function', name));
        }
      } else if (member is TopLevelVariableDeclaration) {
        for (final VariableDeclaration v in member.variables.variables) {
          final String name = v.name.lexeme;
          if (_isPublic(name) && !_hasDocs(member)) {
            issues.add(Issue(path, lineInfo.getLocation(v.name.offset).lineNumber, 'top-var', name));
          }
        }
      } else if (member is GenericTypeAlias) {
        final String name = member.name.lexeme;
        if (_isPublic(name) && !_hasDocs(member)) {
          issues.add(Issue(path, lineInfo.getLocation(member.name.offset).lineNumber, 'typedef', name));
        }
      }
    }
  }

  final Map<String, int> byFile = <String, int>{};
  for (final Issue issue in issues) {
    byFile.update(issue.path, (int value) => value + 1, ifAbsent: () => 1);
  }

  final List<MapEntry<String, int>> ranked = byFile.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('TOTAL_ISSUES=${issues.length}');
  print('TOP_FILES');
  for (final MapEntry<String, int> e in ranked.take(80)) {
    print('${e.value.toString().padLeft(3)} ${e.key}');
  }

  print('SAMPLE');
  for (final Issue issue in issues.take(200)) {
    print(issue);
  }
}
