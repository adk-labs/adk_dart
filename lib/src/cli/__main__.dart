/// Process entrypoint for launching the ADK CLI executable.
library;

import 'dart:io';

import 'cli_tools_click.dart' as cli_tools_click;

/// Delegates CLI argument handling to the shared ADK CLI entrypoint.
Future<void> main(List<String> args) async {
  exitCode = await cli_tools_click.main(args);
}
