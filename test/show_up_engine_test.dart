import 'package:flutter_test/flutter_test.dart';
import 'package:daily_command/features/show_up_engine.dart';
import 'package:daily_command/shared/models.dart';

void main() {
  test('free-time suggestions keep activities longer than the available time',
      () {
    final activities = [
      _activity('Long research', 90),
      _activity('Short break', 10),
      _activity('No estimate', null),
    ];

    final suggestions = ShowUpEngine.filterByFreeTime(
      activities: activities,
      availableMinutes: 10,
    );

    expect(suggestions, hasLength(3));
    expect(suggestions.map((activity) => activity.name), [
      'Short break',
      'Long research',
      'No estimate',
    ]);
    expect(ShowUpEngine.suggestedSmallStart(90, 10), 10);
    expect(ShowUpEngine.suggestedSmallStart(90, 20), 20);
  });
}

Activity _activity(String name, int? estimate) => Activity(
      name: name,
      estimatedMinutes: estimate,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );
