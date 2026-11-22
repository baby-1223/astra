import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'bound_text_field.dart';
import 'theme.dart';
import 'widgets.dart';

class WsView extends StatefulWidget {
  final AppState state;

  WsView({super.key, required this.state});

  @override
  State<WsView> createState() => _WsViewState();
}

class _WsViewState extends State<WsView> {
  String _tab = 'headers';
  final TextEditingController _messageController = TextEditingController();

  AppState get state => widget.state;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _messageController.text;
    if (text.isEmpty) return;
    state.sendWs(text);
    _messageController.clear();
  }

  void _resend(String text) {
    if (state.wsState != 'open') {
      state.showToast('Connect first');
      return;
    }
    state.sendWs(text);
  }

  void _applyTemplate(String text) {
    _messageController.text = text;
    _messageController.selection =
        TextSelection.collapsed(offset: _messageController.text.length);
  }

  String? get _lastOutgoing {
    for (final message in state.wsLog.reversed) {
      if (message.outgoing) return message.text;
    }
    return null;
  }

  static const List<(String, String)> _templates = [
    ('Ping', '{"type":"ping"}'),
    ('Subscribe', '{"type":"subscribe","payload":{"query":"subscription { messages }"}}'),
    ('Unsubscribe', '{"type":"unsubscribe","id":"1"}'),
    ('JSON-RPC request', '{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}'),
    ('Plain text', 'hello'),
  ];

  @override
  Widget build(BuildContext context) {
    final connected = state.wsState == 'open';
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(flex: 3, child: _connectionCard()),
          SizedBox(height: 14),
          Expanded(flex: 4, child: _logCard(connected)),
        ],
      ),
    );
  }

  Widget _connectionCard() {
    final ws = state.ws;
    return AstraCard(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 14, color: AstraColors.faint),
              SizedBox(width: 8),
              SizedBox(
                width: 340,
                height: 40,
                child: KeyedSubtree(
                  key: ValueKey('active-name'),
                  child: BoundTextField(
                    value: state.activeName,
                    hint: 'Connection name',
                    fontSize: 13,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    onChanged: state.renameActive,
                    onSubmitted: (_) => state.saveActive(),
                  ),
                ),
              ),
              Spacer(),
              Text(
                '⌘ / Ctrl + S to save',
                style: TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Text('WebSocket Connection',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              SizedBox(width: 10),
              _statusChip(),
              Spacer(),
              if (state.wsLog.isNotEmpty)
                TextButton.icon(
                  onPressed: state.clearWsLog,
                  style: TextButton.styleFrom(
                    foregroundColor: AstraColors.faint,
                    textStyle: TextStyle(fontSize: 11),
                  ),
                  icon: Icon(Icons.delete_outline, size: 13),
                  label: Text('Clear log'),
                ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: BoundTextField(
                    value: ws.url,
                    hint: 'ws://localhost:8080/ws or wss://example.com/socket',
                    fontSize: 13,
                    contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    onChanged: (value) {
                      ws.url = value;
                      state.touch();
                    },
                  ),
                ),
              ),
              SizedBox(width: 9),
              GradientButton(
                label: state.wsState == 'idle' ? 'Connect' : 'Disconnect',
                danger: state.wsState != 'idle',
                icon: state.wsState == 'idle'
                    ? Icons.power_settings_new
                    : Icons.link_off_rounded,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                onPressed: state.wsState == 'connecting'
                    ? null
                    : state.wsState == 'idle'
                        ? state.connectWs
                        : state.disconnectWs,
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: AstraTabs(
                  compact: true,
                  selected: _tab,
                  onSelect: (id) => setState(() => _tab = id),
                  items: [
                    AstraTabItem('headers', 'Headers',
                        count: ws.headers.where((e) => e.on && e.k.isNotEmpty).length),
                    AstraTabItem('options', 'Settings'),
                  ],
                ),
              ),
              Spacer(),
              if (state.wsError != null)
                Flexible(
                  child: Text(
                    state.wsError!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: AstraColors.err),
                  ),
                ),
            ],
          ),
          Divider(height: 1, color: AstraColors.line),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: 12),
              child: _tab == 'headers'
                  ? KVEditor(
                      rows: ws.headers,
                      keyHint: 'Header name',
                      valueHint: 'Header value (supports {{variables}})',
                      onChanged: state.touch,
                      onAdd: () => setState(() => ws.headers.add(KV())),
                      onRemove: (index) => setState(() => ws.headers.removeAt(index)),
                    )
                  : _settings(ws),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settings(WsConfig ws) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 120,
              child: Text('Subprotocols (comma-separated)', style: TextStyle(fontSize: 11.5, color: AstraColors.muted)),
            ),
            Expanded(
              child: BoundTextField(
                value: ws.subprotocol,
                hint: 'graphql-ws, json',
                onChanged: (value) {
                  ws.subprotocol = value;
                  state.touch();
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verify TLS certificate', style: TextStyle(fontSize: 12.5)),
                  SizedBox(height: 2),
                  Text('Turn off to connect to test servers using self-signed certificates',
                      style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
                ],
              ),
            ),
            Switch(
              value: ws.verify,
              activeThumbColor: AstraColors.accent,
              onChanged: (value) {
                setState(() => ws.verify = value);
                state.touch();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusChip() {
    late final Color color;
    late final String label;
    switch (state.wsState) {
      case 'open':
        color = AstraColors.ok;
        label = 'Connected';
      case 'connecting':
        color = AstraColors.warn;
        label = 'Connecting';
      default:
        color = AstraColors.faint;
        label = 'Disconnected';
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _logCard(bool connected) {
    return AstraCard(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text('Messages',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              SizedBox(width: 12),
              Text('↑ ${state.wsSent}', style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
              SizedBox(width: 10),
              Text('↓ ${state.wsReceived}', style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
              Spacer(),
              if (state.wsLog.isNotEmpty)
                CopyButton(
                  text: state.wsLog
                      .map((m) => '[${_time(m.time)}] ${m.outgoing ? '↑' : m.system ? '·' : '↓'} ${m.text}')
                      .join('\n'),
                  tooltip: 'Copy all messages',
                ),
            ],
          ),
          SizedBox(height: 8),
          Divider(height: 1, color: AstraColors.line),
          Expanded(
            child: state.wsLog.isEmpty
                ? EmptyHint(
                    icon: Icons.electrical_services_rounded,
                    title: 'No messages yet',
                    subtitle: 'Sent and received messages will appear here once connected',
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(top: 10),
                    itemCount: state.wsLog.length,
                    itemBuilder: (context, index) => _LogRow(message: state.wsLog[index]),
                  ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _messageController,
                    enabled: connected,
                    style: monoStyle(size: 12),
                    decoration: astraInput(
                      hint: connected ? 'Type a message, press Enter to send' : 'Connect first',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Message templates',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                color: AstraColors.surface2,
                onSelected: _applyTemplate,
                itemBuilder: (context) => _templates
                    .map((item) => PopupMenuItem<String>(
                          value: item.$2,
                          height: 38,
                          child: Text(item.$1, style: TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                child: Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.auto_awesome_motion_outlined,
                      size: 16, color: AstraColors.muted),
                ),
              ),
              if (_lastOutgoing != null)
                Tooltip(
                  message: 'Resend last message',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => _resend(_lastOutgoing!),
                    child: Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(Icons.replay_rounded, size: 16, color: AstraColors.muted),
                    ),
                  ),
                ),
              SizedBox(width: 5),
              GradientButton(
                label: 'Send',
                icon: Icons.arrow_upward_rounded,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                onPressed: connected ? _send : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}

class _LogRow extends StatelessWidget {
  final WsMessage message;

  _LogRow({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.system) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_time()}  ${message.text}',
                style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
              ),
            ],
          ),
        ),
      );
    }
    final outgoing = message.outgoing;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: outgoing ? AstraColors.accent2Soft : AstraColors.accentSoft,
          border: Border.all(
            color: outgoing ? AstraColors.accent2Soft : AstraColors.accentSoft,
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(outgoing ? 10 : 3),
            bottomRight: Radius.circular(outgoing ? 3 : 10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: monoStyle(size: 11.5, height: 1.55),
            ),
            SizedBox(height: 4),
            Text(
              _time(),
              style: TextStyle(fontSize: 9, color: AstraColors.faint),
            ),
          ],
        ),
      ),
    );
  }

  String _time() =>
      '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}:${message.time.second.toString().padLeft(2, '0')}';
}
