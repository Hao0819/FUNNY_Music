import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/app_backup.dart';

/// A backup file on disk, with its contents if they could be parsed.
class StoredAppBackup {
  const StoredAppBackup({required this.file, this.backup, this.error});

  final File file;

  /// Null when the file could not be read as a backup; [error] then says why.
  final AppBackup? backup;
  final String? error;

  String get fileName => p.basename(file.path);
}

/// Reads and writes backups as JSON files.
///
/// Files go somewhere a file manager can see, because one case this exists for
/// is the app's own storage going wrong: a backup kept inside the app's
/// private directory would be lost by the same clear-data that loses the
/// folders. Nothing here touches Hive or the user's audio.
///
/// It is not somewhere *another phone* can see, though — Android 11 put
/// `Android/data` out of reach of file managers. So the screen above this
/// shares the file out through the system share sheet and takes one back in
/// through the file picker, and this class copies what the picker returned
/// into the same directory ([adopt]) so a restore has one code path.
class AppBackupStore {
  /// Still `folder_backups`, although a backup is no longer only folders:
  /// renaming the directory would orphan the backups already sitting on real
  /// devices, which is the one thing a backup directory must not do.
  static const _directoryName = 'folder_backups';
  static const _prefix = 'funny-music-';
  static const _extension = '.json';

  /// 16 MB. See [adopt].
  static const _maxReadableBytes = 16 * 1024 * 1024;

  /// `Android/data/<package>/files/folder_backups` on Android: visible to a
  /// file manager, writable without asking for any storage permission, and
  /// the app's own space so nothing else is at risk if it goes wrong.
  Future<Directory> directory() async {
    final external = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final base = external ?? await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, _directoryName));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> write(AppBackup backup) async {
    final file = await _freeFile(backup.createdAt);
    await file.writeAsString(backup.encode(), flush: true);
    return file;
  }

  /// Takes a copy of a backup the user picked from somewhere else, so it joins
  /// the saved list and can be restored again later without picking it twice.
  ///
  /// The contents are parsed before anything is written: a file chosen by hand
  /// from a share sheet is as likely to be the wrong file as the right one.
  Future<StoredAppBackup> adopt(File source) async {
    // A picker shows every file on the device, so the thing most likely to be
    // handed to this method after the right file is an audio file. Reading one
    // as text would mean decoding tens of megabytes to reach the conclusion
    // that it is not JSON; a backup of a very large library is a few hundred
    // kilobytes, so the ceiling here is generous by two orders of magnitude.
    final size = await source.length();
    if (size > _maxReadableBytes) {
      throw const FormatException('that file is far too large to be a backup');
    }

    final AppBackup backup;
    try {
      backup = AppBackup.decode(await source.readAsString());
    } on FileSystemException {
      // Not text at all. Still the user picking the wrong file, so it is
      // reported the same way rather than as a storage failure.
      throw const FormatException('that file is not text');
    }

    final file = await _freeFile(backup.createdAt);
    await file.writeAsString(backup.encode(), flush: true);
    return StoredAppBackup(file: file, backup: backup);
  }

  /// Every backup in the directory, newest first, each parsed so the list can
  /// show what restoring it would bring back.
  Future<List<StoredAppBackup>> list() async {
    final directory = await this.directory();
    final files = (await directory.list().toList())
        .whereType<File>()
        .where((file) => p.extension(file.path) == _extension)
        .toList()
      // Names carry a sortable timestamp, so this is chronological. Mtime
      // would not be: copying files about rewrites it. The older `folders-`
      // prefix sorts after this one, which costs nothing — the two prefixes
      // only ever interleave on a device that upgraded mid-history.
      ..sort((a, b) => _stampOf(b).compareTo(_stampOf(a)));

    final result = <StoredAppBackup>[];
    for (final file in files) {
      try {
        result.add(StoredAppBackup(file: file, backup: AppBackup.decode(await file.readAsString())));
      } catch (error) {
        // Listed anyway: an unreadable file in this directory is something the
        // user should see rather than have quietly hidden from them.
        result.add(StoredAppBackup(file: file, error: '$error'));
      }
    }
    return result;
  }

  Future<AppBackup> read(File file) async => AppBackup.decode(await file.readAsString());

  Future<void> delete(File file) async {
    if (await file.exists()) await file.delete();
  }

  /// A path in the backup directory that nothing is using yet. Two backups can
  /// genuinely share a timestamp — a file imported from another phone, then
  /// the same file imported again — and the second must not overwrite the
  /// first silently.
  Future<File> _freeFile(DateTime createdAt) async {
    final directory = await this.directory();
    final base = p.join(directory.path, '$_prefix${_stamp(createdAt)}');

    var file = File('$base$_extension');
    var attempt = 2;
    while (await file.exists()) {
      file = File('$base-$attempt$_extension');
      attempt++;
    }
    return file;
  }

  /// `2026-10-06-153012` — sortable as text, and legible in a file name.
  String _stamp(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        '-${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }

  /// The timestamp part of a file name, with the prefix dropped so files
  /// written under either prefix sort against each other by date.
  String _stampOf(File file) =>
      p.basenameWithoutExtension(file.path).replaceFirst(RegExp(r'^(funny-music|folders)-'), '');
}
