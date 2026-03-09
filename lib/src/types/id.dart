/// Helpers for generating ADK-scoped unique identifiers.
library;

import '../platform/uuid.dart';

/// Returns a new identifier prefixed by [prefix].
String newAdkId({String prefix = ''}) => '$prefix${newUuid()}';
