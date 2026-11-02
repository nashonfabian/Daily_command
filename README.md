
# DAILY COMMAND
TODAY MATTERS. SHOW UP.

Offline-first Flutter app. Android first.

## Build
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release

## Features
- My Day / Activities / Settings
- Offline SQLite storage with daily activity snapshots and safe migrations
- Activity library with custom categories, archive and restore
- Ordered daily plans with drag reordering and deliberate rescheduling
- Persisted stopwatch segments, one-running rule and interruption recovery
- Free-time suggestions, smaller starts and intentional recreation prompts
- Optional local reminders with weekday selection, quiet hours and timezone support
- Manual, evening and next-open day review; no automatic rollover

## Validation
Run `flutter analyze` and `flutter test` before building. Android builds require
an installed Android SDK and configured Flutter Android toolchain.

The current Android release build type uses the debug signing configuration
for local build verification. Configure a production keystore before
distributing a release APK.
