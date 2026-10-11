import 'dart:convert';

import 'folder_backup.dart';

/// Everything the app remembers that a rescan cannot rebuild, as one portable
/// file: the folders, plus the hidden list, the play log, the first-seen
/// bookkeeping and the settings.
///
/// This exists for moving to a new phone. Folders alone were enough while a
/// backup was only insurance against this device's own storage going wrong —
/// but someone changing phones also loses their play counts, what they had
/// hidden and their theme, and those live in four other boxes.
///
/// ## Why the folders stay at the top level
///
/// A v2 file writes the `folders` list exactly where a v1 file had it, so
/// [FolderBackup.fromJson] still reads a v2 file and recovers the folders from
/// it — an older build can restore a backup written by a newer one. The
/// reverse holds because every section added here is optional: reading a v1
/// file simply leaves them empty. Neither direction is allowed to throw, since
/// the file the user picks is often the only copy they have.
class AppBackup {
  const AppBackup({
    required this.createdAt,
    required this.folders,
    this.hiddenTrackPaths = const [],
    this.playHistory = const [],
    this.knownTracks = const [],
    this.settings,
    this.version = currentVersion,
  });

  factory AppBackup.fromJson(Map<String, Object?> json) {
    // The folders section is handed to the v1 parser rather than re-read here:
    // it owns what counts as a usable folder entry, and that judgement should
    // not drift between the two readers.
    final folders = FolderBackup.fromJson(json);
    final settings = json['settings'];

    return AppBackup(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      createdAt: folders.createdAt,
      folders: folders,
      hiddenTrackPaths: _paths(json['hiddenTrackPaths']),
      playHistory: _section(json['playHistory'], BackedUpPlay.fromJson),
      knownTracks: _section(json['knownTracks'], BackedUpKnownTrack.fromJson),
      settings: settings is Map ? BackedUpSettings.fromJson(settings.cast<String, Object?>()) : null,
    );
  }

  /// Parses a backup file's text, throwing [FormatException] on anything that
  /// is not one — the user picks these files by hand, so "this isn't a backup"
  /// has to be a reportable outcome rather than a crash.
  factory AppBackup.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('A backup must be a JSON object.');
    }
    return AppBackup.fromJson(decoded.cast<String, Object?>());
  }

  /// 1 was folders only; 2 added the four sections below.
  static const currentVersion = 2;

  final int version;
  final DateTime createdAt;
  final FolderBackup folders;
  final List<String> hiddenTrackPaths;
  final List<BackedUpPlay> playHistory;
  final List<BackedUpKnownTrack> knownTracks;

  /// Null when the file carries no settings section, which is what a v1 file
  /// looks like.
  final BackedUpSettings? settings;

  int get folderCount => folders.folders.length;

  int get trackCount => folders.trackCount;

  /// Every path the file references, which is what an import has to match
  /// against the library on this device.
  Set<String> get allTrackPaths => {
        for (final folder in folders.folders) ...folder.trackPaths,
        ...hiddenTrackPaths,
        for (final play in playHistory) play.trackPath,
        for (final known in knownTracks) known.path,
      };

  Map<String, Object?> toJson() => {
        // Spread first so the folders section is written exactly as a v1
        // writer would write it, then correct the header to this version.
        ...folders.toJson(),
        'version': version,
        'createdAt': createdAt.toIso8601String(),
        'hiddenTrackPaths': hiddenTrackPaths,
        'playHistory': [for (final play in playHistory) play.toJson()],
        'knownTracks': [for (final known in knownTracks) known.toJson()],
        'settings': settings?.toJson(),
      };

  /// Indented deliberately: a backup is something a person may well end up
  /// opening in a text editor to check, or to fix a path by hand.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// One entry of the play log. The log is the only source for "recently
/// played", "most played" and every play count, so it travels as its raw
/// entries rather than as counts.
class BackedUpPlay {
  const BackedUpPlay({required this.trackPath, required this.playedAt});

  /// Null for an entry with no usable path or date. Unlike a folder, an entry
  /// is nothing but those two fields, so a broken one is dropped.
  static BackedUpPlay? fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final playedAt = tryParseBackupDate(json['playedAt']);
    if (path is! String || path.isEmpty || playedAt == null) return null;
    return BackedUpPlay(trackPath: path, playedAt: playedAt);
  }

  final String trackPath;
  final DateTime playedAt;

  Map<String, Object?> toJson() => {
        'path': trackPath,
        'playedAt': playedAt.toIso8601String(),
      };
}

/// When a file was first seen, so the "recently added" filter on the new
/// device does not report a whole migrated library as new.
class BackedUpKnownTrack {
  const BackedUpKnownTrack({
    required this.path,
    required this.firstSeenAt,
    this.acknowledged = true,
  });

  static BackedUpKnownTrack? fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final firstSeenAt = tryParseBackupDate(json['firstSeenAt']);
    if (path is! String || path.isEmpty || firstSeenAt == null) return null;
    return BackedUpKnownTrack(
      path: path,
      firstSeenAt: firstSeenAt,
      // Only an unacknowledged record is worth announcing as new, so the safe
      // default for a field an older file lacks is "already seen".
      acknowledged: json['acknowledged'] != false,
    );
  }

  final String path;
  final DateTime firstSeenAt;
  final bool acknowledged;

  Map<String, Object?> toJson() => {
        'path': path,
        'firstSeenAt': firstSeenAt.toIso8601String(),
        'acknowledged': acknowledged,
      };
}

/// The settings worth carrying between devices. Every field is nullable
/// because restoring applies only what the file actually says: a backup
/// written by a build that did not know about a setting leaves it alone.
class BackedUpSettings {
  const BackedUpSettings({
    this.themeMode,
    this.librarySortField,
    this.librarySortAscending,
    this.repeatMode,
    this.downloadHistoryHidden,
    this.recentDownloadSearches,
  });

  factory BackedUpSettings.fromJson(Map<String, Object?> json) {
    final searches = json['recentDownloadSearches'];
    return BackedUpSettings(
      themeMode: json['themeMode'] as String?,
      librarySortField: json['librarySortField'] as String?,
      librarySortAscending: json['librarySortAscending'] as bool?,
      repeatMode: json['repeatMode'] as String?,
      downloadHistoryHidden: json['downloadHistoryHidden'] as bool?,
      recentDownloadSearches: searches is List ? searches.whereType<String>().toList() : null,
    );
  }

  final String? themeMode;
  final String? librarySortField;
  final bool? librarySortAscending;
  final String? repeatMode;
  final bool? downloadHistoryHidden;
  final List<String>? recentDownloadSearches;

  Map<String, Object?> toJson() => {
        'themeMode': themeMode,
        'librarySortField': librarySortField,
        'librarySortAscending': librarySortAscending,
        'repeatMode': repeatMode,
        'downloadHistoryHidden': downloadHistoryHidden,
        'recentDownloadSearches': recentDownloadSearches,
      };
}

List<String> _paths(Object? value) =>
    value is List ? value.whereType<String>().where((path) => path.isNotEmpty).toList() : const [];

/// Maps a section's entries through a parser that returns null for the ones it
/// cannot use, dropping those rather than rejecting the whole file.
List<T> _section<T>(Object? value, T? Function(Map<String, Object?>) parse) {
  if (value is! List) return const [];
  final result = <T>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    final parsed = parse(entry.cast<String, Object?>());
    if (parsed != null) result.add(parsed);
  }
  return result;
}
