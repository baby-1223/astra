part of '../sidebar.dart';

/* 侧栏子项组件 */

class _SideItem extends StatefulWidget {
  final bool active;
  final double indent;
  final String method;
  final String name;
  final String url;
  final String? tooltip;
  final bool hideDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String>? onMenuSelected;
  final List<PopupMenuEntry<String>>? menuItems;

  _SideItem({
    required this.active,
    required this.method,
    required this.name,
    required this.url,
    required this.onTap,
    required this.onDelete,
    this.indent = 0,
    this.tooltip,
    this.hideDelete = false,
    this.onMenuSelected,
    this.menuItems,
  });

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  Future<void> _showMenu(Offset position) async {
    final items = widget.menuItems;
    if (items == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: AstraColors.surface2,
      items: items,
    );
    if (selected != null) widget.onMenuSelected?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final content = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.menuItems == null
            ? null
            : (details) => _showMenu(details.globalPosition),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 130),
          margin: EdgeInsets.only(bottom: 3),
          padding: EdgeInsets.fromLTRB(9 + widget.indent, 8, 9, 8),
          decoration: BoxDecoration(
            color: widget.active
                ? AstraColors.accentSoft
                : _hover
                    ? AstraColors.overlay
                    : Colors.transparent,
            border: Border.all(
              color: widget.active
                  ? AstraColors.accentBorder
                  : _hover
                      ? AstraColors.line
                      : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              MethodBadge(method: widget.method),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AstraColors.text),
                    ),
                    if (widget.url.isNotEmpty) ...[
                      SizedBox(height: 2),
                      Text(
                        widget.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(size: 10.5, color: AstraColors.faint),
                      ),
                    ],
                  ],
                ),
              ),
              if (_hover || widget.active) ...[
                if (widget.menuItems != null)
                  Padding(
                    padding: EdgeInsets.only(left: 4, right: 2),
                    child: Icon(Icons.more_horiz, size: 15, color: AstraColors.faint),
                  )
                else if (!widget.hideDelete)
                  SizedBox(
                    width: 24,
                    child: IconButton(
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: 'Close',
                      color: AstraColors.faint,
                      highlightColor: AstraColors.errSoft,
                      icon: Icon(Icons.close),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip == null) return content;
    return Tooltip(
      message: widget.tooltip!,
      waitDuration: Duration(milliseconds: 600),
      child: content,
    );
  }
}

class _SearchSectionLabel extends StatelessWidget {
  final String text;

  _SearchSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 10, 8, 5),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: AstraColors.faint, letterSpacing: 0.6),
      ),
    );
  }
}

class _HistoryItem extends StatefulWidget {
  final HistoryEntry entry;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  _HistoryItem({
    required this.entry,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.selectMode ? widget.onToggle : widget.onTap,
        child: Container(
          margin: EdgeInsets.only(bottom: 3),
          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? AstraColors.accentSoft
                : _hover
                    ? AstraColors.overlay
                    : Colors.transparent,
            border: Border.all(
              color: widget.selected
                  ? AstraColors.accent
                  : _hover
                      ? AstraColors.line
                      : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              if (widget.selectMode) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: widget.selected,
                    onChanged: (_) => widget.onToggle(),
                    activeColor: AstraColors.accent,
                    side: BorderSide(color: AstraColors.lineStrong, width: 1),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                SizedBox(width: 8),
              ],
              MethodBadge(method: entry.method),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(size: 10.5, color: AstraColors.muted),
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: statusColor(entry.status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text(
                          entry.status == null ? 'Failed' : '${entry.status}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: statusColor(entry.status),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '${entry.ms} ms',
                          style: TextStyle(fontSize: 9.5, color: AstraColors.faint),
                        ),
                        Spacer(),
                        Text(
                          formatTime(entry.ts),
                          style: TextStyle(fontSize: 9.5, color: AstraColors.faint),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!widget.selectMode && _hover) ...[
                SizedBox(width: 6),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    tooltip: 'Delete this history entry',
                    padding: EdgeInsets.zero,
                    iconSize: 13,
                    color: AstraColors.faint,
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Star shown on collection rows: always visible once starred, otherwise on hover.
class _GroupStarButton extends StatefulWidget {
  final bool starred;
  final VoidCallback onTap;

  const _GroupStarButton({required this.starred, required this.onTap});

  @override
  State<_GroupStarButton> createState() => _GroupStarButtonState();
}

class _GroupStarButtonState extends State<_GroupStarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final visible = widget.starred || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.starred ? 'Unstar collection' : 'Star collection',
          waitDuration: const Duration(milliseconds: 500),
          child: SizedBox(
            width: 18,
            height: 18,
            child: visible
                ? Icon(
                    widget.starred
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 15,
                    color: widget.starred
                        ? const Color(0xFFF2A93B)
                        : AstraColors.faint,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Toolbar toggle that filters the collection list down to starred items.
class _StarFilterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _StarFilterButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Show all collections' : 'Only starred collections',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active
                ? AstraColors.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AstraColors.accent.withValues(alpha: 0.45)
                  : AstraColors.line,
            ),
          ),
          child: Icon(
            active ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: active ? AstraColors.accent : AstraColors.faint,
          ),
        ),
      ),
    );
  }
}
