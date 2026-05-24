enum TaskInterval { all, hourly, daily, weekly, monthly, cron }

class ScheduledTask {
  final String key;
  final String appId;
  final TaskInterval interval;
  final String? cronExpression;
  final Future<void> Function() dispatch;

  const ScheduledTask({
    required this.key,
    required this.appId,
    required this.interval,
    this.cronExpression,
    required this.dispatch,
  });
}
