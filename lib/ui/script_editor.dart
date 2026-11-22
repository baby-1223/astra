import 'package:flutter/material.dart';

import 'bound_text_field.dart';
import 'theme.dart';

/// 脚本编辑器：行号、自动缩进、括号自动配对，并复用 JS 语法高亮。
class ScriptEditor extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final double height;

  ScriptEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.height = 176,
  });

  @override
  State<ScriptEditor> createState() => _ScriptEditorState();
}

class _ScriptEditorState extends State<ScriptEditor> {
  static const TextStyle _textStyle = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Monaco', 'Consolas', 'monospace'],
    fontSize: 11.5,
    height: 1.55,
  );

  late final JsHighlightController _controller;
  final ScrollController _scroll = ScrollController();
  double _offset = 0;
  late String _last;

  @override
  void initState() {
    super.initState();
    _controller = JsHighlightController(text: widget.value);
    _last = widget.value;
    _scroll.addListener(() {
      if ((_scroll.offset - _offset).abs() < 0.5) return;
      setState(() => _offset = _scroll.offset);
    });
  }

  @override
  void didUpdateWidget(ScriptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _last = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleChanged(String text) {
    final selection = _controller.selection;
    final caret = selection.baseOffset;
    final insertedOne = text.length == _last.length + 1 && selection.isValid;

    if (insertedOne && caret > 0 && caret <= text.length) {
      final inserted = text[caret - 1];

      // 回车自动缩进，并在 { [ ( 后额外缩进两个空格
      if (inserted == '\n') {
        final before = text.substring(0, caret - 1);
        final lineStart = before.lastIndexOf('\n') + 1;
        final line = before.substring(lineStart);
        final indent = RegExp(r'^[ \t]*').firstMatch(line)?.group(0) ?? '';
        final trimmed = line.trimRight();
        final extra = (trimmed.endsWith('{') || trimmed.endsWith('['))
            ? '  '
            : '';
        if (indent.isNotEmpty || extra.isNotEmpty) {
          _insert('$indent$extra', caret);
          return;
        }
      }

      // 括号自动配对
      const pairs = {'(': ')', '[': ']', '{': '}'};
      final closing = pairs[inserted];
      if (closing != null) {
        final next = caret < text.length ? text[caret] : '';
        if (next.trim().isEmpty) {
          _insert(closing, caret);
          return;
        }
      }
      // 已存在对应右括号时直接跳过
      if (inserted == ')' || inserted == ']' || inserted == '}') {
        if (caret < text.length && text[caret] == inserted) {
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: caret + 1),
          );
          _last = text;
          widget.onChanged(text);
          return;
        }
      }
    }

    _last = text;
    widget.onChanged(text);
  }

  void _insert(String value, int caret) {
    final text = _controller.text;
    if (value.isEmpty) return;
    final next = '${text.substring(0, caret)}$value${text.substring(caret)}';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret + value.length),
    );
    _last = next;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(_controller.text).length + 1;
    final lineHeight = 11.5 * 1.55;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: AstraColors.inset,
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(0, 10 - _offset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(lineCount, (index) {
                      return Container(
                        height: lineHeight,
                        alignment: Alignment.centerRight,
                        padding: EdgeInsets.only(right: 8),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.55,
                            color: AstraColors.faint.withValues(alpha: 0.75),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          VerticalDivider(width: 1, color: AstraColors.line),
          Expanded(
            child: TextField(
              controller: _controller,
              scrollController: _scroll,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: _textStyle,
              strutStyle: const StrutStyle(fontSize: 11.5, height: 1.55),
              decoration: astraInput(
                hint: widget.hint,
                contentPadding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              ),
              onChanged: _handleChanged,
            ),
          ),
        ],
      ),
    );
  }
}
