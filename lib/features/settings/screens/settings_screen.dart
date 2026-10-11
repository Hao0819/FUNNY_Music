import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/utils/date_format.dart';

import '../../library/providers/library_providers.dart';
import '../../../services/permissions/permission_provider.dart';
import '../providers/backup_providers.dart';
import '../providers/maintenance_providers.dart';
import '../providers/theme_mode_provider.dart';
import 'backup_screen.dart';
import 'hidden_tracks_screen.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final stale = ref.watch(staleRecordsProvider);
    final hidden = ref.watch(hiddenTracksProvider);
    final backups = ref.watch(appBackupsProvider).value;
    final setAside = ref.watch(setAsideBoxesProvider);
    final packageInfo = ref.watch(_packageInfoProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(title: 'Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            // The same chips the Library filters use. SegmentedButton is one
            // of the most recognisable Material components there is, outlines
            // and all, and three of its icons on a settings page were doing
            // nothing the three words did not already do.
            child: Wrap(
              spacing: 8,
              children: [
                for (final mode in ThemeMode.values)
                  ChoiceChip(
                    label: Text(switch (mode) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                    selected: themeMode == mode,
                    showCheckmark: false,
                    onSelected: (_) => ref.read(themeModeProvider.notifier).setThemeMode(mode),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          _SectionHeader(title: 'Playback'),
          _NotificationPermissionTile(),
          const SizedBox(height: 28),

          _SectionHeader(title: 'Library'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Rescan device'),
            subtitle: const Text('Look for audio added or removed since the last scan'),
            onTap: () async {
              await ref.read(libraryScanProvider.notifier).refresh();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Rescan finished')),
              );
            },
          ),
          ListTile(
            leading: Icon(
              stale.isEmpty ? Icons.check_circle_outline : Icons.cleaning_services_outlined,
              color: stale.isEmpty ? null : theme.colorScheme.error,
            ),
            title: const Text('Clean up missing files'),
            subtitle: Text(
              stale.isEmpty
                  ? 'Nothing to clean up'
                  : '${stale.missingPaths.length} file${stale.missingPaths.length == 1 ? '' : 's'} '
                      'no longer on this device',
            ),
            enabled: !stale.isEmpty,
            onTap: stale.isEmpty ? null : () => _confirmCleanup(context, ref, stale),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hidden tracks'),
            // Named even when the list is empty, since this is the only place
            // that explains where a hidden track went and how to get it back.
            subtitle: Text(
              hidden.isEmpty
                  ? 'Nothing hidden — hold a track in your Library to hide it'
                  : '${hidden.length} track${hidden.length == 1 ? '' : 's'} kept out of the Library list',
            ),
            enabled: hidden.isNotEmpty,
            trailing: hidden.isEmpty ? null : const Icon(Icons.chevron_right),
            onTap: hidden.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const HiddenTracksScreen()),
                    ),
          ),
          const SizedBox(height: 28),

          _SectionHeader(title: 'Backup'),
          ListTile(
            leading: Icon(
              setAside.isEmpty ? Icons.backup_outlined : Icons.warning_amber_rounded,
              color: setAside.isEmpty ? null : theme.colorScheme.error,
            ),
            title: const Text('Backup & transfer'),
            subtitle: Text(
              setAside.isNotEmpty
                  ? 'Some saved data could not be read on this launch'
                  : switch (backups) {
                      null => 'Export, send to another phone, or restore from a file',
                      [] => 'No backup yet — your playlists exist in one place only',
                      [final latest, ...] => 'Last backup '
                          '${latest.backup == null ? latest.fileName : formatTimestamp(latest.backup!.createdAt)}',
                    },
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
            ),
          ),
          const SizedBox(height: 28),

          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(packageInfo?.appName ?? 'FUNNY Music'),
            subtitle: Text(
              packageInfo == null
                  ? 'Local audio player'
                  : 'Version ${packageInfo.version} (build ${packageInfo.buildNumber})',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Everything stays on your device'),
            subtitle: Text(
              'Your library, folders and play history are stored locally. '
              'Nothing is uploaded anywhere.',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmCleanup(BuildContext context, WidgetRef ref, StaleRecords stale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean up missing files?'),
        content: Text(
          '${stale.missingPaths.length} audio file(s) that used to be on this device are gone.\n\n'
          'This removes ${stale.folderLinks} playlist entr${stale.folderLinks == 1 ? 'y' : 'ies'} '
          'and ${stale.historyEntries} history entr${stale.historyEntries == 1 ? 'y' : 'ies'} '
          'pointing at them.\n\n'
          'Your other folders, favorites and audio files are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clean up')),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(maintenanceActionsProvider).cleanUpStaleRecords();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleaned up records for missing files')),
    );
  }
}

/// Whether the media notification may appear, and a way to fix it when it may
/// not.
///
/// Worth a row of its own because the dialog is shown once: Android stops
/// offering it after a refusal, so from then on the only route back is the
/// system settings page, and nothing in the app was pointing at it.
class _NotificationPermissionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(notificationPermissionProvider).value;
    final granted = status?.isGranted ?? true;

    return ListTile(
      leading: Icon(granted ? Icons.lock_open_outlined : Icons.lock_outline),
      title: const Text('Lock screen controls'),
      subtitle: Text(
        granted
            ? 'The player shows on the lock screen and in the notification shade'
            : "Blocked — the player can't appear on the lock screen or in the shade",
      ),
      trailing: granted ? null : const Icon(Icons.chevron_right),
      onTap: granted
          ? null
          : () async {
              final notifier = ref.read(notificationPermissionProvider.notifier);
              // A refused permission cannot be re-requested; the call would
              // return straight away and nothing would happen on screen.
              if (status != null && status.isPermanentlyDenied) {
                await ref.read(permissionServiceProvider).openSettings();
              } else {
                await notifier.request();
              }
              await notifier.refresh();
            },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        title.toUpperCase(),
        // Small, grey and tracked out, the way the reference labels a block of
        // content. It used to be the accent colour, which with the accent gone
        // would simply be white — too loud for a label above the thing it
        // names.
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}
