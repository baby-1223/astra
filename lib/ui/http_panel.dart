import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/file_io.dart';
import '../state.dart';
import 'advanced_dialogs.dart';
import 'bound_text_field.dart';
import 'dialogs.dart';
import 'json_tree.dart';
import 'runner_dialog.dart';
import 'script_editor.dart';
import 'theme.dart';
import 'widgets.dart';

const List<String> _commonHeaders = [
  'Accept',
  'Accept-Charset',
  'Accept-Encoding',
  'Accept-Language',
  'Authorization',
  'Cache-Control',
  'Content-Disposition',
  'Content-Encoding',
  'Content-Language',
  'Content-Length',
  'Content-Type',
  'Cookie',
  'Date',
  'ETag',
  'Forwarded',
  'Host',
  'If-Match',
  'If-Modified-Since',
  'If-None-Match',
  'Origin',
  'Pragma',
  'Referer',
  'User-Agent',
  'X-Api-Key',
  'X-Correlation-Id',
  'X-CSRF-Token',
  'X-Forwarded-For',
  'X-Request-Id',
  'X-Requested-With',
];

class HttpView extends StatefulWidget {
  final AppState state;

  const HttpView({super.key, required this.state});

  @override
  State<HttpView> createState() => _HttpViewState();
}

class _HttpViewState extends State<HttpView> {
  String _reqTab = 'params';
  String _respTab = 'body';
  String _jsonView = 'tree'; // tree | text
  bool _oauthBusy = false;
  bool _imageFit = true;
  double _reqFraction = 0.44;
  final TextEditingController _headerFilter = TextEditingController();
  bool _headerSortAsc = true;
  double _headerKeyWidth = 190;

  AppState get state => widget.state;

  @override
  void dispose() {
    _headerFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => state.send(),
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () => state.send(),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            const dividerHeight = 16.0;
            final available = (constraints.maxHeight - dividerHeight).clamp(160.0, 4000.0);
            final requestHeight =
                (available * _reqFraction).clamp(150.0, available - 150.0);
            return Column(
              children: [
                SizedBox(height: requestHeight, child: _requestCard()),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _reqFraction =
                            ((requestHeight + details.delta.dy) / available)
                                .clamp(0.18, 0.82);
                      });
                    },
                    child: SizedBox(
                      height: dividerHeight,
                      child: Center(
                        child: Container(
                          width: 46,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AstraColors.lineStrong,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _responseCard()),
              ],
            );
          },
        ),
      ),
    );
  }

  /* ---------------------------------------------------------------- */
  /* 请求                                                              */
  /* ---------------------------------------------------------------- */

  Widget _requestCard() {
    final req = state.request;
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
                    hint: 'API 名称',
                    fontSize: 13,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    onChanged: state.renameActive,
                    onSubmitted: (_) => state.saveActive(),
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'cURL',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                onSelected: (value) async {
                  if (value == 'import') {
                    await showCurlImportDialog(context, state);
                  } else {
                    await Clipboard.setData(ClipboardData(text: state.curlFor(state.request)));
                    state.showToast('cURL 已复制到剪贴板');
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'import', height: 38, child: Text('从 cURL 导入')),
                  PopupMenuItem(value: 'export', height: 38, child: Text('复制为 cURL')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AstraColors.line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.terminal_rounded, size: 12, color: AstraColors.muted),
                      SizedBox(width: 5),
                      Text('cURL', style: TextStyle(fontSize: 10.5, color: AstraColors.muted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _iconAction(
                icon: Icons.visibility_outlined,
                tooltip: '预览最终请求',
                onPressed: () => showRequestPreviewDialog(context, state),
              ),
              _iconAction(
                icon: Icons.data_object,
                tooltip: '变量面板',
                onPressed: () => showVariablesDialog(context, state),
              ),
              _iconAction(
                icon: Icons.playlist_play,
                tooltip: '集合运行器',
                onPressed: () => showRunnerDialog(context, state),
              ),
              const SizedBox(width: 4),
              const Text(
                '⌘ / Ctrl + S 保存',
                style: TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MethodSelector(
                value: req.method,
                onChanged: (value) {
                  setState(() => req.method = value);
                  state.touch();
                },
              ),
              const SizedBox(width: 9),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: BoundTextField(
                    value: req.url,
                    hint: 'https://api.example.com/users 或 {{baseUrl}}/users',
                    fontSize: 13,
                    varNames: state.varNames,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    onChanged: (value) {
                      req.url = value;
                      state.touch();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 9),
              GradientButton(
                label: state.sending ? '发送中' : '发送',
                icon: state.sending ? null : Icons.send_rounded,
                onPressed: state.sending ? null : state.send,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AstraTabs(
                  selected: _reqTab,
                  onSelect: (id) => setState(() => _reqTab = id),
                  items: [
                    AstraTabItem('params',
                        '参数', count: req.params.where((e) => e.on && e.k.isNotEmpty).length),
                    AstraTabItem('headers',
                        '请求头', count: req.headers.where((e) => e.on && e.k.isNotEmpty).length),
                    AstraTabItem('body',
                        '请求体${req.bodyMode == 'none' ? '' : ' · ${_bodyLabel(req.bodyMode)}'}'),
                    AstraTabItem('auth',
                        req.auth.type == 'none' ? '认证' : '认证 · ${_authLabel(req.auth.type)}'),
                    const AstraTabItem('scripts', '脚本'),
                    const AstraTabItem('options', '选项'),
                  ],
                ),
              ),
              if (req.method == 'GET' || req.method == 'HEAD')
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${req.method} 请求不携带 Body',
                    style: const TextStyle(fontSize: 10, color: AstraColors.faint),
                  ),
                ),
            ],
          ),
          const Divider(height: 1, color: AstraColors.line),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: _requestTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  String _bodyLabel(String mode) {
    switch (mode) {
      case 'json':
        return 'JSON';
      case 'text':
        return '文本';
      case 'form':
        return '表单';
      case 'form-data':
        return '多部分表单';
      case 'graphql':
        return 'GraphQL';
      case 'grpc':
        return 'gRPC';
    }
    return '';
  }

  String _authLabel(String type) {
    switch (type) {
      case 'bearer':
        return 'Bearer';
      case 'basic':
        return 'Basic';
      case 'apikey':
        return 'API Key';
      case 'oauth2':
        return 'OAuth 2.0';
      case 'inherit':
        return '继承';
    }
    return type;
  }

  Widget _requestTabContent() {
    final req = state.request;
    switch (_reqTab) {
      case 'headers':
        return KVEditor(
          rows: req.headers,
          keyHint: 'Header 名称',
          valueHint: 'Header 值（支持 {{变量}}）',
          varNames: state.varNames,
          keySuggestions: _commonHeaders,
          onBulkEdit: () => showBulkEditDialog(
            context,
            title: '批量编辑请求头',
            rows: req.headers,
          ),
          onChanged: state.touch,
          onAdd: () => setState(() => req.headers.add(KV())),
          onRemove: (index) => setState(() => req.headers.removeAt(index)),
        );
      case 'body':
        return _bodyEditor(req);
      case 'auth':
        return _authEditor(req);
      case 'scripts':
        return _scriptsEditor(req);
      case 'options':
        return _optionsEditor(req);
      default:
        return KVEditor(
          rows: req.params,
          keyHint: 'Query 参数',
          valueHint: '值（支持 {{变量}}）',
          varNames: state.varNames,
          onBulkEdit: () => showBulkEditDialog(
            context,
            title: '批量编辑查询参数',
            rows: req.params,
          ),
          onChanged: state.touch,
          onAdd: () => setState(() => req.params.add(KV())),
          onRemove: (index) => setState(() => req.params.removeAt(index)),
        );
    }
  }

  Widget _bodyEditor(ApiRequest req) {
    const modes = [
      ['none', '无'],
      ['json', 'JSON'],
      ['text', '文本'],
      ['form', '表单'],
      ['form-data', 'Multipart'],
      ['graphql', 'GraphQL'],
      ['grpc', 'gRPC'],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0x08FFFFFF),
                border: Border.all(color: AstraColors.line),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: modes.map((mode) {
                  final active = req.bodyMode == mode[0];
                  return GestureDetector(
                    onTap: () {
                      setState(() => req.bodyMode = mode[0]);
                      state.touch();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: active ? const Color(0x1F38BDF8) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: active ? const Color(0x4038BDF8) : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        mode[1],
                        style: TextStyle(
                          fontSize: 11.5,
                          color: active ? AstraColors.accent : AstraColors.muted,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Spacer(),
            if (req.bodyMode == 'json')
              TextButton.icon(
                onPressed: () {
                  try {
                    final pretty =
                        const JsonEncoder.withIndent('  ').convert(jsonDecode(req.body));
                    setState(() => req.body = pretty);
                    state.touch();
                  } catch (_) {
                    state.showToast('JSON 格式无效，无法格式化');
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AstraColors.muted,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                icon: const Icon(Icons.auto_fix_high, size: 13),
                label: const Text('格式化 JSON'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (req.bodyMode == 'none')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              '该请求不携带 Body',
              style: TextStyle(fontSize: 12, color: AstraColors.faint),
            ),
          )
        else if (req.bodyMode == 'json' || req.bodyMode == 'text')
          BoundTextField(
            value: req.body,
            hint: req.bodyMode == 'json' ? '{\n  "name": "Astra"\n}' : '纯文本内容',
            minLines: 8,
            maxLines: 16,
            fontSize: 12,
            lineHeight: 1.55,
            varNames: state.varNames,
            contentPadding: const EdgeInsets.all(12),
            onChanged: (value) {
              req.body = value;
              state.touch();
            },
          )
        else if (req.bodyMode == 'form')
          KVEditor(
            rows: req.form,
            keyHint: '字段名',
            valueHint: '字段值（支持 {{变量}}）',
            varNames: state.varNames,
            onBulkEdit: () => showBulkEditDialog(
              context,
              title: '批量编辑表单字段',
              rows: req.form,
            ),
            onChanged: state.touch,
            onAdd: () => setState(() => req.form.add(KV())),
            onRemove: (index) => setState(() => req.form.removeAt(index)),
          )
        else if (req.bodyMode == 'graphql')
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Query', hint: '支持 {{变量}}，发送时会自动转成 GraphQL 请求'),
              const SizedBox(height: 8),
              BoundTextField(
                value: req.graphqlQuery,
                hint: 'query Users(\$limit: Int) {\n  users(limit: \$limit) { id name }\n}',
                minLines: 6,
                maxLines: 10,
                fontSize: 12,
                lineHeight: 1.55,
                varNames: state.varNames,
                contentPadding: const EdgeInsets.all(12),
                onChanged: (value) {
                  req.graphqlQuery = value;
                  state.touch();
                },
              ),
              const SizedBox(height: 12),
              const SectionLabel('Variables', hint: 'JSON 对象，例如 {"limit": 10}'),
              const SizedBox(height: 8),
              BoundTextField(
                value: req.graphqlVars,
                hint: '{\n  "limit": 10\n}',
                minLines: 3,
                maxLines: 6,
                fontSize: 12,
                lineHeight: 1.55,
                varNames: state.varNames,
                contentPadding: const EdgeInsets.all(12),
                onChanged: (value) {
                  req.graphqlVars = value;
                  state.touch();
                },
              ),
            ],
          )
        else if (req.bodyMode == 'grpc')
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _miniSegments(
                label: '载荷类型',
                options: const [
                  ['binary', 'Base64 Protobuf'],
                  ['json', 'JSON 文本'],
                ],
                value: req.grpcBinary ? 'binary' : 'json',
                onSelect: (value) {
                  setState(() => req.grpcBinary = value == 'binary');
                  state.touch();
                },
              ),
              const SizedBox(height: 10),
              BoundTextField(
                value: req.grpcPayload,
                hint: req.grpcBinary
                    ? '粘贴 base64 编码的 protobuf 消息'
                    : '{"message": "hello"}',
                minLines: 6,
                maxLines: 12,
                fontSize: 12,
                lineHeight: 1.55,
                varNames: state.varNames,
                contentPadding: const EdgeInsets.all(12),
                onChanged: (value) {
                  req.grpcPayload = value;
                  state.touch();
                },
              ),
              const SizedBox(height: 8),
              const Text(
                '以 gRPC-Web 帧（5 字节头 + 载荷）发送到上方地址，响应会按帧解析展示。'
                '适用于 Envoy / grpc-web 代理后的服务。',
                style: TextStyle(fontSize: 10.5, color: AstraColors.faint, height: 1.6),
              ),
            ],
          )
        else
          _FormDataEditor(
            rows: req.formData,
            onChanged: () {
              setState(() {});
              state.touch();
            },
          ),
      ],
    );
  }

  Widget _authEditor(ApiRequest req) {
    const types = [
      ['inherit', '继承上级'],
      ['none', '无认证'],
      ['bearer', 'Bearer Token'],
      ['basic', 'Basic Auth'],
      ['apikey', 'API Key'],
      ['oauth2', 'OAuth 2.0'],
    ];
    final inherited = state.effectiveAuth(req);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types.map((type) {
            final active = req.auth.type == type[0];
            return GestureDetector(
              onTap: () {
                setState(() => req.auth.type = type[0]);
                state.touch();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? const Color(0x1F38BDF8) : const Color(0x08FFFFFF),
                  border: Border.all(
                    color: active ? const Color(0x4038BDF8) : AstraColors.line,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  type[1],
                  style: TextStyle(
                    fontSize: 11.5,
                    color: active ? AstraColors.accent : AstraColors.muted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (req.auth.type == 'inherit') ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0x0F38BDF8),
              border: Border.all(color: const Color(0x2938BDF8)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, size: 14, color: AstraColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前使用${state.authSourceLabel(req)}的认证配置'
                    '${inherited.type == 'none' ? '（未配置）' : ' · ${_authLabel(inherited.type)}'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AstraColors.muted,
                      height: 1.5,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => showVariablesDialog(context, state),
                  style: TextButton.styleFrom(
                    foregroundColor: AstraColors.accent,
                    textStyle: const TextStyle(fontSize: 10.5),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('管理集合变量'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        ..._authFields(req),
      ],
    );
  }

  List<Widget> _authFields(ApiRequest req) {
    switch (req.auth.type) {
      case 'bearer':
        return [
          BoundTextField(
            value: req.auth.token,
            hint: 'Token（支持 {{token}}）',
            onChanged: (value) {
              req.auth.token = value;
              state.touch();
            },
          ),
        ];
      case 'basic':
        return [
          Row(
            children: [
              Expanded(
                child: BoundTextField(
                  value: req.auth.username,
                  hint: '用户名',
                  onChanged: (value) {
                    req.auth.username = value;
                    state.touch();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BoundTextField(
                  value: req.auth.password,
                  hint: '密码',
                  obscure: true,
                  onChanged: (value) {
                    req.auth.password = value;
                    state.touch();
                  },
                ),
              ),
            ],
          ),
        ];
      case 'apikey':
        return [
          Row(
            children: [
              Expanded(
                child: BoundTextField(
                  value: req.auth.apiKeyName,
                  hint: 'Key 名称，如 X-API-Key',
                  onChanged: (value) {
                    req.auth.apiKeyName = value;
                    state.touch();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BoundTextField(
                  value: req.auth.apiKeyValue,
                  hint: 'Key 值（支持 {{变量}}）',
                  onChanged: (value) {
                    req.auth.apiKeyValue = value;
                    state.touch();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _miniSegments(
            label: '添加到',
            options: const [['header', 'Header'], ['query', 'Query 参数']],
            value: req.auth.apiKeyIn,
            onSelect: (value) {
              setState(() => req.auth.apiKeyIn = value);
              state.touch();
            },
          ),
        ];
      case 'oauth2':
        return _oauthFields(req);
      case 'inherit':
        return const [];
      default:
        return const [
          Text('未启用认证', style: TextStyle(fontSize: 12, color: AstraColors.faint)),
        ];
    }
  }

  List<Widget> _oauthFields(ApiRequest req) {
    final auth = req.auth;
    return [
      _miniSegments(
        label: '授权类型',
        options: const [
          ['client_credentials', 'Client Credentials'],
          ['password', 'Password'],
          ['authorization_code', '授权码 + PKCE'],
        ],
        value: auth.oauthGrantType,
        onSelect: (value) {
          setState(() => auth.oauthGrantType = value);
          state.touch();
        },
      ),
      if (auth.oauthGrantType == 'authorization_code') ...[
        const SizedBox(height: 10),
        BoundTextField(
          value: auth.oauthAuthUrl,
          hint: 'Authorization 端点，如 https://demo.com/oauth/authorize',
          varNames: state.varNames,
          onChanged: (value) {
            auth.oauthAuthUrl = value;
            state.touch();
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Checkbox(
              value: auth.oauthPkce,
              activeColor: AstraColors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) {
                setState(() => auth.oauthPkce = value ?? true);
                state.touch();
              },
            ),
            const Text('使用 PKCE（S256）', style: TextStyle(fontSize: 11, color: AstraColors.muted)),
            const SizedBox(width: 12),
            const Text(
              '回调地址 http://127.0.0.1:8765/callback',
              style: TextStyle(fontSize: 10, color: AstraColors.faint),
            ),
          ],
        ),
      ],
      const SizedBox(height: 10),
      BoundTextField(
        value: auth.oauthTokenUrl,
        hint: 'Token 端点，如 https://api.demo.com/oauth/token',
        varNames: state.varNames,
        onChanged: (value) {
          auth.oauthTokenUrl = value;
          state.touch();
        },
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: BoundTextField(
              value: auth.oauthClientId,
              hint: 'Client ID',
              onChanged: (value) {
                auth.oauthClientId = value;
                state.touch();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BoundTextField(
              value: auth.oauthClientSecret,
              hint: 'Client Secret',
              obscure: true,
              onChanged: (value) {
                auth.oauthClientSecret = value;
                state.touch();
              },
            ),
          ),
        ],
      ),
      if (auth.oauthGrantType == 'password') ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BoundTextField(
                value: auth.username,
                hint: '用户名',
                onChanged: (value) {
                  auth.username = value;
                  state.touch();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BoundTextField(
                value: auth.password,
                hint: '密码',
                obscure: true,
                onChanged: (value) {
                  auth.password = value;
                  state.touch();
                },
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 10),
      BoundTextField(
        value: auth.oauthScope,
        hint: 'Scope（可选，空格分隔）',
        onChanged: (value) {
          auth.oauthScope = value;
          state.touch();
        },
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          GhostButton(
            label: _oauthBusy ? '获取中…' : '获取 Token',
            icon: Icons.vpn_key_outlined,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            onPressed: _oauthBusy
                ? null
                : () async {
                    setState(() => _oauthBusy = true);
                    final error = await state.fetchOAuthToken(req);
                    if (!mounted) return;
                    setState(() => _oauthBusy = false);
                    state.showToast(error ?? '已获取 access_token');
                  },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.token.isEmpty
                      ? '尚未获取 Token，发送请求前请先获取或手动填写'
                      : '已获取：${_maskToken(auth.token)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: auth.token.isEmpty ? AstraColors.faint : AstraColors.ok,
                  ),
                ),
                if (auth.oauthExpiresAt > 0)
                  Text(
                    '${auth.oauthExpired ? '已过期' : '有效期至'} '
                    '${_timeText(auth.oauthExpiresAt)}'
                    '${auth.oauthRefreshToken.isEmpty ? '' : ' · 支持自动刷新'}',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: auth.oauthExpired ? AstraColors.warn : AstraColors.faint,
                    ),
                  ),
              ],
            ),
          ),
          if (auth.oauthGrantType != 'authorization_code')
            TextButton(
              onPressed: _oauthBusy
                  ? null
                  : () async {
                      setState(() => _oauthBusy = true);
                      final error = await state.fetchOAuthToken(req, force: true);
                      if (!mounted) return;
                      setState(() => _oauthBusy = false);
                      state.showToast(error ?? '已获取 access_token');
                    },
              style: TextButton.styleFrom(
                foregroundColor: AstraColors.muted,
                textStyle: const TextStyle(fontSize: 10.5),
              ),
              child: const Text('强制刷新'),
            ),
        ],
      ),
    ];
  }

  String _timeText(int ms) {
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String _maskToken(String token) {
    if (token.length <= 12) return token;
    return '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
  }

  Widget _miniSegments({
    required String label,
    required List<List<String>> options,
    required String value,
    required ValueChanged<String> onSelect,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 11.5, color: AstraColors.muted)),
        ),
        ...options.map((option) {
          final active = value == option[0];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(option[0]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? const Color(0x1F38BDF8) : const Color(0x08FFFFFF),
                  border: Border.all(color: active ? const Color(0x4038BDF8) : AstraColors.line),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  option[1],
                  style: TextStyle(
                    fontSize: 11,
                    color: active ? AstraColors.accent : AstraColors.muted,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _scriptsEditor(ApiRequest req) {
    Widget editor(
      String title,
      String hint,
      String value,
      ValueChanged<String> onChanged, {
      required List<List<String>> templates,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SectionLabel(title),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: templates.map((template) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        final next = value.isEmpty ? template[1] : '$value\n${template[1]}';
                        onChanged(next);
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: AstraColors.line),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+ ${template[0]}',
                          style: const TextStyle(fontSize: 10.5, color: AstraColors.muted),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          ScriptEditor(
            value: value,
            hint: hint,
            height: 176,
            onChanged: onChanged,
          ),
        ],
      );
    }

    const preTemplates = [
      ['时间戳', 'pm.environment.set("ts", Date.now());'],
      ['随机数', 'pm.environment.set("nonce", Math.random().toString(36).slice(2));'],
      ['加 Header', 'pm.request.headers.add({ key: "X-Debug", value: "1" });'],
    ];
    const postTemplates = [
      ['断言 200', 'pm.test("状态码 200", () => pm.response.to.have.status(200));'],
      ['断言 JSON', 'pm.test("返回 JSON", () => {\n  pm.expect(pm.response.json()).to.be.an("object");\n});'],
      ['保存变量',
        'const data = pm.response.json();\npm.environment.set("token", data.token || "");'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x0F38BDF8),
            border: Border.all(color: const Color(0x2938BDF8)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.bolt_outlined, size: 14, color: AstraColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '脚本在本地 JavaScript 引擎中执行，可使用 pm.environment / pm.variables / pm.request / pm.response / pm.test / console.log，运行结果在响应区的「脚本」标签中查看。',
                  style: TextStyle(fontSize: 10.5, color: AstraColors.muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        editor(
          '前置脚本',
          '// 发送前执行，例如：\n// pm.environment.set("ts", Date.now());\n// pm.request.headers.add({ key: "X-Debug", value: "1" });',
          req.preScript,
          (value) {
            req.preScript = value;
            state.touch();
            setState(() {});
          },
          templates: preTemplates,
        ),
        const SizedBox(height: 10),
        editor(
          '后置脚本',
          '// 响应返回后执行，例如：\n// pm.test("状态码 200", () => pm.response.to.have.status(200));\n// console.log(pm.response.json());',
          req.postScript,
          (value) {
            req.postScript = value;
            state.touch();
            setState(() {});
          },
          templates: postTemplates,
        ),
      ],
    );
  }

  Widget _optionsEditor(ApiRequest req) {
    Widget toggle(String title, String desc, bool value, ValueChanged<bool> onChanged) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 10.5, color: AstraColors.faint)),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: AstraColors.accent,
              onChanged: (next) {
                setState(() => onChanged(next));
                state.touch();
              },
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        toggle('自动跟随重定向', '跟随 3xx 响应，最多由底层客户端处理', req.options.followRedirects,
            (value) => req.options.followRedirects = value),
        toggle('校验 TLS 证书', '关闭后可访问自签名证书的测试服务', req.options.rejectUnauthorized,
            (value) => req.options.rejectUnauthorized = value),
        toggle('自动管理 Cookie', '保存响应中的 Set-Cookie 并在后续请求中携带', req.options.manageCookies,
            (value) => req.options.manageCookies = value),
        toggle('以事件流接收', '按 SSE 逐条接收 text/event-stream 响应，而不是等待完整响应',
            req.options.streamSse, (value) => req.options.streamSse = value),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('代理与客户端证书', style: TextStyle(fontSize: 12.5)),
                    SizedBox(height: 2),
                    Text('HTTP / SOCKS5 代理、mTLS 双向证书，作用于所有请求',
                        style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
                  ],
                ),
              ),
              GhostButton(
                label: state.settings.proxyEnabled || state.settings.hasClientCert
                    ? '已配置'
                    : '配置',
                icon: Icons.lan_outlined,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: () => showNetworkSettingsDialog(context, state),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('超时时间', style: TextStyle(fontSize: 12.5)),
                    SizedBox(height: 2),
                    Text('单位秒，0 表示不限制', style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                child: BoundTextField(
                  value: req.options.timeoutSeconds.toString(),
                  hint: '90',
                  onChanged: (value) {
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed < 0) return;
                    req.options.timeoutSeconds = parsed;
                    state.touch();
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Text('秒', style: TextStyle(fontSize: 11.5, color: AstraColors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  /* ---------------------------------------------------------------- */
  /* 响应                                                              */
  /* ---------------------------------------------------------------- */

  Widget _responseCard() {
    final result = state.response;
    final failedTests = state.scriptTests.where((item) => !item.passed).length;
    final sseActive = state.sseRunning || state.sseLog.isNotEmpty;
    final hasTabs = result != null || state.scriptRan || sseActive;
    return AstraCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '响应',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              if (state.sending)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AstraColors.accent),
                )
              else if (result != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor(result.status).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${result.status} ${result.reason}',
                    style: monoStyle(
                      size: 11,
                      color: statusColor(result.status),
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${result.ms} ms',
                  style: const TextStyle(fontSize: 11, color: AstraColors.muted),
                ),
                const SizedBox(width: 10),
                Text(
                  formatBytes(result.size),
                  style: const TextStyle(fontSize: 11, color: AstraColors.muted),
                ),
              ],
              if (state.scriptRan && (failedTests > 0 || state.scriptError != null)) ...[
                const SizedBox(width: 10),
                const Icon(Icons.error_outline, size: 13, color: AstraColors.err),
                const SizedBox(width: 4),
                Text(
                  state.scriptError != null ? '脚本异常' : '$failedTests 个断言失败',
                  style: const TextStyle(fontSize: 10.5, color: AstraColors.err),
                ),
              ],
              if (state.sseRunning) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: AstraColors.ok),
                ),
              ],
              const Spacer(),
              if (state.responseHistory.length > 1)
                _iconAction(
                  icon: Icons.compare_arrows,
                  tooltip: '对比最近两次响应',
                  onPressed: () => showTextDiffDialog(
                    context,
                    title: '响应对比',
                    before: state.responseHistory[1].prettyBody,
                    after: state.responseHistory[0].prettyBody,
                    beforeLabel: '上一次 · ${state.responseHistory[1].status}',
                    afterLabel: '本次 · ${state.responseHistory[0].status}',
                  ),
                ),
              if (result != null && state.selectedId != null)
                _iconAction(
                  icon: Icons.bookmark_add_outlined,
                  tooltip: '存为响应示例',
                  onPressed: () => showSaveExampleDialog(context, state, state.selectedId!),
                ),
              if (result != null) _downloadButton(result),
              if (result != null)
                CopyButton(
                  text: _respTab == 'headers'
                      ? result.headers.entries
                          .map((e) => '${e.key}: ${e.value.join(', ')}')
                          .join('\n')
                      : result.prettyBody,
                  tooltip: '复制响应内容',
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasTabs)
            Row(
              children: [
                Flexible(
                  child: AstraTabs(
                    compact: true,
                    selected: _respTab,
                    onSelect: (id) => setState(() => _respTab = id),
                    items: [
                      if (result != null) const AstraTabItem('body', '响应体'),
                      if (result != null) const AstraTabItem('headers', '响应头'),
                      if (state.responseCookies.isNotEmpty)
                        AstraTabItem(
                          'cookies',
                          'Cookies',
                          count: state.responseCookies.length,
                        ),
                      if (result != null) const AstraTabItem('raw', '原始'),
                      if (sseActive)
                        AstraTabItem('sse', '事件流', count: state.sseLog.length),
                      if (state.scriptRan)
                        AstraTabItem(
                          'scripts',
                          '脚本',
                          count: state.scriptTests.isEmpty ? null : state.scriptTests.length,
                        ),
                    ],
                  ),
                ),
                if (result != null &&
                    _respTab == 'body' &&
                    _decodedJson != null) ...[
                  const SizedBox(width: 6),
                  _viewToggle(),
                ],
                if (sseActive) ...[
                  const SizedBox(width: 8),
                  GhostButton(
                    label: state.sseRunning ? '停止' : '重新连接',
                    icon: state.sseRunning ? Icons.stop_circle_outlined : Icons.sync,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    onPressed: state.sseRunning ? state.stopSse : state.startSse,
                  ),
                ],
              ],
            ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AstraColors.line),
          Expanded(child: _responseContent()),
        ],
      ),
    );
  }

  Widget _responseContent() {
    final available = <String>[
      if (state.response != null) ...['body', 'headers', 'raw'],
      if (state.responseCookies.isNotEmpty) 'cookies',
      if (state.scriptRan) 'scripts',
      if (state.sseRunning || state.sseLog.isNotEmpty) 'sse',
    ];
    if (available.isNotEmpty && !available.contains(_respTab)) {
      return _scriptResultPanel();
    }
    if (_respTab == 'scripts') return _scriptResultPanel();
    if (_respTab == 'cookies') return _cookiesPanel();
    if (_respTab == 'sse') return _ssePanel();
    final error = state.responseError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 17, color: AstraColors.err),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                error,
                style: const TextStyle(fontSize: 12, color: AstraColors.err, height: 1.6),
              ),
            ),
          ],
        ),
      );
    }
    final result = state.response;
    if (result == null) {
      return const EmptyHint(
        icon: Icons.bolt_rounded,
        title: '等待发送请求',
        subtitle: '输入地址后点击「发送」，或按 ⌘/Ctrl + Enter\n响应状态、耗时与内容会显示在这里',
      );
    }
    if (_respTab == 'headers') {
      final query = _headerFilter.text.trim().toLowerCase();
      var entries = result.headers.entries.toList();
      if (query.isNotEmpty) {
        entries = entries
            .where((entry) =>
                entry.key.toLowerCase().contains(query) ||
                entry.value.join(', ').toLowerCase().contains(query))
            .toList();
      }
      entries.sort((a, b) => _headerSortAsc
          ? a.key.toLowerCase().compareTo(b.key.toLowerCase())
          : b.key.toLowerCase().compareTo(a.key.toLowerCase()));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 230,
                  height: 33,
                  child: BoundTextField(
                    value: _headerFilter.text,
                    hint: '过滤响应头',
                    fontSize: 11.5,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    onChanged: (value) {
                      _headerFilter.text = value;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                GhostButton(
                  label: _headerSortAsc ? '名称 ↑' : '名称 ↓',
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  onPressed: () => setState(() => _headerSortAsc = !_headerSortAsc),
                ),
                const Spacer(),
                Text(
                  '${entries.length} 个响应头',
                  style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _headerKeyWidth,
                        child: SelectableText(
                          entry.key,
                          style: monoStyle(size: 11.5, color: AstraColors.accent),
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _headerKeyWidth =
                                  (_headerKeyWidth + details.delta.dx).clamp(120.0, 440.0);
                            });
                          },
                          child: Container(
                            width: 9,
                            alignment: Alignment.center,
                            child: Container(
                              width: 1,
                              color: AstraColors.line.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          entry.value.join(', '),
                          style: monoStyle(size: 11.5, color: AstraColors.muted, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    if (_respTab == 'raw') {
      final buffer = StringBuffer('HTTP/1.1 ${result.status} ${result.reason}\n');
      result.headers.forEach((key, values) {
        for (final value in values) {
          buffer.write('$key: $value\n');
        }
      });
      buffer.write('\n');
      buffer.write(result.text ?? '[二进制内容 ${formatBytes(result.size)}]');
      return _textBlock(buffer.toString());
    }
    if (result.text == null) {
      final type = result.header('content-type') ?? '';
      if (type.startsWith('image/') && result.bytes.isNotEmpty) {
        return _imagePreview(result);
      }
      return _binaryPlaceholder(result, type);
    }
    final json = _decodedJson;
    if (json != null && _jsonView == 'tree') {
      return JsonTreeView(data: json);
    }
    return _textBlock(result.prettyBody);
  }

  dynamic get _decodedJson {
    final text = state.response?.text;
    if (text == null) return null;
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  Widget _viewToggle() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewChip('树形', 'tree'),
          _viewChip('文本', 'text'),
        ],
      ),
    );
  }

  Widget _viewChip(String label, String value) {
    return _pairChip(label, _jsonView == value, () => setState(() => _jsonView = value));
  }

  Widget _imagePreview(HttpResult result) {
    final type = (result.header('content-type') ?? 'image/*').split(';').first.trim();
    final bytes = Uint8List.fromList(result.bytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.image_outlined, size: 14, color: AstraColors.accent),
              const SizedBox(width: 6),
              const Text('图片预览', style: TextStyle(fontSize: 11.5, color: AstraColors.text)),
              const SizedBox(width: 10),
              Flexible(child: _metaChip(type)),
              const SizedBox(width: 8),
              Text(formatBytes(result.size),
                  style: monoStyle(size: 10.5, color: AstraColors.faint)),
              const Spacer(),
              _viewTogglePair(
                leftLabel: '适应窗口',
                rightLabel: '原始尺寸',
                leftActive: _imageFit,
                onSelect: (fit) => setState(() => _imageFit = fit),
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: '保存图片',
                icon: Icons.download_rounded,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: () => _saveResponse(result),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B0F17),
              border: Border.all(color: AstraColors.line),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GridPaper(
                    color: const Color(0x0AFFFFFF),
                    interval: 24,
                    divisions: 2,
                    subdivisions: 2,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: _imageFit
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stack) =>
                                _imageError('图片解析失败'),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Image.memory(
                              bytes,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stack) =>
                                  _imageError('图片解析失败'),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 26, color: AstraColors.err),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 12, color: AstraColors.err)),
        ],
      ),
    );
  }

  Widget _binaryPlaceholder(HttpResult result, String type) {
    final mime = type.split(';').first.trim();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            border: Border.all(color: AstraColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AstraColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.insert_drive_file_outlined,
                    size: 22, color: AstraColors.accent),
              ),
              const SizedBox(height: 14),
              const Text(
                '二进制响应',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '${mime.isEmpty ? 'application/octet-stream' : mime} · ${formatBytes(result.size)}',
                textAlign: TextAlign.center,
                style: monoStyle(size: 10.8, color: AstraColors.faint),
              ),
              const SizedBox(height: 6),
              const Text(
                '该内容无法以文本展示，可下载到本地查看',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AstraColors.muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: '保存到本地',
                icon: Icons.download_rounded,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                onPressed: () => _saveResponse(result),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoStyle(size: 10, color: AstraColors.muted),
      ),
    );
  }

  Widget _viewTogglePair({
    required String leftLabel,
    required String rightLabel,
    required bool leftActive,
    required ValueChanged<bool> onSelect,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pairChip(leftLabel, leftActive, () => onSelect(true)),
          _pairChip(rightLabel, !leftActive, () => onSelect(false)),
        ],
      ),
    );
  }

  Widget _pairChip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: active ? AstraColors.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: active ? AstraColors.accent : AstraColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _downloadButton(HttpResult result) {
    return Tooltip(
      message: '下载响应内容',
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _saveResponse(result),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.download_rounded, size: 14, color: AstraColors.muted),
        ),
      ),
    );
  }

  Future<void> _saveResponse(HttpResult result) async {
    final type = result.header('content-type') ?? '';
    final name = _suggestFileName(type);
    try {
      final path = await saveBytesFile(name, Uint8List.fromList(result.bytes), type);
      if (path != null) state.showToast('已保存到 $path');
    } catch (err) {
      state.showToast('保存失败：$err');
    }
  }

  String _suggestFileName(String type) {
    if (type.contains('json')) return 'response.json';
    if (type.contains('html')) return 'response.html';
    if (type.contains('xml')) return 'response.xml';
    if (type.contains('image/png')) return 'response.png';
    if (type.contains('image/jpeg')) return 'response.jpg';
    if (type.contains('image/gif')) return 'response.gif';
    if (type.contains('image/webp')) return 'response.webp';
    if (type.contains('svg')) return 'response.svg';
    if (type.contains('pdf')) return 'response.pdf';
    if (type.startsWith('text/')) return 'response.txt';
    return 'response.bin';
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 14, color: AstraColors.muted),
        ),
      ),
    );
  }

  Widget _cookiesPanel() {
    final list = state.responseCookies;
    if (list.isEmpty) {
      return const EmptyHint(
        icon: Icons.cookie_outlined,
        title: '没有收到 Cookie',
        subtitle: '响应中的 Set-Cookie 会显示在这里',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              const Icon(Icons.cookie_outlined, size: 13, color: AstraColors.accent),
              const SizedBox(width: 6),
              Text(
                '${list.length} 个 Cookie',
                style: const TextStyle(fontSize: 11, color: AstraColors.muted),
              ),
              const Spacer(),
              CopyButton(
                text: list
                    .map((item) =>
                        '${item.name}=${item.value}; domain=${item.domain}; path=${item.path}')
                    .join('\n'),
                tooltip: '复制全部 Cookie',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final cookie = list[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x06FFFFFF),
                  border: Border.all(color: AstraColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cookie.name,
                            style: monoStyle(size: 11.5, color: AstraColors.accent),
                          ),
                        ),
                        if (cookie.secure)
                          const _CookieTag('Secure', Color(0xFF4ADE80)),
                        if (cookie.httpOnly) const _CookieTag('HttpOnly', Color(0xFF60A5FA)),
                        if (cookie.expired)
                          const _CookieTag('已过期', AstraColors.err),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      cookie.value,
                      style: monoStyle(size: 11, color: const Color(0xFFD6DEF0), height: 1.5),
                    ),
                    if (cookie.domain.isNotEmpty || cookie.path.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${cookie.domain.isEmpty ? '-' : cookie.domain}${cookie.path}',
                        style: monoStyle(size: 10, color: AstraColors.faint),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ssePanel() {
    final events = state.sseLog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              Icon(
                state.sseRunning ? Icons.sensors : Icons.sensors_off,
                size: 13,
                color: state.sseRunning ? AstraColors.ok : AstraColors.faint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  state.sseStatus ?? '等待事件…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: state.sseRunning ? AstraColors.ok : AstraColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${events.length} 条事件',
                style: const TextStyle(fontSize: 10.5, color: AstraColors.faint),
              ),
              const Spacer(),
              CopyButton(
                text: events
                    .map((item) => 'event: ${item.event}\ndata: ${item.data}')
                    .join('\n\n'),
                tooltip: '复制事件流',
              ),
            ],
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? const Center(
                  child: Text(
                    '等待服务端推送事件…',
                    style: TextStyle(fontSize: 11.5, color: AstraColors.faint),
                  ),
                )
              : ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final time = event.time;
                    final stamp =
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 58,
                            child: Text(
                              stamp,
                              style: monoStyle(size: 10, color: AstraColors.faint),
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AstraColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event.event,
                              style: monoStyle(size: 9.5, color: AstraColors.accent),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              event.data,
                              style: monoStyle(
                                size: 11.2,
                                color: const Color(0xFFD6DEF0),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _scriptResultPanel() {
    final logs = state.scriptLogs;
    final tests = state.scriptTests;
    final error = state.scriptError;
    if (!state.scriptRan) {
      return const EmptyHint(
        icon: Icons.code_rounded,
        title: '尚未执行脚本',
        subtitle: '在请求的 Scripts 标签中填写前置 / 后置脚本\n发送请求后会在这里显示控制台输出与断言结果',
      );
    }
    if (error == null && logs.isEmpty && tests.isEmpty) {
      return const EmptyHint(
        icon: Icons.check_circle_outline,
        title: '脚本执行完成',
        subtitle: '没有控制台输出，也没有断言结果',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x14F87171),
                border: Border.all(color: const Color(0x3DF87171)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: AstraColors.err),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      error,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AstraColors.err,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (tests.isNotEmpty) ...[
            const SectionLabel('断言结果'),
            ...tests.map((test) {
              final color = test.passed ? const Color(0xFF4ADE80) : AstraColors.err;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      test.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                      size: 13,
                      color: color,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            test.name,
                            style: TextStyle(fontSize: 11.5, color: color, height: 1.45),
                          ),
                          if (test.error != null)
                            Text(
                              test.error!,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AstraColors.muted,
                                height: 1.45,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
          if (logs.isNotEmpty) ...[
            const SectionLabel('控制台'),
            ...logs.map((log) {
              final color = switch (log.level) {
                'warn' => AstraColors.warn,
                'error' => AstraColors.err,
                _ => const Color(0xFFD6DEF0),
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        log.level,
                        style: monoStyle(size: 10, color: AstraColors.faint),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        log.message.isEmpty ? '(空)' : log.message,
                        style: monoStyle(size: 11.3, color: color, height: 1.55),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _textBlock(String text) {
    final clipped = text.length > 4000000 ? '${text.substring(0, 4000000)}\n\n… 内容过长，已截断显示' : text;
    final show = clipped.isEmpty ? '(空响应)' : clipped;
    final lines = show.split('\n');
    if (lines.length <= 400) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Container(
          alignment: Alignment.topLeft,
          width: double.infinity,
          child: SelectableText(
            show,
            textAlign: TextAlign.left,
            style: monoStyle(size: 11.8, height: 1.6, color: const Color(0xFFD6DEF0)),
          ),
        ),
      );
    }
    // 大响应按行虚拟滚动，避免一次性构建整段文本造成卡顿
    return ListView.builder(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) => SelectableText(
        lines[index].isEmpty ? ' ' : lines[index],
        style: monoStyle(size: 11.8, height: 1.6, color: const Color(0xFFD6DEF0)),
      ),
    );
  }
}

class _CookieTag extends StatelessWidget {
  final String label;
  final Color color;

  const _CookieTag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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

  const _MethodSelector({required this.value, required this.onChanged});

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
    return Container(
      width: 100,
      height: 32,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17),
        border: Border.all(color: AstraColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: methods.contains(value) ? value : 'GET',
          isDense: true,
          isExpanded: true,
          itemHeight: 34,
          dropdownColor: AstraColors.surface2,
          borderRadius: BorderRadius.circular(10),
          menuMaxHeight: 340,
          icon: const Icon(Icons.expand_more, size: 15, color: AstraColors.faint),
          style: monoStyle(size: 13, weight: FontWeight.w700),
          items: methods
              .map((method) => DropdownMenuItem<String>(
                    value: method,
                    child: Text(method, style: monoStyle(size: 13, color: methodColor(method), weight: FontWeight.w700)),
                  ))
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
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

  const _FormDataEditor({required this.rows, required this.onChanged});

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
              textStyle: const TextStyle(fontSize: 11.5),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('添加字段'),
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

  const _FormDataRow({
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
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Transform.scale(
              scale: 0.78,
              child: Checkbox(
                value: row.on,
                activeColor: AstraColors.accent,
                side: const BorderSide(color: AstraColors.lineStrong),
                onChanged: (value) {
                  setState(() => row.on = value ?? false);
                  widget.onChanged();
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _key,
              style: monoStyle(size: 12),
              decoration: astraInput(
                hint: '字段名',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onChanged: (value) {
                row.k = value;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(width: 7),
          GestureDetector(
            onTap: () {
              setState(() => row.type = isFile ? 'text' : 'file');
              widget.onChanged();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
              decoration: BoxDecoration(
                color: isFile ? const Color(0x1F8B5CF6) : const Color(0x0AFFFFFF),
                border: Border.all(color: isFile ? const Color(0x408B5CF6) : AstraColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isFile ? '文件' : '文本',
                style: TextStyle(
                  fontSize: 11,
                  color: isFile ? const Color(0xFFC4B5FD) : AstraColors.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            flex: 8,
            child: isFile
                ? _fileBox(row)
                : TextField(
                    controller: _value,
                    style: monoStyle(size: 12),
                    decoration: astraInput(
                      hint: '字段值（支持 {{变量}}）',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
              tooltip: '删除该行',
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close, size: 15),
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F17),
          border: Border.all(color: ready ? const Color(0x408B5CF6) : AstraColors.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(
              ready ? Icons.insert_drive_file_outlined : Icons.upload_file_outlined,
              size: 15,
              color: ready ? const Color(0xFFC4B5FD) : AstraColors.faint,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                file == null
                    ? '选择文件'
                    : file.usable
                        ? '${file.name} · ${formatBytes(file.size)}'
                        : '${file.name}（需重新选择）',
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
