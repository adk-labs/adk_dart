import 'dart:io';

import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/plugins/base_plugin.dart';
import 'package:adk_dart/src/types/content.dart';

class DynamicExtraPlugin extends BasePlugin {
  DynamicExtraPlugin({
    super.name = 'dynamic_extra_plugin',
    String? baseDir,
    String? pluginSpec,
  }) : _baseDir = baseDir ?? Directory.current.path,
       _pluginSpec = pluginSpec;

  final String _baseDir;
  final String? _pluginSpec;

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final File marker = File(
      '$_baseDir${Platform.pathSeparator}.dynamic_extra_plugin_marker',
    );
    await marker.writeAsString(
      'loaded:${_pluginSpec ?? ''}:${invocationContext.invocationId}',
      flush: true,
    );
    return null;
  }
}
