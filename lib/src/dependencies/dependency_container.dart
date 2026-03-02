/// Simple dependency container for singleton and factory registrations.
library;

/// Runtime dependency container keyed by type.
class DependencyContainer {
  final Map<Type, Object> _singletons = <Type, Object>{};
  final Map<Type, Object Function()> _factories = <Type, Object Function()>{};

  /// Registers [instance] as singleton for type [T].
  void registerSingleton<T extends Object>(T instance) {
    _singletons[T] = instance;
    _factories.remove(T);
  }

  /// Registers a factory for type [T].
  void registerFactory<T extends Object>(T Function() factory) {
    _factories[T] = factory;
    _singletons.remove(T);
  }

  /// Resolves dependency [T] or throws when missing.
  T resolve<T extends Object>() {
    final T? resolved = resolveOrNull<T>();
    if (resolved != null) {
      return resolved;
    }

    throw StateError('No dependency registered for type $T');
  }

  /// Resolves dependency [T] or returns `null` when missing.
  T? resolveOrNull<T extends Object>() {
    final Object? singleton = _singletons[T];
    if (singleton != null) {
      if (singleton is T) {
        return singleton;
      }
      throw StateError(
        'Registered singleton for type $T has runtime type '
        '${singleton.runtimeType}.',
      );
    }

    final Object Function()? factory = _factories[T];
    if (factory == null) {
      return null;
    }

    final Object produced = factory();
    if (produced is T) {
      return produced;
    }
    throw StateError('Factory for type $T returned ${produced.runtimeType}.');
  }

  /// Unregisters singleton/factory for type [T].
  bool unregister<T extends Object>() {
    final bool removedSingleton = _singletons.remove(T) != null;
    final bool removedFactory = _factories.remove(T) != null;
    return removedSingleton || removedFactory;
  }

  /// Whether a dependency for type [T] is registered.
  bool contains<T extends Object>() {
    return _singletons.containsKey(T) || _factories.containsKey(T);
  }

  /// Clears all registrations.
  void clear() {
    _singletons.clear();
    _factories.clear();
  }
}
