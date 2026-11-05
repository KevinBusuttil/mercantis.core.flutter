import 'dart:io';

import 'package:sqflite_common/sqflite.dart';

import '../document_engine/document_engine_error.dart';

/// What to tell the operator when a save, submit or other storage action
/// fails. Raw SQLite text ("DatabaseException(database or disk is full
/// (code 13 SQLITE_FULL)) sql 'INSERT …' args […]") is never shown: it is
/// meaningless to the operator and can echo the record's values.
///
/// Returns null when [error] is not a storage failure, so callers can fall
/// back to their own message.
String? storageErrorText(Object error) {
  final text = error is DatabaseException
      ? error.toString()
      : error is FileSystemException
          ? '${error.osError?.message} ${error.osError?.errorCode} ${error.message}'
          : null;
  if (text == null) return null;
  final t = text.toLowerCase();
  final code = error is FileSystemException ? error.osError?.errorCode : null;
  // The caller may have stored part of a multi-step action before the
  // failure (a file write after a database write, an export after a
  // posting), so no message promises that nothing was saved: each one asks
  // the operator to check before trying again.
  if (t.contains('sqlite_full') ||
      t.contains('disk is full') ||
      t.contains('no space') ||
      code == 28 ||
      code == 112) {
    return 'This device is out of storage space, so the change may not have '
        'been saved. Free some space (photos, videos, unused apps), then '
        'check the record before trying again. Records saved earlier are '
        'not affected.';
  }
  if (t.contains('readonly') ||
      t.contains('read-only') ||
      t.contains('sqlite_perm')) {
    return 'Atlas cannot write to its data on this device, so the change may '
        'not have been saved. Restart Atlas and check the record before '
        'trying again. If this continues, contact support from Help & '
        'diagnostics.';
  }
  if (t.contains('sqlite_corrupt') ||
      t.contains('malformed') ||
      t.contains('sqlite_notadb')) {
    return 'Atlas found a problem reading its data, so the change may not '
        'have been saved. Do not reinstall. Open Help & diagnostics and '
        'contact support; your latest backup can restore the books.';
  }
  if (t.contains('sqlite_busy') || t.contains('database is locked')) {
    return 'Atlas was busy finishing another change, so this change may not '
        'have been saved. Check the record, then try again in a moment.';
  }
  if (t.contains('sqlite_ioerr') || t.contains('disk i/o')) {
    return 'The device could not write the data, so the change may not have '
        'been saved. Check free space and the record, then try again.';
  }
  return 'The change could not be stored completely. Check the record before '
      'trying again. If this continues, contact support from Help & '
      'diagnostics.';
}

/// The message for any error shown to an operator: the engine's own
/// explanation, a plain storage message, or the error text.
String operatorErrorText(Object error) {
  if (error is DocumentEngineError) return error.humanMessage;
  return storageErrorText(error) ?? error.toString();
}
