import 'flutter_adk_platform_interface.dart';
export 'package:adk_dart/adk_core.dart' hide State;

class FlutterAdk {
  Future<String?> getPlatformVersion() {
    return FlutterAdkPlatform.instance.getPlatformVersion();
  }
}
