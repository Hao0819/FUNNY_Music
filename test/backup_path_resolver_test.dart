import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/domain/backup_path_resolver.dart';

void main() {
  test('a path the library has resolves to itself', () {
    final resolver = BackupPathResolver(const ['/storage/emulated/0/Music/a.mp3']);

    final resolved = resolver.resolve('/storage/emulated/0/Music/a.mp3');

    expect(resolved.match, PathMatch.exact);
    expect(resolved.path, '/storage/emulated/0/Music/a.mp3');
  });

  test('a moved file is matched by name', () {
    // What a new phone looks like: same songs, different volume id.
    final resolver = BackupPathResolver(const ['/storage/1A2B-3C4D/Music/a.mp3']);

    final resolved = resolver.resolve('/storage/emulated/0/Music/a.mp3');

    expect(resolved.match, PathMatch.renamed);
    expect(resolved.path, '/storage/1A2B-3C4D/Music/a.mp3');
  });

  test('name matching ignores case, since the backup may come off another filesystem', () {
    final resolver = BackupPathResolver(const ['/storage/emulated/0/Download/Song.MP3']);

    expect(resolver.resolve('/elsewhere/song.mp3').path, '/storage/emulated/0/Download/Song.MP3');
  });

  test('between files of the same name, the one in the most similar place wins', () {
    final resolver = BackupPathResolver(const [
      '/storage/emulated/0/Music/demos/intro.mp3',
      '/storage/emulated/0/Music/live/intro.mp3',
    ]);

    final resolved = resolver.resolve('/old-phone/live/intro.mp3');

    expect(resolved.match, PathMatch.renamed);
    expect(resolved.path, '/storage/emulated/0/Music/live/intro.mp3');
  });

  test('a tie between identically named files resolves the same way every time', () {
    // The preview the user is shown and the restore they confirm ask
    // separately, so the answer cannot depend on iteration order.
    const library = ['/b/intro.mp3', '/a/intro.mp3', '/c/intro.mp3'];

    final first = BackupPathResolver(library).resolve('/old/intro.mp3');
    final second = BackupPathResolver(library.reversed).resolve('/old/intro.mp3');

    expect(first.path, second.path);
    expect(first.path, '/a/intro.mp3');
  });

  test('a path matching nothing keeps the path the backup gave it', () {
    final resolver = BackupPathResolver(const ['/storage/emulated/0/Music/a.mp3']);

    final resolved = resolver.resolve('/storage/emulated/0/Music/gone.mp3');

    expect(resolved.match, PathMatch.unresolved);
    expect(resolved.isUnresolved, isTrue);
    expect(resolved.path, '/storage/emulated/0/Music/gone.mp3');
  });

  test('an empty resolver leaves every path alone', () {
    final resolver = BackupPathResolver.none();

    expect(resolver.isEmpty, isTrue);
    expect(resolver.resolve('/a.mp3').path, '/a.mp3');
    expect(resolver.resolve('/a.mp3').match, PathMatch.unresolved);
  });

  test('tally counts each kind of match for the restore preview', () {
    final resolver = BackupPathResolver(const ['/here/a.mp3', '/moved/b.mp3']);

    final counts = resolver.tally(const ['/here/a.mp3', '/old/b.mp3', '/old/c.mp3']);

    expect(counts.exact, 1);
    expect(counts.renamed, 1);
    expect(counts.unresolved, 1);
    expect(counts.total, 3);
  });
}
