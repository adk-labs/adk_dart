import 'dart:io';

void main() {
  final File rootPubspec = File('pubspec.yaml');
  final File facadePubspec = File('packages/adk/pubspec.yaml');
  final File facadeLib = File('packages/adk/lib/adk.dart');
  final File facadeCli = File('packages/adk/lib/cli.dart');
  final File flutterFacadePubspec = File('packages/flutter_adk/pubspec.yaml');
  final File flutterFacadeLib = File(
    'packages/flutter_adk/lib/flutter_adk.dart',
  );

  if (!rootPubspec.existsSync()) {
    _fail('Missing root pubspec.yaml');
  }
  if (!facadePubspec.existsSync()) {
    _fail('Missing packages/adk/pubspec.yaml');
  }
  if (!flutterFacadePubspec.existsSync()) {
    _fail('Missing packages/flutter_adk/pubspec.yaml');
  }

  final String rootText = rootPubspec.readAsStringSync();
  final String facadeText = facadePubspec.readAsStringSync();
  final String flutterFacadeText = flutterFacadePubspec.readAsStringSync();

  final String rootName = _extractScalar(rootText, 'name');
  final String rootVersion = _extractScalar(rootText, 'version');
  final String facadeName = _extractScalar(facadeText, 'name');
  final String facadeVersion = _extractScalar(facadeText, 'version');
  final String facadeDependency = _extractDependencyVersion(
    facadeText,
    'adk_dart',
  );
  final String flutterFacadeName = _extractScalar(flutterFacadeText, 'name');
  final String flutterFacadeVersion = _extractScalar(
    flutterFacadeText,
    'version',
  );
  final String flutterFacadeDependency = _extractDependencyVersion(
    flutterFacadeText,
    'adk_dart',
  );

  if (rootName != 'adk_dart') {
    _fail('Root package name must be adk_dart. Found: $rootName');
  }
  if (facadeName != 'adk') {
    _fail('Facade package name must be adk. Found: $facadeName');
  }
  if (flutterFacadeName != 'flutter_adk') {
    _fail(
      'Flutter facade package name must be flutter_adk. '
      'Found: $flutterFacadeName',
    );
  }
  if (facadeVersion != rootVersion) {
    _fail(
      'Version mismatch: root=$rootVersion facade=$facadeVersion. '
      'Run `dart run tool/sync_facade_versions.dart`.',
    );
  }
  if (flutterFacadeVersion != rootVersion) {
    _fail(
      'Version mismatch: root=$rootVersion '
      'flutter_facade=$flutterFacadeVersion.',
    );
  }
  if (facadeDependency != rootVersion) {
    _fail(
      'Dependency mismatch: packages/adk depends on adk_dart:$facadeDependency '
      'but root version is $rootVersion.',
    );
  }
  if (flutterFacadeDependency != rootVersion) {
    _fail(
      'Dependency mismatch: packages/flutter_adk depends on '
      'adk_dart:$flutterFacadeDependency but root version is $rootVersion.',
    );
  }

  if (!facadeLib.existsSync()) {
    _fail('Missing packages/adk/lib/adk.dart');
  }
  if (!facadeCli.existsSync()) {
    _fail('Missing packages/adk/lib/cli.dart');
  }
  if (!flutterFacadeLib.existsSync()) {
    _fail('Missing packages/flutter_adk/lib/flutter_adk.dart');
  }

  final String facadeLibText = facadeLib.readAsStringSync().trim();
  final String facadeCliText = facadeCli.readAsStringSync().trim();
  final String flutterFacadeLibText = flutterFacadeLib.readAsStringSync();

  if (facadeLibText != "export 'package:adk_dart/adk_dart.dart';") {
    _fail(
      'packages/adk/lib/adk.dart must re-export package:adk_dart/adk_dart.dart',
    );
  }
  if (facadeCliText != "export 'package:adk_dart/cli.dart';") {
    _fail('packages/adk/lib/cli.dart must re-export package:adk_dart/cli.dart');
  }
  if (!flutterFacadeLibText.contains(
    "export 'package:adk_dart/adk_core.dart';",
  )) {
    _fail(
      'packages/flutter_adk/lib/flutter_adk.dart must re-export '
      'package:adk_dart/adk_core.dart',
    );
  }

  stdout.writeln('Package sync check passed.');
  stdout.writeln('root: $rootName@$rootVersion');
  stdout.writeln(
    'facade: $facadeName@$facadeVersion -> adk_dart:$facadeDependency',
  );
  stdout.writeln(
    'flutter_facade: $flutterFacadeName@$flutterFacadeVersion '
    '-> adk_dart:$flutterFacadeDependency',
  );
}

String _extractScalar(String text, String key) {
  final RegExp exp = RegExp('^$key\\s*:\\s*([^\\n#]+)', multiLine: true);
  final Match? match = exp.firstMatch(text);
  if (match == null) {
    _fail('Missing `$key` in pubspec.');
  }
  return match.group(1)!.trim();
}

String _extractDependencyVersion(String text, String dependencyName) {
  final RegExp depsSection = RegExp(
    r'^dependencies:\s*\n((?:^[ \t]+.*\n?)*)',
    multiLine: true,
  );
  final Match? section = depsSection.firstMatch(text);
  if (section == null) {
    _fail('Missing `dependencies:` section in facade pubspec.');
  }
  final String depsBody = section.group(1)!;
  final RegExp depLine = RegExp(
    '^\\s*$dependencyName\\s*:\\s*([^\\n#]+)',
    multiLine: true,
  );
  final Match? dep = depLine.firstMatch(depsBody);
  if (dep == null) {
    _fail('Missing dependency `$dependencyName` in facade pubspec.');
  }
  return dep.group(1)!.trim();
}

Never _fail(String message) {
  stderr.writeln('Sync check failed: $message');
  exit(1);
}
