import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// No Windows não há sqlite3.dll no sistema. Usa a de `SQLITE3_DLL` ou a
/// que vem com o Python (tem FTS5 e JSON1).
void setUpSqlite() {
  if (!Platform.isWindows) return;
  final candidates = [
    Platform.environment['SQLITE3_DLL'],
    r'C:\Python313\DLLs\sqlite3.dll',
    r'C:\Python312\DLLs\sqlite3.dll',
    r'C:\Python311\DLLs\sqlite3.dll',
  ].whereType<String>();
  for (final path in candidates) {
    if (File(path).existsSync()) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(path));
      return;
    }
  }
}
