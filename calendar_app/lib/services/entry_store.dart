import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_entry.dart';

/// Saves all entries on the device as one JSON list.
class EntryStore {
  static const _key = 'calendar_entries_v1';

  Future<List<CalendarEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((item) => CalendarEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<CalendarEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
