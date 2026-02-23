enum ComputerEnvironment { environmentUnspecified, environmentBrowser }

class ComputerState {
  ComputerState({List<int>? screenshot, this.url})
    : screenshot = screenshot ?? <int>[];

  List<int> screenshot;
  String? url;

  Map<String, Object?> toJson() => <String, Object?>{
    'screenshot': List<int>.from(screenshot),
    'url': url,
  };
}

abstract class BaseComputer {
  Future<(int, int)> screenSize();

  Future<ComputerState> openWebBrowser();

  Future<ComputerState> clickAt(int x, int y);

  Future<ComputerState> hoverAt(int x, int y);

  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  });

  Future<ComputerState> scrollDocument(String direction);

  Future<ComputerState> scrollAt(int x, int y, String direction, int magnitude);

  Future<ComputerState> wait(int seconds);

  Future<ComputerState> goBack();

  Future<ComputerState> goForward();

  Future<ComputerState> search();

  Future<ComputerState> navigate(String url);

  Future<ComputerState> keyCombination(List<String> keys);

  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  );

  Future<ComputerState> currentState();

  Future<void> initialize() async {}

  Future<void> close() async {}

  Future<ComputerEnvironment> environment();
}
