/// Mutable reference container used for shared in-memory state.
library;

/// Shared mutable holder for a single value of type [T].
class SharedValue<T> {
  /// Creates a shared value holder initialized with [value].
  SharedValue(this.value);

  /// The current stored value.
  T value;
}
