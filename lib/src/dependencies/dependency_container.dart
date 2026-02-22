class DependencyContainer {
  final Map<Type, Object> _singletons = <Type, Object>{};
  final Map<Type, Object Function()> _factories = <Type, Object Function()>{};

  void registerSingleton<T extends Object>(T instance) {
    _singletons[T] = instance;
  }

  void registerFactory<T extends Object>(T Function() factory) {
    _factories[T] = factory;
  }

  T resolve<T extends Object>() {
    final Object? singleton = _singletons[T];
    if (singleton != null) {
      return singleton as T;
    }

    final Object Function()? factory = _factories[T];
    if (factory != null) {
      return factory() as T;
    }

    throw StateError('No dependency registered for type $T');
  }

  bool contains<T extends Object>() {
    return _singletons.containsKey(T) || _factories.containsKey(T);
  }
}
