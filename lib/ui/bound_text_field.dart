import 'package:flutter/material.dart';

import 'theme.dart';

/// 受控文本框：外部值变化（如切换请求）时同步，用户输入时只回调不重建。
class BoundTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int minLines;
  final int maxLines;
  final double fontSize;
  final double lineHeight;
  final EdgeInsetsGeometry contentPadding;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;
  final bool codeHighlight;

  /// 可用的变量名；非空时输入 `{{` 会弹出补全列表。
  final List<String> varNames;

  BoundTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.fontSize = 12.5,
    this.lineHeight = 1.4,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
    this.autofocus = false,
    this.onSubmitted,
    this.obscure = false,
    this.codeHighlight = false,
    this.varNames = const [],
  });

  @override
  State<BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<BoundTextField> {
  late final TextEditingController _controller;
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlay = OverlayPortalController();
  final FocusNode _focus = FocusNode();
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _controller = widget.codeHighlight
        ? JsHighlightController(text: widget.value)
        : TextEditingController(text: widget.value);
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _overlay.hide();
        if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      }
    });
  }

  @override
  void didUpdateWidget(BoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    widget.onChanged(value);
    _updateVarSuggestions();
  }

  void _updateVarSuggestions() {
    if (widget.varNames.isEmpty) return;
    final caret = _controller.selection.baseOffset >= 0
        ? _controller.selection.baseOffset
        : _controller.text.length;
    final before = _controller.text.substring(0, caret);
    final match = RegExp(r'\{\{([\w.-]*)$').firstMatch(before);
    if (match == null) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      _overlay.hide();
      return;
    }
    final query = match.group(1)!.toLowerCase();
    final items = widget.varNames
        .where((name) =>
            name.toLowerCase().contains(query) || name.toLowerCase().startsWith(query))
        .take(8)
        .toList();
    setState(() => _suggestions = items);
    if (items.isEmpty) {
      _overlay.hide();
    } else {
      _overlay.show();
    }
  }

  void _pickVariable(String name) {
    final caret = _controller.selection.baseOffset >= 0
        ? _controller.selection.baseOffset
        : _controller.text.length;
    final before = _controller.text.substring(0, caret);
    final start = before.lastIndexOf('{{');
    if (start < 0) return;
    final next =
        '${_controller.text.substring(0, start)}{{$name}}${_controller.text.substring(caret)}';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + name.length + 4),
    );
    widget.onChanged(next);
    _overlay.hide();
    setState(() => _suggestions = []);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      obscureText: widget.obscure,
      style: monoStyle(
        size: widget.fontSize,
        height: widget.lineHeight,
      ),
      decoration: astraInput(hint: widget.hint, contentPadding: widget.contentPadding),
      onChanged: _handleChanged,
      onSubmitted: widget.onSubmitted,
    );
    if (widget.varNames.isEmpty) return field;
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) {
          if (_suggestions.isEmpty) return SizedBox.shrink();
          return CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: Offset(0, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 220,
                  constraints: BoxConstraints(maxHeight: 190),
                  decoration: BoxDecoration(
                    color: AstraColors.surface2,
                    border: Border.all(color: AstraColors.lineStrong),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final name = _suggestions[index];
                      return InkWell(
                        onTap: () => _pickVariable(name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: Row(
                            children: [
                              Icon(Icons.data_object, size: 12, color: AstraColors.accent),
                              SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoStyle(size: 11.5),
                                ),
                              ),
                              Text(
                                '{{ }}',
                                style: TextStyle(fontSize: 9, color: AstraColors.faint),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
        child: field,
      ),
    );
  }
}

/// JavaScript 轻量语法高亮控制器：注释、字符串、数字、关键字与 pm/console。
class JsHighlightController extends TextEditingController {
  JsHighlightController({super.text});

  static final RegExp _pattern = RegExp(
    r'''(\/\/[^\n]*|\/\*[\s\S]*?\*\/)'''
    r'''|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)'''
    r'''|(\b\d+(?:\.\d+)?\b)'''
    r'''|(\b(?:if|else|for|while|do|return|function|var|let|const|new|try|catch|finally|throw|typeof|instanceof|true|false|null|undefined|this|async|await|of|in|switch|case|break|continue)\b)'''
    r'''|(\b(?:pm|console|JSON|Date|Math|Object|Array|String|Number)\b)''',
    multiLine: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? TextStyle();
    final spans = <TextSpan>[];
    var start = 0;
    for (final match in _pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: base));
      }
      late final Color color;
      if (match.group(1) != null) {
        color = AstraColors.faint;
      } else if (match.group(2) != null) {
        color = AstraColors.codeString;
      } else if (match.group(3) != null) {
        color = AstraColors.codeNumber;
      } else if (match.group(4) != null) {
        color = AstraColors.codeKeyword;
      } else {
        color = AstraColors.accent;
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: base.copyWith(color: color),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    return TextSpan(children: spans, style: base);
  }
}
