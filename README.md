# FUNNY Music

A local audio player for Android, built with Flutter. It plays the audio files
already on your device — no streaming service, no account, no cloud library.

One optional feature breaks the "purely local" rule: a built-in **downloader**
that pulls audio off a link using a copy of yt-dlp embedded in the APK. It is
the only part of the app that touches the network, it only ever downloads, and
nothing about your library is uploaded anywhere. See
[Downloading](#downloading) for what it does and the conditions attached.

Its main idea is that **organizing your music never touches your files**. You
group tracks into folders inside the app; those groupings live in a local
database keyed by file path, so removing a track from a folder only removes the
link — the file itself is untouched.

---

## Features

### Library
- Scans on-device audio via MediaStore (m4a, mp3, wav, flac and others),
  including folders like `Download/MusicDownload` and secondary volumes
- Search box and a filter panel, both in the Library tab's own app bar
- Songs filed into folders show the folder names on their row (Favorites is
  left out, since the heart already shows it)
- Sort by title, artist, album, date added or duration, ascending or descending
- Total song count above the list
- A–Z index down the right edge — tap or drag a letter to jump straight to
  that section instead of scrolling a long library
- Pull down to rescan
- Hold a row to select, then hide what you never want to see in this list
  again. Hiding is **not** deleting: the file stays on the device and keeps
  every playlist link, favorite and history entry pointing at it, so restoring
  it later puts everything back
- Album art, and for a track that has none, one of six bundled sleeves chosen
  from its MediaStore id — random across a library, fixed for one track, so a
  song never changes sleeve under you
- WhatsApp voice notes and audio are filtered out

### Folders
- Create, rename and delete folders
- Long-press any track to multi-select, then batch-add to a folder
- Drag tracks by their ☰ handle to reorder them inside a folder (only in
  "Custom order" mode). The handle drags; long-press on the row still selects
- Per-folder sort: custom / title / artist / album / date added / duration
- Reverse order ('swap' button next to Sort) reads the folder back to front,
  including the custom order. Dragging still works while reversed: what you
  arrange is what is saved
- Removing a track from a folder unlinks it only — the file and the main
  library entry are untouched
- **Favorites** is a built-in folder that can't be renamed or deleted; every
  track row has a heart toggle
- Entries whose file the current scan can't find are **counted, not hidden**:
  the folder list shows "N not found" and the folder itself says so above the
  tracks. They stay in the folder, so they come back if the files do

### Auto-collections
Pinned above your own folders in the Folders tab, built from the play log
rather than created by hand:
- **Recently played** — most recent first, one entry per track
- **Most played** — ordered by play count, with the count shown on each row
- Both support tap-to-play, the heart toggle, and long-press multi-select to
  file tracks into a folder
- "Clear history" empties the log without touching folders, favorites or files

### Search & filter
- Search across title, artist and album from the Library tab — multi-word
  queries match across fields in any order ("beatles yesterday" works)
- Per-folder search inside any folder
- Filters, combinable: format · duration range · in-a-folder vs unfiled ·
  recently added / recently played
- There is no separate Search tab. It searched the same three fields the
  Library tab's own field does, so the quarter of the navigation bar it was
  spending went to the downloader instead

### Playback
- Play, pause, previous, next, seek
- Shuffle, and repeat all / one / off — **repeat all is the default**, so a
  folder loops back to its first song, and your choice is remembered
- Queue view: reorder by dragging, remove items, jump to any track
- Mini player docked above the navigation bar, expanding to a full player.
  It also appears inside folders, history and new-audio screens
- Next / previous start playback, so skipping from a paused or just-restored
  player plays the track you skipped to
- Play and Shuffle buttons at the top of every folder
- The row of the currently playing track is highlighted in every list
- Background playback with notification and lock-screen controls
- **Resumes where you left off**: reopening the app brings back the last queue,
  song and position, paused. Saved on every pause, every 5 seconds while
  playing, and whenever the app leaves the screen, so it survives the system
  killing the app

### New audio detection
- Each scan is diffed against a record of files already seen. New arrivals get
  a quiet **New audio** row at the top of the Folders tab — never a popup
- Open it to multi-select and file the new tracks into folders, or "Mark all
  seen" to dismiss
- Your existing library on first install is the baseline, not "new"

### Downloading
- Its own **Download** tab, third in the navigation bar. The screen is built
  the first time you open it rather than at launch, so the Python runtime is
  not unpacked during startup for a tab you may never open
- **Search by name**, then tap a result to download it. No copying links, no
  browser
- **Or paste a link** into the same box — one field, not two: text that parses
  as an http(s) URL is downloaded, anything else is searched. So when search
  doesn't surface what you want, a link copied from YouTube still works
- Results show thumbnail, channel and duration
- **A download leaves the search alone.** The query and all twenty results
  stay where they are, so taking a second and third song out of one search is
  a tap each; the X in the field is the only thing that clears them
- The **last five queries** sit under the field and survive a restart. A
  repeat moves to the front rather than taking a second slot, and the list
  stands down while results are on screen
- **Hold a finished download** to file it into a playlist, without going to
  find its row in the library first
- Downloads land in `Music/MusicPlayer/` as tagged audio, indexed by MediaStore
  so they show up in your library like any other track
- Choose **MP3 / M4A / Opus**; the video stream is never downloaded, only the
  best audio-only format
- Live progress, ETA and per-download cancel
- **Update yt-dlp** button — sites change how they serve media often enough to
  break extraction between app releases, so the extractor can be refreshed
  without shipping a new APK
- Download history can be hidden (the choice is remembered), cleared in one go,
  or removed row by row with a left swipe. Anything still downloading is never
  hidden or removable — cancel it first

### Appearance
- **Black and white only.** Light / dark / follow-system, and in both modes the
  app has no hue of its own anywhere: emphasis is the far end of the greyscale,
  so the primary button is black-on-paper in light mode and white-on-ink in
  dark. Every one of the colour scheme's 46 roles is pinned neutral and a test
  asserts it channel by channel — Material derives `primaryContainer`,
  `tertiary`, `error` and the fixed variants from the seed, and those come back
  coloured whatever the seed is
- The only colour on screen is album art. Playlists therefore have no colour of
  their own, and there is no recolour action
- Playlists are a list of rows: cover, name, song count. A playlist's cover is
  a picture the user chose for it, else the first track in it that actually has
  artwork, else the same bundled sleeve its first track shows in a list
- The mini player is an inverted card — near-black on a paper screen, white on
  an ink one — with the position as a hairline along its bottom edge
- The playing row sits on a raised rounded block with a level meter over its
  cover, rather than changing colour
- The Now Playing scrubber is drawn as a waveform. Its shape comes from a hash
  of the track id, **not** from the audio — decoding every file for real
  amplitudes would be far too slow on a phone. It is stable per track, so a
  song always looks the same.

### Lock screen and notification controls
`audio_service` posts a media notification with play/pause and skip, which is
also what the lock screen shows. On Android 13+ that needs the
`POST_NOTIFICATIONS` runtime permission: it was declared in the manifest but
nothing ever requested it, so the notification was created and then silently
dropped by the system. It is asked for after the first frame — never as a gate,
since the app works without it — and **Settings → Playback → Lock screen
controls** reports the state and links out to system settings, because Android
shows the dialog once and a refusal cannot be re-requested.

### Settings
- **Rescan device** on demand
- **Clean up missing files** — removes folder links and history entries left
  behind by audio that is no longer on the device, telling you exactly how many
  of each will go. Never touches files or your other folders
- **Hidden tracks** — everything hidden from the Library, with a one-tap
  restore per track and a Restore all. The row names itself even when the list
  is empty, since this is the only place that explains where a hidden track
  went
- **Backup & transfer** — writes everything a rescan can't rebuild to one JSON
  file: your folders and what's in them, favorites, the hidden list, the play
  log behind "recently played" and "most played", and your settings. The file
  is saved under `Android/data/com.example.music_player/files/folder_backups`
  and offered to the share sheet, so it can leave the device; **Import** takes
  one back from anywhere with the file picker. Restoring adds back only what's
  missing, so it never removes, renames or reorders anything and is safe to run
  twice — settings are the one exception, and are asked about separately. The
  same screen reports any saved data the app couldn't read at launch, and where
  the unreadable file was kept. See [Moving to a new phone](#moving-to-a-new-phone)
- App version and a note that your library stays on the device

---

## Moving to a new phone

Nothing here is in the cloud, so a move is two separate jobs: the audio files,
which you copy yourself, and everything the app remembers about them, which
travels as one backup file.

1. **Old phone:** Settings → Backup & transfer → **Export and share**, and send
   the file to yourself — Drive, a chat with yourself, Bluetooth, anything. It
   is a few hundred KB of text.
2. **Copy the audio across**, before importing anything. The app's own
   downloads are in the public `Music/MusicPlayer/` directory —
   `/storage/emulated/0/Music/MusicPlayer/`, visible to a file manager and to a
   PC over USB — and anything you added yourself is wherever you put it,
   usually `Music/` or `Download/`. USB to a PC and back, the new phone's own
   migration tool, an SD card, or `adb pull /sdcard/Music/MusicPlayer <dir>`
   and `adb push` into the same place on the new phone. Landing the files at
   the *same* absolute paths is the easiest case, but see the note below if
   they end up somewhere else. Don't send audio through a chat app — several
   of them rename or re-encode what they carry. The backup JSON is fine that
   way; the music isn't.
3. **New phone:** install the same APK — the same application id, or it counts
   as a different app — open it, grant audio access, and let the library scan
   finish.
4. If the songs you copied don't show up, the app can't see them: it only lists
   what MediaStore has indexed, and a copy made by some tools never triggers a
   media scan. A reboot fixes it.
5. Settings → Backup & transfer → **Import a backup file**, pick the JSON, and
   read the dialog: it says how many tracks in the file it found here, how many
   it matched by file name, and how many it couldn't place.

### What happens when the paths don't match

Folders, favorites, the hidden list and the play log all reference tracks by
absolute path, and those paths change between devices — a different volume id,
or a directory you renamed on the way over. So a path with nothing behind it is
retried by **file name** against the library on this device, and the link is
re-pointed at what it finds. Entries that match nothing keep their original
path and show up in their folder as "not found", which means they come back on
their own if the files turn up later.

Three caveats worth knowing:

- Import waits for the first library scan, because it matches against what the
  scan found. The button says so while it's disabled.
- Import the backup *after* the audio has arrived and been scanned. A restore
  only ever adds, so importing first stores every link at its old path as "not
  found", and importing again once the files are there adds a second,
  name-matched link beside the stale one for you to delete by hand.
- The restored repeat mode is read when playback starts up, so it applies on
  the next launch.

A playlist cover picked from a photo is stored as a path to that photo, so it
won't resolve on the new phone — the playlist falls back to its tracks'
artwork, and you can pick the picture again.

## Installing

There is no prebuilt APK to download — you build it yourself. You need a
machine with the [Flutter SDK](https://docs.flutter.dev/get-started/install)
installed, and an Android phone running **Android 6.0 (API 23) or newer**.

```bash
git clone https://github.com/Hao0819/Music_Player.git
cd Music_Player
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi
```

If that last step fails on Windows with `An Application Control policy has
blocked this file`, add `--no-tree-shake-icons` — see
[Building an APK](#building-an-apk) for why.

It writes one APK per architecture to `build/app/outputs/flutter-apk/`:

| File | For |
|---|---|
| `app-arm64-v8a-release.apk` | Any phone from roughly 2019 onward — pick this one |
| `app-armeabi-v7a-release.apk` | Older 32-bit devices |

Then either plug the phone in over USB with USB debugging enabled and run
`flutter install --release`, or copy the APK onto the phone and open it,
allowing "install from unknown sources" when prompted.

### After installing

- **Grant the audio permission** on first launch, or the library stays empty.
- **Update by installing the new APK over the old one.** Uninstalling deletes
  your folders and favorites — Android wipes app-private data on uninstall, and
  there is no export yet.
- The APK is signed with Flutter's **debug keys**, which is fine for personal
  use but means a build signed with any other key cannot be installed over it
  later without uninstalling first.
- On **MIUI / HyperOS** (Xiaomi, Redmi, POCO), enable **Autostart** for the app
  and set battery saver to **No restrictions**. Otherwise Android blocks the
  foreground service and you lose the media notification and lock-screen
  controls — playback itself still works.
- The **downloader** unpacks its Python runtime the first time you open the
  download screen, which takes a few seconds. That happens once.

---

## Tech stack

| Purpose | Package |
|---|---|
| Audio metadata / MediaStore queries | `on_audio_query` |
| Playback engine | `just_audio` |
| Background playback, notification, lock screen | `audio_service` |
| Local database | `hive` / `hive_flutter` |
| State management | `flutter_riverpod` |
| Runtime permissions | `permission_handler` |
| App version in Settings | `package_info_plus` |
| Sending a backup off the device | `share_plus` |
| Picking a backup file back in | `file_picker` |
| Launcher icon generation | `flutter_launcher_icons` |
| Native splash screen | `flutter_native_splash` |
| Downloader (embedded Python + yt-dlp) | `io.github.junkfood02.youtubedl-android:library` |
| Audio extraction / transcoding for downloads | `io.github.junkfood02.youtubedl-android:ffmpeg` |

Android only — iOS is out of scope. The downloader is doubly so: it runs a
Python build compiled for Android, so it has no equivalent on other platforms.

---

## Architecture

Four layers, each depending only on the ones above it:

```
features/   UI + per-feature Riverpod providers
domain/     app-level models (Track, filter state, sort modes, filtering rules)
data/       Hive models + repositories
services/   audio playback handler, permissions, native MediaStore scan
```

### Key decision: the database stores relationships, never metadata

Hive only ever holds **links and bookkeeping**:

| Box | Holds |
|---|---|
| `folders` | folder id, name, created date, sort mode, reverse flag, system flag |
| `folder_track_links` | folder id ↔ track **file path**, added date, manual order |
| `known_tracks` | files seen in previous scans, for new/deleted diffing |
| `play_history` | append-only play log |
| `settings` | theme mode, library sort preference, repeat mode, download-history visibility, recent download searches |
| `hidden_tracks` | track **file paths** the Library does not list |
| `playback_session` | last queue (paths), current track, position |

Titles, artists, artwork and durations are always re-read live from
`on_audio_query` at render time. Nothing is duplicated into the database, so a
rescan can never leave stale metadata behind, and your folders survive any
change to the underlying files.

Tracks are keyed by **file path**, not by MediaStore id, because MediaStore ids
can be reassigned when the system re-indexes.

**Hive keys are a SHA-1 digest of that path, never the path itself.** Hive
writes a String key's UTF-8 length into a single byte with no check, so a key
over 255 bytes writes a truncated length; the write succeeds and the box is
unreadable on the next launch. These are files pulled off YouTube and a Han
character costs three bytes, so paths pass 255 easily -- on one real device, 2
of 1130 paths were over on their own and 7 were over once a folder id was
prepended, which is what emptied every folder on it. See
`data/hive/box_keys.dart`; `key_migration.dart` rewrites entries left by the
old layout. `play_history` uses auto-increment int keys and `playback_session`
fixed short ones, so neither is affected.

Because folders are keyed by path and stored in the app's private directory,
they survive an **update** (installing a newer APK over the old one) but not an
**uninstall** — Android deletes app-private data on uninstall. Install over the
top to keep your folders, and export a backup first if you're not sure.

Since `folder_track_links` is the only copy of work the user did by hand, an
unreadable box file is **renamed aside**, never deleted, and the next launch
starts a fresh box beside it. If even the rename fails, the box runs in memory
for that session so the file is left intact for the next attempt. Settings →
Backup & transfer reports what was set aside and where.

### Startup never blocks on the platform

`main()` shows the UI as soon as Hive is open. Registering with `audio_service`
happens *after* the first frame, because it binds an Android foreground
service and some skins — MIUI especially — stall or refuse that binding. When
it was awaited before `runApp`, a refusal meant a permanently white,
unresponsive window with nothing on screen to explain it.

Now the worst case is an app that plays audio without notification or
lock-screen controls. Hive failures are caught too: a corrupt box is rebuilt
rather than thrown, and anything still fatal renders the actual error on
screen instead of a blank window.

The native MediaStore scan likewise runs on a worker thread — method-channel
handlers run on the main thread, so scanning a real library there froze the UI
before it could paint.

### Scanning uses two sources

`on_audio_query` only queries `MediaStore.Audio` on the primary volume, which
misses audio MediaStore filed into its generic "files" collection — common for
anything a downloader dropped into `Download/`. So the library is the union of:

1. the plugin's query (richer metadata, wins on conflict), and
2. a native query in `MainActivity.kt` over the files collection on every
   volume, keeping rows whose mime type or extension looks like audio.

Results are merged by path, then noise paths (WhatsApp audio and voice notes)
are dropped — see `_excludedPathFragments` in `audio_library_repository.dart`.

**The two passes are not awaited together.** `startScan()` returns the plugin's
rows as `firstPass` and the merged union as `complete`, because the native query
walks every volume and is far the slower of the two — while the plugin's result
alone is usually the whole library. The list paints on the first pass; the
second is merged in when it arrives, or skipped entirely when it found nothing
new (`complete` resolves to null). The Hive bookkeeping that records what the
scan saw runs after that, so a disk write never sits between the scan and the
first frame.

A rescan also **reuses the previous `Track` objects** for files whose metadata
is unchanged (`Track.matches`). `Track` computes its sort keys, index letters
and search haystack lazily and caches them per instance, so replacing every
object made the next sort recompute all of it — romanising every Han title
again — even though a rescan usually finds the library exactly as it left it.
Measured on a desktop VM: ~60–150 ms of key work per rescan before, 0.2 ms
after. The romanisation itself is additionally cached by source string, since
artists and albums repeat across a library.

Favorites is implemented as a folder with `isSystem: true` rather than a
separate table, so it reuses the same linking code as every other folder.

### Downloads re-enter through MediaStore, not a side door

`YtdlpBridge.kt` runs yt-dlp into a private scratch directory, then **publishes
the finished file into the shared `Music/MusicPlayer/` collection** via a
MediaStore insert (`getExternalFilesDir` on pre-Android-10, which has no insert
API and would otherwise need a storage permission).

That is the whole integration: a downloaded track is an ordinary file the
normal scan finds, so folders, favorites, history and search work on it with no
special-casing anywhere. The Dart side only triggers a library refresh when a
download completes.

Progress arrives on an `EventChannel` keyed by a download id, because a
`MethodChannel` reply can only fire once and a download reports for minutes.

Search goes through yt-dlp's own `ytsearch` prefix rather than the **YouTube
Data API**, for three reasons: the free API quota allows about 100 searches a
day (a `search.list` call costs 100 of 10,000 daily units), an API key cannot
be hidden inside a distributed APK, and the API's terms forbid using data
obtained through it to download media — precisely the pairing this feature
would create. Going through yt-dlp costs no key, no quota and no extra
dependency, and `--flat-playlist` keeps a query to a few seconds by skipping
per-result format resolution.

`--dump-json` field names drift between yt-dlp releases, so `parseSearchOutput`
takes alternatives for each one (`channel` → `uploader` → `uploader_id`,
`thumbnail` → largest of `thumbnails`) and logs the raw output when a parse
yields nothing, rather than failing silently.

### Project layout

```
lib/
  main.dart                     bootstraps Hive + AudioService, runs the app
  app.dart                      MaterialApp, permission gate, tab shell, mini player
  core/                         theme, shared notifiers, formatting/matching helpers
  data/
    hive/                       box setup + @HiveType models
    repositories/               audio library, folders, history, known tracks, hidden tracks, settings
  domain/                       Track, sort modes, filter state, filtering rules
  features/
    library/                    scan, sort, search, filters, multi-select, hiding, A–Z index
    folders/                    CRUD, folder detail, add-to-folder sheet
    favorites_history/          recently played / most played views
    player/                     player controller, mini player, now playing, queue
    download/                   search, recent searches, download queue, history
    settings/                   theme, rescan, cleanup, hidden tracks, backup & transfer, about
  services/
    audio/                      AudioPlayerHandler (just_audio + audio_service)
    permissions/                permission service + provider
    scanning/                   bridge to the native MediaStore query
    download/                   bridge to the embedded yt-dlp
    backup/                     reads and writes the backup files
  widgets/                      shared: artwork, stand-in covers, empty state, permission gate
```

---

## Running it

Requires the Flutter SDK and an Android device or emulator.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates Hive adapters
flutter run
```

Regenerate adapters (`*.g.dart`) any time you change a `@HiveType` model.

### Building an APK

```bash
flutter build apk --release --no-tree-shake-icons --split-per-abi
# output: build/app/outputs/flutter-apk/app-<abi>-release.apk
```

Both flags are load-bearing:

- **`--split-per-abi`** produces one APK per architecture (~45 MB each) instead
  of one fat APK (~114 MB). The downloader ships a Python runtime and an FFmpeg
  build *per ABI*, roughly 30 MB apiece, so the ABI list dominates the APK
  size. Install `app-arm64-v8a-release.apk` on any phone from roughly 2019
  onward; `app-armeabi-v7a-release.apk` covers older 32-bit devices.

  Note that `abiFilters` in `build.gradle.kts` will *not* do this: the Flutter
  Gradle plugin assigns that itself from `--target-platform`, anything added
  there only unions with it, and `--target-platform` in turn only governs
  Flutter's own engine — the downloader AAR's other architectures ride along
  regardless. Splitting is what actually drops them.

- **`--no-tree-shake-icons`** is only needed on Windows machines where
  **Smart App Control** or a WDAC policy blocks Flutter's unsigned
  `font-subset.exe`. Release builds run icon tree-shaking through that binary,
  and the block surfaces as
  `Target aot_android_asset_bundle failed: ... An Application Control policy
  has blocked this file`. Skipping tree-shaking ships the full Material icon
  font (~1.6 MB) and sidesteps it. Drop the flag if your machine allows the
  binary to run.

To install straight onto a connected phone: `flutter install --release`.

### App icon and splash screen

Both are generated from `assets/icon/source.jpeg`:

```bash
dart run tool/prep_icons.dart        # source.jpeg -> the four PNGs below
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

`prep_icons.dart` writes `app_icon.png` (legacy launcher icon),
`app_icon_foreground.png` (adaptive-icon foreground, deliberately full-bleed
because `flutter_launcher_icons` applies its own 16% safe-zone inset),
`splash_android12.png` (1152 px with the art inset to 768 px for Android 12's
circular mask) and `splash_logo.png`. It also snaps the near-black JPEG
backdrop to true `#000000`, without which compression noise shows as a faint
square against the black splash and icon backgrounds.

### Checks

```bash
flutter analyze
flutter test
```

---

## Android configuration notes

A few non-obvious things live in `android/`, each there for a specific reason:

- **`AndroidManifest.xml`** declares `READ_MEDIA_AUDIO` (Android 13+) with
  `READ_EXTERNAL_STORAGE` capped at API 32 for older devices, plus the
  foreground-service and notification permissions playback needs. It also
  registers `audio_service`'s `AudioService` and `MediaButtonReceiver`.
- **`MainActivity`** extends `AudioServiceActivity` instead of `FlutterActivity`
  so media buttons reach the handler, and hosts the `music_player/media_store`
  method channel used for the broader audio scan described above.
- **`build.gradle.kts` (root)** patches `on_audio_query_android`, which predates
  current Android Gradle Plugin requirements: it backfills the missing
  `namespace`, pins Java/Kotlin to JVM 17 so the two compilers agree, and raises
  its `compileSdk` through the variant API's `finalizeDsl` (a plain
  `afterEvaluate` is too late — AGP has already locked the value).
- **`gradle.properties`** disables Kotlin incremental compilation, which crashes
  on Windows when the project and the pub cache sit on different drives.
- **The downloader's Gradle setup** needs four things that are easy to miss:
  `useLegacyPackaging = true` (its Python and FFmpeg payloads are unzipped out
  of the APK at first launch, which only works when the native libs are stored
  extractably), `extractNativeLibs="true"` in the manifest for the same reason,
  `keepDebugSymbols` exclusions for `libpython.zip.so` / `libffmpeg.zip.so`
  (they are zip archives named `.so` so they get packaged at all, and the NDK
  strip step errors on them otherwise), and the `INTERNET` permission.
- **`proguard-rules.pro` keeps `org.apache.commons.compress`.** yt-dlp's
  payloads are unzipped with commons-compress, whose `ExtraFieldUtils`
  registers field types reflectively in a static initializer. Without the keep
  rule R8 sees classes like `AsiExtraField` as never instantiated, makes them
  non-concrete, and the unpack dies with `RuntimeException: class ... is not a
  concrete class` — wrapped in an `ExceptionInInitializerError`, which is an
  `Error`, not an `Exception`. `YtdlpBridge` therefore catches `Throwable`
  throughout: letting one escape a pool thread kills the process instead of
  failing one call.
- **`permission_handler` is pinned to 11.4.0.** Newer versions require
  `compileSdk 37`, which current SDK installs expose only as `android-37.x`
  folders that AGP cannot resolve as a plain `compileSdk = 37`.

---

## Status

Built and verified:

1. Scaffolding, permissions, tab shell, theming
2. Library scanning and sorting
3. Folders, multi-select, reordering, Favorites
4. Search and filters
5. Playback, queue, mini player, background audio
6. Recently played / most played views
7. Visual polish pass
8. Settings: rescan, cleanup of records for missing files, about/version

All eight modules from the original plan are built and verified on a device.

Added since: app icon and splash screen, and the yt-dlp downloader
(downloading, cancelling and history hide/clear all verified on a device).

Then a pass on the downloader and on covers: it took the Search tab's place in
the navigation bar, a download stopped clearing the search that found it, the
last five queries are remembered, a finished download can be filed into a
playlist by holding it, and a track with no embedded artwork gets a bundled
sleeve instead of a grey square. Installed and checked on a device.

Then the Library learned to hide a track. That came up as "can you delete
audio from the Library" and landed as hiding rather than deleting on purpose:
deleting is the one thing this app has never done, it cannot be undone, and
under scoped storage it would have meant a system consent dialog for every file
the app did not download itself. Hiding costs one Hive box of paths, is a
complete undo, and leaves the files alone.

Most recently, a backup became a way to change phones. It came up as "how
do I get my audio and playlists onto a new phone", and the honest answer was
"with a PC and adb": the backup file is written inside `Android/data`, which
no file manager has been able to open since Android 11, and restoring only
listed files already in that one directory. So the file now goes out through
the share sheet and comes back through the file picker, it carries the hidden
list, the play log and the settings rather than folders alone, and a path with
no file behind it is retried by file name — because the one thing guaranteed
to differ on the new device is the absolute paths every link is keyed by. See
[Moving to a new phone](#moving-to-a-new-phone).

### Known limitations

- The **"recently played" filter** returns nothing until you've actually played
  something — the history log starts empty.
- The scan can only see files **MediaStore has indexed**. Audio copied onto the
  device by a method that never triggers a media scan stays invisible to every
  app that queries MediaStore, this one included.
- **Uninstalling deletes your folders and favorites.** Install a newer APK over
  the old one instead, or export a backup first — see
  [Moving to a new phone](#moving-to-a-new-phone).
- The release APK is signed with Flutter's **debug keys**, and while the app
  is called FUNNY Music everywhere a user can read it, its application id is
  still the template's `com.example.music_player`. Both need changing before
  distributing anywhere — but changing the id installs a second app beside the
  first and abandons its folders, so it is a one-time, deliberate move.
- Notification artwork isn't shown yet; the notification uses the app icon.
- **Downloading from YouTube violates its Terms of Service**, whatever tool is
  used. That is why apps of this kind are not on Google Play, and it applies to
  this one. Decide for yourself whether to keep the feature.
- **Download history lives in memory only** and is gone when the app is killed.
  Hiding and clearing it work within a session; there is no persisted log.
- **The downloader roughly doubles the APK.** ~45 MB per-ABI versus ~22 MB
  before it existed.
- During yt-dlp's extraction and FFmpeg transcoding phases **no percentage is
  reported** — the progress bar sits at 0% and then at 100% while real work
  continues. On a long track the transcode alone can run for a minute and look
  stalled.
- Extraction **will break eventually** as sites change; use the in-app
  **Update yt-dlp** button rather than waiting for an app release. The same
  applies to search, which runs through the same extractor.
- **Search takes a few seconds.** It scrapes rather than calling an API, so it
  will never feel as immediate as a search box usually does.
- On MIUI (Xiaomi / Redmi / POCO) the media notification and background
  playback need **Autostart** enabled for the app in Security settings, and
  battery saver set to **No restrictions**. Without those, Android blocks the
  foreground service; the app still runs and plays, just without
  notification and lock-screen controls.
