// SPDX-License-Identifier: AGPL-3.0-or-later

/// Turns a [MeterDiagnosticLog] into something a driver can send and a
/// developer can read.
///
/// Written in Mongolian rather than as bare data because the person who
/// presses share is the driver, and a screen of untranslated field names
/// asks them to forward something they cannot check. The rows underneath
/// are numbers either way.
///
/// The summary is deliberately ordered to answer one question first — *how
/// much distance did the app refuse, and under which rule* — because that
/// is the question the field test raised and every other figure here is
/// only context for it.
library;

import 'meter_diagnostics.dart';
import 'meter_fix_verdict.dart';

/// The interval `location_source.dart` asks Android for, in seconds. Quoted
/// in the report so a stalled stream is obvious by comparison rather than
/// requiring the reader to already know what normal looks like.
const double kRequestedFixIntervalSeconds = 5.0;

String _int(num value) {
  final digits = value.round().abs().toString();
  final sign = value < 0 ? '-' : '';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '$sign$buffer';
}

String _seconds(num seconds) => seconds.toStringAsFixed(1);

String _duration(int millis) {
  final total = millis ~/ 1000;
  final minutes = total ~/ 60;
  final rest = total % 60;
  if (minutes == 0) return '$rest с';
  return '$minutes м $rest с';
}

String _percent(double fraction) => '${(fraction * 100).round()}%';

/// One "how much was thrown away, and how often" line.
String _discardLine(MeterDiagnosticLog log, String label, MeterFixOutcome o) {
  final meters = log.discardedMetersBy(o);
  final count = log.countOf(o);
  return '    ${label.padRight(22)}${_int(meters).padLeft(7)} м  '
      '($count цэг)';
}

/// The human-readable summary.
String formatMeterDiagnosticReport(
  MeterDiagnosticLog log, {
  required String appVersion,
}) {
  if (log.isEmpty) {
    return 'Тахь — GPS оношилгоо\n'
        'Хувилбар: $appVersion\n\n'
        'Бичигдсэн цэг алга. Тоолуур ажиллуулаад дахин үзнэ үү.';
  }

  final buffer = StringBuffer()
    ..writeln('Тахь — GPS оношилгоо')
    ..writeln('Хувилбар: $appVersion')
    ..writeln(
      'Үргэлжилсэн: ${_duration(log.spanMillis)}  ·  '
      'Цэг: ${_int(log.recordedCount)}',
    )
    ..writeln()
    ..writeln('ЗАЙ')
    ..writeln('  GPS-ийн хэмжсэн:   ${_int(log.rawMeters).padLeft(8)} м')
    ..writeln(
      '  Тоологдсон:        ${_int(log.countedMeters).padLeft(8)} м  '
      '(${_percent(log.countedFraction)})',
    )
    ..writeln(
      '  Хаягдсан:          ${_int(log.discardedMeters).padLeft(8)} м  '
      '(${_percent(1 - log.countedFraction)})',
    )
    ..writeln(
      _discardLine(log, 'донслолтын босго', MeterFixOutcome.belowNoiseFloor),
    )
    ..writeln(
      _discardLine(log, 'нарийвчлал муу', MeterFixOutcome.accuracyTooPoor),
    )
    ..writeln(
      _discardLine(log, 'боломжгүй хурд', MeterFixOutcome.implausible),
    )
    ..writeln(
      _discardLine(log, 'түр зогсолтын зах', MeterFixOutcome.pauseBoundary),
    )
    ..writeln()
    ..writeln('ЦЭГИЙН ИРЭЛТ')
    ..writeln(
      '  Дундаж завсар:      ${_seconds(log.meanArrivalGapMillis / 1000)} с  '
      '(хүссэн: ${_seconds(kRequestedFixIntervalSeconds)} с)',
    )
    ..writeln(
      '  Хамгийн урт завсар: '
      '${_seconds(log.longestArrivalGapMillis / 1000)} с',
    )
    ..writeln(
      '  ${_seconds(kStalledArrivalMillis / 1000)} с-ээс урт тасалдал: '
      '${log.stalledArrivalCount} удаа',
    );

  if (log.stalledArrivalCount > 0) {
    buffer.writeln(
      '  → тасалдал байна: апп ард байхад GPS зогссон байж болзошгүй',
    );
  }

  buffer
    ..writeln()
    ..writeln('НАРИЙВЧЛАЛ БА БОСГО')
    ..writeln(
      '  Дундаж нарийвчлал:  ${_seconds(log.meanAccuracyMeters)} м  '
      '(хамгийн муу ${_int(log.worstAccuracyMeters)} м)',
    )
    ..writeln('  Дундаж босго:       ${_seconds(log.meanNoiseFloorMeters)} м');

  final threshold = log.billingSpeedThresholdKmh;
  if (threshold > 0) {
    buffer.writeln(
      '  → зай тоологдохын тулд ${_seconds(threshold)} км/ц-ээс '
      'хурдан явах шаардлагатай байсан',
    );
  }

  if (log.trimmedCount > 0) {
    buffer
      ..writeln()
      ..writeln(
        'Тэмдэглэл: эхний ${_int(log.trimmedCount)} цэгийн мөр хасагдсан '
        '(нийлбэр тоо бүрэн хэвээр).',
      );
  }

  return buffer.toString();
}

/// Column names for the row export, newline-terminated.
const String kMeterDiagnosticCsvHeader =
    'i,arrival_ms,fix_s,lat,lon,accuracy_m,seconds,'
    'raw_m,counted_m,floor_m,kmh,outcome\n';

/// Machine-readable rows for [samples].
///
/// Times are offsets from [firstArrivalMillis] / [firstFixSeconds] rather
/// than absolute clocks: the file is going to be pasted into a chat window,
/// and a driver's exact whereabouts at an exact wall-clock second is not
/// something this project asks anyone to hand over to read a bug report.
/// The coordinates are still there — they have to be, the route is the
/// evidence — but nothing else in the row helps place the driver in time.
///
/// Takes explicit baselines and a [startIndex] so a run can be flushed to
/// disk in batches as it happens and still read back as one continuous,
/// correctly numbered file.
String formatMeterDiagnosticCsvRows(
  Iterable<MeterDiagnosticSample> samples, {
  required int firstArrivalMillis,
  required int firstFixSeconds,
  int startIndex = 0,
}) {
  final buffer = StringBuffer();
  var i = startIndex;
  for (final s in samples) {
    final v = s.verdict;
    buffer.writeln(
      [
        i++,
        s.arrivalMillis - firstArrivalMillis,
        s.fix.timestampSeconds - firstFixSeconds,
        s.fix.lat.toStringAsFixed(6),
        s.fix.lon.toStringAsFixed(6),
        s.fix.accuracyMeters?.toStringAsFixed(1) ?? '',
        v.seconds,
        v.rawMeters.toStringAsFixed(1),
        v.countedMeters.toStringAsFixed(1),
        v.noiseFloorMeters.toStringAsFixed(1),
        v.speedKmh.toStringAsFixed(1),
        v.outcome.name,
      ].join(','),
    );
  }
  return buffer.toString();
}

/// The whole retained run as one CSV document.
String formatMeterDiagnosticCsv(MeterDiagnosticLog log) {
  final samples = log.samples;
  if (samples.isEmpty) return kMeterDiagnosticCsvHeader;
  return kMeterDiagnosticCsvHeader +
      formatMeterDiagnosticCsvRows(
        samples,
        firstArrivalMillis: samples.first.arrivalMillis,
        firstFixSeconds: samples.first.fix.timestampSeconds,
      );
}
