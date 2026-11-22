import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tab strip above the request editor: shows the open API and WebSocket tabs.
class RequestTabBar extends StatefulWidget {
  final AppState state;

  RequestTabBar({super.key, required this.state});

  @override
  State<RequestTabBar> createState() => _RequestTabBarState();
}

class _RequestTabBarState extends State<RequestTabBar> {
  final _scrollController = ScrollController();
  final _chipKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant RequestTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tabs = widget.state.tabsFor(widget.state.mode);
    final index = tabs.indexWhere((tab) => tab.id == widget.state.activeTabId);
    if (index >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _chipKeys[tabs[index].id];
        final context = key?.currentContext;
        if (context != null && mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration(milliseconds: 120),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _close(WorkspaceTab tab) async {
    final dirty = tab.entryId.isEmpty &&
        (tab.request.url.trim().isNotEmpty || tab.ws.url.trim().isNotEmpty);
    if (dirty) {
      final ok = await showConfirmDialog(
        context,
        title: 'Close draft',
        message: '“${tab.name}” has unsaved changes. Close it anyway?',
        confirmLabel: 'Close',
      );
      if (!ok) return;
    }
    widget.state.closeTab(tab.id);
  }

  void _selectSibling(int offset) {
    final state = widget.state;
    final tabs = state.tabsFor(state.mode);
    final index = tabs.indexWhere((tab) => tab.id == state.activeTabId);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= tabs.length) return;
    state.activateTab(tabs[target].id);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final modeTabs = state.tabsFor(state.mode);
    if (modeTabs.isEmpty) return SizedBox.shrink();
    final index = modeTabs.indexWhere((tab) => tab.id == state.activeTabId);
    final canPrev = index > 0;
    final canNext = index >= 0 && index < modeTabs.length - 1;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AstraColors.bgSoft,
        border: Border(bottom: BorderSide(color: AstraColors.line)),
      ),
      child: Row(
        children: [
          _ArrowButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous tab (Alt+Left)',
            enabled: canPrev,
            onPressed: () => _selectSibling(-1),
          ),
          _ArrowButton(
            icon: Icons.chevron_right,
            tooltip: 'Next tab (Alt+Right)',
            enabled: canNext,
            onPressed: () => _selectSibling(1),
          ),
          SizedBox(width: 4),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              thickness: 3,
              radius: Radius.circular(99),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    for (final tab in modeTabs)
                      _TabChip(
                        key: _chipKeys.putIfAbsent(tab.id, () => GlobalKey()),
                        tab: tab,
                        active: tab.id == state.activeTabId,
                        onTap: () => state.activateTab(tab.id),
                        onClose: () => _close(tab),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              tooltip: 'New request ($_modifierLabel+N)',
              padding: EdgeInsets.zero,
              iconSize: 15,
              color: AstraColors.muted,
              onPressed: state.newRequest,
              icon: Icon(Icons.add),
            ),
          ),
          SizedBox(width: 6),
        ],
      ),
    );
  }

  String get _modifierLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 26,
          height: 26,
          margin: EdgeInsets.only(left: 4),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AstraColors.muted : AstraColors.faint.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  _TabChip({
    super.key,
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
        height: 28,
        constraints: BoxConstraints(maxWidth: 210),
        margin: EdgeInsets.only(right: 4, top: 5),
        padding: EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: active ? AstraColors.surface2 : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: active ? AstraColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
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
            SizedBox(width: 7),
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
              SizedBox(width: 5),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AstraColors.warn,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            SizedBox(width: 2),
            SizedBox(
              width: 20,
              height: 20,
              child: IconButton(
                tooltip: 'Close',
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
