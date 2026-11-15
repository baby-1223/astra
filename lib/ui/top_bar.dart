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

  const TopBar({super.key, required this.state});

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
        title: '导入失败',
        message: err.message,
        error: true,
      );
    } catch (err) {
      if (!context.mounted) return;
      await showMessageDialog(
        context,
        title: '导入失败',
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
      if (path != null) state.showToast('已导出：$path');
    } catch (err) {
      if (!context.mounted) return;
      await showMessageDialog(
        context,
        title: '导出失败',
        message: '$err',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xB307090E),
        border: Border(bottom: BorderSide(color: AstraColors.line)),
      ),
      child: Row(
        children: [
          const _Brand(),
          Expanded(
            child: Center(
              child: _ModeSwitch(
                mode: state.mode,
                onChanged: state.switchMode,
              ),
            ),
          ),
          _IconAction(
            icon: Icons.data_object,
            tooltip: '变量面板与优先级',
            onTap: () => showVariablesDialog(context, state),
          ),
          _IconAction(
            icon: Icons.playlist_play,
            tooltip: '集合运行器',
            onTap: () => showRunnerDialog(context, state),
          ),
          _IconAction(
            icon: Icons.lan_outlined,
            tooltip: '代理与客户端证书',
            onTap: () => showNetworkSettingsDialog(context, state),
          ),
          _IconAction(
            icon: Icons.keyboard_outlined,
            tooltip: '快捷键',
            onTap: () => showShortcutsDialog(context),
          ),
          _EnvChip(state: state),
          const SizedBox(width: 8),
          _IconAction(
            icon: Icons.cookie_outlined,
            tooltip: 'Cookie 管理',
            badge: state.cookies.length,
            onTap: () => showCookieDialog(context, state),
          ),
          _IconAction(
            icon: Icons.file_download_outlined,
            tooltip: '导入 Postman / OpenAPI / Astra',
            onTap: () => _import(context),
          ),
          _IconAction(
            icon: Icons.ios_share_rounded,
            tooltip: '导出工作区',
            onTap: () => _export(context),
          ),
          const SizedBox(width: 4),
          GhostButton(
            label: '新建',
            icon: Icons.add,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            onPressed: state.newRequest,
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

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
              gradient: const LinearGradient(
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
            child: const Icon(Icons.auto_awesome, size: 17, color: Color(0xFF06121C)),
          ),
          const SizedBox(width: 11),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Color(0xFF8BE9FF), Color(0xFFC4B5FD)],
                ).createShader(rect),
                child: const Text(
                  'ASTRA',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4.6,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              const Text(
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

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
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
              color: active ? const Color(0xFF071019) : AstraColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? const Color(0xFF071019) : AstraColors.muted,
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

  const _EnvChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state.env;
    final count = active.vars.where((item) => item.k.trim().isNotEmpty).length;
    return PopupMenuButton<String>(
      tooltip: '切换 / 管理环境',
      color: AstraColors.surface2,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AstraColors.line),
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
                const SizedBox(width: 9),
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
                const SizedBox(width: 12),
                Text(
                  '${env.vars.where((item) => item.k.trim().isNotEmpty).length}',
                  style: const TextStyle(fontSize: 10, color: AstraColors.faint),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__manage',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 14, color: AstraColors.muted),
              SizedBox(width: 9),
              Text(
                '管理环境…',
                style: TextStyle(fontSize: 12, color: AstraColors.muted),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AstraColors.line),
          borderRadius: BorderRadius.circular(99),
          color: const Color(0x08FFFFFF),
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
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                active.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AstraColors.muted),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 14, color: AstraColors.faint),
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

  const _IconAction({
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 18, color: AstraColors.muted),
              if (badge != null && badge! > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
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
