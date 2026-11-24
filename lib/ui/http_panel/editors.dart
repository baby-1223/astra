part of '../http_panel.dart';

/* 编辑器与选择器组件 */

class _CookieTag extends StatelessWidget {
  final String label;
  final Color color;

  _CookieTag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: 5),
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: monoStyle(size: 9, color: color)),
    );
  }
}

/* ------------------------------------------------------------------ */
/* 方法选择器                                                          */
/* ------------------------------------------------------------------ */

class _MethodSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  _MethodSelector({required this.value, required this.onChanged});

  static const List<String> methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
  ];

  @override
  Widget build(BuildContext context) {
    final current = methods.contains(value) ? value : 'GET';
    return PopupMenuButton<String>(
      tooltip: 'Request method',
      initialValue: current,
      position: PopupMenuPosition.under,
      color: AstraColors.surface2,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: 100, maxWidth: 160),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final method in methods)
          PopupMenuItem<String>(
            value: method,
            height: 34,
            child: Text(
              method,
              style: monoStyle(
                size: 13,
                color: methodColor(method),
                weight: FontWeight.w700,
              ),
            ),
          ),
      ],
      child: Container(
        width: 100,
        height: 32,
        padding: EdgeInsets.only(left: 9, right: 6),
        decoration: BoxDecoration(
          color: AstraColors.inset,
          border: Border.all(color: AstraColors.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: monoStyle(
                  size: 13,
                  color: methodColor(current),
                  weight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 15, color: AstraColors.faint),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* multipart 编辑器                                                    */
/* ------------------------------------------------------------------ */

class _FormDataEditor extends StatelessWidget {
  final List<FormRow> rows;
  final VoidCallback onChanged;

  _FormDataEditor({required this.rows, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(rows.length, (index) {
          final row = rows[index];
          return _FormDataRow(
            key: ObjectKey(row),
            row: row,
            onChanged: onChanged,
            onRemove: () {
              rows.removeAt(index);
              onChanged();
            },
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              rows.add(FormRow());
              onChanged();
            },
            style: TextButton.styleFrom(
              foregroundColor: AstraColors.muted,
              textStyle: TextStyle(fontSize: 11.5),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: Icon(Icons.add, size: 14),
            label: Text('Add field'),
          ),
        ),
      ],
    );
  }
}

class _FormDataRow extends StatefulWidget {
  final FormRow row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  _FormDataRow({
    super.key,
    required this.row,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_FormDataRow> createState() => _FormDataRowState();
}

class _FormDataRowState extends State<_FormDataRow> {
  late final TextEditingController _key = TextEditingController(text: widget.row.k);
  late final TextEditingController _value = TextEditingController(text: widget.row.v);

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickUploadFile();
    if (picked == null) return;
    setState(() => widget.row.file = picked);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final isFile = row.type == 'file';
    return Padding(
      padding: EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Transform.scale(
              scale: 0.78,
              child: Checkbox(
                value: row.on,
                activeColor: AstraColors.accent,
                side: BorderSide(color: AstraColors.lineStrong),
                onChanged: (value) {
                  setState(() => row.on = value ?? false);
                  widget.onChanged();
                },
              ),
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _key,
              style: monoStyle(size: 12),
              decoration: astraInput(
                hint: 'Field name',
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onChanged: (value) {
                row.k = value;
                widget.onChanged();
              },
            ),
          ),
          SizedBox(width: 7),
          GestureDetector(
            onTap: () {
              setState(() => row.type = isFile ? 'text' : 'file');
              widget.onChanged();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 10),
              decoration: BoxDecoration(
                color: isFile ? AstraColors.accent2Soft : AstraColors.overlay,
                border: Border.all(color: isFile ? AstraColors.accent2Soft : AstraColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isFile ? 'File' : 'Text',
                style: TextStyle(
                  fontSize: 11,
                  color: isFile ? AstraColors.codeKeyword : AstraColors.muted,
                ),
              ),
            ),
          ),
          SizedBox(width: 7),
          Expanded(
            flex: 8,
            child: isFile
                ? _fileBox(row)
                : TextField(
                    controller: _value,
                    style: monoStyle(size: 12),
                    decoration: astraInput(
                      hint: 'Field value (supports {{variables}})',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (value) {
                      row.v = value;
                      widget.onChanged();
                    },
                  ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              tooltip: 'Delete row',
              onPressed: widget.onRemove,
              icon: Icon(Icons.close, size: 15),
              color: AstraColors.faint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileBox(FormRow row) {
    final file = row.file;
    final ready = file != null && file.usable;
    return InkWell(
      onTap: _pick,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AstraColors.inset,
          border: Border.all(color: ready ? AstraColors.accent2Soft : AstraColors.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(
              ready ? Icons.insert_drive_file_outlined : Icons.upload_file_outlined,
              size: 15,
              color: ready ? AstraColors.codeKeyword : AstraColors.faint,
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                file == null
                    ? 'Choose file'
                    : file.usable
                        ? '${file.name} · ${formatBytes(file.size)}'
                        : '${file.name} (needs re-selection)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: ready ? AstraColors.text : AstraColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
