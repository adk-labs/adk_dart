import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_adk_method_channel.dart';

abstract class FlutterAdkPlatform extends PlatformInterface {
  /// Constructs a FlutterAdkPlatform.
  FlutterAdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAdkPlatform _instance = MethodChannelFlutterAdk();

  /// The default instance of [FlutterAdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAdk].
  static FlutterAdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterAdkPlatform] when
  /// they register themselves.
  static set instance(FlutterAdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
