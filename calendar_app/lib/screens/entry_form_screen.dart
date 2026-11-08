import 'package:flutter/material.dart';

import '../models/calendar_entry.dart';

/// Create or edit a task, event or birthday. Pops with the saved entry.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, this.entry, required this.initialDate});

  final CalendarEntry? entry;
  final DateTime initialDate;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late EntryType _type;
  late DateTime _date;
  late TimeOfDay _time;
  late int _reminder;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? EntryType.event;
    final d = widget.initialDate;
    final base = e?.dateTime ?? DateTime(d.year, d.month, d.day, 9);
    _date = DateTime(base.year, base.month, base.day);
    _time = TimeOfDay(hour: base.hour, minute: base.minute);
    _reminder = e?.reminderMinutes ?? 10;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  // Birthdays need a date of birth, so they can go back to 1900.
  // Everything else must fall inside the calendar's years.
  DateTime get _firstAllowed => _type == EntryType.birthday
      ? DateTime(1900)
      : DateTime(calendarFirstYear);
  DateTime get _lastAllowed => DateTime(calendarLastYear, 12, 31);

  Future<void> _pickDate() async {
    var initial = _date;
    if (initial.isBefore(_firstAllowed)) initial = _firstAllowed;
    if (initial.isAfter(_lastAllowed)) initial = _lastAllowed;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _firstAllowed,
      lastDate: _lastAllowed,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_date.isBefore(_firstAllowed) || _date.isAfter(_lastAllowed)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick a date between $calendarFirstYear and '
            '$calendarLastYear.'),
      ));
      return;
    }
    final e = widget.entry;
    Navigator.pop(
      context,
      CalendarEntry(
        id: e?.id ?? CalendarEntry.newId(),
        title: _title.text.trim(),
        note: _note.text.trim(),
        type: _type,
        dateTime: DateTime(
            _date.year, _date.month, _date.day, _time.hour, _time.minute),
        reminderMinutes: _reminder,
        done: e?.done ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBirthday = _type == EntryType.birthday;
    final timeAsDate = DateTime(2000, 1, 1, _time.hour, _time.minute);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'New entry' : 'Edit entry'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<EntryType>(
              segments: EntryType.values
                  .map((t) => ButtonSegment(
                        value: t,
                        label: Text(t.label),
                        icon: Icon(t.icon),
                      ))
                  .toList(),
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: isBirthday ? 'Whose birthday?' : 'Title',
                hintText: isBirthday ? 'e.g. Mum' : null,
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Add a title' : null,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(isBirthday ? 'Date of birth' : 'Date'),
              subtitle: Text(formatDate(_date)),
              onTap: _pickDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(isBirthday ? 'Remind me at' : 'Time'),
              subtitle: Text(formatTime(timeAsDate)),
              onTap: _pickTime,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Reminder'),
              trailing: DropdownButton<int>(
                value: _reminder,
                underline: const SizedBox.shrink(),
                items: reminderOptions.entries
                    .map((o) =>
                        DropdownMenuItem(value: o.key, child: Text(o.value)))
                    .toList(),
                onChanged: (v) => setState(() => _reminder = v ?? -1),
              ),
            ),
            if (isBirthday)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Repeats every year on this date.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: _type.color,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Save ${_type.label.toLowerCase()}'),
            ),
          ],
        ),
      ),
    );
  }
}