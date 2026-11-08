import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/calendar_entry.dart';

/// Wraps flutter_local_notifications (v18 API).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _exactAllowed = false;

  Future<void> init() async {
    tzdata.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // Android 13+: the "Allow notifications" pop-up.
      await android.requestNotificationsPermission();
      // Android 12+: exact alarms make reminders fire on the minute.
      _exactAllowed = await android.canScheduleExactNotifications() ?? false;
      if (!_exactAllowed) {
        await android.requestExactAlarmsPermission();
        _exactAllowed = await android.canScheduleExactNotifications() ?? false;
      }
    }
  }

  NotificationDetails _details(EntryType type) => NotificationDetails(
        android: AndroidNotificationDetails(
          'calendar_${type.name}',
          '${type.label} reminders',
          channelDescription: 'Reminders for your ${type.label.toLowerCase()}s',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  /// Schedules the reminder for [entry]. Returns when it will fire, or null
  /// if no reminder was set (none chosen, task done, or the time has passed).
  Future<DateTime?> schedule(CalendarEntry entry) async {
    await cancel(entry);
    if (entry.reminderMinutes < 0 || entry.done) return null;

    final now = DateTime.now();
    final offset = Duration(minutes: entry.reminderMinutes);
    DateTime fireAt;
    DateTimeComponents? repeat;

    if (entry.type == EntryType.birthday) {
      // Next birthday whose reminder is still in the future.
      var year = now.year;
      DateTime occurrence() => DateTime(year, entry.dateTime.month,
          entry.dateTime.day, entry.dateTime.hour, entry.dateTime.minute);
      fireAt = occurrence().subtract(offset);
      if (!fireAt.isAfter(now)) {
        year++;
        fireAt = occurrence().subtract(offset);
      }
      repeat = DateTimeComponents.dateAndTime; // same date and time every year
    } else {
      fireAt = entry.dateTime.subtract(offset);
      if (!fireAt.isAfter(now)) return null;
    }

    final body = entry.reminderMinutes == 0
        ? 'Starting now'
        : '${entry.reminderLabel.replaceAll(' before', '')} to go '
            '(${formatTime(entry.dateTime)})';

    try {
      await _plugin.zonedSchedule(
        entry.id,
        entry.displayTitle,
        body,
        tz.TZDateTime.from(fireAt, tz.local),
        _details(entry.type),
        androidScheduleMode: _exactAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: repeat,
        payload: entry.id.toString(),
      );
      return fireAt;
    } catch (e) {
      debugPrint('Could not schedule reminder for ${entry.id}: $e');
      return null;
    }
  }

  Future<void> cancel(CalendarEntry entry) => _plugin.cancel(entry.id);

  /// Called on app start so the scheduled reminders always match what's saved.
  Future<void> rescheduleAll(List<CalendarEntry> entries) async {
    await _plugin.cancelAll();
    for (final e in entries) {
      await schedule(e);
    }
  }

  Future<void> showTest() => _plugin.show(
        0,
        'Notifications are working',
        'Your reminders will look like this.',
        _details(EntryType.event),
      );
}
