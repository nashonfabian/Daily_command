import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../shared/date_time_utils.dart';
import '../shared/models.dart';
import 'history_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repository = HistoryRepository();
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());
  HistoryDay? _day;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  Future<void> _loadDay() async {
    setState(() => _loading = true);
    final day =
        await _repository.getDay(DateTimeUtils.formatDate(_selectedDate));
    if (!mounted) return;
    setState(() {
      _day = day;
      _loading = false;
    });
  }

  Future<void> _selectDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (date == null || !mounted) return;
    setState(() => _selectedDate = DateUtils.dateOnly(date));
    await _loadDay();
  }

  Future<void> _changeDate(int days) async {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    await _loadDay();
  }

  String _statusLabel(PlanItemStatus status) => switch (status) {
        PlanItemStatus.notStarted => 'Not started',
        PlanItemStatus.inProgress => 'In progress',
        PlanItemStatus.paused => 'Paused',
        PlanItemStatus.completed => 'Completed',
        PlanItemStatus.removed => 'Removed from plan',
      };

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String _sessionLabel(ActivitySession session) {
    final start = DateTime.parse(session.startedAt).toLocal();
    final end = session.endedAt == null
        ? null
        : DateTime.parse(session.endedAt!).toLocal();
    final timeFormat = DateFormat('HH:mm');
    return '${timeFormat.format(start)} – ${end == null ? 'In progress' : timeFormat.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final dateLabel = DateFormat('EEEE, d MMMM yyyy').format(_selectedDate);
    final day = _day;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Choose date',
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  onPressed: () => _changeDate(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      dateLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next day',
                  onPressed: _selectedDate.isBefore(today)
                      ? () => _changeDate(1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : day == null || day.activities.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No activities were planned for this day.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(Icons.checklist_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${day.activities.length} planned ${day.activities.length == 1 ? 'activity' : 'activities'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _durationLabel(day.recordedDuration),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text(
                                        'recorded',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final record in day.activities)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            record.item.snapshotName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _statusLabel(record.item.status),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                    if (record.item.snapshotCategory != null ||
                                        record.item.snapshotDescription != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text([
                                          if (record.item.snapshotCategory !=
                                              null)
                                            record.item.snapshotCategory!,
                                          if (record.item.snapshotDescription !=
                                              null)
                                            record.item.snapshotDescription!,
                                        ].join(' • ')),
                                      ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Recorded time: ${_durationLabel(record.recordedDuration)}'
                                      '${record.item.estimatedMinutes == null ? '' : ' · Planned ${record.item.estimatedMinutes}m'}',
                                    ),
                                    for (final session in record.sessions)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _sessionLabel(session),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
