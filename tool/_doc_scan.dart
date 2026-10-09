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

void _scanClassMembers({
  required String path,
  required LineInfo lineInfo,
  required String containerName,
  required NodeList<ClassMember> members,
  required List<Issue> issues,
}) {
  final Set<String> documentedGetters = <String>{};
  for (final ClassMember cm in members) {
    if (cm is MethodDeclaration && cm.isGetter && _hasDocs(cm)) {
      documentedGetters.add(cm.name.lexeme);
    }
  }

  for (final ClassMember cm in members) {
    if (cm is FieldDeclaration) {
      for (final VariableDeclaration v in cm.fields.variables) {
        final String n = v.name.lexeme;
        if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
          issues.add(
            Issue(
              path,
              lineInfo.getLocation(cm.offset).lineNumber,
              'field',
              '$containerName.$n',
            ),
          );
        }
      }
    } else if (cm is MethodDeclaration) {
      final String n = cm.name.lexeme;
      if (cm.isSetter && documentedGetters.contains(n)) {
        continue;
      }
      if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
        issues.add(
          Issue(
            path,
            lineInfo.getLocation(cm.offset).lineNumber,
            'method',
            '$containerName.$n',
          ),
        );
      }
    } else if (cm is ConstructorDeclaration) {
      final String n = cm.name?.lexeme ?? containerName;
      if (_isPublic(n) && !_hasDocs(cm) && !_hasOverride(cm)) {
        issues.add(
          Issue(
            path,
            lineInfo.getLocation(cm.offset).lineNumber,
            'ctor',
            '$containerName.$n',
          ),
        );
      }
    }
  }
}

void main(List<String> args) {
  final List<String> targets = args.isEmpty ? <String>['lib'] : args;
  final List<Issue> issues = <Issue>[];

  for (final String targetPath in targets) {
    final Directory root = Directory(targetPath);
    if (!root.existsSync()) {
      stderr.writeln('Target directory does not exist: $targetPath');
      exitCode = 2;
      return;
    }

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
          final String name = member.namePart.typeName.lexeme;
          final bool classPublic = _isPublic(name);
          if (classPublic && !_hasDocs(member)) {
            issues.add(
              Issue(
                path,
                lineInfo.getLocation(member.offset).lineNumber,
                'class',
                name,
              ),
            );
          }
          if (classPublic) {
            _scanClassMembers(
              path: path,
              lineInfo: lineInfo,
              containerName: name,
              members: member.body.members,
              issues: issues,
            );
          }
        } else if (member is MixinDeclaration) {
          final String name = member.name.lexeme;
          final bool mixinPublic = _isPublic(name);
          if (mixinPublic && !_hasDocs(member)) {
            issues.add(
              Issue(
                path,
                lineInfo.getLocation(member.offset).lineNumber,
                'mixin',
                name,
              ),
            );
          }
          if (mixinPublic) {
            _scanClassMembers(
              path: path,
              lineInfo: lineInfo,
              containerName: name,
              members: member.body.members,
              issues: issues,
            );
          }
        } else if (member is EnumDeclaration) {
          final String name = member.namePart.typeName.lexeme;
          final bool enumPublic = _isPublic(name);
          if (enumPublic && !_hasDocs(member)) {
            issues.add(
              Issue(
                path,
                lineInfo.getLocation(member.offset).lineNumber,
                'enum',
                name,
              ),
            );
          }
          if (enumPublic) {
            for (final EnumConstantDeclaration c in member.body.constants) {
              final String cn = c.name.lexeme;
              if (_isPublic(cn) && !_hasDocs(c)) {
                issues.add(
                  Issue(
                    path,
                    lineInfo.getLocation(c.offset).lineNumber,
                    'enum-const',
                    '$name.$cn',
                  ),
                );
              }
            }
            _scanClassMembers(
              path: path,
              lineInfo: lineInfo,
              containerName: name,
              members: member.body.members,
              issues: issues,
            );
          }
        } else if (member is ExtensionDeclaration) {
          final String? extName = member.name?.lexeme;
          if (extName != null && _isPublic(extName)) {
            if (!_hasDocs(member)) {
              issues.add(
                Issue(
                  path,
                  lineInfo.getLocation(member.offset).lineNumber,
                  'extension',
                  extName,
                ),
              );
            }
            _scanClassMembers(
              path: path,
              lineInfo: lineInfo,
              containerName: extName,
              members: member.body.members,
              issues: issues,
            );
          }
        } else if (member is FunctionDeclaration) {
          final String name = member.name.lexeme;
          if (_isPublic(name) && !_hasDocs(member)) {
            issues.add(
              Issue(
                path,
                lineInfo.getLocation(member.name.offset).lineNumber,
                'function',
                name,
              ),
            );
          }
        } else if (member is TopLevelVariableDeclaration) {
          for (final VariableDeclaration v in member.variables.variables) {
            final String name = v.name.lexeme;
            if (_isPublic(name) && !_hasDocs(member)) {
              issues.add(
                Issue(
                  path,
                  lineInfo.getLocation(v.name.offset).lineNumber,
                  'top-var',
                  name,
                ),
              );
            }
          }
        } else if (member is GenericTypeAlias) {
          final String name = member.name.lexeme;
          if (_isPublic(name) && !_hasDocs(member)) {
            issues.add(
              Issue(
                path,
                lineInfo.getLocation(member.name.offset).lineNumber,
                'typedef',
                name,
              ),
            );
          }
        }
      }
    }
  }

  final Map<String, int> byFile = <String, int>{};
  for (final Issue issue in issues) {
    byFile.update(issue.path, (int value) => value + 1, ifAbsent: () => 1);
  }

  final List<MapEntry<String, int>> ranked = byFile.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));

  print('TOTAL_ISSUES=${issues.length}');
  print('TOP_FILES');
  for (final MapEntry<String, int> e in ranked.take(80)) {
    print('${e.value.toString().padLeft(3)} ${e.key}');
  }

  print('ALL_ISSUES');
  for (final Issue issue in issues) {
    print(issue);
  }
}
