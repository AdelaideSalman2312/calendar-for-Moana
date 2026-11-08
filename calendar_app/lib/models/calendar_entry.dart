import 'package:flutter/material.dart';

/// The three kinds of things a person can put on the calendar.
enum EntryType { task, event, birthday }

extension EntryTypeDetails on EntryType {
  String get label => switch (this) {
        EntryType.task => 'Task',
        EntryType.event => 'Event',
        EntryType.birthday => 'Birthday',
      };

  IconData get icon => switch (this) {
        EntryType.task => Icons.check_circle_outline,
        EntryType.event => Icons.event_outlined,
        EntryType.birthday => Icons.cake_outlined,
      };

  Color get color => switch (this) {
        EntryType.task => const Color(0xFF2F7D6D), // deep teal
        EntryType.event => const Color(0xFF3B5BA9), // lake blue
        EntryType.birthday => const Color(0xFFD9922B), // marigold
      };
}

/// The span the calendar covers. Change these two numbers to widen it.
const int calendarFirstYear = 2026;
const int calendarLastYear = 2030;

/// Reminder choices, in minutes before the entry. -1 means no reminder.
const Map<int, String> reminderOptions = {
  -1: 'No reminder',
  0: 'At the time',
  10: '10 minutes before',
  30: '30 minutes before',
  60: '1 hour before',
  1440: '1 day before',
};

class CalendarEntry {
  /// Also used as the notification id, so it must be a positive 32-bit int.
  final int id;
  final String title;
  final String note;
  final EntryType type;

  /// For birthdays this holds the date of birth (the year is used for age).
  final DateTime dateTime;
  final int reminderMinutes;
  final bool done;

  const CalendarEntry({
    required this.id,
    required this.title,
    required this.type,
    required this.dateTime,
    this.note = '',
    this.reminderMinutes = 10,
    this.done = false,
  });

  static int newId() =>
      DateTime.now().millisecondsSinceEpoch.remainder(2147483646) + 1;

  /// Birthdays repeat every year; everything else happens once.
  bool occursOn(DateTime day) {
    if (type == EntryType.birthday) {
      return day.month == dateTime.month &&
          day.day == dateTime.day &&
          day.year >= dateTime.year;
    }
    return day.year == dateTime.year &&
        day.month == dateTime.month &&
        day.day == dateTime.day;
  }

  int get minutesOfDay => dateTime.hour * 60 + dateTime.minute;

  String get displayTitle =>
      type == EntryType.birthday ? "$title's birthday" : title;

  String get reminderLabel => reminderOptions[reminderMinutes] ?? 'Custom';

  CalendarEntry copyWith({bool? done}) => CalendarEntry(
        id: id,
        title: title,
        note: note,
        type: type,
        dateTime: dateTime,
        reminderMinutes: reminderMinutes,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'type': type.name,
        'dateTime': dateTime.toIso8601String(),
        'reminderMinutes': reminderMinutes,
        'done': done,
      };

  factory CalendarEntry.fromJson(Map<String, dynamic> json) => CalendarEntry(
        id: json['id'] as int,
        title: json['title'] as String,
        note: (json['note'] as String?) ?? '',
        type: EntryType.values.byName(json['type'] as String),
        dateTime: DateTime.parse(json['dateTime'] as String),
        reminderMinutes: (json['reminderMinutes'] as int?) ?? 10,
        done: (json['done'] as bool?) ?? false,
      );
}

// Small formatting helpers so the app doesn't need the intl package.
const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];

String _two(int n) => n.toString().padLeft(2, '0');

String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String formatDayHeading(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

String formatMonthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatDateTime(DateTime d) =>
    '${_weekdays[d.weekday - 1].substring(0, 3)} ${d.day} '
    '${_months[d.month - 1].substring(0, 3)}, ${formatTime(d)}';