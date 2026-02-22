import 'dart:io';

import 'package:adk_dart/src/dev/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runAdkCli(args);
}
