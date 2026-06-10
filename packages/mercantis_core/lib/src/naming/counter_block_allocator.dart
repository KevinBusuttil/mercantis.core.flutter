import 'package:sqflite_common/sqflite.dart';

/// Hands out monotonic counter values for naming series using per-device
/// **blocks** (ADR-042).
///
/// Each device reserves a disjoint block of [blockSize] values for a given
/// series (e.g. `SINV-2026-`) from a shared high-water mark, then consumes
/// values from that block locally. Because blocks never overlap, two devices
/// saving offline can't mint the same id; and because the high-water mark only
/// ever advances, a deleted document never frees its number for reuse (unlike
/// the old `COUNT(*)` approach).
///
/// Reservation + consumption run in a single transaction so concurrent saves
/// on one database stay correct.
class CounterBlockAllocator {
  final int blockSize;

  const CounterBlockAllocator({this.blockSize = 1000});

  /// Returns the next value for [series] reserved to [deviceId].
  ///
  /// [seedFloor] is consulted only the first time a block is reserved for a
  /// series (no allocation row yet); it lets callers start the counter above
  /// pre-existing data so a fresh counter can't mint an id that already exists.
  Future<int> next(
    Database db,
    String series,
    String deviceId, {
    Future<int> Function(DatabaseExecutor txn)? seedFloor,
  }) {
    return db.transaction<int>((txn) async {
      final blocks = await txn.query(
        'naming_counter_blocks',
        where: 'series = ? AND device_id = ?',
        whereArgs: [series, deviceId],
      );
      if (blocks.isNotEmpty) {
        final nextValue = blocks.first['next_value'] as int;
        final blockEnd = blocks.first['block_end'] as int;
        if (nextValue <= blockEnd) {
          await txn.update(
            'naming_counter_blocks',
            {'next_value': nextValue + 1},
            where: 'series = ? AND device_id = ?',
            whereArgs: [series, deviceId],
          );
          return nextValue;
        }
      }

      // No active block (or it is exhausted): reserve the next one by advancing
      // the shared high-water mark.
      final allocs = await txn.query(
        'naming_block_allocations',
        where: 'series = ?',
        whereArgs: [series],
      );
      final allocatedThrough = allocs.isEmpty
          ? (seedFloor == null ? 0 : await seedFloor(txn))
          : allocs.first['allocated_through'] as int;
      final blockStart = allocatedThrough + 1;
      final blockEnd = allocatedThrough + blockSize;

      if (allocs.isEmpty) {
        await txn.insert('naming_block_allocations',
            {'series': series, 'allocated_through': blockEnd});
      } else {
        await txn.update(
          'naming_block_allocations',
          {'allocated_through': blockEnd},
          where: 'series = ?',
          whereArgs: [series],
        );
      }

      await txn.insert(
        'naming_counter_blocks',
        {
          'series': series,
          'device_id': deviceId,
          'block_start': blockStart,
          'block_end': blockEnd,
          'next_value': blockStart + 1, // blockStart is consumed by this call
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return blockStart;
    });
  }

  /// The current high-water mark for [series] — the highest number reserved
  /// across all devices. Returns 0 when the series has minted nothing yet, so
  /// the next number handed out will be `peek + 1`. Read-only.
  Future<int> peek(Database db, String series) async {
    final rows = await db.query(
      'naming_block_allocations',
      columns: ['allocated_through'],
      where: 'series = ?',
      whereArgs: [series],
    );
    if (rows.isEmpty) return 0;
    return rows.first['allocated_through'] as int;
  }

  /// Force the next number minted for [series] to be [nextNumber]: sets the
  /// shared high-water mark to `nextNumber - 1` and clears any reserved
  /// per-device blocks so the following [next] reserves a fresh block starting
  /// at [nextNumber]. Use to seed a migrated legacy sequence or reset a series
  /// at year start. [nextNumber] must be >= 1.
  ///
  /// Lowering the counter below ids already issued can mint duplicates; callers
  /// own that decision.
  Future<void> setNextNumber(Database db, String series, int nextNumber) {
    if (nextNumber < 1) {
      throw ArgumentError.value(nextNumber, 'nextNumber', 'must be >= 1');
    }
    final through = nextNumber - 1;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'naming_block_allocations',
        where: 'series = ?',
        whereArgs: [series],
      );
      if (existing.isEmpty) {
        await txn.insert('naming_block_allocations',
            {'series': series, 'allocated_through': through});
      } else {
        await txn.update(
          'naming_block_allocations',
          {'allocated_through': through},
          where: 'series = ?',
          whereArgs: [series],
        );
      }
      // Drop reserved blocks so every device re-reserves from the new mark.
      await txn.delete('naming_counter_blocks',
          where: 'series = ?', whereArgs: [series]);
    });
  }
}
