import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../domain/app_backup.dart';
import '../hive/hive_setup.dart';
import '../hive/models/app_settings_model.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository());

class SettingsRepository {
  static const _key = 'settings';

  Box<AppSettingsModel> get _box => Hive.box<AppSettingsModel>(HiveBoxes.settings);

  AppSettingsModel get current => _box.get(_key) ?? AppSettingsModel();

  Future<void> save(AppSettingsModel settings) => _box.put(_key, settings);

  Future<void> updateThemeMode(String themeMode) async {
    final settings = current;
    settings.themeMode = themeMode;
    await save(settings);
  }

  /// Defaults to repeating the whole queue, so a folder or playlist loops
  /// back to its first track instead of stopping after the last.
  String get repeatMode => current.repeatMode ?? 'all';

  Future<void> updateRepeatMode(String repeatMode) async {
    final settings = current;
    settings.repeatMode = repeatMode;
    await save(settings);
  }

  bool get downloadHistoryHidden => current.downloadHistoryHidden ?? false;

  Future<void> updateDownloadHistoryHidden(bool hidden) async {
    final settings = current;
    settings.downloadHistoryHidden = hidden;
    await save(settings);
  }

  /// How many recent download searches are kept. Short on purpose: the list
  /// sits directly under the search field, and anything longer pushes the
  /// results off the screen.
  static const recentDownloadSearchLimit = 5;

  List<String> get recentDownloadSearches =>
      List.unmodifiable(current.recentDownloadSearches ?? const <String>[]);

  Future<void> saveRecentDownloadSearches(List<String> queries) async {
    final settings = current;
    settings.recentDownloadSearches = queries.take(recentDownloadSearchLimit).toList();
    await save(settings);
  }

  BackedUpSettings exportBackup() {
    final settings = current;
    return BackedUpSettings(
      themeMode: settings.themeMode,
      librarySortField: settings.librarySortField,
      librarySortAscending: settings.librarySortAscending,
      repeatMode: settings.repeatMode,
      downloadHistoryHidden: settings.downloadHistoryHidden,
      recentDownloadSearches: settings.recentDownloadSearches,
    );
  }

  /// Applies the settings a backup carried, field by field.
  ///
  /// This is the one part of a restore that overwrites rather than fills in
  /// gaps — there is no way to merge two answers to "which theme". It is why
  /// the restore dialog asks about settings separately, and why a field the
  /// backup left null is skipped rather than reset to its default.
  Future<void> applyBackup(BackedUpSettings backup) async {
    final settings = current;
    settings.themeMode = backup.themeMode ?? settings.themeMode;
    settings.librarySortField = backup.librarySortField ?? settings.librarySortField;
    settings.librarySortAscending = backup.librarySortAscending ?? settings.librarySortAscending;
    settings.repeatMode = backup.repeatMode ?? settings.repeatMode;
    settings.downloadHistoryHidden = backup.downloadHistoryHidden ?? settings.downloadHistoryHidden;
    settings.recentDownloadSearches =
        backup.recentDownloadSearches?.take(recentDownloadSearchLimit).toList() ??
            settings.recentDownloadSearches;
    await save(settings);
  }
}
