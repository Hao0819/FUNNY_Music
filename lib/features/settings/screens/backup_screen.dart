import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../../../data/hive/hive_setup.dart';
import '../../../domain/app_backup.dart';
import '../../../domain/backup_path_resolver.dart';
import '../../../services/backup/app_backup_store.dart';
import '../../../widgets/empty_state.dart';
import '../../library/providers/library_providers.dart';
import '../../player/widgets/mini_player.dart';
import '../providers/backup_providers.dart';

/// Export, share, import and restore of everything a rescan cannot rebuild.
///
/// Two jobs that turn out to be the same job: insuring this device's folders
/// against its own storage going wrong, and moving them to a new phone. Both
/// come down to a plain JSON file — the first needs it to survive a clear-data,
/// the second needs it to leave the device, which is why the share sheet and
/// the file picker are here.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preview = ref.watch(appBackupPreviewProvider);
    final backupsAsync = ref.watch(appBackupsProvider);
    final directory = ref.watch(appBackupDirectoryProvider).value;
    final setAside = ref.watch(setAsideBoxesProvider);
    final scanning = ref.watch(libraryScanProvider).isLoading;

    return Scaffold(
      bottomNavigationBar: const MiniPlayer(isBottomMost: true),
      appBar: AppBar(title: const Text('Backup & transfer')),
      body: ListView(
        children: [
          if (setAside.isNotEmpty) _SetAsideNotice(setAside: setAside),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'A backup is a small text file holding your folders, favorites, '
              'hidden tracks, play history and settings. Your audio files are '
              'not copied or moved.\n\n'
              'Changing phones: copy your music across yourself, then export '
              'here, send the file to the new phone and import it there.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: Text(
                'Export and share '
                '(${countLabel(preview.folderCount, 'folder')}, '
                '${countLabel(preview.trackCount, 'entry', plural: 'entries')})',
              ),
              onPressed: () => _export(context, ref),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import a backup file'),
              onPressed: scanning ? null : () => _import(context, ref),
            ),
          ),
          if (scanning)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Importing waits for the library scan to finish — a restore '
                'matches the backup against the files it can see.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (directory != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SelectableText(
                directory,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Saved backups', style: theme.textTheme.titleSmall),
          ),
          ..._backupList(backupsAsync),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _backupList(AsyncValue<List<StoredAppBackup>> backupsAsync) {
    return switch (backupsAsync) {
      AsyncError(:final error) => [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("Couldn't read the backup folder: $error"),
          ),
        ],
      AsyncData(:final value) when value.isEmpty => const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No backups yet',
              message: 'Export one now, then send the file somewhere safe.',
            ),
          ),
        ],
      AsyncData(:final value) => [for (final stored in value) _BackupTile(stored: stored)],
      _ => const [
          Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ],
    };
  }

  /// Writes the file, then offers it straight to the share sheet. The file is
  /// already on disk at that point, so cancelling the share loses nothing.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(appBackupActionsProvider);
    try {
      final stored = await actions.exportNow();
      messenger.showSnackBar(SnackBar(content: Text('Saved ${stored.fileName}')));
      await actions.share(stored);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't write the backup: $error")));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stored = await ref.read(appBackupActionsProvider).importFromFile();
      if (stored == null || !context.mounted) return;
      await confirmRestore(context, ref, stored);
    } on FormatException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text("That file isn't a FUNNY Music backup: ${error.message}")),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't read that file: $error")));
    }
  }
}

/// Said out loud, because the alternative is the user meeting this as
/// "my folders are empty and I have no idea why".
class _SetAsideNotice extends StatelessWidget {
  const _SetAsideNotice({required this.setAside});

  final List<SetAsideBox> setAside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onError = theme.colorScheme.onErrorContainer;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: onError),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Some saved data could not be read',
                  style: theme.textTheme.titleSmall?.copyWith(color: onError),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This launch had to start it over. The old file was kept, not '
            'deleted — if you need what was in it, copy it off the device '
            'before reinstalling the app.',
            style: theme.textTheme.bodySmall?.copyWith(color: onError),
          ),
          const SizedBox(height: 8),
          for (final box in setAside)
            SelectableText(
              box.savedPath,
              style: theme.textTheme.bodySmall?.copyWith(color: onError, fontFamily: 'monospace'),
            ),
        ],
      ),
    );
  }
}

class _BackupTile extends ConsumerWidget {
  const _BackupTile({required this.stored});

  final StoredAppBackup stored;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = stored.backup;

    return ListTile(
      leading: Icon(backup == null ? Icons.broken_image_outlined : Icons.description_outlined),
      title: Text(backup == null ? stored.fileName : formatTimestamp(backup.createdAt)),
      subtitle: Text(backup == null ? 'Not a readable backup' : _describe(backup)),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => switch (action) {
          'restore' => confirmRestore(context, ref, stored),
          'share' => ref.read(appBackupActionsProvider).share(stored),
          _ => _confirmDelete(context, ref),
        },
        itemBuilder: (context) => [
          if (backup != null) const PopupMenuItem(value: 'restore', child: Text('Restore')),
          const PopupMenuItem(value: 'share', child: Text('Share')),
          const PopupMenuItem(value: 'delete', child: Text('Delete backup')),
        ],
      ),
      onTap: backup == null ? null : () => confirmRestore(context, ref, stored),
    );
  }

  String _describe(AppBackup backup) {
    final parts = [
      countLabel(backup.folderCount, 'folder'),
      countLabel(backup.trackCount, 'entry', plural: 'entries'),
      if (backup.hiddenTrackPaths.isNotEmpty) '${backup.hiddenTrackPaths.length} hidden',
      if (backup.playHistory.isNotEmpty) '${backup.playHistory.length} plays',
    ];
    return parts.join(' · ');
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this backup file?'),
        content: Text('${stored.fileName} will be removed. Your folders are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(appBackupActionsProvider).delete(stored);
  }
}

/// Shows what restoring would do, then does it if the user agrees.
///
/// Shared by the saved list and by a freshly imported file, so importing from
/// another phone ends in exactly the same confirmation as restoring a local
/// backup — including the count of paths that will not match anything here,
/// which is the number that matters after a move between devices.
Future<void> confirmRestore(BuildContext context, WidgetRef ref, StoredAppBackup stored) async {
  final backup = stored.backup;
  if (backup == null) return;

  final counts = ref.read(appBackupActionsProvider).preview(backup);
  var applySettings = backup.settings != null;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adds back anything from ${formatTimestamp(backup.createdAt)} that '
              'is missing right now.\n\n'
              'Nothing is removed or renamed, and your audio files are not '
              'touched. Restoring the same backup twice does nothing the '
              'second time.',
            ),
            const SizedBox(height: 16),
            Text(_matchSummary(counts)),
            if (backup.settings != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: applySettings,
                onChanged: (value) => setState(() => applySettings = value ?? false),
                title: const Text('Also restore settings'),
                // The only part of a restore that replaces rather than adds,
                // so it is the only part the user is asked about.
                subtitle: const Text('Theme, library sort and repeat mode replace the current ones'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final summary = await ref.read(appBackupActionsProvider).restore(
          stored,
          applySettings: applySettings,
        );
    messenger.showSnackBar(SnackBar(content: Text(_restoreSummary(summary))));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't restore: $error")));
  }
}

String _matchSummary(PathMatchCounts counts) {
  if (counts.total == 0) return 'This backup lists no tracks.';

  final parts = [
    if (counts.exact > 0) '${counts.exact} found on this device',
    if (counts.renamed > 0) '${counts.renamed} matched by file name',
    if (counts.unresolved > 0) "${counts.unresolved} whose file isn't here",
  ];
  return 'Of ${countLabel(counts.total, 'track')} in the file: ${parts.join(', ')}. '
      "Entries whose file isn't here are kept, not dropped — they come back if "
      'the file turns up later.';
}

String _restoreSummary(RestoreSummary summary) {
  if (summary.changedNothing) return 'Everything in this backup was already here';

  final folders = summary.folders;
  final parts = [
    if (folders.foldersCreated > 0) countLabel(folders.foldersCreated, 'folder'),
    if (folders.linksAdded > 0) countLabel(folders.linksAdded, 'entry', plural: 'entries'),
    if (summary.tracksHidden > 0) '${summary.tracksHidden} hidden',
    if (summary.playsLogged > 0) '${summary.playsLogged} plays',
    if (summary.settingsApplied) 'settings',
  ];

  final matched = folders.linksRemapped > 0 ? ' (${folders.linksRemapped} matched by file name)' : '';
  return 'Restored ${parts.join(', ')}$matched';
}

/// `1 folder` / `3 folders`, for the many counts this screen reports.
String countLabel(int value, String singular, {String? plural}) =>
    '$value ${value == 1 ? singular : plural ?? '${singular}s'}';
