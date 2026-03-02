import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_adk_method_channel.dart';

/// Defines the platform interface contract for the `flutter_adk` plugin.
abstract class FlutterAdkPlatform extends PlatformInterface {
  /// Creates a platform interface protected by a verification token.
  FlutterAdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAdkPlatform _instance = MethodChannelFlutterAdk();

  /// The default instance of [FlutterAdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAdk].
  static FlutterAdkPlatform get instance => _instance;

  /// Sets the active platform implementation.
  ///
  /// Platform plugins should set this to their implementation of
  /// [FlutterAdkPlatform] during registration.
  static set instance(FlutterAdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// The platform version reported by this implementation.
  ///
  /// Throws an [UnimplementedError] when a platform plugin does not override
  /// this method.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
