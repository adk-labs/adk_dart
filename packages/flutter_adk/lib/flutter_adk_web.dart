// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_adk_platform_interface.dart';

/// A web implementation of [FlutterAdkPlatform] for the `flutter_adk` plugin.
class FlutterAdkWeb extends FlutterAdkPlatform {
  /// Creates a [FlutterAdkWeb] platform implementation.
  FlutterAdkWeb();

  /// Registers this class as the active [FlutterAdkPlatform] implementation.
  static void registerWith(Registrar registrar) {
    FlutterAdkPlatform.instance = FlutterAdkWeb();
  }

  /// The browser user agent string for the current web platform.
  @override
  Future<String?> getPlatformVersion() async {
    final version = web.window.navigator.userAgent;
    return version;
  }
}
