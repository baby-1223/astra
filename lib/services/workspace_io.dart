import 'package:flutter/material.dart';

import '../state.dart';
import '../ui/dialogs.dart';
import 'file_io.dart';

/// Shared import action used by the top bar and the application menu.
Future<void> importWorkspaceData(BuildContext context, AppState state) async {
  try {
    final picked = await pickImportFile();
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

/// Shared export action used by the top bar and the application menu.
Future<void> exportWorkspaceData(BuildContext context, AppState state) async {
  final format = await showExportDialog(context);
  if (format == null || !context.mounted) return;
  try {
    final stamp = DateTime.now();
    final suffix =
        '${stamp.year}'
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
