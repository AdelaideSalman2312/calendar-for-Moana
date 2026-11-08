import 'package:flutter/material.dart';

import 'models/calendar_entry.dart';
import 'screens/entry_form_screen.dart';
import 'services/entry_store.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const CalendarApp());
}

const _ink = Color(0xFF18242E);
const _mist = Color(0xFFF3F6F8);
const _line = Color(0xFFDCE3E8);
const _muted = Color(0xFF7A8994);

// Every month has the same height (header + 6 week rows), which lets the
// list jump straight to any month without measuring anything.
const _monthHeaderHeight = 56.0;
const _cellHeight = 48.0;
const _monthExtent = _monthHeaderHeight + 6 * _cellHeight;
const _totalMonths = (calendarLastYear - calendarFirstYear + 1) * 12;
const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _monthAt(int index) =>
    DateTime(calendarFirstYear + index ~/ 12, index % 12 + 1);

int _indexOf(DateTime d) =>
    ((d.year - calendarFirstYear) * 12 + d.month - 1).clamp(0, _totalMonths - 1);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
int _monthDayKey(DateTime d) => d.month * 100 + d.day;

/// Today if it falls in range, otherwise the nearest end of the range.
DateTime _startDay() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (today.year < calendarFirstYear) return DateTime(calendarFirstYear);
  if (today.year > calendarLastYear) return DateTime(calendarLastYear, 12, 31);
  return today;
}

class CalendarApp extends StatelessWidget {
  const CalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: EntryType.event.color,
          surface: _mist,
        ),
        scaffoldBackgroundColor: _mist,
        appBarTheme: const AppBarTheme(
          backgroundColor: _mist,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = EntryStore();
  List<CalendarEntry> _entries = [];
  bool _loading = true;

  late DateTime _selectedDay = _startDay();
  late int _visibleMonth = _indexOf(_selectedDay);
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _indexOf(_selectedDay) * _monthExtent,
  );

  // Lookup tables so each day cell doesn't scan every entry.
  Map<int, List<CalendarEntry>> _oneOff = {};
  Map<int, List<CalendarEntry>> _yearly = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final index =
        (_scroll.offset / _monthExtent + 0.3).floor().clamp(0, _totalMonths - 1);
    if (index != _visibleMonth) setState(() => _visibleMonth = index);
  }

  Future<void> _load() async {
    final entries = await _store.load();
    await NotificationService.instance.rescheduleAll(entries);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _rebuildIndex();
      _loading = false;
    });
  }

  void _rebuildIndex() {
    _oneOff = {};
    _yearly = {};
    for (final e in _entries) {
      if (e.type == EntryType.birthday) {
        _yearly.putIfAbsent(_monthDayKey(e.dateTime), () => []).add(e);
      } else {
        _oneOff.putIfAbsent(_dayKey(e.dateTime), () => []).add(e);
      }
    }
  }

  List<CalendarEntry> _entriesFor(DateTime day) => [
        ...?_oneOff[_dayKey(day)],
        ...?_yearly[_monthDayKey(day)]?.where((e) => e.occursOn(day)),
      ]..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));

  void _scrollToMonth(DateTime day) {
    _scroll.animateTo(
      _indexOf(day) * _monthExtent,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _snack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _openForm({CalendarEntry? entry}) async {
    final result = await Navigator.push<CalendarEntry>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EntryFormScreen(entry: entry, initialDate: _selectedDay),
      ),
    );
    if (result == null) return;
    await _upsert(result);
    final fireAt = await NotificationService.instance.schedule(result);
    if (!mounted) return;

    // Show the day the entry landed on (birthdays: this range's occurrence).
    if (result.type != EntryType.birthday) {
      final d = result.dateTime;
      setState(() => _selectedDay = DateTime(d.year, d.month, d.day));
      _scrollToMonth(_selectedDay);
    }

    if (result.reminderMinutes < 0) {
      _snack('Saved without a reminder.');
    } else if (fireAt == null) {
      _snack('Saved. The reminder time has already passed, so no '
          'notification is set.');
    } else {
      _snack('Saved. Reminder on ${formatDateTime(fireAt)}.');
    }
  }

  Future<void> _upsert(CalendarEntry entry) async {
    setState(() {
      final i = _entries.indexWhere((e) => e.id == entry.id);
      if (i >= 0) {
        _entries[i] = entry;
      } else {
        _entries.add(entry);
      }
      _rebuildIndex();
    });
    await _store.save(_entries);
  }

  Future<void> _delete(CalendarEntry entry) async {
    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
      _rebuildIndex();
    });
    await _store.save(_entries);
    await NotificationService.instance.cancel(entry);
    if (!mounted) return;
    _snack(
      'Deleted ${entry.displayTitle}.',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await _upsert(entry);
          await NotificationService.instance.schedule(entry);
        },
      ),
    );
  }

  Future<void> _toggleDone(CalendarEntry entry) async {
    final updated = entry.copyWith(done: !entry.done);
    await _upsert(updated);
    await NotificationService.instance.schedule(updated);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _monthAt(_visibleMonth);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          formatMonthYear(visible),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Go to year',
            icon: const Icon(Icons.calendar_view_month_outlined),
            onSelected: (year) => _scrollToMonth(DateTime(year)),
            itemBuilder: (_) => [
              for (var y = calendarFirstYear; y <= calendarLastYear; y++)
                PopupMenuItem(value: y, child: Text('$y')),
            ],
          ),
          IconButton(
            tooltip: 'Go to today',
            icon: const Icon(Icons.today_outlined),
            onPressed: () {
              setState(() => _selectedDay = _startDay());
              _scrollToMonth(_selectedDay);
            },
          ),
          IconButton(
            tooltip: 'Send a test notification',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: NotificationService.instance.showTest,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _weekdayHeader(),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemExtent: _monthExtent,
                    itemCount: _totalMonths,
                    itemBuilder: (_, i) => _MonthView(
                      month: _monthAt(i),
                      selectedDay: _selectedDay,
                      entriesFor: _entriesFor,
                      onDayTap: (d) => setState(() => _selectedDay = d),
                    ),
                  ),
                ),
                _dayPanel(),
              ],
            ),
    );
  }

  Widget _weekdayHeader() => Container(
        height: 32,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            for (final label in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      );

  Widget _dayPanel() {
    final dayEntries = _entriesFor(_selectedDay);
    return Container(
      height: 250,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatDayHeading(_selectedDay)} ${_selectedDay.year}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _ink),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  style: FilledButton.styleFrom(backgroundColor: _ink),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: dayEntries.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing on this day yet.',
                      style: TextStyle(color: _muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: dayEntries.length,
                    itemBuilder: (_, i) => _tile(dayEntries[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(CalendarEntry e) {
    final age = _selectedDay.year - e.dateTime.year;
    final detail = e.type == EntryType.birthday && age > 0
        ? 'Turns $age'
        : formatTime(e.dateTime);
    final reminder =
        e.reminderMinutes < 0 ? '' : '   Reminder: ${e.reminderLabel}';

    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(e),
      child: ListTile(
        onTap: () => _openForm(entry: e),
        leading: Container(
          width: 5,
          height: 40,
          decoration: BoxDecoration(
            color: e.type.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Text(
          e.displayTitle,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: e.done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text('$detail$reminder'),
        trailing: e.type == EntryType.task
            ? Checkbox(
                value: e.done,
                activeColor: e.type.color,
                onChanged: (_) => _toggleDone(e),
              )
            : Icon(e.type.icon, color: e.type.color),
      ),
    );
  }
}

/// One month: a title and a fixed 6-row grid of days.
class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.selectedDay,
    required this.entriesFor,
    required this.onDayTap,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<CalendarEntry> Function(DateTime) entriesFor;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final now = DateTime.now();
    final isJanuary = month.month == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _monthHeaderHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              formatMonthYear(month),
              style: TextStyle(
                // January opens a new year, so it gets a heavier title.
                fontSize: isJanuary ? 22 : 17,
                fontWeight: isJanuary ? FontWeight.w800 : FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
        ),
        for (var row = 0; row < 6; row++)
          SizedBox(
            height: _cellHeight,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(row * 7 + col - leadingBlanks + 1,
                        daysInMonth, now, col),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int dayNumber, int daysInMonth, DateTime now, int col) {
    if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox();
    final day = DateTime(month.year, month.month, dayNumber);
    final isSelected = _sameDay(day, selectedDay);
    final isToday = _sameDay(day, now);
    final types = entriesFor(day).map((e) => e.type).toSet();

    return InkWell(
      onTap: () => onDayTap(day),
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? _ink : null,
              border: isToday && !isSelected
                  ? Border.all(color: _ink, width: 1.5)
                  : null,
            ),
            child: Text(
              '$dayNumber',
              style: TextStyle(
                fontWeight:
                    isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? Colors.white
                    : (col == 6 ? _muted : _ink),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in types)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration:
                        BoxDecoration(color: t.color, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}