/// Introspection and bypass helpers for `opentelemetry-instrumentation-google-genai`.
library;

import 'dart:async';

/// Module path where `opentelemetry-instrumentation-google-genai` wrapper
/// functions live across all releases.
const String genAiInstrumentorModulePath =
    'opentelemetry/instrumentation/google_genai';

/// The newest `opentelemetry-util-genai` release verified not to record the
/// `gen_ai.client.inference.*` token metrics.
///
/// The instrumentor `>= 1.0` records its metrics through `opentelemetry-util-genai`,
/// and `< 1.0` (which pins `util-genai < 0.4`) records none of these, so up to
/// this version ADK records them alongside it without double counting.
const String lastUtilGenAiWithoutInferenceTokenMetrics = '1.3b0';

/// Default context key used by `opentelemetry-util-genai >= 1.3b0` to detect
/// an enclosing client inference span.
const String defaultClientInferenceContextKey =
    'opentelemetry.util.genai.client_inference';

/// Marker value attached to the active context while ADK's own inference span
/// is open, mirroring `opentelemetry.util.genai.invocation.InferenceData`.
class GenAiClientInferenceData {
  /// Creates a client inference context marker.
  const GenAiClientInferenceData();
}

/// Callback signature for a `wrapt`-style proxy wrapper function.
typedef GenAiProxyWrapper =
    FutureOr<Object?> Function(
      GenAiCallable wrapped,
      Object? instance,
      List<Object?> positionalArgs,
      Map<Symbol, Object?> namedArgs,
    );

/// Callback signature for an underlying SDK function or plain wrapper body.
typedef GenAiBoundFunction =
    FutureOr<Object?> Function(
      Object? instance,
      List<Object?> positionalArgs,
      Map<Symbol, Object?> namedArgs,
    );

/// Base representation of a callable layer over a GenAI SDK `generateContent`
/// method.
abstract class GenAiCallable {
  /// Creates a callable layer.
  const GenAiCallable();

  /// Source file path associated with this callable's code object, if any.
  String? get codeFilename;

  /// The inner callable wrapped by this layer, or `null` for an unwrapped leaf.
  GenAiCallable? get wrapped;

  /// Invokes this callable with [positionalArgs] and [namedArgs].
  FutureOr<Object?> call([
    List<Object?> positionalArgs = const <Object?>[],
    Map<Symbol, Object?> namedArgs = const <Symbol, Object?>{},
  ]);

  /// Returns a view of this callable bound to [instance].
  GenAiCallable bindToInstance(Object? instance);
}

/// An unwrapped leaf SDK function (e.g. `Models.generate_content`).
class GenAiRawFunction extends GenAiCallable {
  /// Creates a leaf callable backed by [_fn].
  const GenAiRawFunction(
    this._fn, {
    this.codeFilename,
    this.instance,
  });

  final GenAiBoundFunction _fn;

  @override
  final String? codeFilename;

  /// Optional bound receiver instance.
  final Object? instance;

  @override
  GenAiCallable? get wrapped => null;

  @override
  FutureOr<Object?> call([
    List<Object?> positionalArgs = const <Object?>[],
    Map<Symbol, Object?> namedArgs = const <Symbol, Object?>{},
  ]) {
    return _fn(instance, positionalArgs, namedArgs);
  }

  @override
  GenAiCallable bindToInstance(Object? instance) {
    return GenAiRawFunction(
      _fn,
      codeFilename: codeFilename,
      instance: instance,
    );
  }
}

/// A plain function wrapper (analogous to `< 1.0` `functools.wraps` replacement
/// or an opaque plain foreign wrapper).
class GenAiPlainWrapper extends GenAiCallable {
  /// Creates a plain wrapper over [wrapped].
  const GenAiPlainWrapper({
    required this.invoke,
    this.wrapped,
    this.codeFilename,
    this.instance,
  });

  /// Wrapper implementation invoked when this layer is called.
  final FutureOr<Object?> Function(
    GenAiCallable? wrapped,
    Object? instance,
    List<Object?> positionalArgs,
    Map<Symbol, Object?> namedArgs,
  )
  invoke;

  @override
  final GenAiCallable? wrapped;

  @override
  final String? codeFilename;

  /// Bound receiver instance (analogous to `MethodType.__self__`).
  final Object? instance;

  @override
  FutureOr<Object?> call([
    List<Object?> positionalArgs = const <Object?>[],
    Map<Symbol, Object?> namedArgs = const <Symbol, Object?>{},
  ]) {
    return invoke(wrapped, instance, positionalArgs, namedArgs);
  }

  @override
  GenAiCallable bindToInstance(Object? instance) {
    return GenAiPlainWrapper(
      invoke: invoke,
      wrapped: wrapped,
      codeFilename: codeFilename,
      instance: instance,
    );
  }
}

/// A `wrapt`-style proxy wrapper (used by `opentelemetry-instrumentation-google-genai >= 1.0`
/// and third-party `wrapt` wrappers).
///
/// Just like `wrapt.FunctionWrapper`, [codeFilename] reports the wrapped
/// callable's [codeFilename], while [wrapperCodeFilename] identifies the
/// proxy's own `_self_wrapper` function.
class GenAiWraptProxy extends GenAiCallable {
  /// Creates a `wrapt`-style proxy wrapping [wrapped] with [selfWrapper].
  const GenAiWraptProxy({
    required this.wrapped,
    required this.selfWrapper,
    this.wrapperCodeFilename,
    this.selfInstance,
    this.exposeSelfWrapper = true,
  });

  @override
  final GenAiCallable wrapped;

  /// The proxy's `_self_wrapper` function.
  final GenAiProxyWrapper selfWrapper;

  /// Source file path of [selfWrapper] (i.e. `_self_wrapper.__code__.co_filename`).
  final String? wrapperCodeFilename;

  /// Optional bound receiver instance (i.e. `_self_instance`).
  final Object? selfInstance;

  /// Whether `_self_wrapper` is exposed for introspection (defaults to `true`).
  final bool exposeSelfWrapper;

  @override
  String? get codeFilename => wrapped.codeFilename;

  @override
  FutureOr<Object?> call([
    List<Object?> positionalArgs = const <Object?>[],
    Map<Symbol, Object?> namedArgs = const <Symbol, Object?>{},
  ]) {
    return selfWrapper(wrapped, selfInstance, positionalArgs, namedArgs);
  }

  @override
  GenAiCallable bindToInstance(Object? instance) {
    return GenAiWraptProxy(
      wrapped: wrapped.bindToInstance(instance),
      selfWrapper: selfWrapper,
      wrapperCodeFilename: wrapperCodeFilename,
      selfInstance: instance,
      exposeSelfWrapper: exposeSelfWrapper,
    );
  }
}

/// Returns `true` when [codeFilename] belongs to
/// `opentelemetry-instrumentation-google-genai`.
bool isGenAiInstrumentorCode(String? codeFilename) {
  if (codeFilename == null || codeFilename.isEmpty) {
    return false;
  }
  return codeFilename.replaceAll(r'\', '/').contains(genAiInstrumentorModulePath);
}

/// Returns `true` when [callable] is a layer added by
/// `opentelemetry-instrumentation-google-genai`.
///
/// For `wrapt` proxies (`>= 1.0`), inspects `_self_wrapper`'s code path rather
/// than the proxy's proxied `co_filename`, so both `1.0b0` (unstamped) and
/// foreign `wrapt` proxies stacked above `>= 1.0b1` (stamped) are classified
/// accurately. Falls back to [GenAiCallable.codeFilename] if `_self_wrapper`
/// is not exposed.
bool isGenAiInstrumentorLayer(GenAiCallable callable) {
  if (callable is GenAiWraptProxy && callable.exposeSelfWrapper) {
    return isGenAiInstrumentorCode(callable.wrapperCodeFilename);
  }
  return isGenAiInstrumentorCode(callable.codeFilename);
}

/// Returns `true` when [callable] has an
/// `opentelemetry-instrumentation-google-genai` layer anywhere in its wrapper
/// chain.
bool isGenAiInstrumentedCallable(GenAiCallable? callable) {
  GenAiCallable? current = callable;
  while (current != null && current.wrapped != null) {
    if (isGenAiInstrumentorLayer(current)) {
      return true;
    }
    current = current.wrapped;
  }
  return false;
}

/// Returns [method] with the `opentelemetry-instrumentation-google-genai` layer
/// removed, or [method] unchanged if no removable instrumentor layer is found.
///
/// Foreign `wrapt` proxy layers stacked above the instrumentor are preserved
/// and re-bound to invoke what lies beneath the instrumentor.
GenAiCallable withoutGenAiInstrumentor(GenAiCallable method) {
  final GenAiCallable? inner = method.wrapped;
  if (inner == null) {
    return method;
  }
  if (isGenAiInstrumentorLayer(method)) {
    if (method is GenAiPlainWrapper) {
      // < 1.0: a plain replacement wrapping the unbound SDK function or an
      // unbound wrapt proxy beneath it.
      return inner.bindToInstance(method.instance);
    }
    // >= 1.0: a bound wrapt proxy wrapping the bound SDK method.
    return inner;
  }
  final GenAiCallable beneath = withoutGenAiInstrumentor(inner);
  if (method is! GenAiWraptProxy ||
      !method.exposeSelfWrapper ||
      identical(beneath, inner)) {
    return method;
  }
  return GenAiWraptProxy(
    wrapped: beneath,
    selfWrapper: method.selfWrapper,
    wrapperCodeFilename: method.wrapperCodeFilename,
    selfInstance: method.selfInstance,
  );
}

String? _utilGenAiVersion;

/// Sets the simulated `opentelemetry-util-genai` package version for tests.
void setUtilGenAiVersionForTest(String? version) {
  _utilGenAiVersion = version;
}

/// Returns the simulated `opentelemetry-util-genai` package version, if set.
String? getUtilGenAiVersionForTest() => _utilGenAiVersion;

Object _clientInferenceContextKey = defaultClientInferenceContextKey;
Object Function() _clientInferenceDataFactory =
    () => const GenAiClientInferenceData();
bool _clientInferenceContextEnabled = true;

/// Returns the active context key used to mark ADK's enclosing inference span.
Object get currentClientInferenceContextKey => _clientInferenceContextKey;

/// Whether ADK's inference span marks the active context for
/// `opentelemetry-util-genai >= 1.3b0`.
bool get isUtilGenAiClientInferenceContextEnabled =>
    _clientInferenceContextEnabled;

/// Creates a new client inference context marker value.
Object createClientInferenceData() => _clientInferenceDataFactory();

/// Returns the client inference context value attached to the current [Zone],
/// or `null` when no ADK inference span is active.
Object? getCurrentClientInferenceContextValue([Object? contextKey]) {
  return Zone.current[contextKey ?? _clientInferenceContextKey];
}

/// Returns `true` when execution is currently inside an ADK inference span
/// that marked the context for `opentelemetry-util-genai >= 1.3b0`.
bool isInsideAdkInferenceSpan([Object? contextKey]) {
  return getCurrentClientInferenceContextValue(contextKey) != null;
}

/// Configures the `opentelemetry-util-genai` client inference context hook for
/// tests.
void setUtilGenAiClientInferenceContextHookForTest({
  Object? contextKey,
  Object Function()? createInferenceData,
  bool enabled = true,
}) {
  if (contextKey != null) {
    _clientInferenceContextKey = contextKey;
  }
  if (createInferenceData != null) {
    _clientInferenceDataFactory = createInferenceData;
  }
  _clientInferenceContextEnabled = enabled;
}

/// Restores the default `opentelemetry-util-genai` client inference context
/// hook.
void resetUtilGenAiClientInferenceContextHookForTest() {
  _clientInferenceContextKey = defaultClientInferenceContextKey;
  _clientInferenceDataFactory = () => const GenAiClientInferenceData();
  _clientInferenceContextEnabled = true;
}
