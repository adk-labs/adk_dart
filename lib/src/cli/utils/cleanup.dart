import 'dart:async';

import '../../runners/runner.dart';

Future<void> closeRunners(
  List<Runner> runners, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final List<Future<void>> closeFutures = runners
      .map((Runner runner) => runner.close())
      .toList(growable: false);
  if (closeFutures.isEmpty) {
    return;
  }

  await Future.any<Object>(<Future<Object>>[
    Future.wait<void>(closeFutures).then<Object>((_) => Object()),
    Future<void>.delayed(timeout).then<Object>((_) => Object()),
  ]);
}
