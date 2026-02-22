import 'dart:io';

void main() {
  final File rootPubspec = File('pubspec.yaml');
  final File facadePubspec = File('packages/adk/pubspec.yaml');

  if (!rootPubspec.existsSync()) {
    _fail('Missing root pubspec.yaml');
  }
  if (!facadePubspec.existsSync()) {
    _fail('Missing packages/adk/pubspec.yaml');
  }

  final String rootText = rootPubspec.readAsStringSync();
  final String rootVersion = _extractScalar(rootText, 'version');
  String facadeText = facadePubspec.readAsStringSync();

  facadeText = _replaceScalar(facadeText, 'version', rootVersion);
  facadeText = _replaceDependency(facadeText, 'adk_dart', rootVersion);

  facadePubspec.writeAsStringSync(facadeText);
  stdout.writeln(
    'Synchronized packages/adk version and adk_dart dependency to $rootVersion',
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

String _replaceScalar(String text, String key, String value) {
  final RegExp exp = RegExp('^$key\\s*:\\s*([^\\n#]+)', multiLine: true);
  if (!exp.hasMatch(text)) {
    _fail('Missing `$key` in facade pubspec.');
  }
  return text.replaceFirstMapped(exp, (Match match) {
    final String oldValue = match.group(1)!;
    return match.group(0)!.replaceFirst(oldValue, value);
  });
}

String _replaceDependency(String text, String dependencyName, String version) {
  final RegExp exp = RegExp(
    '^([ \\t]*$dependencyName\\s*:\\s*)([^\\n#]+)',
    multiLine: true,
  );
  if (!exp.hasMatch(text)) {
    _fail('Missing dependency `$dependencyName` in facade pubspec.');
  }
  return text.replaceFirstMapped(exp, (Match match) {
    return '${match.group(1)}$version';
  });
}

Never _fail(String message) {
  stderr.writeln('Sync failed: $message');
  exit(1);
}
