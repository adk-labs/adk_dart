import 'dart:io';

import 'cli_tools_click.dart' as cli_tools_click;

Future<void> main(List<String> args) async {
  exitCode = await cli_tools_click.main(args);
}
