import 'package:flutter/material.dart';

class AppRouter {
  const AppRouter._();

  static Future<void> push(BuildContext context, Widget page) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }
}
