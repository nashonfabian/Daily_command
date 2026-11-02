import '../shared/models.dart';

class ShowUpEngine {
  static List<Activity> filterByFreeTime({required List<Activity> activities, required int availableMinutes}){
    final fitting = <Activity>[];
    final longer = <Activity>[];
    for(final a in activities){
      final est = a.estimatedMinutes ?? 30;
      if(est <= availableMinutes) { fitting.add(a); } else { longer.add(a); }
    }
    return [...fitting, ...longer];
  }

  static int suggestedSmallStart(int? estimated, int available){
    if(available <= 10) return available;
    if(estimated == null) return available.clamp(10, 30);
    if(estimated > available) return available;
    return estimated;
  }

  static const String freeTimePrompt = "You have free time. What are you actually doing with it?";
  static const String freeTimeFollow = "What matters to you right now?";
  static const String goodLetsShowUp = "Good. Let's show up.";

  static String postponementQuestion(String activityName) => 'Is it genuinely impossible to do "$activityName" today, or are you postponing something you could begin now?';
  static String plannedNotStarted(String name) => 'You planned to give time to "$name". Are you ready to show up?';
}
