import 'package:flutter/material.dart';

import '../shared/date_time_utils.dart';
import '../shared/models.dart';
import '../shared/widgets.dart';
import 'activity_repository.dart';
import 'daily_plan_repository.dart';

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  final _repo = ActivityRepository();
  final _planRepo = DailyPlanRepository();
  List<Activity> _activities = [];
  List<String> _categories = [];
  String _filter = 'All';
  bool _loading = true;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final allActivities = await _repo.getAll(includeArchived: true);
    final activities = allActivities
        .where((activity) => activity.isArchived == _showArchived)
        .toList();
    final categories = await _repo.getCategories();
    if (!mounted) return;
    setState(() {
      _activities = activities;
      _categories = ['All', ...categories];
      _loading = false;
      if (_filter != 'All' && !_categories.contains(_filter)) {
        _filter = 'All';
      }
    });
  }

  Future<void> _showCreate({Activity? existing}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descriptionController =
        TextEditingController(text: existing?.description ?? '');
    final categoryController =
        TextEditingController(text: existing?.category ?? '');
    final estimateController = TextEditingController(
      text: existing?.estimatedMinutes?.toString() ?? '',
    );
    var importance = existing?.importance ?? '';
    var nudge = existing?.endNudgeEnabled ??
        categoryController.text.trim() == 'Rest & Recreation';
    var nudgeExplicitlySet = existing != null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Create Activity' : 'Edit Activity',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter an activity name.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: categoryController,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (value) {
                      if (!nudgeExplicitlySet) {
                        setSheetState(() {
                          nudge = value.trim() == 'Rest & Recreation';
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                      helperText: 'Use any category name you like.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: estimateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Estimated minutes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final minutes = int.tryParse(value.trim());
                      if (minutes == null || minutes <= 0) {
                        return 'Enter a whole number greater than zero.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: importance,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Not set')),
                      DropdownMenuItem(value: 'Low', child: Text('Low')),
                      DropdownMenuItem(
                        value: 'Normal',
                        child: Text('Normal'),
                      ),
                      DropdownMenuItem(value: 'High', child: Text('High')),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => importance = value ?? ''),
                    decoration: const InputDecoration(
                      labelText: 'Importance (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Estimated-duration nudge'),
                    subtitle: const Text(
                      'On by default for Rest & Recreation.',
                    ),
                    value: nudge,
                    onChanged: (value) => setSheetState(() {
                      nudge = value;
                      nudgeExplicitlySet = true;
                    }),
                  ),
                  const SizedBox(height: 16),
                  StartButton(
                    label: existing == null ? 'CREATE' : 'SAVE',
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final now = DateTimeUtils.nowUtcIso();
                      final activity = Activity(
                        id: existing?.id,
                        name: nameController.text.trim(),
                        description: _nullableText(descriptionController.text),
                        category: _nullableText(categoryController.text),
                        estimatedMinutes:
                            int.tryParse(estimateController.text.trim()),
                        importance: _nullableText(importance),
                        endNudgeEnabled: nudge,
                        isArchived: existing?.isArchived ?? false,
                        createdAt: existing?.createdAt ?? now,
                        updatedAt: now,
                      );
                      if (existing == null) {
                        await _repo.create(activity);
                      } else {
                        await _repo.update(activity);
                      }
                      if (!sheetContext.mounted) return;
                      Navigator.pop(sheetContext, true);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) await _load();
    nameController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
    estimateController.dispose();
  }

  String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _addToToday(Activity activity) async {
    final plan = await _planRepo.getOrCreateToday();
    await _planRepo.addActivityToPlan(planId: plan.id!, activity: activity);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${activity.name} added to My Day')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filtered = _filter == 'All'
        ? _activities
        : _activities
            .where((activity) => activity.category == _filter)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived Activities' : 'Activities'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Show active activities' : 'Show archived',
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
                _filter = 'All';
              });
              _load();
            },
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.archive_outlined,
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (!_showArchived)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final category in _categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: _filter == category,
                        onSelected: (_) => setState(() => _filter = category),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    message: _showArchived
                        ? 'No archived activities.'
                        : 'No activities yet. Create your reusable activity library.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final activity = filtered[index];
                      return Card(
                        child: ListTile(
                          title: Text(
                            activity.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text([
                            activity.category ?? 'General',
                            if (activity.estimatedMinutes != null)
                              '${activity.estimatedMinutes}m',
                            if (activity.importance != null)
                              activity.importance!,
                            if (activity.endNudgeEnabled) 'nudge on',
                            if (activity.description != null)
                              activity.description!,
                          ].join(' • ')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit activity',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    _showCreate(existing: activity),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'archive') {
                                    await _repo.archive(activity.id!);
                                    await _load();
                                  } else if (value == 'restore') {
                                    await _repo.restore(activity.id!);
                                    await _load();
                                  } else if (value == 'add_today') {
                                    await _addToToday(activity);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (!_showArchived)
                                    const PopupMenuItem(
                                      value: 'add_today',
                                      child: Text('Add to My Day'),
                                    ),
                                  PopupMenuItem(
                                    value:
                                        _showArchived ? 'restore' : 'archive',
                                    child: Text(
                                      _showArchived ? 'Restore' : 'Archive',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: _showArchived
                              ? null
                              : () => _addToToday(activity),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _showArchived
          ? null
          : FloatingActionButton(
              onPressed: () => _showCreate(),
              child: const Icon(Icons.add),
            ),
    );
  }
}
