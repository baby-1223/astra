import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

/// 右侧编辑器顶部的标签页栏：展示已打开 / 新建的 API 与连接。
class RequestTabBar extends StatelessWidget {
  final AppState state;

  const RequestTabBar({super.key, required this.state});

  Future<void> _close(BuildContext context, WorkspaceTab tab) async {
    final dirty = tab.entryId.isEmpty &&
        (tab.request.url.trim().isNotEmpty || tab.ws.url.trim().isNotEmpty);
    if (dirty) {
      final ok = await showConfirmDialog(
        context,
        title: '关闭草稿',
        message: '「${tab.name}」尚未保存，关闭后内容将丢失。',
        confirmLabel: '关闭',
      );
      if (!ok) return;
    }
    state.closeTab(tab.id);
  }

  @override
  Widget build(BuildContext context) {
    final modeTabs = state.tabsFor(state.mode);
    if (modeTabs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 0),
      decoration: const BoxDecoration(
        color: AstraColors.bgSoft,
        border: Border(bottom: BorderSide(color: AstraColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final tab in modeTabs)
                  _TabChip(
                    tab: tab,
                    active: tab.id == state.activeTabId,
                    onTap: () => state.activateTab(tab.id),
                    onClose: () => _close(context, tab),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 26,
            height: 26,
            child: IconButton(
              tooltip: '新建请求',
              padding: EdgeInsets.zero,
              iconSize: 15,
              color: AstraColors.muted,
              onPressed: state.newRequest,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final method = tab.mode == 'ws' ? 'WS' : tab.request.method.toUpperCase();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        constraints: const BoxConstraints(maxWidth: 210),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: active ? AstraColors.surface2 : Colors.transparent,
          border: Border.all(
            color: active ? AstraColors.line : Colors.transparent,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              method,
              style: monoStyle(
                size: 9,
                color: methodColor(method),
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                tab.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: active ? AstraColors.text : AstraColors.muted,
                ),
              ),
            ),
            if (tab.entryId.isEmpty) ...[
              const SizedBox(width: 5),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AstraColors.warn,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            const SizedBox(width: 3),
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                tooltip: '关闭',
                padding: EdgeInsets.zero,
                iconSize: 12,
                color: AstraColors.faint,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
