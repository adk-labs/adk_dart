import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('computer use tool parity', () {
    test('normalizes coordinates and serializes ComputerState image', () async {
      final _FakeComputer computer = _FakeComputer();
      final ComputerUseTool tool = ComputerUseTool(
        name: 'click_at',
        func: ({required int x, required int y}) => computer.clickAt(x, y),
        screenSize: const (200, 100),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'x': 500, 'y': 500},
        toolContext: _toolContext(),
      );

      expect(computer.lastClick, (100, 50));
      expect(result, isA<Map>());
      final Map<String, Object?> payload = Map<String, Object?>.from(
        result as Map,
      );
      expect((payload['image'] as Map)['mimetype'], 'image/png');
      expect((payload['image'] as Map)['data'], base64Encode(<int>[1, 2, 3]));
      expect(payload['url'], 'https://example.com/page');
    });

    test('clamps coordinates and validates numeric arguments', () async {
      final _FakeComputer computer = _FakeComputer();
      final ComputerUseTool tool = ComputerUseTool(
        name: 'drag_and_drop',
        func:
            ({
              required int x,
              required int y,
              required int destination_x,
              required int destination_y,
            }) => computer.dragAndDrop(x, y, destination_x, destination_y),
        screenSize: const (100, 100),
      );

      await tool.run(
        args: <String, dynamic>{
          'x': 2000,
          'y': -5,
          'destination_x': -10,
          'destination_y': 1000,
        },
        toolContext: _toolContext(),
      );

      expect(computer.lastDrag, (99, 0, 0, 99));

      await expectLater(
        () => tool.run(
          args: <String, dynamic>{'x': 'bad', 'y': 0},
          toolContext: _toolContext(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('computer use toolset parity', () {
    test('initializes once and exposes expected tool names', () async {
      final _FakeComputer computer = _FakeComputer();
      final ComputerUseToolset toolset = ComputerUseToolset(computer: computer);

      final List<ComputerUseTool> first = await toolset.getTools();
      final List<ComputerUseTool> second = await toolset.getTools();

      expect(identical(first, second), isTrue);
      expect(computer.initializeCount, 1);
      expect(
        first.map((ComputerUseTool tool) => tool.name).toSet(),
        containsAll(<String>{
          'open_web_browser',
          'click_at',
          'hover_at',
          'type_text_at',
          'scroll_document',
          'scroll_at',
          'wait',
          'go_back',
          'go_forward',
          'search',
          'navigate',
          'key_combination',
          'drag_and_drop',
          'current_state',
        }),
      );
    });

    test('processLlmRequest appends tools and environment label', () async {
      final _FakeComputer computer = _FakeComputer();
      final ComputerUseToolset toolset = ComputerUseToolset(computer: computer);
      final LlmRequest request = LlmRequest();

      await toolset.processLlmRequest(
        toolContext: _toolContext(),
        llmRequest: request,
      );

      expect(request.toolsDict, isNotEmpty);
      expect(
        request.config.labels['adk_computer_use_environment'],
        ComputerEnvironment.environmentBrowser.name,
      );
    });

    test('adaptComputerUseTool swaps tool implementation and name', () async {
      final _FakeComputer computer = _FakeComputer();
      final ComputerUseToolset toolset = ComputerUseToolset(computer: computer);
      final LlmRequest request = LlmRequest();

      await toolset.processLlmRequest(
        toolContext: _toolContext(),
        llmRequest: request,
      );

      await ComputerUseToolset.adaptComputerUseTool(
        methodName: 'wait',
        adapterFunc: (Function original) {
          return ComputerUseToolAdapter(
            name: 'wait_fast',
            func: ({required int seconds}) => original(seconds: 1),
          );
        },
        llmRequest: request,
      );

      expect(request.toolsDict.containsKey('wait'), isFalse);
      expect(request.toolsDict.containsKey('wait_fast'), isTrue);
      await request.toolsDict['wait_fast']!.run(
        args: <String, dynamic>{'seconds': 8},
        toolContext: _toolContext(),
      );
      expect(computer.lastWaitSeconds, 1);
    });
  });
}

class _FakeComputer extends BaseComputer {
  int initializeCount = 0;
  (int, int)? lastClick;
  (int, int, int, int)? lastDrag;
  int? lastWaitSeconds;

  @override
  Future<ComputerState> clickAt(int x, int y) async {
    lastClick = (x, y);
    return ComputerState(
      screenshot: <int>[1, 2, 3],
      url: 'https://example.com/page',
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<ComputerState> currentState() async {
    return ComputerState(
      screenshot: <int>[9, 9, 9],
      url: 'https://example.com/state',
    );
  }

  @override
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) async {
    lastDrag = (x, y, destinationX, destinationY);
    return ComputerState(screenshot: <int>[4], url: 'https://example.com/drag');
  }

  @override
  Future<ComputerEnvironment> environment() async {
    return ComputerEnvironment.environmentBrowser;
  }

  @override
  Future<ComputerState> goBack() async => ComputerState();

  @override
  Future<ComputerState> goForward() async => ComputerState();

  @override
  Future<ComputerState> hoverAt(int x, int y) async => ComputerState();

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<ComputerState> keyCombination(List<String> keys) async {
    return ComputerState();
  }

  @override
  Future<ComputerState> navigate(String url) async => ComputerState(url: url);

  @override
  Future<ComputerState> openWebBrowser() async {
    return ComputerState(url: 'https://example.com');
  }

  @override
  Future<(int, int)> screenSize() async => const (1920, 1080);

  @override
  Future<ComputerState> scrollAt(
    int x,
    int y,
    String direction,
    int magnitude,
  ) async {
    return ComputerState();
  }

  @override
  Future<ComputerState> scrollDocument(String direction) async {
    return ComputerState();
  }

  @override
  Future<ComputerState> search() async => ComputerState();

  @override
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) async {
    return ComputerState();
  }

  @override
  Future<ComputerState> wait(int seconds) async {
    lastWaitSeconds = seconds;
    return ComputerState();
  }
}

ToolContext _toolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: _FakeSessionService(),
    invocationId: 'invocation',
    agent: Agent(name: 'root', model: _NoopModel()),
    session: Session(id: 'session', appName: 'app', userId: 'user'),
  );
  return Context(invocationContext);
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _FakeSessionService extends BaseSessionService {
  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    return Session(
      id: sessionId ?? 'session',
      appName: appName,
      userId: userId,
      state: state,
    );
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {}

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    return null;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    return ListSessionsResponse();
  }
}
