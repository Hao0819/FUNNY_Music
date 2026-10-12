import 'dart:convert';

/// A portable snapshot of the folder structure: every folder, and the file
/// paths filed into each one.
///
/// Folder links are the one thing in this app that cannot be rebuilt. The
/// library is rescanned from the device on every launch, but which track
/// belongs in which folder only ever exists in one local box — so it is worth
/// being able to write it out as a plain file and read it back.
class FolderBackup {
  const FolderBackup({
    required this.createdAt,
    required this.folders,
    this.version = currentVersion,
  });

  factory FolderBackup.fromJson(Map<String, Object?> json) {
    final folders = json['folders'];
    if (folders is! List) {
      throw const FormatException('A folder backup needs a "folders" list.');
    }

    return FolderBackup(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      createdAt: parseBackupDate(json['createdAt']),
      folders: folders.map((entry) {
        if (entry is! Map) {
          throw const FormatException('Every folder entry must be an object.');
        }
        return BackedUpFolder.fromJson(entry.cast<String, Object?>());
      }).toList(),
    );
  }

  /// Parses a backup file's text, throwing [FormatException] on anything that
  /// is not one — the user picks these files by hand, so "this isn't a folder
  /// backup" has to be a reportable outcome rather than a crash.
  factory FolderBackup.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('A folder backup must be a JSON object.');
    }
    return FolderBackup.fromJson(decoded.cast<String, Object?>());
  }

  /// Bumped only if the shape stops being readable by an older build.
  static const currentVersion = 1;

  final int version;
  final DateTime createdAt;
  final List<BackedUpFolder> folders;

  int get trackCount => folders.fold(0, (sum, folder) => sum + folder.trackPaths.length);

  Map<String, Object?> toJson() => {
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'folders': [for (final folder in folders) folder.toJson()],
      };

  /// Indented deliberately: a backup is something a person may well end up
  /// opening in a text editor to check, or to fix a path by hand.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class BackedUpFolder {
  const BackedUpFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackPaths,
    this.isSystem = false,
    this.sortMode = 'manual',
    this.sortDescending = false,
    this.colorValue,
    this.coverPath,
  });

  factory BackedUpFolder.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Every folder in a backup needs a name.');
    }

    final paths = json['trackPaths'];
    return BackedUpFolder(
      id: json['id'] as String? ?? '',
      name: name,
      createdAt: parseBackupDate(json['createdAt']),
      isSystem: json['isSystem'] == true,
      sortMode: json['sortMode'] as String? ?? 'manual',
      sortDescending: json['sortDescending'] == true,
      colorValue: (json['colorValue'] as num?)?.toInt(),
      coverPath: json['coverPath'] as String?,
      // Paths are the payload, so anything that isn't a usable one is dropped
      // rather than taken as grounds to reject the whole file.
      trackPaths: paths is List
          ? paths.whereType<String>().where((path) => path.isNotEmpty).toList()
          : const [],
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final bool isSystem;
  final String sortMode;

  /// Whether the folder was being read back to front on the device that
  /// wrote the backup.
  final bool sortDescending;
  final int? colorValue;

  /// Where the chosen cover lived on the device that wrote the backup. Carried
  /// so restoring onto the same device keeps the picture; on another device the
  /// path simply will not resolve and the playlist falls back to its artwork.
  final String? coverPath;

  final List<String> trackPaths;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'isSystem': isSystem,
        'sortMode': sortMode,
        'sortDescending': sortDescending,
        'colorValue': colorValue,
        'coverPath': coverPath,
        'trackPaths': trackPaths,
      };
}

/// What restoring a backup actually changed.
class FolderImportSummary {
  const FolderImportSummary({
    required this.foldersCreated,
    required this.linksAdded,
    this.linksRemapped = 0,
    this.linksUnresolved = 0,
  });

  final int foldersCreated;
  final int linksAdded;

  /// Of [linksAdded], how many were matched to a file by name because the path
  /// the backup carried had nothing behind it. Expected when the backup came
  /// from another device; worth reporting, because the match is a guess.
  final int linksRemapped;

  /// Of [linksAdded], how many matched nothing at all and kept the path the
  /// backup gave them. These show up in their folder as "not found".
  final int linksUnresolved;

  bool get changedNothing => foldersCreated == 0 && linksAdded == 0;
}

/// Reads a date written by [FolderBackup.encode], or null if it is not one.
///
/// Public because every section of a backup file stores its dates this way,
/// and the sections are parsed from different files — see `app_backup.dart`.
DateTime? tryParseBackupDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// [tryParseBackupDate] falling back to the epoch, for the dates a backup can
/// manage without: one with an unreadable date is still a perfectly good list
/// of paths.
DateTime parseBackupDate(Object? value) =>
    tryParseBackupDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
