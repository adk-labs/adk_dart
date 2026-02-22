import 'dart:io';

import 'package:adk/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runAdkCli(args);
}
