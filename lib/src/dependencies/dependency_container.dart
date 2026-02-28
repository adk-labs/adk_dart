class DependencyContainer {
  final Map<Type, Object> _singletons = <Type, Object>{};
  final Map<Type, Object Function()> _factories = <Type, Object Function()>{};

  void registerSingleton<T extends Object>(T instance) {
    _singletons[T] = instance;
    _factories.remove(T);
  }

  void registerFactory<T extends Object>(T Function() factory) {
    _factories[T] = factory;
    _singletons.remove(T);
  }

  T resolve<T extends Object>() {
    final T? resolved = resolveOrNull<T>();
    if (resolved != null) {
      return resolved;
    }

    throw StateError('No dependency registered for type $T');
  }

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

    final Object? produced = factory();
    if (produced is T) {
      return produced;
    }
    if (produced == null) {
      throw StateError('Factory for type $T returned null.');
    }
    throw StateError('Factory for type $T returned ${produced.runtimeType}.');
  }

  bool unregister<T extends Object>() {
    final bool removedSingleton = _singletons.remove(T) != null;
    final bool removedFactory = _factories.remove(T) != null;
    return removedSingleton || removedFactory;
  }

  bool contains<T extends Object>() {
    return _singletons.containsKey(T) || _factories.containsKey(T);
  }

  void clear() {
    _singletons.clear();
    _factories.clear();
  }
}
