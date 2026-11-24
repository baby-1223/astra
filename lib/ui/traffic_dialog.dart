import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/capture_proxy.dart';
import '../state.dart';
import 'bound_text_field.dart';
import 'theme.dart';
import 'widgets.dart';

/// 打开 Mock Server / 抓包代理工作台。
Future<void> showTrafficStudioDialog(
  BuildContext context,
  AppState state, {
  String initialTab = 'mock',
  MockRoute? draftRoute,
}) {
  if (draftRoute != null) {
    state.addMockRoute(draftRoute);
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => _TrafficStudio(
      state: state,
      initialTab: initialTab,
      initialRouteId: draftRoute?.id,
    ),
  );
}

class _TrafficStudio extends StatefulWidget {
  final AppState state;
  final String initialTab;
  final String? initialRouteId;

  _TrafficStudio({required this.state, required this.initialTab, this.initialRouteId});

  @override
  State<_TrafficStudio> createState() => _TrafficStudioState();
}

class _TrafficStudioState extends State<_TrafficStudio> {
  late String _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) => AstraDialogShell(
        title: 'Traffic Studio',
        subtitle: 'Mock undocumented endpoints with generated data, or capture real traffic through a local proxy.',
        width: 1000,
        child: SizedBox(
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabBar(
                value: _tab,
                options: const [
                  ('mock', 'Mock Server', Icons.dns_outlined),
                  ('capture', 'Traffic Capture', Icons.radar),
                ],
                onChanged: (value) => setState(() => _tab = value),
              ),
              SizedBox(height: 14),
              Expanded(
                child: _tab == 'mock'
                    ? _MockTab(
                        state: widget.state,
                        initialRouteId: widget.initialRouteId,
                      )
                    : _CaptureTab(state: widget.state),
              ),
            ],
          ),
        ),
        actions: [
          GhostButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final String value;
  final List<(String, String, IconData)> options;
  final ValueChanged<String> onChanged;

  _TabBar({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in options)
          Padding(
            padding: EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(option.$1),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: value == option.$1 ? AstraColors.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: value == option.$1 ? AstraColors.accentBorder : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      option.$3,
                      size: 14,
                      color: value == option.$1 ? AstraColors.accent : AstraColors.muted,
                    ),
                    SizedBox(width: 7),
                    Text(
                      option.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: value == option.$1 ? AstraColors.text : AstraColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ------------------------------------------------------------------ */
/* Mock Server                                                         */
/* ------------------------------------------------------------------ */

class _MockTab extends StatefulWidget {
  final AppState state;
  final String? initialRouteId;

  _MockTab({required this.state, this.initialRouteId});

  @override
  State<_MockTab> createState() => _MockTabState();
}

class _MockTabState extends State<_MockTab> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialRouteId ??
        (widget.state.mockServer.routes.isNotEmpty ? widget.state.mockServer.routes.first.id : null);
  }

  MockRoute? get _selected {
    for (final route in widget.state.mockServer.routes) {
      if (route.id == _selectedId) return route;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final routes = state.mockServer.routes;
    if (_selectedId == null && routes.isNotEmpty) {
      _selectedId = routes.first.id;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 96,
              child: BoundTextField(
                key: const ValueKey('mock-port'),
                value: '${state.mockServer.port}',
                hint: 'Port',
                fontSize: 11.5,
                onChanged: (value) {
                  final port = int.tryParse(value.trim());
                  if (port != null) state.setMockPort(port);
                },
              ),
            ),
            SizedBox(width: 8),
            GradientButton(
              label: state.mockServerRunning ? 'Stop server' : 'Start server',
              icon: state.mockServerRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
              danger: state.mockServerRunning,
              onPressed: () => state.mockServerRunning
                  ? state.stopMockServer()
                  : state.startMockServer(),
            ),
            SizedBox(width: 10),
            if (state.mockServerRunning)
              _StatusPill(
                color: AstraColors.ok,
                text: 'Running · http://127.0.0.1:${state.mockServerService.port}',
              )
            else
              _StatusPill(color: AstraColors.faint, text: 'Stopped'),
            if (state.mockServerRunning) ...[
              SizedBox(width: 6),
              _IconTip(
                icon: Icons.copy_rounded,
                tooltip: 'Copy base URL',
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: 'http://127.0.0.1:${state.mockServerService.port}'),
                  );
                  state.showToast('Base URL copied');
                },
              ),
            ],
            Spacer(),
            GhostButton(
              label: 'From request…',
              icon: Icons.download_outlined,
              onPressed: () => _pickRequest(context),
            ),
            SizedBox(width: 8),
            GhostButton(
              label: 'New route',
              icon: Icons.add,
              onPressed: () {
                final route = MockRoute(path: '/new-endpoint', body: kSampleMockBody);
                state.addMockRoute(route);
                setState(() => _selectedId = route.id);
              },
            ),
          ],
        ),
        if (state.mockServerError != null) ...[
          SizedBox(height: 8),
          Text(
            state.mockServerError!,
            style: TextStyle(fontSize: 11, color: AstraColors.err),
          ),
        ],
        SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 262,
                decoration: BoxDecoration(
                  color: AstraColors.inset,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AstraColors.line),
                ),
                child: routes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'No mock routes yet.\nCreate one, or import a saved request with its response example.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AstraColors.muted, height: 1.6),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(6),
                        itemCount: routes.length,
                        separatorBuilder: (_, __) => SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final route = routes[index];
                          final selected = route.id == _selectedId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => setState(() => _selectedId = route.id),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected ? AstraColors.accentSoft : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: selected ? AstraColors.accentBorder : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: route.enabled,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (value) =>
                                        state.toggleMockRoute(route.id, value ?? false),
                                  ),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          route.name.isEmpty ? 'Untitled route' : route.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.8,
                                            fontWeight: FontWeight.w600,
                                            color: route.enabled ? AstraColors.text : AstraColors.muted,
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                        Text(
                                          '${route.method} ${route.path}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: monoStyle(size: 10, color: AstraColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _IconTip(
                                    icon: Icons.delete_outline,
                                    tooltip: 'Delete route',
                                    onTap: () {
                                      if (route.id == _selectedId) {
                                        setState(() => _selectedId = null);
                                      }
                                      state.deleteMockRoute(route.id);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _selected == null
                    ? _EmptyPanel(
                        icon: Icons.dns_outlined,
                        text: 'Select a route to edit its response',
                      )
                    : _RouteEditor(
                        key: ValueKey(_selected!.id),
                        state: state,
                        route: _selected!,
                      ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        _HitLog(state: state),
      ],
    );
  }

  Future<void> _pickRequest(BuildContext context) async {
    final entries = widget.state.collections.where((item) => item.mode == 'http').toList();
    if (entries.isEmpty) {
      widget.state.showToast('No saved HTTP requests yet');
      return;
    }
    final picked = await showDialog<CollectionEntry>(
      context: context,
      builder: (ctx) => AstraDialogShell(
        title: 'Create mock from request',
        subtitle: 'Method, path and the first saved response example are copied into a new route.',
        width: 460,
        child: SizedBox(
          height: 320,
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
                title: Text(entry.name, style: TextStyle(fontSize: 12.5)),
                subtitle: Text(
                  '${entry.request?.method ?? 'GET'} ${entry.request?.url ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 10, color: AstraColors.muted),
                ),
                onTap: () => Navigator.of(ctx).pop(entry),
              );
            },
          ),
        ),
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
    if (picked == null) return;
    final route = widget.state.mockRouteForEntry(picked);
    widget.state.addMockRoute(route);
    setState(() => _selectedId = route.id);
  }
}

class _RouteEditor extends StatelessWidget {
  final AppState state;
  final MockRoute route;

  _RouteEditor({super.key, required this.state, required this.route});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 4,
              child: _LabeledField(
                label: 'Route name',
                child: BoundTextField(
                  key: ValueKey('mock-name-${route.id}'),
                  value: route.name,
                  hint: 'Users list',
                  onChanged: (value) {
                    route.name = value;
                    state.updateMockRoute(route);
                  },
                ),
              ),
            ),
            SizedBox(width: 8),
            _LabeledField(
              label: 'Status',
              width: 76,
              child: BoundTextField(
                key: ValueKey('mock-status-${route.id}'),
                value: '${route.status}',
                hint: '200',
                onChanged: (value) {
                  final status = int.tryParse(value.trim());
                  if (status == null) return;
                  route.status = status;
                  state.updateMockRoute(route);
                },
              ),
            ),
            SizedBox(width: 8),
            _LabeledField(
              label: 'Delay ms',
              width: 90,
              child: BoundTextField(
                key: ValueKey('mock-delay-${route.id}'),
                value: '${route.delayMs}',
                hint: '0',
                onChanged: (value) {
                  route.delayMs = int.tryParse(value.trim()) ?? 0;
                  state.updateMockRoute(route);
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            _LabeledField(
              label: 'Method',
              width: 104,
              child: _MethodDropdown(
                value: route.method,
                onChanged: (value) {
                  route.method = value;
                  state.updateMockRoute(route);
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _LabeledField(
                label: 'Path pattern — supports :params and trailing *',
                child: BoundTextField(
                  key: ValueKey('mock-path-${route.id}'),
                  value: route.path,
                  hint: '/users/:id',
                  onChanged: (value) {
                    route.path = value;
                    state.updateMockRoute(route);
                  },
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        SectionLabel('Response headers'),
        SizedBox(
          height: 88,
          child: SingleChildScrollView(
            child: KVEditor(
              rows: route.headers,
              keyHint: 'Header',
              valueHint: 'Value',
              onChanged: () => state.updateMockRoute(route),
              onAdd: () {
                route.headers.add(KV());
                state.updateMockRoute(route);
              },
              onRemove: (index) {
                route.headers.removeAt(index);
                if (route.headers.isEmpty) route.headers.add(KV());
                state.updateMockRoute(route);
              },
            ),
          ),
        ),
        SizedBox(height: 6),
        Row(
          children: [
            SectionLabel('Response body'),
            Spacer(),
            Text(
              'Templates: {{param}} · {{query.x}} · {{header.x}} · {{body.x}} · {{\$guid}} · {{\$randomInt}} · {{\$randomFullName}} · {{\$randomEmail}} · {{\$isoTimestamp}}',
              style: TextStyle(fontSize: 9.5, color: AstraColors.faint),
            ),
          ],
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AstraColors.inset,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AstraColors.line),
            ),
            padding: EdgeInsets.all(4),
            child: SingleChildScrollView(
              child: BoundTextField(
                key: ValueKey('mock-body-${route.id}'),
                value: route.body,
                hint: '{\n  "message": "Hello from Astra mock"\n}',
                minLines: 10,
                maxLines: 24,
                fontSize: 11.5,
                lineHeight: 1.55,
                onChanged: (value) {
                  route.body = value;
                  state.updateMockRoute(route);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MethodDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  _MethodDropdown({required this.value, required this.onChanged});

  static const List<String> methods = [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
    'OPTIONS',
    'ANY',
  ];

  @override
  Widget build(BuildContext context) {
    final normalized = methods.contains(value) ? value : 'GET';
    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AstraColors.inset,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AstraColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: normalized,
          isExpanded: true,
          dropdownColor: AstraColors.surface2,
          style: monoStyle(size: 11.5, color: AstraColors.text),
          icon: Icon(Icons.expand_more, size: 16, color: AstraColors.muted),
          items: [
            for (final method in methods)
              DropdownMenuItem(
                value: method,
                child: Text(method, style: monoStyle(size: 11.5, color: AstraColors.text)),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  final double? width;

  _LabeledField({required this.label, required this.child, this.width});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontSize: 9.5, color: AstraColors.muted, letterSpacing: 0.4)),
        SizedBox(height: 5),
        child,
      ],
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

class _HitLog extends StatelessWidget {
  final AppState state;

  _HitLog({required this.state});

  @override
  Widget build(BuildContext context) {
    final hits = state.mockServerService.hits.take(3).toList();
    if (hits.isEmpty) {
      return Text(
        'Requests will appear here once the server is running.',
        style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
      );
    }
    return Row(
      children: [
        Text('Recent', style: TextStyle(fontSize: 10, color: AstraColors.muted)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            hits
                .map((hit) =>
                    '${_time(hit.ts)}  ${hit.method} ${hit.path} → ${hit.status} ${hit.matched ? hit.routeName : 'no match'}')
                .join('      '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(size: 9.5, color: AstraColors.muted),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------ */
/* Traffic capture                                                     */
/* ------------------------------------------------------------------ */

class _CaptureTab extends StatefulWidget {
  final AppState state;

  _CaptureTab({required this.state});

  @override
  State<_CaptureTab> createState() => _CaptureTabState();
}

class _CaptureTabState extends State<_CaptureTab> {
  late final TextEditingController _portController =
      TextEditingController(text: '${CaptureProxyService.defaultPort}');
  bool _mitm = true;
  bool _allowInsecure = true;
  String? _selectedId;

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  CaptureRecord? get _selected {
    for (final record in widget.state.captureProxy.records) {
      if (record.id == _selectedId) return record;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final proxy = state.captureProxy;
    final running = proxy.running;
    final ca = state.captureCertificateAuthority;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _portController,
                enabled: !running,
                style: monoStyle(size: 11.5, color: AstraColors.text),
                decoration: _decoration('Port'),
              ),
            ),
            SizedBox(width: 8),
            GradientButton(
              label: running ? 'Stop capture' : 'Start capture',
              icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              danger: running,
              onPressed: state.captureCaLoading
                  ? null
                  : () {
                      if (running) {
                        state.stopCaptureProxy();
                      } else {
                        final port = int.tryParse(_portController.text.trim()) ??
                            CaptureProxyService.defaultPort;
                        _portController.text = '$port';
                        state.startCaptureProxy(
                          port: port,
                          mitmHttps: _mitm,
                          allowInsecureUpstream: _allowInsecure,
                        );
                      }
                    },
            ),
            SizedBox(width: 10),
            _Check(
              label: 'Decrypt HTTPS',
              value: _mitm,
              enabled: !running,
              onChanged: (value) => setState(() => _mitm = value),
            ),
            SizedBox(width: 10),
            _Check(
              label: 'Allow insecure upstream',
              value: _allowInsecure,
              enabled: !running,
              onChanged: (value) => setState(() => _allowInsecure = value),
            ),
            Spacer(),
            if (ca != null) ...[
              _IconTip(
                icon: Icons.download_rounded,
                tooltip: 'Export CA certificate',
                onTap: () async {
                  final path = await ca.exportCaCertificate();
                  state.showToast('CA exported to $path');
                },
              ),
              _IconTip(
                icon: Icons.copy_rounded,
                tooltip: 'Copy CA PEM',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: ca.caPem));
                  state.showToast('CA certificate copied');
                },
              ),
            ],
            _IconTip(
              icon: Icons.delete_sweep_outlined,
              tooltip: 'Clear captured traffic',
              onTap: proxy.clear,
            ),
          ],
        ),
        if (state.captureCaLoading) ...[
          SizedBox(height: 8),
          LinearProgressIndicator(minHeight: 2, color: AstraColors.accent),
        ],
        SizedBox(height: 8),
        Text(
          running
              ? 'Set your HTTP/HTTPS proxy to 127.0.0.1:${proxy.port}. '
                  '${_mitm ? 'For HTTPS bodies, trust the Astra CA (${ca?.commonName ?? 'Astra Local Traffic CA'}) in your client or OS store.' : 'HTTPS is tunneled: only host and byte counts are recorded.'}'
              : 'Start the proxy, then point your app or browser at 127.0.0.1:${_portController.text} as the HTTP and HTTPS proxy.',
          style: TextStyle(fontSize: 10.5, color: AstraColors.muted, height: 1.5),
        ),
        if (state.captureProxyError != null)
          Text(
            state.captureProxyError!,
            style: TextStyle(fontSize: 10.5, color: AstraColors.err),
          ),
        SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: AstraColors.inset,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AstraColors.line),
                  ),
                  child: proxy.records.isEmpty
                      ? Center(
                          child: Text(
                            running
                                ? 'Waiting for traffic…'
                                : 'Captured requests and responses will appear here.',
                            style: TextStyle(fontSize: 11, color: AstraColors.muted),
                          ),
                        )
                      : Column(
                          children: [
                            _headerRow(),
                            Divider(height: 1, color: AstraColors.line),
                            Expanded(
                              child: ListView.separated(
                                itemCount: proxy.records.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, color: AstraColors.line),
                                itemBuilder: (context, index) {
                                  final record = proxy.records[index];
                                  final selected = record.id == _selectedId;
                                  return InkWell(
                                    onTap: () => setState(() => _selectedId = record.id),
                                    child: Container(
                                      color: selected ? AstraColors.accentSoft : Colors.transparent,
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                      child: Row(
                                        children: [
                                          MethodBadge(method: record.method),
                                          SizedBox(width: 7),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  record.url,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AstraColors.text,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  record.error ??
                                                      '${record.status ?? '—'} · ${record.durationMs} ms · '
                                                          '${_size(record.responseBytes)}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    color: record.error != null
                                                        ? AstraColors.err
                                                        : AstraColors.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            _time(record.ts),
                                            style: monoStyle(size: 9, color: AstraColors.faint),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Actions',
                                            icon: Icon(
                                              Icons.more_vert,
                                              size: 15,
                                              color: AstraColors.muted,
                                            ),
                                            onSelected: (value) {
                                              if (value == 'open') {
                                                state.openCapturedRequest(record);
                                              } else if (value == 'mock') {
                                                state.createMockFromCaptureRecord(record);
                                              } else if (value == 'delete') {
                                                proxy.remove(record.id);
                                                if (_selectedId == record.id) {
                                                  setState(() => _selectedId = null);
                                                }
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              PopupMenuItem(
                                                value: 'open',
                                                enabled: !record.tunneled,
                                                child: Text('Open as request'),
                                              ),
                                              PopupMenuItem(
                                                value: 'mock',
                                                enabled: !record.tunneled &&
                                                    record.responseBody.isNotEmpty,
                                                child: Text('Create mock route'),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: _selected == null
                    ? _EmptyPanel(
                        icon: Icons.radar,
                        text: 'Select a captured exchange to inspect request and response bodies',
                      )
                    : _CaptureDetail(record: _selected!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerRow() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Text(
            '${widget.state.captureProxy.records.length} exchanges',
            style: TextStyle(fontSize: 10, color: AstraColors.muted),
          ),
          Spacer(),
          Text(
            'Newest first',
            style: TextStyle(fontSize: 9.5, color: AstraColors.faint),
          ),
        ],
      ),
    );
  }
}

class _CaptureDetail extends StatelessWidget {
  final CaptureRecord record;

  _CaptureDetail({required this.record});

  @override
  Widget build(BuildContext context) {
    final requestHeaders = record.requestHeaders.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
    final responseHeaders = record.responseHeaders.entries
        .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
        .join('\n');
    return Container(
      decoration: BoxDecoration(
        color: AstraColors.inset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AstraColors.line),
      ),
      padding: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${record.method} ${record.url}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(size: 10.5, color: AstraColors.text),
          ),
          SizedBox(height: 6),
          if (record.error != null)
            Text(record.error!, style: TextStyle(fontSize: 10, color: AstraColors.err)),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Request headers', requestHeaders.isEmpty ? '—' : requestHeaders),
                  _section(
                    'Request body',
                    record.requestBody.isEmpty
                        ? '—'
                        : '${record.requestBody}${record.requestTruncated ? '\n… truncated' : ''}',
                  ),
                  _section('Response headers', responseHeaders.isEmpty ? '—' : responseHeaders),
                  _section(
                    'Response body',
                    record.responseBody.isEmpty
                        ? '—'
                        : '${prettyCaptureJson(record.responseBody)}'
                            '${record.responseTruncated ? '\n… truncated' : ''}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 9.5, color: AstraColors.muted)),
          SizedBox(height: 3),
          SelectableText(
            body,
            style: monoStyle(size: 10, color: AstraColors.codeText, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String text;

  _EmptyPanel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AstraColors.inset,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AstraColors.line),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: AstraColors.faint),
              SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AstraColors.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final Color color;
  final String text;

  _StatusPill({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: monoStyle(size: 9.5, color: color)),
    );
  }
}

class _Check extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  _Check({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (next) => onChanged(next ?? false) : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: enabled ? AstraColors.text : AstraColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconTip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconTip({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: AstraColors.muted),
        ),
      ),
    );
  }
}

InputDecoration _decoration(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      filled: true,
      fillColor: AstraColors.inset,
      hintStyle: TextStyle(fontSize: 11, color: AstraColors.faint),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: AstraColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: AstraColors.accentBorder),
      ),
    );

String _time(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String prettyCaptureJson(String body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
  } catch (_) {
    return body;
  }
}
