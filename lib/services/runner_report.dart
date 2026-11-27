import '../models.dart';

String _csvCell(String value) {
  final text = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
  if (text.contains(',') || text.contains('"')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// CSV report with one row per executed request.
String runnerReportCsv({
  required String collection,
  required DateTime startedAt,
  required List<RunStepResult> steps,
}) {
  final rows = <List<String>>[
    [
      'iteration',
      'request',
      'method',
      'status',
      'timeMs',
      'passed',
      'testsPassed',
      'testsTotal',
      'url',
      'error',
      'failures',
    ],
    for (final step in steps)
      [
        '${step.iteration}',
        step.name,
        step.method,
        step.status?.toString() ?? '',
        '${step.ms}',
        step.passed ? 'true' : 'false',
        '${step.testPassed}',
        '${step.testTotal}',
        step.url,
        step.error ?? '',
        step.failures.join('; '),
      ],
  ];
  return rows.map((row) => row.map(_csvCell).join(',')).join('\n');
}

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// JUnit XML report consumable by CI dashboards.
String runnerReportJunit({
  required String collection,
  required DateTime startedAt,
  required List<RunStepResult> steps,
}) {
  final failed = steps.where((step) => !step.passed).length;
  final totalMs = steps.fold<int>(0, (sum, step) => sum + step.ms);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
        '<testsuite name="${_xmlEscape(collection)}" tests="${steps.length}" failures="$failed" '
        'errors="0" time="${(totalMs / 1000).toStringAsFixed(3)}" '
        'timestamp="${startedAt.toUtc().toIso8601String()}">');
  for (final step in steps) {
    final name = '${step.iteration}. ${step.name}';
    buffer.write(
        '  <testcase classname="${_xmlEscape(collection)}" name="${_xmlEscape(name)}" '
        'time="${(step.ms / 1000).toStringAsFixed(3)}"');
    if (step.passed) {
      buffer.writeln('/>');
      continue;
    }
    final message = step.error ??
        (step.failures.isEmpty
            ? 'Request failed${step.status == null ? '' : ' with status ${step.status}'}'
            : step.failures.join('; '));
    buffer
      ..writeln('>')
      ..writeln('    <failure message="${_xmlEscape(message)}">')
      ..writeln('      ${_xmlEscape('${step.method} ${step.url}')}')
      ..writeln('    </failure>')
      ..writeln('  </testcase>');
  }
  buffer.writeln('</testsuite>');
  return buffer.toString();
}
