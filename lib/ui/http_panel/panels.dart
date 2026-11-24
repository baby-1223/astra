part of '../http_panel.dart';

/* 响应侧面板 */

Widget _cookiesPanel(AppState state) {
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

Widget _ssePanel(AppState state) {
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

Widget _scriptResultPanel(AppState state) {
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
