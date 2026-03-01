import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_adk/flutter_adk_platform_interface.dart';
import 'package:flutter_adk/flutter_adk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterAdkPlatform
    with MockPlatformInterfaceMixin
    implements FlutterAdkPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterAdkPlatform initialPlatform = FlutterAdkPlatform.instance;

  test('$MethodChannelFlutterAdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterAdk>());
  });

  test('getPlatformVersion', () async {
    FlutterAdk flutterAdkPlugin = FlutterAdk();
    MockFlutterAdkPlatform fakePlatform = MockFlutterAdkPlatform();
    FlutterAdkPlatform.instance = fakePlatform;

    expect(await flutterAdkPlugin.getPlatformVersion(), '42');
  });

  test('exports adk_core symbols', () {
    final Session session = Session(
      id: 'session_1',
      appName: 'app',
      userId: 'u',
    );
    final InMemorySessionService sessions = InMemorySessionService();
    expect(session.id, 'session_1');
    expect(sessions.runtimeType, InMemorySessionService);
  });
}
