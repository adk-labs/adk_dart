import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  group('built_in_agents assets parity', () {
    test('all python baseline files are bundled and non-empty', () async {
      final Directory packageRoot = await _packageRoot();
      const List<String> expected = <String>[
        'lib/src/cli/built_in_agents/README.md',
        'lib/src/cli/built_in_agents/__init__.py',
        'lib/src/cli/built_in_agents/adk_agent_builder_assistant.py',
        'lib/src/cli/built_in_agents/agent.py',
        'lib/src/cli/built_in_agents/instruction_embedded.template',
        'lib/src/cli/built_in_agents/sub_agents/__init__.py',
        'lib/src/cli/built_in_agents/sub_agents/google_search_agent.py',
        'lib/src/cli/built_in_agents/sub_agents/url_context_agent.py',
        'lib/src/cli/built_in_agents/tools/__init__.py',
        'lib/src/cli/built_in_agents/tools/cleanup_unused_files.py',
        'lib/src/cli/built_in_agents/tools/delete_files.py',
        'lib/src/cli/built_in_agents/tools/explore_project.py',
        'lib/src/cli/built_in_agents/tools/query_schema.py',
        'lib/src/cli/built_in_agents/tools/read_config_files.py',
        'lib/src/cli/built_in_agents/tools/read_files.py',
        'lib/src/cli/built_in_agents/tools/search_adk_knowledge.py',
        'lib/src/cli/built_in_agents/tools/search_adk_source.py',
        'lib/src/cli/built_in_agents/tools/write_config_files.py',
        'lib/src/cli/built_in_agents/tools/write_files.py',
        'lib/src/cli/built_in_agents/utils/__init__.py',
        'lib/src/cli/built_in_agents/utils/adk_source_utils.py',
        'lib/src/cli/built_in_agents/utils/path_normalizer.py',
        'lib/src/cli/built_in_agents/utils/resolve_root_directory.py',
      ];

      for (final String relativePath in expected) {
        final File file = File(_join(packageRoot.path, relativePath));
        expect(file.existsSync(), isTrue, reason: '$relativePath must exist');
        expect(
          file.lengthSync(),
          greaterThan(0),
          reason: '$relativePath must be non-empty',
        );
      }
    });

    test(
      'embedded instruction template contains callback/tool snippets',
      () async {
        final Directory packageRoot = await _packageRoot();
        final File template = File(
          _join(
            packageRoot.path,
            'lib/src/cli/built_in_agents/instruction_embedded.template',
          ),
        );
        final String content = template.readAsStringSync();
        expect(content, contains('content_filter_callback'));
        expect(content, contains('log_model_request'));
        expect(content, contains('validate_tool_input'));
      },
    );
  });
}

Future<Directory> _packageRoot() async {
  final Uri? libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:adk_dart/adk_dart.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Unable to resolve package:adk_dart/adk_dart.dart');
  }
  return File.fromUri(libraryUri).parent.parent;
}

String _join(String root, String relativePath) =>
    relativePath.split('/').fold(root, (String path, String segment) {
      return '$path${Platform.pathSeparator}$segment';
    });
