import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/features/download/providers/download_providers.dart';
import 'package:music_player/services/download/ytdlp_service.dart';

/// Stands in for the embedded yt-dlp so the rules about a cancelled row can be
/// exercised without a Python runtime.
class _FakeYtdlpService extends YtdlpService {
  final StreamController<YtdlpEvent> _controller = StreamController<YtdlpEvent>.broadcast();

  int cancels = 0;

  @override
  Stream<YtdlpEvent> get events => _controller.stream;

  @override
  Future<String?> startDownload(String url, {String format = 'mp3'}) async => 'download-1';

  @override
  Future<void> cancel(String id) async => cancels++;

  void emit(YtdlpEvent event) => _controller.add(event);

  void close() => _controller.close();
}

/// A download whose process has stopped answering is exactly the one that gets
/// cancelled, so these rules are about the row staying truthful when the
/// native side has gone quiet — or answers late.
void main() {
  late _FakeYtdlpService service;
  late ProviderContainer container;

  setUp(() {
    service = _FakeYtdlpService();
    container = ProviderContainer(
      overrides: [ytdlpServiceProvider.overrideWithValue(service)],
    );
    addTearDown(() {
      container.dispose();
      service.close();
    });
  });

  DownloadQueueNotifier notifier() => container.read(downloadQueueProvider.notifier);

  DownloadTask row() => container.read(downloadQueueProvider).single;

  Future<void> startOne() async {
    expect(await notifier().start('https://example.com/song'), isNull);
  }

  test('a cancel marks the row without waiting for the native side', () async {
    await startOne();
    await notifier().cancel('download-1');

    expect(row().status, DownloadStatus.cancelled);
    expect(service.cancels, 1);
  });

  test('progress from a cancelled download does not put the bar back', () async {
    await startOne();
    await notifier().cancel('download-1');

    service.emit(
      const YtdlpProgress('download-1', percent: 40, eta: Duration(seconds: 3), line: '40%'),
    );
    await pumpEventQueue();

    expect(row().status, DownloadStatus.cancelled);
    expect(row().percent, 0);
  });

  test('a failure that raced the cancel still gets the last word', () async {
    await startOne();
    await notifier().cancel('download-1');

    service.emit(const YtdlpFailed('download-1', message: 'network went away'));
    await pumpEventQueue();

    expect(row().status, DownloadStatus.failed);
    expect(row().detail, 'network went away');
  });

  test('a cancelled row can be cleared, unlike a running one', () async {
    await startOne();
    notifier().clearFinished();
    expect(container.read(downloadQueueProvider), hasLength(1));

    await notifier().cancel('download-1');
    notifier().clearFinished();
    expect(container.read(downloadQueueProvider), isEmpty);
  });
}
