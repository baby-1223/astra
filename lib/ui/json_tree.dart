import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// JSON 树形视图：支持逐级折叠、关键字搜索高亮、全部展开 / 折叠与复制。
class JsonTreeView extends StatefulWidget {
  final dynamic data;

  JsonTreeView({super.key, required this.data});

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonRow {
  final String path;
  final int depth;
  final String label;
  final dynamic value;
  final bool container;
  final bool expanded;
  final bool last;

  _JsonRow({
    required this.path,
    required this.depth,
    required this.label,
    required this.value,
    required this.container,
    required this.expanded,
    required this.last,
  });
}

class _JsonTreeViewState extends State<JsonTreeView> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _collapsed = {};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _match(dynamic value, String label) {
    final query = _query.toLowerCase();
    if (label.toLowerCase().contains(query)) return true;
    if (value is Map) {
      for (final entry in value.entries) {
        if (_match(entry.value, '${entry.key}')) return true;
      }
      return false;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        if (_match(value[i], '[$i]')) return true;
      }
      return false;
    }
    return _scalarText(value).toLowerCase().contains(query);
  }

  void _walk(dynamic value, String path, String label, int depth, List<_JsonRow> out) {
    final container = value is Map || value is List;
    final expanded = _query.isNotEmpty || !_collapsed.contains(path);
    out.add(_JsonRow(
      path: path,
      depth: depth,
      label: label,
      value: value,
      container: container,
      expanded: expanded,
      last: false,
    ));
    if (!container || !expanded) return;
    if (value is Map) {
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (_query.isNotEmpty && !_match(entry.value, '${entry.key}')) continue;
        _walk(entry.value, '$path/${entry.key}', '${entry.key}', depth + 1, out);
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        if (_query.isNotEmpty && !_match(value[i], '[$i]')) continue;
        _walk(value[i], '$path/$i', '[$i]', depth + 1, out);
      }
    }
  }

  List<_JsonRow> _rows() {
    final rows = <_JsonRow>[];
    _walk(widget.data, r'$', '', 0, rows);
    return rows;
  }

  String _scalarText(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    return '$value';
  }

  Color _scalarColor(dynamic value) {
    if (value == null) return AstraColors.faint;
    if (value is String) return AstraColors.codeString;
    if (value is num) return AstraColors.codeNumber;
    if (value is bool) return AstraColors.codeKeyword;
    return AstraColors.text;
  }

  void _toggleAll(bool collapse) {
    setState(() {
      _collapsed.clear();
      if (collapse) {
        final rows = <_JsonRow>[];
        _walk(widget.data, r'$', '', 0, rows);
        for (final row in rows) {
          if (row.container) _collapsed.add(row.path);
        }
      }
    });
  }

  RichText _highlight(String text, Color color, {bool bold = false, double size = 11.8}) {
    final style = monoStyle(
      size: size,
      color: color,
      weight: bold ? FontWeight.w600 : FontWeight.w400,
    );
    if (_query.isEmpty) return RichText(text: TextSpan(text: text, style: style));
    final lower = text.toLowerCase();
    final query = _query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(query, start);
      if (index < 0) {
        if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: style.copyWith(
          backgroundColor: AstraColors.warnSoft,
          color: AstraColors.codeMatch,
        ),
      ));
      start = index + query.length;
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _countBadge(dynamic value) {
    final count = value is Map ? value.length : (value as List).length;
    final label = value is Map ? '{$count}' : '[$count]';
    return Text(label, style: monoStyle(size: 10.5, color: AstraColors.faint));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 230,
              height: 30,
              child: TextField(
                controller: _search,
                style: TextStyle(fontSize: 11.5, color: AstraColors.text),
                decoration: astraInput(hint: 'Search keys or values', contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            SizedBox(width: 8),
            if (_query.isNotEmpty)
              Text(
                '${rows.length} matches',
                style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
              ),
            Spacer(),
            _miniAction('Expand All', () => _toggleAll(false)),
            SizedBox(width: 6),
            _miniAction('Collapse All', () => _toggleAll(true)),
            SizedBox(width: 6),
            _miniAction('Copy JSON', () async {
              final text = const JsonEncoder.withIndent('  ').convert(widget.data);
              await Clipboard.setData(ClipboardData(text: text));
            }),
          ],
        ),
        SizedBox(height: 8),
        Divider(height: 1, color: AstraColors.line),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text('No matching content', style: TextStyle(fontSize: 12, color: AstraColors.faint)),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _rowWidget(rows[index]),
                ),
        ),
      ],
    );
  }

  Widget _miniAction(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(label, style: TextStyle(fontSize: 10.5, color: AstraColors.muted)),
      ),
    );
  }

  Widget _rowWidget(_JsonRow row) {
    final indent = 8.0 + row.depth * 14;
    final hasLabel = row.label.isNotEmpty;
    return InkWell(
      onTap: row.container
          ? () => setState(() {
                if (_collapsed.contains(row.path)) {
                  _collapsed.remove(row.path);
                } else {
                  _collapsed.add(row.path);
                }
              })
          : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 3, 10, 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 14,
              child: row.container
                  ? AnimatedRotation(
                      turns: row.expanded ? 0.25 : 0,
                      duration: Duration(milliseconds: 120),
                      child: Icon(Icons.chevron_right, size: 13, color: AstraColors.faint),
                    )
                  : null,
            ),
            if (hasLabel) ...[
              _highlight(row.label, AstraColors.accent),
              Text(' : ', style: TextStyle(fontSize: 11.8, color: AstraColors.faint)),
            ],
            if (row.container)
              _countBadge(row.value)
            else
              Flexible(child: _highlight(_scalarText(row.value), _scalarColor(row.value))),
          ],
        ),
      ),
    );
  }
}
