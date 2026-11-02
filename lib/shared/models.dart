enum PlanItemStatus { notStarted, inProgress, paused, completed, removed }

extension PlanItemStatusX on PlanItemStatus {
  String get value => switch (this) {
        PlanItemStatus.notStarted => 'not_started',
        PlanItemStatus.inProgress => 'in_progress',
        PlanItemStatus.paused => 'paused',
        PlanItemStatus.completed => 'completed',
        PlanItemStatus.removed => 'removed',
      };

  static PlanItemStatus fromString(String s) => PlanItemStatus.values
      .firstWhere((e) => e.value == s, orElse: () => PlanItemStatus.notStarted);
}

class Activity {
  final int? id;
  final String name;
  final String? description;
  final String? category;
  final int? estimatedMinutes;
  final String? importance;
  final bool endNudgeEnabled;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;
  Activity(
      {this.id,
      required this.name,
      this.description,
      this.category,
      this.estimatedMinutes,
      this.importance,
      this.endNudgeEnabled = false,
      this.isArchived = false,
      required this.createdAt,
      required this.updatedAt});
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'estimated_minutes': estimatedMinutes,
        'importance': importance,
        'end_nudge_enabled': endNudgeEnabled ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt
      };
  static Activity fromMap(Map<String, dynamic> m) => Activity(
      id: m['id'],
      name: m['name'],
      description: m['description'],
      category: m['category'],
      estimatedMinutes: m['estimated_minutes'],
      importance: m['importance'],
      endNudgeEnabled: (m['end_nudge_enabled'] ?? 0) == 1,
      isArchived: (m['is_archived'] ?? 0) == 1,
      createdAt: m['created_at'],
      updatedAt: m['updated_at']);
}

class DailyPlan {
  final int? id;
  final String planDate; // YYYY-MM-DD local
  final String createdAt;
  final String updatedAt;
  final String? timezoneId;
  DailyPlan(
      {this.id,
      required this.planDate,
      required this.createdAt,
      required this.updatedAt,
      this.timezoneId});
  Map<String, dynamic> toMap() => {
        'id': id,
        'plan_date': planDate,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'timezone_id': timezoneId
      };
  static DailyPlan fromMap(Map<String, dynamic> m) => DailyPlan(
      id: m['id'],
      planDate: m['plan_date'],
      createdAt: m['created_at'],
      updatedAt: m['updated_at'],
      timezoneId: m['timezone_id']);
}

class DailyPlanActivity {
  final int? id;
  final int planId;
  final int? activityId;
  final String snapshotName;
  final String? snapshotDescription;
  final String? snapshotCategory;
  final int displayOrder;
  final PlanItemStatus status;
  final int? estimatedMinutes;
  final String? importance;
  final String? intent; // Relax, Have fun, Recover
  final String? notes;
  final String? completedAt;
  final String createdAt;
  final String updatedAt;
  DailyPlanActivity(
      {this.id,
      required this.planId,
      this.activityId,
      required this.snapshotName,
      this.snapshotDescription,
      this.snapshotCategory,
      required this.displayOrder,
      required this.status,
      this.estimatedMinutes,
      this.importance,
      this.intent,
      this.notes,
      this.completedAt,
      required this.createdAt,
      required this.updatedAt});
  Map<String, dynamic> toMap() => {
        'id': id,
        'plan_id': planId,
        'activity_id': activityId,
        'snapshot_name': snapshotName,
        'snapshot_description': snapshotDescription,
        'snapshot_category': snapshotCategory,
        'display_order': displayOrder,
        'status': status.value,
        'estimated_minutes': estimatedMinutes,
        'importance': importance,
        'intent': intent,
        'notes': notes,
        'completed_at': completedAt,
        'created_at': createdAt,
        'updated_at': updatedAt
      };
  static DailyPlanActivity fromMap(Map<String, dynamic> m) => DailyPlanActivity(
      id: m['id'],
      planId: m['plan_id'],
      activityId: m['activity_id'],
      snapshotName: m['snapshot_name'],
      snapshotDescription: m['snapshot_description'],
      snapshotCategory: m['snapshot_category'],
      displayOrder: m['display_order'],
      status: PlanItemStatusX.fromString(m['status']),
      estimatedMinutes: m['estimated_minutes'],
      importance: m['importance'],
      intent: m['intent'],
      notes: m['notes'],
      completedAt: m['completed_at'],
      createdAt: m['created_at'],
      updatedAt: m['updated_at']);
}

class ActivitySession {
  final int? id;
  final int dailyPlanActivityId;
  final String startedAt; // UTC ISO
  final String? endedAt;
  final String? endReason; // paused / finished / interrupted / corrected
  final String? lastConfirmedAt;
  final String createdAt;
  ActivitySession(
      {this.id,
      required this.dailyPlanActivityId,
      required this.startedAt,
      this.endedAt,
      this.endReason,
      this.lastConfirmedAt,
      required this.createdAt});
  Map<String, dynamic> toMap() => {
        'id': id,
        'daily_plan_activity_id': dailyPlanActivityId,
        'started_at': startedAt,
        'ended_at': endedAt,
        'end_reason': endReason,
        'last_confirmed_at': lastConfirmedAt,
        'created_at': createdAt
      };
  static ActivitySession fromMap(Map<String, dynamic> m) => ActivitySession(
      id: m['id'],
      dailyPlanActivityId: m['daily_plan_activity_id'],
      startedAt: m['started_at'],
      endedAt: m['ended_at'],
      endReason: m['end_reason'],
      lastConfirmedAt: m['last_confirmed_at'],
      createdAt: m['created_at']);
}
