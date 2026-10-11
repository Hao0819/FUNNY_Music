import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/hive/hive_setup.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/app_backup.dart';
import '../../../domain/backup_path_resolver.dart';
import '../../../domain/folder_backup.dart';
import '../../../services/backup/app_backup_store.dart';
import '../../folders/providers/folder_providers.dart';
import '../../library/providers/library_providers.dart';
import 'theme_mode_provider.dart';

final appBackupStoreProvider = Provider<AppBackupStore>((ref) => AppBackupStore());

/// Boxes this launch had to set aside because their file would not open.
/// Startup state, so it never changes while the app is running.
final setAsideBoxesProvider = Provider<List<SetAsideBox>>((ref) => List.unmodifiable(setAsideBoxes));

/// The backup files currently on disk, newest first.
final appBackupsProvider = FutureProvider<List<StoredAppBackup>>((ref) {
  return ref.watch(appBackupStoreProvider).list();
});

/// Where the backups are kept, shown to the user so they can get at the files
/// with a file manager or copy them off the device.
final appBackupDirectoryProvider = FutureProvider<String>((ref) async {
  final directory = await ref.watch(appBackupStoreProvider).directory();
  return directory.path;
});

/// What exporting right now would write out, for the button's subtitle.
final appBackupPreviewProvider = Provider<AppBackup>((ref) {
  ref.watch(folderLinksTickProvider);
  ref.watch(folderListProvider);
  ref.watch(hiddenTracksProvider);
  ref.watch(historyTickProvider);
  return _buildBackup(ref);
});

/// Matches the paths in a backup against the files on this device.
///
/// Built from the whole scan rather than the visible library, since a backup
/// also carries the paths of tracks the user had hidden. Empty until the first
/// scan lands, which is why the restore button waits for it.
final backupPathResolverProvider = Provider<BackupPathResolver>((ref) {
  return BackupPathResolver(ref.watch(tracksByPathProvider).keys);
});

AppBackup _buildBackup(Ref ref) {
  final folders = ref.read(folderRepositoryProvider).exportBackup();
  return AppBackup(
    createdAt: folders.createdAt,
    folders: folders,
    hiddenTrackPaths: ref.read(hiddenTracksRepositoryProvider).paths.toList(),
    playHistory: ref.read(historyRepositoryProvider).exportEntries(),
    knownTracks: ref.read(knownTracksRepositoryProvider).exportRecords(),
    settings: ref.read(settingsRepositoryProvider).exportBackup(),
  );
}

/// What a restore did, across all five boxes it writes to.
class RestoreSummary {
  const RestoreSummary({
    required this.folders,
    required this.tracksHidden,
    required this.playsLogged,
    required this.firstSeenDatesKept,
    required this.settingsApplied,
  });

  final FolderImportSummary folders;
  final int tracksHidden;
  final int playsLogged;
  final int firstSeenDatesKept;
  final bool settingsApplied;

  bool get changedNothing =>
      folders.changedNothing &&
      tracksHidden == 0 &&
      playsLogged == 0 &&
      firstSeenDatesKept == 0 &&
      !settingsApplied;
}

class AppBackupActions {
  AppBackupActions(this._ref);

  final Ref _ref;

  Future<StoredAppBackup> exportNow() async {
    final backup = _buildBackup(_ref);
    final file = await _ref.read(appBackupStoreProvider).write(backup);
    _ref.invalidate(appBackupsProvider);
    return StoredAppBackup(file: file, backup: backup);
  }

  /// Hands the file to whatever the user wants to send it with.
  ///
  /// This is how a backup reaches another phone at all: the directory it is
  /// written to is inside `Android/data`, which no file manager can open since
  /// Android 11, so without the share sheet the only way off the device is a
  /// PC and adb.
  Future<void> share(StoredAppBackup stored) {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(stored.file.path, mimeType: 'application/json')],
        subject: 'FUNNY Music backup',
        text: 'FUNNY Music backup — open the app on the other phone, then '
            'Settings → Backup & transfer → Import.',
      ),
    );
  }

  /// Picks a backup from anywhere on the device and takes a copy of it.
  ///
  /// Returns null when the user backed out of the picker. Throws
  /// [FormatException] when what they picked is not a backup, which is a
  /// perfectly ordinary outcome of choosing a file by hand.
  Future<StoredAppBackup?> importFromFile() async {
    // No `allowedExtensions`: on Android that filters by mime type through the
    // document provider, and a .json file arriving from a chat app or Drive
    // regularly has a type that does not survive the trip. The file is parsed
    // before anything is kept, so letting the picker show everything costs
    // nothing but is the difference between finding the file and not.
    final picked = await FilePicker.pickFile(dialogTitle: 'Pick a FUNNY Music backup');
    final path = picked?.path;
    if (path == null) return null;

    final stored = await _ref.read(appBackupStoreProvider).adopt(File(path));
    _ref.invalidate(appBackupsProvider);
    return stored;
  }

  /// How the paths in a backup line up with this device, so the user can be
  /// told before they commit to anything.
  PathMatchCounts preview(AppBackup backup) =>
      _ref.read(backupPathResolverProvider).tally(backup.allTrackPaths);

  /// Re-read from disk rather than trusting the parsed copy the list is
  /// holding, so what gets restored is what the file says right now.
  Future<RestoreSummary> restore(StoredAppBackup stored, {required bool applySettings}) async {
    final backup = await _ref.read(appBackupStoreProvider).read(stored.file);
    final resolver = _ref.read(backupPathResolverProvider);

    final folders = await _ref.read(folderRepositoryProvider).importBackup(
          backup.folders,
          resolver: resolver,
        );
    final tracksHidden = await _ref.read(hiddenTracksRepositoryProvider).importHidden(
          backup.hiddenTrackPaths,
          resolver: resolver,
        );
    final playsLogged = await _ref.read(historyRepositoryProvider).importEntries(
          backup.playHistory,
          resolver: resolver,
        );
    final firstSeenDatesKept = await _ref.read(knownTracksRepositoryProvider).importRecords(
          backup.knownTracks,
          resolver: resolver,
        );

    final settings = backup.settings;
    final settingsApplied = applySettings && settings != null;
    if (settingsApplied) await _ref.read(settingsRepositoryProvider).applyBackup(settings);

    // Every notifier below reads its box once in `build`, so a restore is
    // invisible until they are told to read it again.
    _ref.read(folderActionsProvider).notifyLinksChanged();
    if (tracksHidden > 0) _ref.invalidate(hiddenTracksProvider);
    if (playsLogged > 0) _ref.read(historyTickProvider.notifier).bump();
    if (firstSeenDatesKept > 0) _ref.read(knownTracksTickProvider.notifier).bump();
    if (settingsApplied) {
      _ref.invalidate(themeModeProvider);
      _ref.invalidate(librarySortProvider);
      // The repeat mode is read by the player when it starts up, so it is
      // deliberately not pushed here — the screen says it needs a restart
      // instead of this reaching into playback behind the user's back.
    }

    return RestoreSummary(
      folders: folders,
      tracksHidden: tracksHidden,
      playsLogged: playsLogged,
      firstSeenDatesKept: firstSeenDatesKept,
      settingsApplied: settingsApplied,
    );
  }

  Future<void> delete(StoredAppBackup stored) async {
    await _ref.read(appBackupStoreProvider).delete(stored.file);
    _ref.invalidate(appBackupsProvider);
  }
}

final appBackupActionsProvider = Provider<AppBackupActions>((ref) => AppBackupActions(ref));
