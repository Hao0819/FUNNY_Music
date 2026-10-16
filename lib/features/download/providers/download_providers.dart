import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../services/download/ytdlp_service.dart';
import '../../library/providers/library_providers.dart';

final ytdlpServiceProvider = Provider<YtdlpService>((ref) => YtdlpService());

/// Whether the download screen's history list is collapsed. Persisted, so it
/// stays the way the user left it.
class DownloadHistoryHiddenNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsRepositoryProvider).downloadHistoryHidden;

  Future<void> toggle() async {
    state = !state;
    await ref.read(settingsRepositoryProvider).updateDownloadHistoryHidden(state);
  }
}

final downloadHistoryHiddenProvider =
    NotifierProvider<DownloadHistoryHiddenNotifier, bool>(DownloadHistoryHiddenNotifier.new);

/// Unpacks the Python runtime once per app run. Kept as a provider so the
/// download screen can show the several-second first-run cost as a normal
/// loading state instead of appearing frozen.
final ytdlpReadyProvider = FutureProvider<bool>((ref) {
  return ref.watch(ytdlpServiceProvider).init();
});

/// The yt-dlp build currently on disk, which is not the one shipped in the APK
/// once the user has updated it.
final ytdlpVersionProvider = FutureProvider<String?>((ref) async {
  await ref.watch(ytdlpReadyProvider.future);
  return ref.watch(ytdlpServiceProvider).version();
});

/// The last few things searched for here, newest first, kept across launches.
///
/// Searching is slow enough — it scrapes rather than calling an API — that
/// retyping a query you ran a minute ago is a real cost, and the terms are
/// usually song names that are awkward to type twice.
class RecentDownloadSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.read(settingsRepositoryProvider).recentDownloadSearches;

  Future<void> remember(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // A repeat moves to the front instead of adding a second row, ignoring
    // case: searching the same thing twice is the common case and it should
    // not spend two of the five slots.
    final lower = trimmed.toLowerCase();
    final next = [
      trimmed,
      ...state.where((entry) => entry.toLowerCase() != lower),
    ].take(SettingsRepository.recentDownloadSearchLimit).toList();

    state = next;
    await ref.read(settingsRepositoryProvider).saveRecentDownloadSearches(next);
  }

  Future<void> forget(String query) async {
    state = state.where((entry) => entry != query).toList();
    await ref.read(settingsRepositoryProvider).saveRecentDownloadSearches(state);
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(settingsRepositoryProvider).saveRecentDownloadSearches(const []);
  }
}

final recentDownloadSearchesProvider =
    NotifierProvider<RecentDownloadSearchesNotifier, List<String>>(
  RecentDownloadSearchesNotifier.new,
);

/// Results for the download screen's search box. Starts empty rather than
/// running a query on build, since there is nothing to search for yet.
class YtdlpSearchNotifier extends AsyncNotifier<List<YtdlpSearchResult>> {
  @override
  Future<List<YtdlpSearchResult>> build() async => const [];

  Future<void> run(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Remembered on the way in, not once the results are back: a search worth
    // retrying from the recent list is exactly one that was slow or came back
    // empty.
    await ref.read(recentDownloadSearchesProvider.notifier).remember(trimmed);

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(ytdlpServiceProvider).search(trimmed));
  }

  void clear() => state = const AsyncValue.data([]);
}

final ytdlpSearchProvider =
    AsyncNotifierProvider<YtdlpSearchNotifier, List<YtdlpSearchResult>>(YtdlpSearchNotifier.new);

enum DownloadStatus { preparing, running, completed, failed, cancelled }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    this.status = DownloadStatus.preparing,
    this.percent = 0,
    this.eta = Duration.zero,
    this.detail = '',
    this.path,
  });

  final String id;
  final String url;
  final String title;
  final DownloadStatus status;
  final double percent;
  final Duration eta;

  /// Last yt-dlp output line, or the failure message once it has one.
  final String detail;
  final String? path;

  bool get isFinished => status != DownloadStatus.preparing && status != DownloadStatus.running;

  DownloadTask copyWith({
    String? title,
    DownloadStatus? status,
    double? percent,
    Duration? eta,
    String? detail,
    String? path,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title ?? this.title,
      status: status ?? this.status,
      percent: percent ?? this.percent,
      eta: eta ?? this.eta,
      detail: detail ?? this.detail,
      path: path ?? this.path,
    );
  }
}

/// Every download this app run has started, newest first.
class DownloadQueueNotifier extends Notifier<List<DownloadTask>> {
  StreamSubscription<YtdlpEvent>? _subscription;

  @override
  List<DownloadTask> build() {
    final service = ref.watch(ytdlpServiceProvider);

    try {
      _subscription = service.events.listen(_apply);
      ref.onDispose(() => _subscription?.cancel());
    } on YtdlpUnavailable {
      // Nothing to listen to off Android; the screen reports that itself.
    }

    return const [];
  }

  Future<String?> start(String url, {String format = 'mp3'}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'Paste a link first';

    try {
      final id = await ref.read(ytdlpServiceProvider).startDownload(trimmed, format: format);
      if (id == null) return 'Could not start the download';

      state = [
        DownloadTask(id: id, url: trimmed, title: trimmed),
        ...state,
      ];
      return null;
    } on YtdlpUnavailable catch (error) {
      return error.toString();
    } on Object catch (error) {
      return error.toString();
    }
  }

  Future<void> cancel(String id) async {
    // Marked cancelled here rather than on the way back: the native side
    // answers with an event, and a download whose process has stopped
    // producing output is exactly the one whose events have stopped arriving.
    // Waiting for it left the row spinning with a Cancel button that visibly
    // did nothing, so the row goes quiet now and the native side catches up.
    _replace(id, (task) => task.copyWith(status: DownloadStatus.cancelled, detail: 'Cancelled'));

    try {
      await ref.read(ytdlpServiceProvider).cancel(id);
    } on Object {
      // The event stream still reports how it actually ended.
    }
  }

  /// Drops finished rows; running downloads are left alone, since removing
  /// one would orphan a process that is still writing a file.
  void clearFinished() {
    state = state.where((task) => !task.isFinished).toList();
  }

  /// Drops a single finished row. Running downloads have to be cancelled
  /// first, for the same reason [clearFinished] leaves them in place.
  void remove(String id) {
    state = state.where((task) => task.id != id || !task.isFinished).toList();
  }

  /// Rewrites one row in place, leaving the rest of the list as it was.
  void _replace(String id, DownloadTask Function(DownloadTask task) update) {
    final index = state.indexWhere((task) => task.id == id);
    if (index < 0) return;
    state = [...state]..[index] = update(state[index]);
  }

  void _apply(YtdlpEvent event) {
    final index = state.indexWhere((task) => task.id == event.id);
    if (index < 0) return;

    final task = state[index];

    // Progress from a download the user already cancelled is ignored, so a
    // process that takes a moment to die can't put the bar back on a row that
    // has been struck out. Anything final still lands: a cancel that raced a
    // finished file should say the file arrived.
    if (task.status == DownloadStatus.cancelled && event is YtdlpProgress) return;

    final updated = switch (event) {
      YtdlpProgress(:final percent, :final eta, :final line) => task.copyWith(
          status: DownloadStatus.running,
          percent: percent,
          eta: eta,
          detail: line,
        ),
      YtdlpDone(:final path, :final title) => task.copyWith(
          status: DownloadStatus.completed,
          percent: 100,
          title: title.isEmpty ? task.title : title,
          path: path,
          detail: path ?? '',
        ),
      YtdlpFailed(:final message) =>
        task.copyWith(status: DownloadStatus.failed, detail: message),
      YtdlpCancelled() =>
        task.copyWith(status: DownloadStatus.cancelled, detail: 'Cancelled'),
    };

    state = [...state]..[index] = updated;

    // A finished file is now in MediaStore, so pull it into the library
    // without making the user hit rescan.
    if (event is YtdlpDone) {
      ref.read(libraryScanProvider.notifier).refresh();
    }
  }
}

final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, List<DownloadTask>>(DownloadQueueNotifier.new);
