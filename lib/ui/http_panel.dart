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

List<String> _commonHeaders = [
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

  HttpView({super.key, required this.state});

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
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.enter, meta: true): () => state.send(),
          SingleActivator(LogicalKeyboardKey.enter, control: true): () => state.send(),
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
                    hint: 'API name',
                    fontSize: 13,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    onChanged: state.renameActive,
                    onSubmitted: (_) => state.saveActive(),
                  ),
                ),
              ),
              Spacer(),
              PopupMenuButton<String>(
                tooltip: 'cURL',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                onSelected: (value) async {
                  if (value == 'import') {
                    await showCurlImportDialog(context, state);
                  } else {
                    await Clipboard.setData(ClipboardData(text: state.curlFor(state.request)));
                    state.showToast('cURL copied to clipboard');
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'import', height: 38, child: Text('Import from cURL')),
                  PopupMenuItem(value: 'export', height: 38, child: Text('Copy as cURL')),
                ],
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AstraColors.line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.terminal_rounded, size: 12, color: AstraColors.muted),
                      SizedBox(width: 5),
                      Text('cURL', style: TextStyle(fontSize: 10.5, color: AstraColors.muted)),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
              _iconAction(
                icon: Icons.visibility_outlined,
                tooltip: 'Preview final request',
                onPressed: () => showRequestPreviewDialog(context, state),
              ),
              _iconAction(
                icon: Icons.data_object,
                tooltip: 'Variables panel',
                onPressed: () => showVariablesDialog(context, state),
              ),
              _iconAction(
                icon: Icons.playlist_play,
                tooltip: 'Collection runner',
                onPressed: () => showRunnerDialog(context, state),
              ),
              SizedBox(width: 4),
              Text(
                '⌘ / Ctrl + S to save',
                style: TextStyle(fontSize: 10, color: AstraColors.faint),
              ),
            ],
          ),
          SizedBox(height: 12),
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
              SizedBox(width: 9),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: BoundTextField(
                    value: req.url,
                    hint: 'https://api.example.com/users or {{baseUrl}}/users',
                    fontSize: 13,
                    varNames: state.varNames,
                    contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    onChanged: (value) {
                      req.url = value;
                      state.touch();
                    },
                  ),
                ),
              ),
              SizedBox(width: 9),
              GradientButton(
                label: state.sending ? 'Sending' : 'Send',
                icon: state.sending ? null : Icons.send_rounded,
                onPressed: state.sending ? null : state.send,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AstraTabs(
                  selected: _reqTab,
                  onSelect: (id) => setState(() => _reqTab = id),
                  items: [
                    AstraTabItem('params',
                        'Params', count: req.params.where((e) => e.on && e.k.isNotEmpty).length),
                    AstraTabItem('headers',
                        'Headers', count: req.headers.where((e) => e.on && e.k.isNotEmpty).length),
                    AstraTabItem('body',
                        'Body${req.bodyMode == 'none' ? '' : ' · ${_bodyLabel(req.bodyMode)}'}'),
                    AstraTabItem('auth',
                        req.auth.type == 'none' ? 'Authorization' : 'Authorization · ${_authLabel(req.auth.type)}'),
                    AstraTabItem('scripts', 'Scripts'),
                    AstraTabItem('options', 'Options'),
                  ],
                ),
              ),
              if (req.method == 'GET' || req.method == 'HEAD')
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    '${req.method} requests have no body',
                    style: TextStyle(fontSize: 10, color: AstraColors.faint),
                  ),
                ),
            ],
          ),
          Divider(height: 1, color: AstraColors.line),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: 12, bottom: 4),
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
        return 'Text';
      case 'form':
        return 'Form';
      case 'form-data':
        return 'Multipart form';
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
        return 'Inherited';
    }
    return type;
  }

  Widget _requestTabContent() {
    final req = state.request;
    switch (_reqTab) {
      case 'headers':
        return KVEditor(
          rows: req.headers,
          keyHint: 'Header name',
          valueHint: 'Header value (supports {{variables}})',
          varNames: state.varNames,
          keySuggestions: _commonHeaders,
          onBulkEdit: () => showBulkEditDialog(
            context,
            title: 'Bulk edit headers',
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
          keyHint: 'Query param',
          valueHint: 'Value (supports {{variables}})',
          varNames: state.varNames,
          onBulkEdit: () => showBulkEditDialog(
            context,
            title: 'Bulk edit query params',
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
      ['none', 'None'],
      ['json', 'JSON'],
      ['text', 'Text'],
      ['form', 'Form'],
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
              padding: EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AstraColors.overlay,
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
                      duration: Duration(milliseconds: 150),
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: active ? AstraColors.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: active ? AstraColors.accentBorder : Colors.transparent,
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
            Spacer(),
            if (req.bodyMode == 'json')
              TextButton.icon(
                onPressed: () {
                  try {
                    final pretty =
                        JsonEncoder.withIndent('  ').convert(jsonDecode(req.body));
                    setState(() => req.body = pretty);
                    state.touch();
                  } catch (_) {
                    state.showToast('Invalid JSON, cannot format');
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AstraColors.muted,
                  textStyle: TextStyle(fontSize: 11),
                ),
                icon: Icon(Icons.auto_fix_high, size: 13),
                label: Text('Format JSON'),
              ),
          ],
        ),
        SizedBox(height: 10),
        if (req.bodyMode == 'none')
          Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'This request has no body',
              style: TextStyle(fontSize: 12, color: AstraColors.faint),
            ),
          )
        else if (req.bodyMode == 'json' || req.bodyMode == 'text')
          BoundTextField(
            value: req.body,
            hint: req.bodyMode == 'json' ? '{\n  "name": "Astra"\n}' : 'Plain text content',
            minLines: 8,
            maxLines: 16,
            fontSize: 12,
            lineHeight: 1.55,
            varNames: state.varNames,
            contentPadding: EdgeInsets.all(12),
            onChanged: (value) {
              req.body = value;
              state.touch();
            },
          )
        else if (req.bodyMode == 'form')
          KVEditor(
            rows: req.form,
            keyHint: 'Field name',
            valueHint: 'Field value (supports {{variables}})',
            varNames: state.varNames,
            onBulkEdit: () => showBulkEditDialog(
              context,
              title: 'Bulk edit form fields',
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
              SectionLabel('Query', hint: 'Supports {{variables}}; sent as a GraphQL request automatically'),
              SizedBox(height: 8),
              BoundTextField(
                value: req.graphqlQuery,
                hint: 'query Users(\$limit: Int) {\n  users(limit: \$limit) { id name }\n}',
                minLines: 6,
                maxLines: 10,
                fontSize: 12,
                lineHeight: 1.55,
                varNames: state.varNames,
                contentPadding: EdgeInsets.all(12),
                onChanged: (value) {
                  req.graphqlQuery = value;
                  state.touch();
                },
              ),
              SizedBox(height: 12),
              SectionLabel('Variables', hint: 'JSON object, e.g. {"limit": 10}'),
              SizedBox(height: 8),
              BoundTextField(
                value: req.graphqlVars,
                hint: '{\n  "limit": 10\n}',
                minLines: 3,
                maxLines: 6,
                fontSize: 12,
                lineHeight: 1.55,
                varNames: state.varNames,
                contentPadding: EdgeInsets.all(12),
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
                label: 'Payload type',
                options: [
                  ['binary', 'Base64 Protobuf'],
                  ['json', 'JSON text'],
                ],
                value: req.grpcBinary ? 'binary' : 'json',
                onSelect: (value) {
                  setState(() => req.grpcBinary = value == 'binary');
                  state.touch();
                },
              ),
              SizedBox(height: 10),
              BoundTextField(
                value: req.grpcPayload,
                hint: req.grpcBinary
                    ? 'Paste a base64-encoded protobuf message'
                    : '{"message": "hello"}',
                minLines: 6,
                maxLines: 12,
                fontSize: 12,
                lineHeight: 1.55,
                varNames: state.varNames,
                contentPadding: EdgeInsets.all(12),
                onChanged: (value) {
                  req.grpcPayload = value;
                  state.touch();
                },
              ),
              SizedBox(height: 8),
              Text(
                'Sends gRPC-Web frames (5-byte header + payload) to the URL above; '
                'responses are parsed frame by frame. Intended for services behind an '
                'Envoy / grpc-web proxy.',
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
      ['inherit', 'Inherit from parent'],
      ['none', 'No authorization'],
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
                padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AstraColors.accentSoft : AstraColors.overlay,
                  border: Border.all(
                    color: active ? AstraColors.accentBorder : AstraColors.line,
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
          SizedBox(height: 14),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AstraColors.accentSoft,
              border: Border.all(color: AstraColors.accentBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: AstraColors.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Using the authorization from ${state.authSourceLabel(req)}'
                    '${inherited.type == 'none' ? ' (not configured)' : ' · ${_authLabel(inherited.type)}'}',
                    style: TextStyle(
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
                    textStyle: TextStyle(fontSize: 10.5),
                    padding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('Manage collection variables'),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: 14),
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
            hint: 'Token (supports {{token}})',
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
                  hint: 'Username',
                  onChanged: (value) {
                    req.auth.username = value;
                    state.touch();
                  },
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: BoundTextField(
                  value: req.auth.password,
                  hint: 'Password',
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
                  hint: 'Key name, e.g. X-API-Key',
                  onChanged: (value) {
                    req.auth.apiKeyName = value;
                    state.touch();
                  },
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: BoundTextField(
                  value: req.auth.apiKeyValue,
                  hint: 'Key value (supports {{variables}})',
                  onChanged: (value) {
                    req.auth.apiKeyValue = value;
                    state.touch();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          _miniSegments(
            label: 'Add to',
            options: [['header', 'Header'], ['query', 'Query param']],
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
        return [];
      default:
        return [
          Text('Authorization disabled', style: TextStyle(fontSize: 12, color: AstraColors.faint)),
        ];
    }
  }

  List<Widget> _oauthFields(ApiRequest req) {
    final auth = req.auth;
    return [
      _miniSegments(
        label: 'Grant type',
        options: [
          ['client_credentials', 'Client Credentials'],
          ['password', 'Password'],
          ['authorization_code', 'Authorization code + PKCE'],
        ],
        value: auth.oauthGrantType,
        onSelect: (value) {
          setState(() => auth.oauthGrantType = value);
          state.touch();
        },
      ),
      if (auth.oauthGrantType == 'authorization_code') ...[
        SizedBox(height: 10),
        BoundTextField(
          value: auth.oauthAuthUrl,
          hint: 'Authorization endpoint, e.g. https://demo.com/oauth/authorize',
          varNames: state.varNames,
          onChanged: (value) {
            auth.oauthAuthUrl = value;
            state.touch();
          },
        ),
        SizedBox(height: 6),
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
            Text('Use PKCE (S256)', style: TextStyle(fontSize: 11, color: AstraColors.muted)),
            SizedBox(width: 12),
            Text(
              'Callback http://127.0.0.1:8765/callback',
              style: TextStyle(fontSize: 10, color: AstraColors.faint),
            ),
          ],
        ),
      ],
      SizedBox(height: 10),
      BoundTextField(
        value: auth.oauthTokenUrl,
        hint: 'Token endpoint, e.g. https://api.demo.com/oauth/token',
        varNames: state.varNames,
        onChanged: (value) {
          auth.oauthTokenUrl = value;
          state.touch();
        },
      ),
      SizedBox(height: 10),
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
          SizedBox(width: 10),
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
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BoundTextField(
                value: auth.username,
                hint: 'Username',
                onChanged: (value) {
                  auth.username = value;
                  state.touch();
                },
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: BoundTextField(
                value: auth.password,
                hint: 'Password',
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
      SizedBox(height: 10),
      BoundTextField(
        value: auth.oauthScope,
        hint: 'Scope (optional, space-separated)',
        onChanged: (value) {
          auth.oauthScope = value;
          state.touch();
        },
      ),
      SizedBox(height: 12),
      Row(
        children: [
          GhostButton(
            label: _oauthBusy ? 'Fetching…' : 'Get token',
            icon: Icons.vpn_key_outlined,
            padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            onPressed: _oauthBusy
                ? null
                : () async {
                    setState(() => _oauthBusy = true);
                    final error = await state.fetchOAuthToken(req);
                    if (!mounted) return;
                    setState(() => _oauthBusy = false);
                    state.showToast(error ?? 'access_token obtained');
                  },
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.token.isEmpty
                      ? 'No token yet. Fetch one or enter it manually before sending.'
                      : 'Obtained: ${_maskToken(auth.token)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: auth.token.isEmpty ? AstraColors.faint : AstraColors.ok,
                  ),
                ),
                if (auth.oauthExpiresAt > 0)
                  Text(
                    '${auth.oauthExpired ? 'Expired' : 'Expires at'} '
                    '${_timeText(auth.oauthExpiresAt)}'
                    '${auth.oauthRefreshToken.isEmpty ? '' : ' · Auto-refresh enabled'}',
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
                      state.showToast(error ?? 'access_token obtained');
                    },
              style: TextButton.styleFrom(
                foregroundColor: AstraColors.muted,
                textStyle: TextStyle(fontSize: 10.5),
              ),
              child: Text('Force refresh'),
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
          child: Text(label, style: TextStyle(fontSize: 11.5, color: AstraColors.muted)),
        ),
        ...options.map((option) {
          final active = value == option[0];
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(option[0]),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? AstraColors.accentSoft : AstraColors.overlay,
                  border: Border.all(color: active ? AstraColors.accentBorder : AstraColors.line),
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
              SizedBox(width: 12),
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
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: AstraColors.line),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+ ${template[0]}',
                          style: TextStyle(fontSize: 10.5, color: AstraColors.muted),
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
      ['Timestamp', 'pm.environment.set("ts", Date.now());'],
      ['Random', 'pm.environment.set("nonce", Math.random().toString(36).slice(2));'],
      ['Add header', 'pm.request.headers.add({ key: "X-Debug", value: "1" });'],
    ];
    const postTemplates = [
      ['Assert 200', 'pm.test("status is 200", () => pm.response.to.have.status(200));'],
      ['Assert JSON', 'pm.test("returns JSON", () => {\n  pm.expect(pm.response.json()).to.be.an("object");\n});'],
      ['Save variable',
        'const data = pm.response.json();\npm.environment.set("token", data.token || "");'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AstraColors.accentSoft,
            border: Border.all(color: AstraColors.accentBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, size: 14, color: AstraColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scripts run in a local JavaScript engine with pm.environment / pm.variables / pm.request / pm.response / pm.test / console.log. Results appear in the Scripts tab of the response area.',
                  style: TextStyle(fontSize: 10.5, color: AstraColors.muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        editor(
          'Pre-request script',
          '// Runs before sending, e.g.:\n// pm.environment.set("ts", Date.now());\n// pm.request.headers.add({ key: "X-Debug", value: "1" });',
          req.preScript,
          (value) {
            req.preScript = value;
            state.touch();
            setState(() {});
          },
          templates: preTemplates,
        ),
        SizedBox(height: 10),
        editor(
          'Post-response script',
          '// Runs after the response returns, e.g.:\n// pm.test("status is 200", () => pm.response.to.have.status(200));\n// console.log(pm.response.json());',
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
        padding: EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12.5)),
                  SizedBox(height: 2),
                  Text(desc, style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
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
        toggle('Follow redirects', 'Follow 3xx responses; handled by the underlying client', req.options.followRedirects,
            (value) => req.options.followRedirects = value),
        toggle('Verify TLS certificate', 'Turn off to access test servers with self-signed certificates', req.options.rejectUnauthorized,
            (value) => req.options.rejectUnauthorized = value),
        toggle('Manage cookies automatically', 'Store Set-Cookie from responses and send it with later requests', req.options.manageCookies,
            (value) => req.options.manageCookies = value),
        toggle('Stream events', 'Receive text/event-stream responses event by event instead of waiting for the full response',
            req.options.streamSse, (value) => req.options.streamSse = value),
        Padding(
          padding: EdgeInsets.only(top: 2, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Proxy and client certificates', style: TextStyle(fontSize: 12.5)),
                    SizedBox(height: 2),
                    Text('HTTP / SOCKS5 proxy and mTLS certificates, applied to all requests',
                        style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
                  ],
                ),
              ),
              GhostButton(
                label: state.settings.proxyEnabled || state.settings.hasClientCert
                    ? 'Configured'
                    : 'Configure',
                icon: Icons.lan_outlined,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: () => showNetworkSettingsDialog(context, state),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Timeout', style: TextStyle(fontSize: 12.5)),
                    SizedBox(height: 2),
                    Text('In seconds; 0 means no limit', style: TextStyle(fontSize: 10.5, color: AstraColors.faint)),
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
              SizedBox(width: 8),
              Text('s', style: TextStyle(fontSize: 11.5, color: AstraColors.muted)),
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
      padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Response',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              SizedBox(width: 12),
              if (state.sending)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AstraColors.accent),
                )
              else if (result != null) ...[
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                SizedBox(width: 10),
                Text(
                  '${result.ms} ms',
                  style: TextStyle(fontSize: 11, color: AstraColors.muted),
                ),
                SizedBox(width: 10),
                Text(
                  formatBytes(result.size),
                  style: TextStyle(fontSize: 11, color: AstraColors.muted),
                ),
              ],
              if (state.scriptRan && (failedTests > 0 || state.scriptError != null)) ...[
                SizedBox(width: 10),
                Icon(Icons.error_outline, size: 13, color: AstraColors.err),
                SizedBox(width: 4),
                Text(
                  state.scriptError != null ? 'Script error' : '$failedTests assertion failures',
                  style: TextStyle(fontSize: 10.5, color: AstraColors.err),
                ),
              ],
              if (state.sseRunning) ...[
                SizedBox(width: 10),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: AstraColors.ok),
                ),
              ],
              Spacer(),
              if (state.responseHistory.length > 1)
                _iconAction(
                  icon: Icons.compare_arrows,
                  tooltip: 'Compare last two responses',
                  onPressed: () => showTextDiffDialog(
                    context,
                    title: 'Response diff',
                    before: state.responseHistory[1].prettyBody,
                    after: state.responseHistory[0].prettyBody,
                    beforeLabel: 'Previous · ${state.responseHistory[1].status}',
                    afterLabel: 'Current · ${state.responseHistory[0].status}',
                  ),
                ),
              if (result != null && state.selectedId != null)
                _iconAction(
                  icon: Icons.bookmark_add_outlined,
                  tooltip: 'Save as example',
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
                  tooltip: 'Copy response',
                ),
            ],
          ),
          SizedBox(height: 8),
          if (hasTabs)
            Row(
              children: [
                Flexible(
                  child: AstraTabs(
                    compact: true,
                    selected: _respTab,
                    onSelect: (id) => setState(() => _respTab = id),
                    items: [
                      if (result != null) AstraTabItem('body', 'Body'),
                      if (result != null) AstraTabItem('headers', 'Headers'),
                      if (state.responseCookies.isNotEmpty)
                        AstraTabItem(
                          'cookies',
                          'Cookies',
                          count: state.responseCookies.length,
                        ),
                      if (result != null) AstraTabItem('raw', 'Raw'),
                      if (sseActive)
                        AstraTabItem('sse', 'Events', count: state.sseLog.length),
                      if (state.scriptRan)
                        AstraTabItem(
                          'scripts',
                          'Scripts',
                          count: state.scriptTests.isEmpty ? null : state.scriptTests.length,
                        ),
                    ],
                  ),
                ),
                if (result != null &&
                    _respTab == 'body' &&
                    _decodedJson != null) ...[
                  SizedBox(width: 6),
                  _viewToggle(),
                ],
                if (sseActive) ...[
                  SizedBox(width: 8),
                  GhostButton(
                    label: state.sseRunning ? 'Stop' : 'Reconnect',
                    icon: state.sseRunning ? Icons.stop_circle_outlined : Icons.sync,
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    onPressed: state.sseRunning ? state.stopSse : state.startSse,
                  ),
                ],
              ],
            ),
          SizedBox(height: 8),
          Divider(height: 1, color: AstraColors.line),
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
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 17, color: AstraColors.err),
            SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                error,
                style: TextStyle(fontSize: 12, color: AstraColors.err, height: 1.6),
              ),
            ),
          ],
        ),
      );
    }
    final result = state.response;
    if (result == null) {
      return EmptyHint(
        icon: Icons.bolt_rounded,
        title: 'Waiting for a request',
        subtitle: 'Enter a URL and click Send, or press ⌘/Ctrl + Enter\nThe status, timing and content will appear here',
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
            padding: EdgeInsets.only(top: 8, bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 230,
                  height: 33,
                  child: BoundTextField(
                    value: _headerFilter.text,
                    hint: 'Filter response headers',
                    fontSize: 11.5,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    onChanged: (value) {
                      _headerFilter.text = value;
                      setState(() {});
                    },
                  ),
                ),
                SizedBox(width: 8),
                GhostButton(
                  label: _headerSortAsc ? 'Name ↑' : 'Name ↓',
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  onPressed: () => setState(() => _headerSortAsc = !_headerSortAsc),
                ),
                Spacer(),
                Text(
                  '${entries.length} response headers',
                  style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
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
                  padding: EdgeInsets.only(bottom: 7),
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
                      SizedBox(width: 8),
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
      buffer.write(result.text ?? '[binary content ${formatBytes(result.size)}]');
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
          _viewChip('Tree', 'tree'),
          _viewChip('Text', 'text'),
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
          padding: EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: 14, color: AstraColors.accent),
              SizedBox(width: 6),
              Text('Image preview', style: TextStyle(fontSize: 11.5, color: AstraColors.text)),
              SizedBox(width: 10),
              Flexible(child: _metaChip(type)),
              SizedBox(width: 8),
              Text(formatBytes(result.size),
                  style: monoStyle(size: 10.5, color: AstraColors.faint)),
              Spacer(),
              _viewTogglePair(
                leftLabel: 'Fit',
                rightLabel: 'Actual size',
                leftActive: _imageFit,
                onSelect: (fit) => setState(() => _imageFit = fit),
              ),
              SizedBox(width: 8),
              GhostButton(
                label: 'Save image',
                icon: Icons.download_rounded,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: () => _saveResponse(result),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AstraColors.inset,
              border: Border.all(color: AstraColors.line),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GridPaper(
                    color: AstraColors.overlay,
                    interval: 24,
                    divisions: 2,
                    subdivisions: 2,
                    child: SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: _imageFit
                      ? Padding(
                          padding: EdgeInsets.all(14),
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stack) =>
                                _imageError('Failed to decode image'),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.all(14),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Image.memory(
                              bytes,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stack) =>
                                  _imageError('Failed to decode image'),
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
          Icon(Icons.broken_image_outlined, size: 26, color: AstraColors.err),
          SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 12, color: AstraColors.err)),
        ],
      ),
    );
  }

  Widget _binaryPlaceholder(HttpResult result, String type) {
    final mime = type.split(';').first.trim();
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: AstraColors.overlay,
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
                child: Icon(Icons.insert_drive_file_outlined,
                    size: 22, color: AstraColors.accent),
              ),
              SizedBox(height: 14),
              Text(
                'Binary response',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                '${mime.isEmpty ? 'application/octet-stream' : mime} · ${formatBytes(result.size)}',
                textAlign: TextAlign.center,
                style: monoStyle(size: 10.8, color: AstraColors.faint),
              ),
              SizedBox(height: 6),
              Text(
                'This content cannot be displayed as text. Download it to view locally.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AstraColors.muted, height: 1.5),
              ),
              SizedBox(height: 16),
              GradientButton(
                label: 'Save to disk',
                icon: Icons.download_rounded,
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
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
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AstraColors.overlay,
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
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
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
      message: 'Download response content',
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _saveResponse(result),
        child: Padding(
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
      if (path != null) state.showToast('Saved to $path');
    } catch (err) {
      state.showToast('Save failed: $err');
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
          padding: EdgeInsets.all(6),
          child: Icon(icon, size: 14, color: AstraColors.muted),
        ),
      ),
    );
  }

  Widget _cookiesPanel() {
    final list = state.responseCookies;
    if (list.isEmpty) {
      return EmptyHint(
        icon: Icons.cookie_outlined,
        title: 'No cookies received',
        subtitle: 'Set-Cookie headers from the response will appear here',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              Icon(Icons.cookie_outlined, size: 13, color: AstraColors.accent),
              SizedBox(width: 6),
              Text(
                '${list.length} cookies',
                style: TextStyle(fontSize: 11, color: AstraColors.muted),
              ),
              Spacer(),
              CopyButton(
                text: list
                    .map((item) =>
                        '${item.name}=${item.value}; domain=${item.domain}; path=${item.path}')
                    .join('\n'),
                tooltip: 'Copy all cookies',
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
                margin: EdgeInsets.only(bottom: 7),
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AstraColors.overlay,
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
                          _CookieTag('Secure', AstraColors.ok),
                        if (cookie.httpOnly) _CookieTag('HttpOnly', AstraColors.accent),
                        if (cookie.expired)
                          _CookieTag('Expired', AstraColors.err),
                      ],
                    ),
                    SizedBox(height: 4),
                    SelectableText(
                      cookie.value,
                      style: monoStyle(size: 11, color: AstraColors.codeText, height: 1.5),
                    ),
                    if (cookie.domain.isNotEmpty || cookie.path.isNotEmpty) ...[
                      SizedBox(height: 3),
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
          padding: EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              Icon(
                state.sseRunning ? Icons.sensors : Icons.sensors_off,
                size: 13,
                color: state.sseRunning ? AstraColors.ok : AstraColors.faint,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  state.sseStatus ?? 'Waiting for events…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: state.sseRunning ? AstraColors.ok : AstraColors.muted,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '${events.length} events',
                style: TextStyle(fontSize: 10.5, color: AstraColors.faint),
              ),
              Spacer(),
              CopyButton(
                text: events
                    .map((item) => 'event: ${item.event}\ndata: ${item.data}')
                    .join('\n\n'),
                tooltip: 'Copy event stream',
              ),
            ],
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Text(
                    'Waiting for server events…',
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
                      padding: EdgeInsets.only(bottom: 7),
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
                                EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AstraColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event.event,
                              style: monoStyle(size: 9.5, color: AstraColors.accent),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              event.data,
                              style: monoStyle(
                                size: 11.2,
                                color: AstraColors.codeText,
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
      return EmptyHint(
        icon: Icons.code_rounded,
        title: 'No scripts run yet',
        subtitle: 'Add pre-request or post-response scripts in the Scripts tab\nConsole output and test results will appear here after sending',
      );
    }
    if (error == null && logs.isEmpty && tests.isEmpty) {
      return EmptyHint(
        icon: Icons.check_circle_outline,
        title: 'Script run complete',
        subtitle: 'No console output or test results',
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Container(
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AstraColors.errSoft,
                border: Border.all(color: AstraColors.errBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 14, color: AstraColors.err),
                  SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      error,
                      style: TextStyle(
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
            SectionLabel('Test results'),
            ...tests.map((test) {
              final color = test.passed ? AstraColors.ok : AstraColors.err;
              return Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      test.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                      size: 13,
                      color: color,
                    ),
                    SizedBox(width: 7),
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
                              style: TextStyle(
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
            SizedBox(height: 6),
          ],
          if (logs.isNotEmpty) ...[
            SectionLabel('Console'),
            ...logs.map((log) {
              final color = switch (log.level) {
                'warn' => AstraColors.warn,
                'error' => AstraColors.err,
                _ => AstraColors.codeText,
              };
              return Padding(
                padding: EdgeInsets.only(bottom: 4),
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
                        log.message.isEmpty ? '(empty)' : log.message,
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
    final clipped = text.length > 4000000 ? '${text.substring(0, 4000000)}\n\n… Content too long, truncated' : text;
    final show = clipped.isEmpty ? '(empty response)' : clipped;
    final lines = show.split('\n');
    if (lines.length <= 400) {
      return SingleChildScrollView(
        padding: EdgeInsets.only(top: 10, bottom: 8),
        child: Container(
          alignment: Alignment.topLeft,
          width: double.infinity,
          child: SelectableText(
            show,
            textAlign: TextAlign.left,
            style: monoStyle(size: 11.8, height: 1.6, color: AstraColors.codeText),
          ),
        ),
      );
    }
    // 大响应按行虚拟滚动，避免一次性构建整段文本造成卡顿
    return ListView.builder(
      padding: EdgeInsets.only(top: 10, bottom: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) => SelectableText(
        lines[index].isEmpty ? ' ' : lines[index],
        style: monoStyle(size: 11.8, height: 1.6, color: AstraColors.codeText),
      ),
    );
  }
}

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
