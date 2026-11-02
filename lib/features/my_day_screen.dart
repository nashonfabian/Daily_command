import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/date_time_utils.dart';
import '../shared/models.dart';
import '../shared/widgets.dart';
import '../theme.dart';
import 'activity_repository.dart';
import 'daily_plan_repository.dart';
import 'daily_review_service.dart';
import 'notification_service.dart';
import 'show_up_engine.dart';
import 'stopwatch_service.dart';

class MyDayScreen extends StatefulWidget {
  const MyDayScreen({super.key});

  @override
  State<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends State<MyDayScreen> with WidgetsBindingObserver {
  final _planRepository = DailyPlanRepository();
  final _activityRepository = ActivityRepository();
  final _stopwatch = StopwatchService();
  DailyPlan? _plan;
  List<DailyPlanActivity> _items = [];
  DailyPlanActivity? _openItemFromAnotherDay;
  Timer? _ticker;
  Map<int, Duration> _durations = {};
  bool _loading = true;
  bool _interruptionDialogShown = false;
  bool _yesterdayReviewPromptShown = false;
  int _tickerCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshDurations(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAfterResume();
  }

  Future<void> _refreshAfterResume() async {
    await NotificationService.refreshLocalTimezone();
    await _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final plan = await _planRepository.getOrCreateToday();
    final items = await _planRepository.getPlanItems(plan.id!);
    final entries = await Future.wait(
      items.map(
        (item) async => MapEntry(
          item.id!,
          await _stopwatch.getTotalActiveDuration(item.id!),
        ),
      ),
    );
    final durations = Map<int, Duration>.fromEntries(entries);
    final session = await _stopwatch.getOpenSession();
    final openItemFromAnotherDay = session == null ||
            items.any((item) => item.id == session.dailyPlanActivityId)
        ? null
        : await _planRepository.getItemById(session.dailyPlanActivityId);
    if (openItemFromAnotherDay != null) {
      durations[openItemFromAnotherDay.id!] =
          await _stopwatch.getTotalActiveDuration(openItemFromAnotherDay.id!);
    }
    final suspicious = await _stopwatch.hasSuspiciousOpenSession();

    if (!mounted) return;
    setState(() {
      _plan = plan;
      _items = items;
      _openItemFromAnotherDay = openItemFromAnotherDay;
      _durations = durations;
      _loading = false;
    });

    if (session != null && suspicious) {
      if (!_interruptionDialogShown) {
        _interruptionDialogShown = true;
        _showInterruptionDialog(session);
      }
      return;
    }

    if (session != null) {
      final item =
          items.where((entry) => entry.id == session.dailyPlanActivityId);
      if (item.isNotEmpty) {
        await _scheduleNudge(item.first);
      } else if (openItemFromAnotherDay != null) {
        await _scheduleNudge(openItemFromAnotherDay);
      }
    }
    _checkYesterdayReview();
  }

  Future<void> _refreshDurations() async {
    final trackedItems = [..._items];
    final openItemFromAnotherDay = _openItemFromAnotherDay;
    if (openItemFromAnotherDay != null &&
        !trackedItems.any((item) => item.id == openItemFromAnotherDay.id)) {
      trackedItems.add(openItemFromAnotherDay);
    }
    if (trackedItems.isEmpty) return;
    _tickerCount++;
    if (_tickerCount % 30 == 0) {
      final session = await _stopwatch.getOpenSession();
      if (session?.id != null) {
        await _stopwatch.recordHeartbeat(session!.id!);
      }
    }

    final entries = await Future.wait(
      trackedItems.map(
        (item) async => MapEntry(
          item.id!,
          await _stopwatch.getTotalActiveDuration(item.id!),
        ),
      ),
    );
    if (mounted) {
      setState(() => _durations = Map<int, Duration>.fromEntries(entries));
    }
  }

  Future<void> _checkYesterdayReview() async {
    if (_yesterdayReviewPromptShown) return;
    _yesterdayReviewPromptShown = true;
    final shouldReview =
        await DailyReviewService.shouldShowReviewForYesterday();
    if (!shouldReview || !mounted) return;
    final date = DailyReviewService.yesterdayLocalDate();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final openReview = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review yesterday'),
        content: const Text(
          'Yesterday has activities that have not been reviewed. '
          'Would you like to decide what to carry forward?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Review day'),
          ),
        ],
      ),
    );
    if (openReview == true && mounted) {
      await _showReviewSheet(date: date);
    }
  }

  Future<void> _showInterruptionDialog(ActivitySession session) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final start = DateTime.parse(session.startedAt).toLocal();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Still going?'),
        content: Text(
          'This timer was last confirmed near '
          '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(start))}. '
          'The phone may have been off or unattended. Unconfirmed time will '
          'not be counted unless you adjust the end time.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _stopwatch.resolveInterruption(
                session.id!,
                action: 'continue',
              );
              await _load();
            },
            child: const Text('Continue timing from now'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _stopwatch.resolveInterruption(
                session.id!,
                action: 'finish_last',
              );
              await _load();
            },
            child: const Text('Finish using the last confirmed time'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _adjustInterruptionEnd(session);
            },
            child: const Text('Adjust the end time'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _stopwatch.resolveInterruption(
                session.id!,
                action: 'pause',
              );
              await _load();
            },
            child: const Text('Keep paused for review'),
          ),
        ],
      ),
    );
  }

  Future<void> _adjustInterruptionEnd(ActivitySession session) async {
    if (!mounted) return;
    final start = DateTime.parse(session.startedAt).toLocal();
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(start.year, start.month, start.day),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (pickedTime == null || !mounted) return;
    final localEnd = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    await _stopwatch.resolveInterruption(
      session.id!,
      action: 'adjust',
      correctedEndTime: localEnd.toUtc().toIso8601String(),
    );
    await _load();
  }

  Future<void> _start(DailyPlanActivity item) async {
    if (item.snapshotCategory == 'Rest & Recreation' && item.intent == null) {
      await _askIntent(item);
    }
    final open = await _stopwatch.getOpenSession();
    final wasSwitching = open != null && open.dailyPlanActivityId != item.id;
    final previousItem = wasSwitching
        ? await _planRepository.getItemById(open.dailyPlanActivityId)
        : null;
    if (wasSwitching) {
      await NotificationService.cancelNudge(open.dailyPlanActivityId);
    }
    await _stopwatch.start(item.id!);
    await _scheduleNudge(item);
    await _load();
    if (!mounted) return;
    if (wasSwitching) {
      final previousName =
          previousItem?.snapshotName ?? 'The previous activity';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$previousName was paused.')),
      );
    }
  }

  Future<void> _scheduleNudge(DailyPlanActivity item) async {
    final activity = item.activityId == null
        ? null
        : await _activityRepository.getById(item.activityId!);
    final shouldNudge = activity?.endNudgeEnabled ??
        item.snapshotCategory == 'Rest & Recreation';
    final id = item.id!;
    if (!shouldNudge || item.estimatedMinutes == null) {
      await NotificationService.cancelNudge(id);
      return;
    }
    final elapsed = await _stopwatch.getTotalActiveDuration(id);
    final remaining = Duration(minutes: item.estimatedMinutes!) - elapsed;
    if (remaining <= Duration.zero) {
      await NotificationService.cancelNudge(id);
      return;
    }
    await NotificationService.scheduleNudge(
      id: id,
      activityName: item.snapshotName,
      after: remaining,
    );
  }

  Future<void> _pause(DailyPlanActivity item) async {
    await _stopwatch.pause(item.id!);
    await NotificationService.cancelNudge(item.id!);
    await _load();
  }

  Future<void> _finish(DailyPlanActivity item) async {
    await _stopwatch.finish(item.id!);
    await NotificationService.cancelNudge(item.id!);
    await _load();
    if (!mounted) return;
    _showAfterCompletionPrompt();
  }

  void _showAfterCompletionPrompt() {
    final next = _items.where(
      (item) =>
          item.status == PlanItemStatus.notStarted ||
          item.status == PlanItemStatus.paused,
    );
    final nextItem = next.isEmpty ? null : next.first;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('You showed up.'),
        content: Text(
          nextItem == null
              ? 'What would you like to do next?'
              : 'Would you like to start "${nextItem.snapshotName}" next?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          if (nextItem != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _start(nextItem);
              },
              child: const Text('Start next activity'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showFreeTimeSheet();
            },
            child: const Text('I have free time'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFreeTimeSheet() async {
    final prefs = await SharedPreferences.getInstance();
    var selectedMinutes = prefs.getInt('default_free_time') ?? 20;
    var notSure = false;
    var lowEnergy = false;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How much time do you have?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('TODAY MATTERS. SHOW UP.'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final minutes in [10, 20, 30, 60])
                    ChoiceChip(
                      label: Text(minutes == 60 ? '60+ min' : '$minutes min'),
                      selected: selectedMinutes == minutes && !notSure,
                      onSelected: (_) => setSheetState(() {
                        selectedMinutes = minutes;
                        notSure = false;
                      }),
                    ),
                  ChoiceChip(
                    label: const Text('Not sure'),
                    selected: notSure,
                    onSelected: (_) => setSheetState(() => notSure = true),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I have low energy'),
                subtitle: const Text('Offer smaller first steps.'),
                value: lowEnergy,
                onChanged: (value) => setSheetState(() => lowEnergy = value),
              ),
              const SizedBox(height: 8),
              const Text(
                ShowUpEngine.freeTimePrompt,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(ShowUpEngine.freeTimeFollow),
              const SizedBox(height: 16),
              StartButton(
                label: 'SHOW SUGGESTIONS',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _showSuggestions(
                    notSure ? 30 : selectedMinutes,
                    lowEnergy: lowEnergy,
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSuggestions(
    int availableMinutes, {
    required bool lowEnergy,
  }) async {
    final activities = await _activityRepository.getAll();
    final suggestions = ShowUpEngine.filterByFreeTime(
      activities: activities,
      availableMinutes: availableMinutes,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'You have ${availableMinutes == 60 ? '60+' : availableMinutes} min — what matters now?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              lowEnergy
                  ? 'You can start with a small, manageable step. You choose when to pause.'
                  : 'Choose what to show up for. Longer activities can begin with a smaller step.',
            ),
            const SizedBox(height: 16),
            if (suggestions.isEmpty)
              const EmptyState(
                message:
                    'Create an activity in your library to see suggestions.',
              ),
            for (final activity in suggestions.take(30))
              Card(
                child: ListTile(
                  title: Text(activity.name),
                  subtitle: Text(
                    '${activity.category ?? 'General'} • '
                    '${activity.estimatedMinutes == null ? 'no estimate' : '${activity.estimatedMinutes}m estimated'}',
                  ),
                  trailing: activity.estimatedMinutes != null &&
                          (lowEnergy ||
                              activity.estimatedMinutes! > availableMinutes)
                      ? Text(
                          'Start ${ShowUpEngine.suggestedSmallStart(activity.estimatedMinutes, availableMinutes)}m',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.restGreen,
                          ),
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final plan = _plan;
                    if (plan == null) return;
                    final item = await _planRepository.addActivityToPlan(
                      planId: plan.id!,
                      activity: activity,
                    );
                    await _promptStartSelected(
                      item,
                      availableMinutes: availableMinutes,
                      lowEnergy: lowEnergy,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askIntent(DailyPlanActivity item) async {
    String? selected = 'Relax';
    final otherIntent = TextEditingController();
    final savedIntent = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('What are you choosing this time for?'),
        content: StatefulBuilder(
          builder: (dialogContext, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in ['Relax', 'Have fun', 'Recover', 'Other'])
                RadioListTile<String>(
                  value: option,
                  groupValue: selected,
                  title: Text(option),
                  onChanged: (value) => setDialogState(() => selected = value),
                ),
              if (selected == 'Other')
                TextField(
                  controller: otherIntent,
                  decoration: const InputDecoration(
                    labelText: 'Your intention',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              final intent =
                  selected == 'Other' ? otherIntent.text.trim() : selected;
              if (intent == null || intent.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter your intention.')),
                );
                return;
              }
              Navigator.pop(dialogContext, intent);
            },
            child: const Text('Save intent'),
          ),
        ],
      ),
    );
    otherIntent.dispose();
    if (savedIntent != null && savedIntent.isNotEmpty) {
      await _planRepository.updateItem(_copyItem(item, intent: savedIntent));
    }
    return savedIntent;
  }

  Future<void> _promptStartSelected(
    DailyPlanActivity item, {
    required int availableMinutes,
    required bool lowEnergy,
  }) async {
    if (!mounted) return;
    final smallStep = lowEnergy
        ? (availableMinutes < 10 ? availableMinutes : 10)
        : ShowUpEngine.suggestedSmallStart(
            item.estimatedMinutes,
            availableMinutes,
          );
    final needsSmallStart = lowEnergy ||
        (item.estimatedMinutes != null &&
            item.estimatedMinutes! > availableMinutes);
    final bool? startSmall;
    if (needsSmallStart) {
      startSmall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(ShowUpEngine.goodLetsShowUp),
          content: Text(
            'Start "${item.snapshotName}" now. '
            'A $smallStep-minute first step is available; you can pause '
            'whenever you choose.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Start $smallStep-minute step'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start now'),
            ),
          ],
        ),
      );
    } else {
      startSmall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Good. Let's show up."),
          content: Text('Start "${item.snapshotName}" now?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('START NOW'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    if (startSmall == true) {
      await _start(item);
      if (needsSmallStart && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Begin with a small step; pause whenever you choose.'),
          ),
        );
      }
    } else {
      await _load();
    }
  }

  Future<void> _showPlannedPrompt(DailyPlanActivity item) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ready to show up?'),
        content: Text(ShowUpEngine.plannedNotStarted(item.snapshotName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'adjust'),
            child: const Text('Adjust my plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'later'),
            child: const Text('Not possible right now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'start'),
            child: const Text('Start now'),
          ),
        ],
      ),
    );
    if (choice == 'start') {
      await _start(item);
    } else if (choice == 'adjust') {
      await _editPlanItem(item);
    }
  }

  Future<void> _editPlanItem(DailyPlanActivity item) async {
    final name = TextEditingController(text: item.snapshotName);
    final description = TextEditingController(
      text: item.snapshotDescription ?? '',
    );
    final category = TextEditingController(text: item.snapshotCategory ?? '');
    final estimate = TextEditingController(
      text: item.estimatedMinutes?.toString() ?? '',
    );
    final importance = TextEditingController(text: item.importance ?? '');
    final notes = TextEditingController(text: item.notes ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: category,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              TextField(
                controller: estimate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Estimated minutes',
                ),
              ),
              TextField(
                controller: importance,
                decoration: const InputDecoration(
                  labelText: 'Importance (optional)',
                  hintText: 'Low, Normal, High',
                ),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 16),
              StartButton(
                label: 'SAVE TODAY’S PLAN ITEM',
                onPressed: () async {
                  final minutes = estimate.text.trim().isEmpty
                      ? null
                      : int.tryParse(estimate.text.trim());
                  if (name.text.trim().isEmpty ||
                      (estimate.text.trim().isNotEmpty &&
                          (minutes == null || minutes <= 0))) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a name and a valid estimate.'),
                      ),
                    );
                    return;
                  }
                  await _planRepository.updateItem(
                    DailyPlanActivity(
                      id: item.id,
                      planId: item.planId,
                      activityId: item.activityId,
                      snapshotName: name.text.trim(),
                      snapshotDescription: _optional(description.text),
                      snapshotCategory: _optional(category.text),
                      displayOrder: item.displayOrder,
                      status: item.status,
                      estimatedMinutes: minutes,
                      importance: _optional(importance.text),
                      intent: item.intent,
                      notes: _optional(notes.text),
                      completedAt: item.completedAt,
                      createdAt: item.createdAt,
                      updatedAt: DateTimeUtils.nowUtcIso(),
                    ),
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  await _load();
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    description.dispose();
    category.dispose();
    estimate.dispose();
    importance.dispose();
    notes.dispose();
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  DailyPlanActivity _copyItem(
    DailyPlanActivity item, {
    String? intent,
    PlanItemStatus? status,
  }) =>
      DailyPlanActivity(
        id: item.id,
        planId: item.planId,
        activityId: item.activityId,
        snapshotName: item.snapshotName,
        snapshotDescription: item.snapshotDescription,
        snapshotCategory: item.snapshotCategory,
        displayOrder: item.displayOrder,
        status: status ?? item.status,
        estimatedMinutes: item.estimatedMinutes,
        importance: item.importance,
        intent: intent ?? item.intent,
        notes: item.notes,
        completedAt: item.completedAt,
        createdAt: item.createdAt,
        updatedAt: DateTimeUtils.nowUtcIso(),
      );

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final reordered = [..._items];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    await _planRepository.updateOrder(
      _plan!.id!,
      reordered.map((entry) => entry.id!).toList(),
    );
    if (mounted) setState(() => _items = reordered);
  }

  Future<String?> _askPostponement(DailyPlanActivity item) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose intentionally'),
        content: Text(ShowUpEngine.postponementQuestion(item.snapshotName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'remove'),
            child: const Text('Remove from this plan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'start'),
            child: const Text('Start a small step now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'reschedule'),
            child: const Text('Reschedule intentionally'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReviewSheet({String? date}) async {
    final reviewDate = date ?? DateTimeUtils.todayLocalYYYYMMDD();
    final reviewItems = await DailyReviewService.getReviewItems(reviewDate);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final unfinished = reviewItems
              .where((item) =>
                  item.status == PlanItemStatus.notStarted ||
                  item.status == PlanItemStatus.inProgress ||
                  item.status == PlanItemStatus.paused)
              .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            builder: (sheetContext, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Review $reviewDate',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Do you want to continue this another day, or is it no longer important?',
                ),
                const SizedBox(height: 16),
                if (reviewItems.isEmpty)
                  const Text('No activities were planned for this day.'),
                for (final item in reviewItems)
                  Card(
                    child: ListTile(
                      title: Text(item.snapshotName),
                      subtitle: Text(_statusLabel(item.status)),
                      trailing: unfinished.contains(item)
                          ? PopupMenuButton<String>(
                              onSelected: (choice) async {
                                var resolved = false;
                                if (choice == 'tomorrow' ||
                                    choice == 'choose_date') {
                                  final decision = await _askPostponement(item);
                                  if (decision == 'start') {
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                    await _start(item);
                                    return;
                                  }
                                  if (decision == 'remove') {
                                    await _planRepository
                                        .removeFromPlan(item.id!);
                                    await NotificationService.cancelNudge(
                                      item.id!,
                                    );
                                    resolved = true;
                                  } else if (decision == 'reschedule') {
                                    DateTime? destination;
                                    if (choice == 'tomorrow') {
                                      final now = DateTime.now();
                                      destination = DateTime(
                                        now.year,
                                        now.month,
                                        now.day + 1,
                                      );
                                    } else if (mounted) {
                                      destination = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now().add(
                                          const Duration(days: 1),
                                        ),
                                        firstDate: DateTime.now().add(
                                          const Duration(days: 1),
                                        ),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 365),
                                        ),
                                      );
                                    }
                                    if (destination != null) {
                                      await NotificationService.cancelNudge(
                                        item.id!,
                                      );
                                      await _planRepository.moveToDate(
                                        item.id!,
                                        DateTimeUtils.formatDate(destination),
                                      );
                                      resolved = true;
                                    }
                                  }
                                } else if (choice == 'keep_library' ||
                                    choice == 'remove') {
                                  await _planRepository
                                      .removeFromPlan(item.id!);
                                  await NotificationService.cancelNudge(
                                    item.id!,
                                  );
                                  resolved = true;
                                }
                                if (resolved) {
                                  setSheetState(() {
                                    reviewItems.removeWhere(
                                      (entry) => entry.id == item.id,
                                    );
                                  });
                                  final stillUnfinished = reviewItems.any(
                                    (entry) =>
                                        entry.status ==
                                            PlanItemStatus.notStarted ||
                                        entry.status ==
                                            PlanItemStatus.inProgress ||
                                        entry.status == PlanItemStatus.paused,
                                  );
                                  if (!stillUnfinished) {
                                    await DailyReviewService.markReviewed(
                                      reviewDate,
                                    );
                                  }
                                  await _load();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'tomorrow',
                                  child: Text('Move to tomorrow'),
                                ),
                                PopupMenuItem(
                                  value: 'choose_date',
                                  child: Text('Choose another date'),
                                ),
                                PopupMenuItem(
                                  value: 'keep_library',
                                  child: Text('Keep in My Activities only'),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove from this plan'),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                if (unfinished.isEmpty)
                  ElevatedButton(
                    onPressed: () async {
                      await DailyReviewService.markReviewed(reviewDate);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Done'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(PlanItemStatus status) => switch (status) {
        PlanItemStatus.notStarted => 'Not started',
        PlanItemStatus.inProgress => 'In progress',
        PlanItemStatus.paused => 'Paused',
        PlanItemStatus.completed => 'Completed',
        PlanItemStatus.removed => 'Removed',
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentItems = _items
        .where(
          (item) =>
              item.status == PlanItemStatus.inProgress ||
              item.status == PlanItemStatus.paused,
        )
        .toList();
    final openItemFromAnotherDay = _openItemFromAnotherDay;
    if (openItemFromAnotherDay != null &&
        !currentItems.any((item) => item.id == openItemFromAnotherDay.id)) {
      currentItems.insert(0, openItemFromAnotherDay);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DAILY COMMAND', style: TextStyle(letterSpacing: 1)),
            Text(
              DateTimeUtils.todayLocalYYYYMMDD(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppTheme.mutedGrey,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.charcoal,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today matters. Show up.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You have time. What are you actually doing? What matters to you? Then show up.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _showFreeTimeSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.charcoal,
                    ),
                    child: const Text('I HAVE FREE TIME'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (currentItems.isNotEmpty) ...[
            const SectionHeader(title: 'Now'),
            const SizedBox(height: 8),
            for (final item in currentItems) _buildCurrentCard(item),
            const SizedBox(height: 16),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionHeader(title: 'My Day'),
              TextButton(
                onPressed: () => _load(),
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const EmptyState(
              message:
                  'Nothing planned yet. Add from Activities or tap I HAVE FREE TIME.',
            ),
          if (_items.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _buildPlanItem(
                  item,
                  index,
                  key: ValueKey(item.id),
                );
              },
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _showReviewSheet(),
            icon: const Icon(Icons.reviews_outlined),
            label: const Text('Review day'),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildCurrentCard(DailyPlanActivity item) {
    final duration = _durations[item.id!] ?? Duration.zero;
    final isRunning = item.status == PlanItemStatus.inProgress;
    return Card(
      color: isRunning ? AppTheme.charcoal : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.snapshotName,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isRunning ? Colors.white : AppTheme.charcoal,
                    ),
                  ),
                ),
                Text(
                  isRunning ? 'IN PROGRESS' : 'PAUSED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isRunning ? AppTheme.restGreen : AppTheme.mutedGrey,
                  ),
                ),
              ],
            ),
            if (item.planId != _plan?.id)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Continued from another day',
                  style: TextStyle(color: AppTheme.mutedGrey),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              DateTimeUtils.formatElapsed(duration),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: isRunning ? Colors.white : AppTheme.charcoal,
              ),
            ),
            if (item.estimatedMinutes != null)
              Text(
                'Estimated ${item.estimatedMinutes}m • Active ${duration.inMinutes}m',
                style: TextStyle(
                  color: isRunning ? Colors.white70 : AppTheme.mutedGrey,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        isRunning ? () => _pause(item) : () => _start(item),
                    child: Text(isRunning ? 'PAUSE' : 'RESUME'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _finish(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.restGreen,
                    ),
                    child: const Text('FINISH'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanItem(
    DailyPlanActivity item,
    int index, {
    required Key key,
  }) {
    final duration = _durations[item.id!] ?? Duration.zero;
    final isUnfinished = item.status != PlanItemStatus.completed;
    return Card(
      key: key,
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Text(
          item.snapshotName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              if (item.snapshotCategory != null) item.snapshotCategory!,
              if (item.estimatedMinutes != null)
                '${item.estimatedMinutes}m estimated',
              _statusLabel(item.status),
            ].join(' • ')),
            if (item.snapshotDescription != null)
              Text(item.snapshotDescription!),
            if (item.importance != null) Text('Importance: ${item.importance}'),
            if (duration.inSeconds > 0)
              Text(
                'Active: ${DateTimeUtils.formatElapsed(duration)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.restGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (item.intent != null)
              Text(
                'Intent: ${item.intent}',
                style:
                    const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (choice) async {
            switch (choice) {
              case 'start':
                if (item.status == PlanItemStatus.notStarted) {
                  await _showPlannedPrompt(item);
                } else {
                  await _start(item);
                }
              case 'pause':
                await _pause(item);
              case 'finish':
                await _finish(item);
              case 'edit':
                await _editPlanItem(item);
              case 'remove':
                await _planRepository.removeFromPlan(item.id!);
                await NotificationService.cancelNudge(item.id!);
                await _load();
            }
          },
          itemBuilder: (_) => [
            if (item.status == PlanItemStatus.notStarted ||
                item.status == PlanItemStatus.paused)
              const PopupMenuItem(value: 'start', child: Text('Start')),
            if (item.status == PlanItemStatus.inProgress)
              const PopupMenuItem(value: 'pause', child: Text('Pause')),
            if (isUnfinished)
              const PopupMenuItem(value: 'finish', child: Text('Finish')),
            const PopupMenuItem(
                value: 'edit', child: Text('Edit today’s item')),
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove from this plan'),
            ),
          ],
        ),
        onTap: item.status == PlanItemStatus.notStarted
            ? () => _showPlannedPrompt(item)
            : item.status == PlanItemStatus.paused
                ? () => _start(item)
                : null,
      ),
    );
  }
}
