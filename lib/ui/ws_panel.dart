import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import 'bound_text_field.dart';
import 'theme.dart';
import 'widgets.dart';

class WsView extends StatefulWidget {
  final AppState state;

  const WsView({super.key, required this.state});

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
      state.showToast('请先建立连接');
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
    ('心跳 Ping', '{"type":"ping"}'),
    ('订阅消息', '{"type":"subscribe","payload":{"query":"subscription { messages }"}}'),
    ('取消订阅', '{"type":"unsubscribe","id":"1"}'),
    ('JSON-RPC 请求', '{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}'),
    ('纯文本', 'hello'),
  ];

  @override
  Widget build(BuildContext context) {
    final connected = state.wsState == 'open';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(flex: 3, child: _connectionCard()),
          const SizedBox(height: 14),
          Expanded(flex: 4, child: _logCard(connected)),
        ],
      ),
    );
  }

  Widget _connectionCard() {
    final ws = state.ws;
    return AstraCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.edit_outlined, size: 14, color: AstraColors.faint),
              const SizedBox(width: 8),
              SizedBox(
                width: 340,
                height: 40,
                child: KeyedSubtree(
                  key: const ValueKey('active-name'),
                  child: BoundTextField(
                    value: state.activeName,
                    hint: '连接名称',
                    fontSize: 13,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    onChanged: state.renameActive,
                    onSubmitted: (_) => state.saveActive(),
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                '⌘ / Ctrl + S 保存',
                style: TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('WebSocket 连接',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              _statusChip(),
              const Spacer(),
              if (state.wsLog.isNotEmpty)
                TextButton.icon(
                  onPressed: state.clearWsLog,
                  style: TextButton.styleFrom(
                    foregroundColor: AstraColors.faint,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 13),
                  label: const Text('清空记录'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: BoundTextField(
                    value: ws.url,
                    hint: 'ws://localhost:8080/ws 或 wss://example.com/socket',
                    fontSize: 13,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    onChanged: (value) {
                      ws.url = value;
                      state.touch();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 9),
              GradientButton(
                label: state.wsState == 'idle' ? '连接' : '断开',
                danger: state.wsState != 'idle',
                icon: state.wsState == 'idle'
                    ? Icons.power_settings_new
                    : Icons.link_off_rounded,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                onPressed: state.wsState == 'connecting'
                    ? null
                    : state.wsState == 'idle'
                        ? state.connectWs
                        : state.disconnectWs,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: AstraTabs(
                  compact: true,
                  selected: _tab,
                  onSelect: (id) => setState(() => _tab = id),
                  items: [
                    AstraTabItem('headers', '请求头',
                        count: ws.headers.where((e) => e.on && e.k.isNotEmpty).length),
                    const AstraTabItem('options', '设置'),
                  ],
                ),
              ),
              const Spacer(),
              if (state.wsError != null)
                Flexible(
                  child: Text(
                    state.wsError!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AstraColors.err),
                  ),
                ),
            ],
          ),
          const Divider(height: 1, color: AstraColors.line),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12),
              child: _tab == 'headers'
                  ? KVEditor(
                      rows: ws.headers,
                      keyHint: 'Header 名称',
                      valueHint: 'Header 值（支持 {{变量}}）',
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
            const SizedBox(
              width: 120,
              child: Text('子协议（逗号分隔）', style: TextStyle(fontSize: 11.5, color: AstraColors.muted)),
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
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('校验 TLS 证书', style: TextStyle(fontSize: 12.5)),
                  SizedBox(height: 2),
                  Text('关闭后可连接使用自签名证书的测试服务',
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
        label = '已连接';
      case 'connecting':
        color = AstraColors.warn;
        label = '连接中';
      default:
        color = AstraColors.faint;
        label = '未连接';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _logCard(bool connected) {
    return AstraCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              const Text('消息记录',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Text('↑ ${state.wsSent}', style: const TextStyle(fontSize: 10.5, color: AstraColors.faint)),
              const SizedBox(width: 10),
              Text('↓ ${state.wsReceived}', style: const TextStyle(fontSize: 10.5, color: AstraColors.faint)),
              const Spacer(),
              if (state.wsLog.isNotEmpty)
                CopyButton(
                  text: state.wsLog
                      .map((m) => '[${_time(m.time)}] ${m.outgoing ? '↑' : m.system ? '·' : '↓'} ${m.text}')
                      .join('\n'),
                  tooltip: '复制全部消息',
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AstraColors.line),
          Expanded(
            child: state.wsLog.isEmpty
                ? const EmptyHint(
                    icon: Icons.electrical_services_rounded,
                    title: '暂无消息',
                    subtitle: '连接成功后，发送与接收的消息会显示在这里',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 10),
                    itemCount: state.wsLog.length,
                    itemBuilder: (context, index) => _LogRow(message: state.wsLog[index]),
                  ),
          ),
          const SizedBox(height: 8),
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
                      hint: connected ? '输入消息内容，按 Enter 发送' : '请先建立连接',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: '消息模板库',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                color: AstraColors.surface2,
                onSelected: _applyTemplate,
                itemBuilder: (context) => _templates
                    .map((item) => PopupMenuItem<String>(
                          value: item.$2,
                          height: 38,
                          child: Text(item.$1, style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.auto_awesome_motion_outlined,
                      size: 16, color: AstraColors.muted),
                ),
              ),
              if (_lastOutgoing != null)
                Tooltip(
                  message: '重发上一条消息',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => _resend(_lastOutgoing!),
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(Icons.replay_rounded, size: 16, color: AstraColors.muted),
                    ),
                  ),
                ),
              const SizedBox(width: 5),
              GradientButton(
                label: '发送',
                icon: Icons.arrow_upward_rounded,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  const _LogRow({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_time()}  ${message.text}',
                style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 620),
        decoration: BoxDecoration(
          color: outgoing ? const Color(0x1F8B5CF6) : const Color(0x1422D3EE),
          border: Border.all(
            color: outgoing ? const Color(0x338B5CF6) : const Color(0x2E22D3EE),
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(10),
            topRight: const Radius.circular(10),
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
            const SizedBox(height: 4),
            Text(
              _time(),
              style: const TextStyle(fontSize: 9, color: AstraColors.faint),
            ),
          ],
        ),
      ),
    );
  }

  String _time() =>
      '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}:${message.time.second.toString().padLeft(2, '0')}';
}
