import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../services/workspace_io.dart';
import '../state.dart';
import 'advanced_dialogs.dart';
import 'dialogs.dart';
import 'theme.dart';

/// Application menu bar.
///
/// macOS uses the native menu bar via [PlatformMenuBar]; Windows and Linux get an
/// in-app menu row above the top bar.
class AstraMenuBar extends StatelessWidget {
  final AppState state;
  final Widget child;

  const AstraMenuBar({super.key, required this.state, required this.child});

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    if (_isMacOS) {
      return PlatformMenuBar(menus: _platformMenus(context), child: child);
    }
    return Column(
      children: [
        _InlineMenuBar(state: state),
        Expanded(child: child),
      ],
    );
  }

  List<PlatformMenuItem> _platformMenus(BuildContext context) => [
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'New Request',
              onSelected: state.newRequest,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Import…',
              onSelected: () => importWorkspaceData(context, state),
            ),
            PlatformMenuItem(
              label: 'Export…',
              onSelected: () => exportWorkspaceData(context, state),
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: [
        PlatformMenuItem(
          label: 'Keyboard Shortcuts',
          onSelected: () => showShortcutsDialog(context),
        ),
      ],
    ),
    PlatformMenu(
      label: 'Help',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Check for Updates…',
              onSelected: () => checkForUpdatesDialog(context),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'GitHub',
              onSelected: () => openExternal(UpdateService.repoUrl),
            ),
            PlatformMenuItem(
              label: 'Documentation',
              onSelected: () => openExternal(UpdateService.documentationUrl),
            ),
            PlatformMenuItem(
              label: 'Support',
              onSelected: () => openExternal(UpdateService.supportUrl),
            ),
          ],
        ),
      ],
    ),
  ];
}

class _InlineMenuBar extends StatelessWidget {
  final AppState state;

  const _InlineMenuBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AstraColors.topBar,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AstraColors.line)),
        ),
        child: Row(
          children: [
            _MenuButton(
              label: 'File',
              actions: {
                'New Request': state.newRequest,
                'Import…': () => importWorkspaceData(context, state),
                'Export…': () => exportWorkspaceData(context, state),
              },
            ),
            _MenuButton(
              label: 'View',
              actions: {
                'Keyboard Shortcuts': () => showShortcutsDialog(context),
              },
            ),
            _MenuButton(
              label: 'Help',
              actions: {
                'Check for Updates…': () => checkForUpdatesDialog(context),
                'GitHub': () => openExternal(UpdateService.repoUrl),
                'Documentation': () =>
                    openExternal(UpdateService.documentationUrl),
                'Support': () => openExternal(UpdateService.supportUrl),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final Map<String, VoidCallback> actions;

  const _MenuButton({required this.label, required this.actions});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (id) => actions[id]?.call(),
      itemBuilder: (context) => [
        for (final entry in actions.entries)
          PopupMenuItem<String>(
            value: entry.key,
            height: 32,
            child: Text(entry.key, style: const TextStyle(fontSize: 12.5)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: AstraColors.muted),
        ),
      ),
    );
  }
}

Future<void> checkForUpdatesDialog(BuildContext context) async {
  try {
    final info = await UpdateService().checkForUpdates();
    if (!context.mounted) return;
    if (info == null) {
      await showMessageDialog(
        context,
        title: 'Check for Updates',
        message: 'No releases are available yet.',
      );
      return;
    }
    if (!info.isNewerThan(AppState.version)) {
      await showMessageDialog(
        context,
        title: 'Check for Updates',
        message: 'Astra v${AppState.version} is up to date.',
      );
      return;
    }
    final download = await showConfirmDialog(
      context,
      title: 'Update Available',
      message:
          'Astra v${info.latestVersion} is available. '
          'You are running v${AppState.version}.',
      confirmLabel: 'Download',
    );
    if (download) await openExternal(info.releaseUrl);
  } catch (error) {
    if (!context.mounted) return;
    await showMessageDialog(
      context,
      title: 'Check for Updates',
      message: '$error',
      error: true,
    );
  }
}

Future<bool> openExternal(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
