import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'bound_text_field.dart';
import 'theme.dart';

Color methodColor(String method) {
  switch (method.toUpperCase()) {
    case 'GET':
      return const Color(0xFF67E8F9);
    case 'POST':
      return const Color(0xFF86EFAC);
    case 'PUT':
      return const Color(0xFFFCD34D);
    case 'PATCH':
      return const Color(0xFFC4B5FD);
    case 'DELETE':
      return const Color(0xFFFDA4AF);
    case 'WS':
      return const Color(0xFFA5B4FC);
    default:
      return const Color(0xFFCBD5E1);
  }
}

Color statusColor(int? status) {
  if (status == null) return AstraColors.err;
  if (status >= 200 && status < 300) return AstraColors.ok;
  if (status >= 300 && status < 400) return AstraColors.warn;
  return AstraColors.err;
}

class AstraCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AstraCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)],
        ),
        color: AstraColors.surface,
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x47000000), blurRadius: 44, offset: Offset(0, 16)),
        ],
      ),
      child: child,
    );
  }
}

class MethodBadge extends StatelessWidget {
  final String method;
  final double fontSize;

  const MethodBadge({super.key, required this.method, this.fontSize = 9});

  @override
  Widget build(BuildContext context) {
    final color = methodColor(method);
    return Container(
      constraints: const BoxConstraints(minWidth: 42),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        method.toUpperCase(),
        textAlign: TextAlign.center,
        style: monoStyle(size: fontSize, color: color, weight: FontWeight.w700),
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool danger;
  final EdgeInsetsGeometry padding;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final gradient = danger
        ? const LinearGradient(colors: [Color(0xFFFB7185), Color(0xFFF43F5E)])
        : const LinearGradient(colors: [Color(0xFF67E8F9), Color(0xFF818CF8)]);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(9),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: (danger ? AstraColors.err : AstraColors.accent).withValues(alpha: 0.24),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onPressed,
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: const Color(0xFF05111B)),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF05111B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;

  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AstraColors.text,
        padding: padding,
        side: const BorderSide(color: AstraColors.line),
        backgroundColor: const Color(0x0AFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AstraColors.muted),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
    );
  }
}

class AstraTabItem {
  final String id;
  final String label;
  final int? count;

  const AstraTabItem(this.id, this.label, {this.count});
}

class AstraTabs extends StatelessWidget {
  final List<AstraTabItem> items;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool compact;

  const AstraTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final active = item.id == selected;
          return InkWell(
            onTap: () => onSelect(item.id),
            borderRadius: BorderRadius.circular(7),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 9 : 11,
                vertical: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          color: active ? AstraColors.text : AstraColors.muted,
                        ),
                      ),
                      if (item.count != null && item.count! > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: active
                                ? AstraColors.accent.withValues(alpha: 0.18)
                                : const Color(0x12FFFFFF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${item.count}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: active ? AstraColors.accent : AstraColors.faint,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 2,
                    width: active ? 20 : 0,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AstraColors.accent, AstraColors.accent2],
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class KVEditor extends StatelessWidget {
  final List<KV> rows;
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String keyHint;
  final String valueHint;
  final bool enabledToggle;
  final List<String> varNames;
  final List<String> keySuggestions;
  final VoidCallback? onBulkEdit;

  const KVEditor({
    super.key,
    required this.rows,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
    this.keyHint = '键',
    this.valueHint = '值',
    this.enabledToggle = true,
    this.varNames = const [],
    this.keySuggestions = const [],
    this.onBulkEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onBulkEdit != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onBulkEdit,
              style: TextButton.styleFrom(
                foregroundColor: AstraColors.muted,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                textStyle: const TextStyle(fontSize: 10.5),
              ),
              child: const Text('批量编辑'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
          child: Row(
            children: [
              if (enabledToggle) const SizedBox(width: 30),
              const SizedBox(width: 6),
              Expanded(flex: 5, child: _label(keyHint)),
              const SizedBox(width: 8),
              Expanded(flex: 8, child: _label(valueHint)),
              const SizedBox(width: 34),
            ],
          ),
        ),
        ...List.generate(rows.length, (index) {
          final row = rows[index];
          return _KVRow(
            key: ObjectKey(row),
            row: row,
            enabledToggle: enabledToggle,
            onChanged: onChanged,
            onRemove: () => onRemove(index),
            varNames: varNames,
            keySuggestions: keySuggestions,
            keyHint: keyHint,
            valueHint: valueHint,
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              foregroundColor: AstraColors.muted,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: const TextStyle(fontSize: 11.5),
            ),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('添加一行'),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 10, color: AstraColors.faint, letterSpacing: 0.6),
      );
}

class _KVRow extends StatefulWidget {
  final KV row;
  final bool enabledToggle;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final List<String> varNames;
  final List<String> keySuggestions;
  final String keyHint;
  final String valueHint;

  const _KVRow({
    super.key,
    required this.row,
    required this.enabledToggle,
    required this.onChanged,
    required this.onRemove,
    this.varNames = const [],
    this.keySuggestions = const [],
    this.keyHint = '键',
    this.valueHint = '值',
  });

  @override
  State<_KVRow> createState() => _KVRowState();
}

class _KVRowState extends State<_KVRow> {
  late final TextEditingController _key = TextEditingController(text: widget.row.k);
  late final TextEditingController _value = TextEditingController(text: widget.row.v);
  final FocusNode _keyFocus = FocusNode();

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (widget.enabledToggle)
            SizedBox(
              width: 30,
              child: Transform.scale(
                scale: 0.78,
                child: Checkbox(
                  value: widget.row.on,
                  activeColor: AstraColors.accent,
                  side: const BorderSide(color: AstraColors.lineStrong),
                  onChanged: (value) {
                    widget.row.on = value ?? false;
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: RawAutocomplete<String>(
              textEditingController: _key,
              focusNode: _keyFocus,
              optionsBuilder: (value) {
                final text = value.text.trim().toLowerCase();
                if (text.isEmpty) return const Iterable<String>.empty();
                return widget.keySuggestions
                    .where((item) => item.toLowerCase().startsWith(text))
                    .take(8);
              },
              onSelected: (value) {
                widget.row.k = value;
                setState(() {});
                widget.onChanged();
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: monoStyle(size: 12),
                  decoration: astraInput(
                    hint: widget.keyHint,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (value) {
                    widget.row.k = value;
                    widget.onChanged();
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 240,
                      constraints: const BoxConstraints(maxHeight: 190),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AstraColors.surface2,
                        border: Border.all(color: AstraColors.lineStrong),
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              child: Text(option, style: monoStyle(size: 11.5)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 8,
            child: BoundTextField(
              value: _value.text,
              hint: widget.valueHint,
              fontSize: 12,
              varNames: widget.varNames,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              onChanged: (value) {
                _value.text = value;
                widget.row.v = value;
                widget.onChanged();
              },
            ),
          ),
          SizedBox(
            width: 34,
            child: IconButton(
              tooltip: '删除该行',
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close, size: 15),
              color: AstraColors.faint,
              hoverColor: const Color(0x1AFB7185),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用弹窗外壳，保证新对话框与现有弹窗风格一致。
class AstraDialogShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  const AstraDialogShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    required this.actions,
    this.width = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: AstraColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AstraColors.line),
          boxShadow: const [
            BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 24)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AstraColors.muted,
                  height: 1.6,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Flexible(child: child),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final String? hint;

  const SectionLabel(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: AstraColors.muted,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint!,
                style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CopyButton extends StatelessWidget {
  final String text;
  final String tooltip;

  const CopyButton({super.key, required this.text, this.tooltip = '复制'});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('已复制到剪贴板'),
              duration: Duration(milliseconds: 1200),
              behavior: SnackBarBehavior.floating,
              width: 220,
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.copy_rounded, size: 14, color: AstraColors.muted),
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AstraColors.accent.withValues(alpha: 0.14),
                  AstraColors.accent2.withValues(alpha: 0.14),
                ],
              ),
              border: Border.all(color: AstraColors.line),
            ),
            child: Icon(icon, size: 22, color: AstraColors.accent),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 13, color: AstraColors.muted)),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AstraColors.faint, height: 1.7),
          ),
        ],
      ),
    );
  }
}

String formatBytes(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
}

String formatTime(int ts) {
  final time = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${time.month}/${time.day} $hh:$mm';
}
