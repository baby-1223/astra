import 'package:flutter/material.dart';

import '../services/file_io.dart';
import '../state.dart';
import 'advanced_dialogs.dart';
import 'dialogs.dart';
import 'runner_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class TopBar extends StatelessWidget {
  final AppState state;

  TopBar({super.key, required this.state});

  Future<void> _import(BuildContext context) async {
    try {
      final picked = await pickJsonFile();
      if (picked == null) return;
      final message = state.importData(picked.data);
      state.showToast(message);
    } on FormatException catch (err) {
      if (!context.mounted) return;
      await showMessageDialog(
        context,
        title: 'Import Failed',
        message: err.message,
        error: true,
      );
    } catch (err) {
      if (!context.mounted) return;
      await showMessageDialog(
        context,
        title: 'Import Failed',
        message: '$err',
        error: true,
      );
    }
  }

  Future<void> _export(BuildContext context) async {
    final format = await showExportDialog(context);
    if (format == null || !context.mounted) return;
    try {
      final stamp = DateTime.now();
      final suffix = '${stamp.year}'
          '${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}';
      late final Map<String, dynamic> data;
      late final String name;
      switch (format) {
        case 'postman':
          data = state.exportPostman();
          name = 'astra-postman-$suffix.json';
        case 'openapi':
          data = state.exportOpenApi();
          name = 'astra-openapi-$suffix.json';
        default:
          data = state.exportAstra();
          name = 'astra-$suffix.json';
      }
      final path = await saveJsonFile(name, data);
      if (path != null) state.showToast('Exported: $path');
    } catch (err) {
      if (!context.mounted) return;
      await showMessageDialog(
        context,
        title: 'Export Failed',
        message: '$err',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AstraColors.topBar,
        border: Border(bottom: BorderSide(color: AstraColors.line)),
      ),
      child: Row(
        children: [
          _Brand(),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _ModeSwitch(
                  mode: state.mode,
                  onChanged: state.switchMode,
                ),
              ),
            ),
          ),
          _IconAction(
            icon: Icons.data_object,
            tooltip: 'Variables & scope precedence',
            onTap: () => showVariablesDialog(context, state),
          ),
          _IconAction(
            icon: Icons.playlist_play,
            tooltip: 'Collection Runner',
            onTap: () => showRunnerDialog(context, state),
          ),
          _IconAction(
            icon: Icons.lan_outlined,
            tooltip: 'Proxy & client certificates',
            onTap: () => showNetworkSettingsDialog(context, state),
          ),
          _IconAction(
            icon: Icons.keyboard_outlined,
            tooltip: 'Keyboard Shortcuts',
            onTap: () => showShortcutsDialog(context),
          ),
          _EnvChip(state: state),
          SizedBox(width: 8),
          _IconAction(
            icon: Icons.cookie_outlined,
            tooltip: 'Cookie Manager',
            badge: state.cookies.length,
            onTap: () => showCookieDialog(context, state),
          ),
          _IconAction(
            icon: Icons.file_download_outlined,
            tooltip: 'Import Postman / OpenAPI / Astra',
            onTap: () => _import(context),
          ),
          _IconAction(
            icon: Icons.ios_share_rounded,
            tooltip: 'Export Workspace',
            onTap: () => _export(context),
          ),
          SizedBox(width: 4),
          GhostButton(
            label: 'New',
            icon: Icons.add,
            padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            onPressed: state.newRequest,
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  _Brand();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AstraColors.accent, AstraColors.accent2],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AstraColors.accent.withValues(alpha: 0.28),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Icon(Icons.auto_awesome, size: 17, color: Color(0xFF06121C)),
          ),
          SizedBox(width: 11),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  colors: [Color(0xFF8BE9FF), Color(0xFFC4B5FD)],
                ).createShader(rect),
                child: Text(
                  'ASTRA',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4.6,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 1),
              Text(
                'HTTP / WEBSOCKET STUDIO',
                style: TextStyle(fontSize: 7.5, letterSpacing: 1.5, color: AstraColors.faint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AstraColors.overlay,
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _item('http', 'HTTP', Icons.swap_horiz_rounded),
          _item('ws', 'WebSocket', Icons.electrical_services_rounded),
        ],
      ),
    );
  }

  Widget _item(String id, String label, IconData icon) {
    final active = mode == id;
    return GestureDetector(
      onTap: () => onChanged(id),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  colors: [Color(0xFF7DD3FC), Color(0xFFA5B4FC)],
                )
              : null,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AstraColors.accent.withValues(alpha: 0.22),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? Color(0xFF071019) : AstraColors.muted,
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Color(0xFF071019) : AstraColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvChip extends StatelessWidget {
  final AppState state;

  _EnvChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state.env;
    final count = active.vars.where((item) => item.k.trim().isNotEmpty).length;
    return PopupMenuButton<String>(
      tooltip: 'Switch / manage environments',
      color: AstraColors.surface2,
      offset: Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AstraColors.line),
      ),
      onSelected: (value) {
        if (value == '__manage') {
          showEnvManagerDialog(context, state);
        } else {
          state.switchEnv(value);
        }
      },
      itemBuilder: (ctx) => [
        for (final env in state.environments)
          PopupMenuItem<String>(
            value: env.id,
            height: 38,
            child: Row(
              children: [
                Icon(
                  env.id == state.activeEnvId
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined,
                  size: 14,
                  color: env.id == state.activeEnvId
                      ? AstraColors.accent
                      : AstraColors.faint,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    env.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: env.id == state.activeEnvId
                          ? AstraColors.text
                          : AstraColors.muted,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '${env.vars.where((item) => item.k.trim().isNotEmpty).length}',
                  style: TextStyle(fontSize: 10, color: AstraColors.faint),
                ),
              ],
            ),
          ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__manage',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 14, color: AstraColors.muted),
              SizedBox(width: 9),
              Flexible(
                child: Text(
                  'Manage environments…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AstraColors.muted),
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        constraints: BoxConstraints(maxWidth: 180),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AstraColors.line),
          borderRadius: BorderRadius.circular(99),
          color: AstraColors.overlay,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: count > 0 ? AstraColors.ok : AstraColors.faint,
                shape: BoxShape.circle,
                boxShadow: count > 0
                    ? [
                        BoxShadow(
                          color: AstraColors.ok.withValues(alpha: 0.7),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                active.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AstraColors.muted),
              ),
            ),
            if (count > 0) ...[
              SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
            SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: AstraColors.faint),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int? badge;

  _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 18, color: AstraColors.muted),
              if (badge != null && badge! > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: AstraColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF06121C),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
