import 'package:flutter/foundation.dart';

import '../widgets/adk_smart_form_view.dart';

/// A reactive controller for managing conversational form fields, auto-extraction, validation, and submission.
class AdkSmartFormController extends ChangeNotifier {
  /// Creates an [AdkSmartFormController].
  AdkSmartFormController({
    required List<AdkFormField> initialFields,
    this.onSubmitted,
  }) : _fields = <String, AdkFormField>{
          for (final AdkFormField f in initialFields) f.key: f,
        };

  final Map<String, AdkFormField> _fields;
  final ValueChanged<Map<String, String>>? onSubmitted;
  bool _isSubmitting = false;
  bool _isCompleted = false;
  String? _errorMessage;

  /// Unmodifiable list of current form fields.
  List<AdkFormField> get fields => List<AdkFormField>.unmodifiable(_fields.values);

  /// Map of field key to field model.
  Map<String, AdkFormField> get fieldMap => Map<String, AdkFormField>.unmodifiable(_fields);

  /// Number of fields with non-empty values.
  int get filledCount => _fields.values.where((AdkFormField f) => f.isFilled).length;

  /// Total number of fields.
  int get totalCount => _fields.length;

  /// Form completion progress ratio (0.0 to 1.0).
  double get progress => totalCount == 0 ? 1.0 : filledCount / totalCount;

  /// Whether all required fields are filled.
  bool get isReady => _fields.values.where((AdkFormField f) => f.isRequired).every((AdkFormField f) => f.isFilled);

  /// Whether the form is currently being submitted.
  bool get isSubmitting => _isSubmitting;

  /// Whether the form has been successfully submitted.
  bool get isCompleted => _isCompleted;

  /// Current validation or submission error.
  String? get errorMessage => _errorMessage;

  /// Updates the value of a specific field by key.
  void updateFieldValue(String key, String value) {
    if (_fields.containsKey(key)) {
      _fields[key] = _fields[key]!.copyWith(value: value);
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Bulk populates field values from an extracted Map (e.g. from tool arguments or JSON).
  void populateFromMap(Map<String, dynamic> map) {
    bool changed = false;
    for (final MapEntry<String, dynamic> entry in map.entries) {
      if (_fields.containsKey(entry.key) && entry.value != null) {
        _fields[entry.key] = _fields[entry.key]!.copyWith(value: entry.value.toString());
        changed = true;
      }
    }
    if (changed) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Validates the form and returns a list of missing required field keys.
  List<String> validate() {
    final List<String> missing = _fields.values
        .where((AdkFormField f) => f.isRequired && !f.isFilled)
        .map((AdkFormField f) => f.key)
        .toList();

    if (missing.isNotEmpty) {
      _errorMessage = 'Please complete all required fields (${missing.join(', ')}).';
    } else {
      _errorMessage = null;
    }
    notifyListeners();
    return missing;
  }

  /// Returns current form values as a Map.
  Map<String, String> getFormData() {
    final Map<String, String> data = <String, String>{};
    for (final AdkFormField f in _fields.values) {
      if (f.value != null) {
        data[f.key] = f.value!;
      }
    }
    return data;
  }

  /// Submits the form data if all required fields are satisfied.
  Future<bool> submit() async {
    final List<String> missing = validate();
    if (missing.isNotEmpty) return false;

    _isSubmitting = true;
    notifyListeners();

    try {
      final Map<String, String> data = getFormData();
      onSubmitted?.call(data);
      _isCompleted = true;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Resets all field values.
  void reset() {
    for (final String k in _fields.keys) {
      _fields[k] = _fields[k]!.copyWith(value: null);
    }
    _isSubmitting = false;
    _isCompleted = false;
    _errorMessage = null;
    notifyListeners();
  }
}
