// ignore_for_file: non_constant_identifier_names

/// Toolset that adapts base computer interfaces into ADK tools.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../tool_context.dart';
import 'base_computer.dart';
import 'computer_use_tool.dart';

/// Base-computer methods that are intentionally excluded from tool adaptation.
const Set<String> excludedComputerMethods = <String>{
  'screen_size',
  'environment',
  'close',
  'prepare',
};

const Set<String> _allowedUrlSchemes = <String>{'http', 'https'};

const Set<String> _blockedHostnames = <String>{
  'localhost',
  'metadata',
  'metadata.goog',
};

const List<String> _blockedHostnameSuffixes = <String>[
  '.localhost',
  '.local',
  '.internal',
  '.metadata.goog',
];

const Map<String, List<String>> _legacyToModernMap = <String, List<String>>{
  'click_at': <String>['click'],
  'hover_at': <String>['move'],
  'type_text_at': <String>['type'],
  'scroll_at': <String>['scroll'],
  'scroll_document': <String>['scroll'],
  'current_state': <String>['take_screenshot'],
  'key_combination': <String>['press_key', 'hotkey'],
};

const Map<String, List<String>> _modernToLegacyMap = <String, List<String>>{
  'click': <String>['click_at'],
  'move': <String>['hover_at'],
  'type': <String>['type_text_at'],
  'scroll': <String>['scroll_at', 'scroll_document'],
  'take_screenshot': <String>['current_state'],
  'press_key': <String>['key_combination'],
  'hotkey': <String>['key_combination'],
};

bool _isModernGeminiModel(String? modelName) {
  if (modelName == null || modelName.isEmpty) {
    return false;
  }
  final RegExpMatch? match = RegExp(
    r'gemini-(\d+)(?:\.(\d+))?',
    caseSensitive: false,
  ).firstMatch(modelName);
  if (match == null) {
    return false;
  }
  final int major = int.tryParse(match.group(1) ?? '') ?? 0;
  return major >= 3;
}

bool _isNonPublicIpAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final Uint8List raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && raw.length == 4) {
    final int b0 = raw[0];
    final int b1 = raw[1];
    final int b2 = raw[2];
    // 0.0.0.0/8 (unspecified / this network)
    if (b0 == 0) {
      return true;
    }
    // 10.0.0.0/8 (private)
    if (b0 == 10) {
      return true;
    }
    // 100.64.0.0/10 (carrier-grade NAT / shared address space)
    if (b0 == 100 && (b1 & 0xC0) == 64) {
      return true;
    }
    // 127.0.0.0/8 (loopback)
    if (b0 == 127) {
      return true;
    }
    // 169.254.0.0/16 (link-local / cloud metadata)
    if (b0 == 169 && b1 == 254) {
      return true;
    }
    // 172.16.0.0/12 (private)
    if (b0 == 172 && b1 >= 16 && b1 <= 31) {
      return true;
    }
    // 192.0.0.0/24 (IETF protocol assignments)
    if (b0 == 192 && b1 == 0 && b2 == 0) {
      return true;
    }
    // 192.0.2.0/24 (TEST-NET-1)
    if (b0 == 192 && b1 == 0 && b2 == 2) {
      return true;
    }
    // 192.168.0.0/16 (private)
    if (b0 == 192 && b1 == 168) {
      return true;
    }
    // 198.18.0.0/15 (benchmarking)
    if (b0 == 198 && (b1 == 18 || b1 == 19)) {
      return true;
    }
    // 198.51.100.0/24 (TEST-NET-2)
    if (b0 == 198 && b1 == 51 && b2 == 100) {
      return true;
    }
    // 203.0.113.0/24 (TEST-NET-3)
    if (b0 == 203 && b1 == 0 && b2 == 113) {
      return true;
    }
    // 224.0.0.0/4 (multicast) and 240.0.0.0/4 (reserved / broadcast)
    if (b0 >= 224) {
      return true;
    }
    return false;
  }
  if (address.type == InternetAddressType.IPv6 && raw.length == 16) {
    // Unspecified ::
    final bool allZero = raw.every((int byte) => byte == 0);
    if (allZero) {
      return true;
    }
    // Unique local fc00::/7
    if ((raw[0] & 0xFE) == 0xFC) {
      return true;
    }
    // Site-local fec0::/10 or link-local fe80::/10
    if (raw[0] == 0xFE && (raw[1] & 0xC0) >= 0x80) {
      return true;
    }
    // IPv4-mapped ::ffff:a.b.c.d or IPv4-compatible ::a.b.c.d
    bool prefixZero = true;
    for (int i = 0; i < 10; i += 1) {
      if (raw[i] != 0) {
        prefixZero = false;
        break;
      }
    }
    if (prefixZero &&
        ((raw[10] == 0xFF && raw[11] == 0xFF) ||
            (raw[10] == 0 && raw[11] == 0))) {
      final InternetAddress mappedIpv4 = InternetAddress.fromRawAddress(
        Uint8List.fromList(raw.sublist(12, 16)),
        type: InternetAddressType.IPv4,
      );
      return _isNonPublicIpAddress(mappedIpv4);
    }
    // Teredo 2001:0000::/32 or documentation 2001:db8::/32
    if (raw[0] == 0x20 && raw[1] == 0x01) {
      if (raw[2] == 0x00 && raw[3] == 0x00) {
        return true;
      }
      if (raw[2] == 0x0D && raw[3] == 0xB8) {
        return true;
      }
    }
  }
  return false;
}

InternetAddress? _tryParseNonStandardIpv4(String host) {
  // Handle hex/octal/integer IPv4 forms like 0x7f000001 or 2130706433.
  final List<String> parts = host.split('.');
  if (parts.isEmpty || parts.length > 4) {
    return null;
  }
  final List<int> parsedParts = <int>[];
  for (final String part in parts) {
    if (part.isEmpty) {
      return null;
    }
    int? value;
    if (part.startsWith('0x') || part.startsWith('0X')) {
      value = int.tryParse(part.substring(2), radix: 16);
    } else if (part.length > 1 && part.startsWith('0')) {
      value = int.tryParse(part.substring(1), radix: 8);
    } else {
      value = int.tryParse(part, radix: 10);
    }
    if (value == null || value < 0) {
      return null;
    }
    parsedParts.add(value);
  }
  int ipv4Int = 0;
  if (parsedParts.length == 1) {
    if (parsedParts[0] > 0xFFFFFFFF) {
      return null;
    }
    ipv4Int = parsedParts[0];
  } else if (parsedParts.length == 2) {
    if (parsedParts[0] > 0xFF || parsedParts[1] > 0xFFFFFF) {
      return null;
    }
    ipv4Int = (parsedParts[0] << 24) | parsedParts[1];
  } else if (parsedParts.length == 3) {
    if (parsedParts[0] > 0xFF ||
        parsedParts[1] > 0xFF ||
        parsedParts[2] > 0xFFFF) {
      return null;
    }
    ipv4Int = (parsedParts[0] << 24) | (parsedParts[1] << 16) | parsedParts[2];
  } else {
    if (parsedParts.any((int p) => p > 0xFF)) {
      return null;
    }
    ipv4Int =
        (parsedParts[0] << 24) |
        (parsedParts[1] << 16) |
        (parsedParts[2] << 8) |
        parsedParts[3];
  }
  return InternetAddress.fromRawAddress(
    Uint8List.fromList(<int>[
      (ipv4Int >> 24) & 0xFF,
      (ipv4Int >> 16) & 0xFF,
      (ipv4Int >> 8) & 0xFF,
      ipv4Int & 0xFF,
    ]),
    type: InternetAddressType.IPv4,
  );
}

Future<bool> _isSafeUrl(String url, {bool allowPrivateNetwork = false}) async {
  // Reject backslashes in the scheme or authority section.
  final int schemeEnd = url.indexOf('://');
  if (schemeEnd <= 0) {
    return false;
  }
  final String afterScheme = url.substring(schemeEnd + 3);
  final int authorityEnd = afterScheme.indexOf(RegExp(r'[/?#]'));
  final String rawAuthority = authorityEnd < 0
      ? afterScheme
      : afterScheme.substring(0, authorityEnd);
  if (rawAuthority.contains(r'\') ||
      url.substring(0, schemeEnd).contains(r'\')) {
    return false;
  }

  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null) {
    return false;
  }
  if (!_allowedUrlSchemes.contains(parsed.scheme.toLowerCase())) {
    return false;
  }
  String hostname = parsed.host.toLowerCase();
  if (hostname.endsWith('.')) {
    hostname = hostname.substring(0, hostname.length - 1);
  }
  if (hostname.isEmpty) {
    return false;
  }
  if (allowPrivateNetwork) {
    return true;
  }

  if (_blockedHostnames.contains(hostname) ||
      _blockedHostnameSuffixes.any(
        (String suffix) => hostname.endsWith(suffix),
      )) {
    return false;
  }

  final InternetAddress? directIp =
      InternetAddress.tryParse(hostname) ?? _tryParseNonStandardIpv4(hostname);
  if (directIp != null) {
    return !_isNonPublicIpAddress(directIp);
  }

  try {
    final List<InternetAddress> resolved = await InternetAddress.lookup(
      hostname,
    );
    for (final InternetAddress addr in resolved) {
      if (_isNonPublicIpAddress(addr)) {
        return false;
      }
    }
  } on SocketException {
    // Could not resolve; let the browser handle the DNS error.
    return true;
  }

  return true;
}

(int?, int?) _resolveCoordinates(int? x, int? y, List<Object?>? coordinate) {
  if (coordinate != null &&
      coordinate.length == 2 &&
      coordinate[0] is num &&
      coordinate[1] is num) {
    return ((coordinate[0] as num).toInt(), (coordinate[1] as num).toInt());
  }
  return (x, y);
}

/// Adapter output used to replace generated computer-use tools.
class ComputerUseToolAdapter {
  /// Creates a computer-use tool adapter output.
  ComputerUseToolAdapter({required this.name, required this.func});

  /// Replacement tool name.
  final String name;

  /// Replacement tool function.
  final Function func;
}

/// Toolset that surfaces [BaseComputer] actions as ADK tools.
class ComputerUseToolset extends BaseToolset {
  /// Creates a computer-use toolset for [computer].
  ComputerUseToolset({
    required BaseComputer computer,
    List<String>? excludedPredefinedFunctions,
    this.allowPrivateNetworkAccess = false,
  }) : _computer = computer,
       _excludedPredefinedFunctions = <String>{...?excludedPredefinedFunctions},
       super();

  final BaseComputer _computer;
  final Set<String> _excludedPredefinedFunctions;

  /// Whether navigation to private, loopback, or link-local URLs is allowed.
  final bool allowPrivateNetworkAccess;

  /// Underlying [BaseComputer] instance managed by this toolset.
  BaseComputer get computer => _computer;

  bool _initialized = false;
  bool _closed = false;
  List<ComputerUseTool>? _tools;
  Future<void> _lock = Future<void>.value();
  Future<void> _execLock = Future<void>.value();

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _lock;
    _lock = next.future;
    try {
      await previous;
      return await action();
    } finally {
      next.complete();
    }
  }

  Future<T> _withExecLock<T>(Future<T> Function() action) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _execLock;
    _execLock = next.future;
    try {
      await previous;
      return await action();
    } finally {
      next.complete();
    }
  }

  Future<Object?> _executeSerialized(
    ToolContext toolContext,
    Future<Object?> Function() action,
  ) {
    return _withExecLock<Object?>(() async {
      await _computer.prepare(toolContext);
      return action();
    });
  }

  Future<void> _ensureInitializedUnlocked() async {
    if (_initialized) {
      return;
    }
    await _computer.initialize();
    _initialized = true;
    _closed = false;
  }

  /// Adapts one generated computer-use tool in [llmRequest].
  static Future<void> adaptComputerUseTool({
    required String methodName,
    required FutureOr<Object> Function(Function original) adapterFunc,
    required LlmRequest llmRequest,
  }) async {
    if (excludedComputerMethods.contains(methodName)) {
      developer.log(
        'Method $methodName is not a valid BaseComputer method.',
        name: 'adk_dart.computer_use',
      );
      return;
    }

    final BaseTool? rawTool = llmRequest.toolsDict[methodName];
    if (rawTool is! ComputerUseTool) {
      developer.log(
        'Method $methodName not found in toolsDict as ComputerUseTool.',
        name: 'adk_dart.computer_use',
      );
      return;
    }

    final Object adapted = await Future<Object>.value(
      adapterFunc(rawTool.func),
    );
    late final String newMethodName;
    late final Function adaptedFunc;

    if (adapted is ComputerUseToolAdapter) {
      newMethodName = adapted.name;
      adaptedFunc = adapted.func;
    } else if (adapted is Function) {
      newMethodName = methodName;
      adaptedFunc = adapted;
    } else {
      developer.log(
        'Adapter result for $methodName must be Function or ComputerUseToolAdapter.',
        name: 'adk_dart.computer_use',
      );
      return;
    }

    final ComputerUseTool adaptedTool = ComputerUseTool(
      name: newMethodName,
      func: adaptedFunc,
      screenSize: rawTool.screenSize,
      virtualScreenSize: rawTool.virtualScreenSize,
      executor: rawTool.executor,
    );
    llmRequest.toolsDict[newMethodName] = adaptedTool;
    if (newMethodName != methodName) {
      llmRequest.toolsDict.remove(methodName);
    }
  }

  /// Returns generated computer-use tools, initializing lazily.
  @override
  Future<List<ComputerUseTool>> getTools({
    ReadonlyContext? readonlyContext,
  }) async {
    return _withLock<List<ComputerUseTool>>(() async {
      if (_tools != null) {
        return _tools!;
      }

      await _ensureInitializedUnlocked();
      final (int, int) screenSize = await _computer.screenSize();

      _tools =
          <ComputerUseTool>[
                ComputerUseTool(
                  name: 'open_web_browser',
                  func: () => _computer.openWebBrowser(),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'click_at',
                  func: ({required int x, required int y}) =>
                      _computer.clickAt(x, y),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'hover_at',
                  func: ({required int x, required int y}) =>
                      _computer.hoverAt(x, y),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'type_text_at',
                  func:
                      ({
                        required int x,
                        required int y,
                        required String text,
                        bool press_enter = true,
                        bool clear_before_typing = true,
                      }) => _computer.typeTextAt(
                        x,
                        y,
                        text,
                        pressEnter: press_enter,
                        clearBeforeTyping: clear_before_typing,
                      ),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'type_text',
                  func: ({required String text, bool press_enter = false}) =>
                      _computer.typeText(text, pressEnter: press_enter),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'scroll_document',
                  func: ({required String direction}) =>
                      _computer.scrollDocument(direction),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'scroll_at',
                  func:
                      ({
                        required int x,
                        required int y,
                        required String direction,
                        required int magnitude,
                      }) => _computer.scrollAt(x, y, direction, magnitude),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'wait',
                  func: ({num seconds = 1}) =>
                      _computer.wait(math.max(0, seconds.ceil())),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'go_back',
                  func: () => _computer.goBack(),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'go_forward',
                  func: () => _computer.goForward(),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'search',
                  func: () => _computer.search(),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'navigate',
                  func: ({required String url}) async {
                    final bool safe = await _isSafeUrl(
                      url,
                      allowPrivateNetwork: allowPrivateNetworkAccess,
                    );
                    if (!safe) {
                      developer.log(
                        'Blocked navigation to disallowed URL: $url',
                        name: 'adk_dart.computer_use',
                      );
                      final ComputerState state = await _computer
                          .currentState();
                      return <String, Object?>{
                        'error':
                            'Navigation to private or internal network URL is not allowed.',
                        'url': state.url,
                      };
                    }
                    return _computer.navigate(url);
                  },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'key_combination',
                  func: ({required List<Object?> keys}) {
                    final List<String> normalized = keys
                        .map((Object? value) => '$value')
                        .toList(growable: false);
                    return _computer.keyCombination(normalized);
                  },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'drag_and_drop',
                  func:
                      ({
                        required int x,
                        required int y,
                        required int destination_x,
                        required int destination_y,
                      }) => _computer.dragAndDrop(
                        x,
                        y,
                        destination_x,
                        destination_y,
                      ),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'current_state',
                  func: () => _computer.currentState(),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                // Modern (Gemini 3.x) action tools.
                ComputerUseTool(
                  name: 'click',
                  func:
                      ({
                        int? x,
                        int? y,
                        List<Object?>? coordinate,
                        String button = 'left',
                        int count = 1,
                      }) {
                        final (int? rx, int? ry) = _resolveCoordinates(
                          x,
                          y,
                          coordinate,
                        );
                        if (rx == null || ry == null) {
                          throw ArgumentError(
                            "Either ('x', 'y') or 'coordinate' must be provided for click",
                          );
                        }
                        return _computer.clickAt(rx, ry);
                      },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'move',
                  func: ({int? x, int? y, List<Object?>? coordinate}) {
                    final (int? rx, int? ry) = _resolveCoordinates(
                      x,
                      y,
                      coordinate,
                    );
                    if (rx == null || ry == null) {
                      throw ArgumentError(
                        "Either ('x', 'y') or 'coordinate' must be provided for move",
                      );
                    }
                    return _computer.hoverAt(rx, ry);
                  },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'type',
                  func:
                      ({
                        required String text,
                        int? x,
                        int? y,
                        List<Object?>? coordinate,
                        bool press_enter = false,
                        bool clear_before_typing = false,
                      }) {
                        final (int? rx, int? ry) = _resolveCoordinates(
                          x,
                          y,
                          coordinate,
                        );
                        if (rx != null && ry != null) {
                          return _computer.typeTextAt(
                            rx,
                            ry,
                            text,
                            pressEnter: press_enter,
                            clearBeforeTyping: clear_before_typing,
                          );
                        }
                        return _computer.typeText(
                          text,
                          pressEnter: press_enter,
                        );
                      },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'scroll',
                  func:
                      ({
                        int? x,
                        int? y,
                        List<Object?>? coordinate,
                        String direction = 'down',
                        num amount = 3,
                      }) {
                        final (int? rx, int? ry) = _resolveCoordinates(
                          x,
                          y,
                          coordinate,
                        );
                        final int magnitude = math.max(
                          1,
                          (amount * 100).toInt(),
                        );
                        if (rx != null && ry != null) {
                          return _computer.scrollAt(
                            rx,
                            ry,
                            direction,
                            magnitude,
                          );
                        }
                        return _computer.scrollDocument(direction);
                      },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'take_screenshot',
                  func: () => _computer.currentState(),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'press_key',
                  func: ({required String key}) =>
                      _computer.keyCombination(<String>[key]),
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
                ComputerUseTool(
                  name: 'hotkey',
                  func: ({required List<Object?> keys}) {
                    final List<String> normalized = keys
                        .map((Object? value) => '$value')
                        .toList(growable: false);
                    return _computer.keyCombination(normalized);
                  },
                  screenSize: screenSize,
                  executor: _executeSerialized,
                ),
              ]
              .where(
                (ComputerUseTool tool) =>
                    !_excludedPredefinedFunctions.contains(tool.name),
              )
              .toList(growable: false);

      return _tools!;
    });
  }

  /// Closes the underlying computer backend.
  @override
  Future<void> close() async {
    await _withLock<void>(() async {
      if (_closed) {
        return;
      }
      try {
        await _computer.close();
      } finally {
        _closed = true;
        _initialized = false;
        _tools = null;
      }
    });
  }

  /// Injects computer-use tools and environment metadata into [llmRequest].
  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final List<ComputerUseTool> tools = await getTools();
    for (final ComputerUseTool tool in tools) {
      llmRequest.toolsDict[tool.name] = tool;
      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: llmRequest,
      );
    }

    final ComputerEnvironment environment = await _computer.environment();
    llmRequest.config.tools ??= <ToolDeclaration>[];
    if (!llmRequest.config.tools!.any(
      (ToolDeclaration tool) => tool.computerUse != null,
    )) {
      final bool isModern = _isModernGeminiModel(llmRequest.model);
      final Map<String, List<String>> mapping = isModern
          ? _legacyToModernMap
          : _modernToLegacyMap;
      final Set<String> mappedExclusions = <String>{};
      for (final String fn in _excludedPredefinedFunctions) {
        if (mapping.containsKey(fn)) {
          mappedExclusions.addAll(mapping[fn]!);
        } else {
          mappedExclusions.add(fn);
        }
      }

      llmRequest.config.tools!.add(
        ToolDeclaration(
          computerUse: <String, Object?>{
            'environment': _computerEnvironmentValue(environment),
            if (mappedExclusions.isNotEmpty)
              'excludedPredefinedFunctions': mappedExclusions.toList()..sort(),
          },
        ),
      );
    }
    llmRequest.config.labels['adk_computer_use_environment'] = environment.name;
  }
}

String _computerEnvironmentValue(ComputerEnvironment environment) {
  switch (environment) {
    case ComputerEnvironment.environmentBrowser:
      return 'ENVIRONMENT_BROWSER';
    case ComputerEnvironment.environmentUnspecified:
      return 'ENVIRONMENT_UNSPECIFIED';
  }
}
