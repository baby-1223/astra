import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state.dart';
import 'ui/advanced_dialogs.dart';
import 'ui/http_panel.dart';
import 'ui/request_tabs.dart';
import 'ui/runner_dialog.dart';
import 'ui/sidebar.dart';
import 'ui/theme.dart';
import 'ui/top_bar.dart';
import 'ui/ws_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AstraApp());
}

class AstraApp extends StatefulWidget {
  final AppState? state;

  const AstraApp({super.key, this.state});

  @override
  State<AstraApp> createState() => _AstraAppState();
}

class _AstraAppState extends State<AstraApp> {
  late final AppState state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    if (widget.state == null) state.load();
  }

  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Astra',
      debugShowCheckedModeBanner: false,
      theme: buildAstraTheme(),
      home: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): state.saveActive,
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  state.saveActive,
              const SingleActivator(LogicalKeyboardKey.keyT, meta: true): state.newRequest,
              const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                  state.newRequest,
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
                  state.closeTab(state.activeTabId),
              const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
                  state.closeTab(state.activeTabId),
              const SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true): () =>
                  showVariablesDialog(context, state),
              const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
                  () => showVariablesDialog(context, state),
              const SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true): () =>
                  showRunnerDialog(context, state),
              const SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true):
                  () => showRunnerDialog(context, state),
              const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                  showShortcutsDialog(context),
              const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                  showShortcutsDialog(context),
              const SingleActivator(LogicalKeyboardKey.slash, meta: true): () =>
                  showShortcutsDialog(context),
              const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
                  showShortcutsDialog(context),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: AstraColors.bg,
                body: Stack(
                  children: [
                    Column(
                      children: [
                        TopBar(state: state),
                        Expanded(
                          child: Row(
                            children: [
                              Sidebar(state: state),
                              Expanded(
                                child: Column(
                                  children: [
                                    RequestTabBar(state: state),
                                    Expanded(
                                      child: state.mode == 'ws'
                                          ? WsView(state: state)
                                          : HttpView(state: state),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (state.toast != null)
                      Positioned(
                        bottom: 26,
                        left: 0,
                        right: 0,
                        child: Center(child: _Toast(message: state.toast!)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String message;

  const _Toast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xF2121726),
        border: Border.all(color: const Color(0x4038BDF8)),
        borderRadius: BorderRadius.circular(11),
        boxShadow: const [
          BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: AstraColors.accent),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AstraColors.text, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
