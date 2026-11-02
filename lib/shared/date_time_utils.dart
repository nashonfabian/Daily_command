import 'package:intl/intl.dart';

class DateTimeUtils {
  static String? localTimezoneId;

  static String todayLocalYYYYMMDD() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(now);
  }

  static String formatDate(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);
  static String nowUtcIso() => DateTime.now().toUtc().toIso8601String();
  static Duration parseDuration(String startedUtc, String? endedUtc) {
    final s = DateTime.parse(startedUtc);
    final e =
        endedUtc != null ? DateTime.parse(endedUtc) : DateTime.now().toUtc();
    return e.difference(s);
  }

  static String formatMinutes(int totalMinutes) {
    if (totalMinutes < 60) return '${totalMinutes}m';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
