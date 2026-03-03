/// Supported runtime environments for computer-use tools.
enum ComputerEnvironment {
  /// Unspecified environment.
  environmentUnspecified,

  /// Browser-based environment.
  environmentBrowser,
}

/// Snapshot of computer state returned by computer-use operations.
class ComputerState {
  /// Creates a computer state snapshot.
  ComputerState({List<int>? screenshot, this.url})
    : screenshot = screenshot ?? <int>[];

  /// Screenshot bytes for the current state.
  List<int> screenshot;

  /// Current page URL when available.
  String? url;

  /// Encodes this state snapshot for transport.
  Map<String, Object?> toJson() => <String, Object?>{
    'screenshot': List<int>.from(screenshot),
    'url': url,
  };
}

/// Interface implemented by platform-specific computer control backends.
abstract class BaseComputer {
  /// Returns the current screen size `(width, height)`.
  Future<(int, int)> screenSize();

  /// Opens a web browser and returns updated state.
  Future<ComputerState> openWebBrowser();

  /// Clicks at `(x, y)` and returns updated state.
  Future<ComputerState> clickAt(int x, int y);

  /// Hovers at `(x, y)` and returns updated state.
  Future<ComputerState> hoverAt(int x, int y);

  /// Types [text] at `(x, y)` and returns updated state.
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  });

  /// Scrolls the document in [direction] and returns updated state.
  Future<ComputerState> scrollDocument(String direction);

  /// Scrolls at `(x, y)` in [direction] with [magnitude].
  Future<ComputerState> scrollAt(int x, int y, String direction, int magnitude);

  /// Waits for [seconds] and returns updated state.
  Future<ComputerState> wait(int seconds);

  /// Navigates backward and returns updated state.
  Future<ComputerState> goBack();

  /// Navigates forward and returns updated state.
  Future<ComputerState> goForward();

  /// Focuses browser search UI and returns updated state.
  Future<ComputerState> search();

  /// Navigates to [url] and returns updated state.
  Future<ComputerState> navigate(String url);

  /// Sends a key combination and returns updated state.
  Future<ComputerState> keyCombination(List<String> keys);

  /// Drags from `(x, y)` to `(destinationX, destinationY)`.
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  );

  /// Returns the current computer state.
  Future<ComputerState> currentState();

  /// Initializes backend resources.
  Future<void> initialize() async {}

  /// Releases backend resources.
  Future<void> close() async {}

  /// Returns the backend environment type.
  Future<ComputerEnvironment> environment();
}
