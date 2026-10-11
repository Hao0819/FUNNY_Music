import 'package:path/path.dart' as p;

/// How a path in a backup was matched to a file on this device.
enum PathMatch {
  /// The library holds this exact path. The common case on the same device.
  exact,

  /// No file at that path, but one with the same name is in the library and
  /// the link now points at it.
  renamed,

  /// Nothing in the library matches. The original path is kept.
  unresolved,
}

class ResolvedPath {
  const ResolvedPath(this.path, this.match);

  /// The path to store: the matched file, or the backup's own path when
  /// nothing matched.
  final String path;

  final PathMatch match;

  bool get isUnresolved => match == PathMatch.unresolved;
}

/// How a whole backup's paths landed, for telling the user what a restore
/// would do before it does it.
class PathMatchCounts {
  const PathMatchCounts({required this.exact, required this.renamed, required this.unresolved});

  final int exact;
  final int renamed;
  final int unresolved;

  int get total => exact + renamed + unresolved;
}

/// Matches the paths in a backup against the files this device actually has.
///
/// Folder links, the hidden list and the play log all reference tracks by
/// absolute path, which is exactly right on one device and wrong as soon as
/// the backup is restored on another: the same songs sit under a different
/// volume id, or in a directory the user renamed while copying them over, and
/// a restore that only compares absolute paths brings back a library-wide list
/// of "not found".
///
/// So a path that is not in the library is retried by file name. That is a
/// guess, but a conservative one — the only thing it can get wrong is which of
/// two identically named files a link points at, and it is checked against the
/// library rather than the filesystem, so it can never invent a path.
///
/// Flutter-free and pure on purpose: this is the part of a restore worth
/// testing exhaustively.
class BackupPathResolver {
  BackupPathResolver(Iterable<String> libraryPaths) : _known = libraryPaths.toSet() {
    for (final path in _known) {
      _byName.putIfAbsent(_nameKey(path), () => <String>[]).add(path);
    }
    // Sorted so a tie between identically named files resolves the same way
    // every time it is asked, including between the preview the user is shown
    // and the restore they then confirm.
    for (final candidates in _byName.values) {
      candidates.sort();
    }
  }

  /// A resolver that matches nothing, so every path keeps the value the backup
  /// gave it. Used when the library has not been scanned yet.
  BackupPathResolver.none() : this(const []);

  final Set<String> _known;
  final Map<String, List<String>> _byName = {};

  bool get isEmpty => _known.isEmpty;

  ResolvedPath resolve(String backupPath) {
    if (_known.contains(backupPath)) return ResolvedPath(backupPath, PathMatch.exact);

    final candidates = _byName[_nameKey(backupPath)];
    if (candidates == null || candidates.isEmpty) {
      // Kept as it was, which is what makes this reversible: the link comes
      // back on its own if the file later turns up where the backup says.
      return ResolvedPath(backupPath, PathMatch.unresolved);
    }
    if (candidates.length == 1) return ResolvedPath(candidates.first, PathMatch.renamed);

    // Several files share the name, so the one sitting in the most similar
    // place wins — `Music/live/intro.mp3` should match another `live/intro.mp3`
    // ahead of a `demos/intro.mp3`.
    var best = candidates.first;
    var bestScore = -1;
    for (final candidate in candidates) {
      final score = _sharedTrailingSegments(backupPath, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return ResolvedPath(best, PathMatch.renamed);
  }

  PathMatchCounts tally(Iterable<String> paths) {
    var exact = 0;
    var renamed = 0;
    var unresolved = 0;
    for (final path in paths) {
      switch (resolve(path).match) {
        case PathMatch.exact:
          exact++;
        case PathMatch.renamed:
          renamed++;
        case PathMatch.unresolved:
          unresolved++;
      }
    }
    return PathMatchCounts(exact: exact, renamed: renamed, unresolved: unresolved);
  }

  /// Always the posix context: these are Android paths, and resolving them
  /// must not depend on the separator the host running the tests uses.
  static String _nameKey(String path) => p.posix.basename(path).toLowerCase();

  static int _sharedTrailingSegments(String a, String b) {
    final left = p.posix.split(a).reversed.toList();
    final right = p.posix.split(b).reversed.toList();
    var shared = 0;
    while (shared < left.length &&
        shared < right.length &&
        left[shared].toLowerCase() == right[shared].toLowerCase()) {
      shared++;
    }
    return shared;
  }
}
