import 'dart:io';

import 'package:path/path.dart' as p;

/// The `dart` executable for spawning fault-injection child processes.
///
/// Under `dart test` that is the running VM, but under `flutter test` the
/// running executable is `flutter_tester`, which cannot `run` a script (the
/// child hangs). Fall back to the SDK beside FLUTTER_ROOT, then to PATH.
String dartExecutable() {
  final current = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(current) == 'dart') return current;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart =
        p.join(flutterRoot, 'bin', Platform.isWindows ? 'dart.bat' : 'dart');
    if (File(dart).existsSync()) return dart;
  }
  return 'dart';
}
