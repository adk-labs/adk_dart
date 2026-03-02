import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_adk_platform_interface.dart';

/// An implementation of [FlutterAdkPlatform] that uses method channels.
class MethodChannelFlutterAdk extends FlutterAdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_adk');

  /// The platform version returned by the method channel implementation.
  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
