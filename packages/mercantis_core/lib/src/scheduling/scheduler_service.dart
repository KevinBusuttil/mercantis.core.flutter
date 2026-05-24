import 'dart:async';
import 'package:sqflite_common/sqflite.dart';
import 'scheduled_task.dart';
import 'cron_expression.dart';

class SchedulerService {
  final Database _db;
  final Duration tickInterval;
  final Map<String, ScheduledTask> _tasks = {};
  Timer? _timer;
  DateTime? _lastTick;

  SchedulerService(this._db, {this.tickInterval = const Duration(seconds: 60)});

  void register(ScheduledTask task) {
    _tasks[task.key] = task;
  }

  void unregister(String appId) {
    _tasks.removeWhere((key, task) => task.appId == appId);
    // Also clear DB state for this app
    _db.delete('scheduler_state', where: 'task_key LIKE ?', whereArgs: ['$appId::%']);
  }

  void start() {
    _timer?.cancel();
    // First tick immediately
    tick();
    _timer = Timer.periodic(tickInterval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    final now = DateTime.now();
    for (final task in _tasks.values) {
      if (await _isDue(task, now)) {
        try {
          await task.dispatch();
          await _updateLastRun(task.key, now);
        } catch (_) {
          // Task failed — will retry next tick
        }
      }
    }
    _lastTick = now;
  }

  Future<bool> _isDue(ScheduledTask task, DateTime now) async {
    final rows = await _db.query(
      'scheduler_state',
      where: 'task_key = ?',
      whereArgs: [task.key],
    );
    final lastRun = rows.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            rows.first['last_run_at'] as int);

    switch (task.interval) {
      case TaskInterval.all:
        return true;
      case TaskInterval.hourly:
        if (lastRun == null) return true;
        return now.difference(lastRun).inMinutes >= 60;
      case TaskInterval.daily:
        if (lastRun == null) return true;
        return now.difference(lastRun).inHours >= 24;
      case TaskInterval.weekly:
        if (lastRun == null) return true;
        return now.difference(lastRun).inDays >= 7;
      case TaskInterval.monthly:
        if (lastRun == null) return true;
        return now.difference(lastRun).inDays >= 30;
      case TaskInterval.cron:
        if (task.cronExpression == null) return false;
        final expr = CronExpression.parse(task.cronExpression!);
        if (!expr.matches(now)) return false;
        if (lastRun == null) return true;
        return now.minute != lastRun.minute;
    }
  }

  Future<void> _updateLastRun(String key, DateTime time) async {
    await _db.insert(
      'scheduler_state',
      {'task_key': key, 'last_run_at': time.millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
