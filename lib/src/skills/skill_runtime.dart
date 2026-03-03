/// Conditional runtime export for IO and web skill implementations.
library;

export 'skill_web.dart' if (dart.library.io) 'skill.dart';
