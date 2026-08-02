// SPDX-License-Identifier: AGPL-3.0-or-later

/// Composes the text a driver hands over when something has gone wrong.
///
/// Written because of how the last bug arrived. A driver noticed the meter
/// was reading short, and told the author over Messenger — which worked
/// only because he happens to know the author. The next fifty drivers will
/// not, and an app with nobody at the middle of it has no support desk to
/// route them to.
///
/// So this does the one thing an ownerless app honestly can: it assembles
/// the facts that make a report worth reading, and hands them back to the
/// driver. **Nothing is sent.** Where the text goes — a chat, a forum, an
/// email, nowhere — is the driver's decision, made after they have read it.
library;

/// The facts a report is useless without.
///
/// A bug report that says "the meter is wrong" costs a day of guessing. The
/// same report with a version and a screen name on it usually costs an
/// hour, and these are the two things a person never thinks to include.
class BugReportContext {
  /// As it appears in `pubspec.yaml`, e.g. `0.4.0+4`.
  final String appVersion;

  /// Which screen the driver was on, in their own language — this is read
  /// by a person, not parsed.
  final String screen;

  /// The operating system, lowercase (`android`, `ios`).
  final String platform;

  /// What the driver typed. Empty is allowed: a report with only the facts
  /// is still worth more than no report.
  final String description;

  const BugReportContext({
    required this.appVersion,
    required this.screen,
    required this.platform,
    this.description = '',
  });
}

/// The report, ready to be copied or shared.
///
/// Deliberately plain text with no markup: it is going into whatever app
/// the driver picked, and a chat window that renders half of it as headings
/// helps nobody.
String composeBugReport(BugReportContext context) {
  final buffer = StringBuffer()
    ..writeln('Тахь — алдааны мэдээлэл')
    ..writeln('Хувилбар: ${context.appVersion}')
    ..writeln('Систем: ${context.platform}')
    ..writeln('Дэлгэц: ${context.screen}');

  final description = context.description.trim();
  if (description.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(description);
  }
  return buffer.toString();
}
