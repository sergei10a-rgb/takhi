// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The last bug arrived over Messenger, because the driver who found it
// happens to know the author. The next fifty drivers will not, and an app
// with nobody at the middle of it has no support desk to route them to.
import 'package:flutter_test/flutter_test.dart';
import 'package:takhi/support/bug_report.dart';

void main() {
  test('carries the two facts a person never thinks to include', () {
    final report = composeBugReport(
      const BugReportContext(
        appVersion: '0.4.0+4',
        screen: 'Таксиметр',
        platform: 'android',
        description: 'Тоолуур зогсчихлоо',
      ),
    );

    // A report that says only "the meter is wrong" costs a day of guessing.
    expect(report, contains('0.4.0+4'));
    expect(report, contains('Таксиметр'));
    expect(report, contains('android'));
    expect(report, contains('Тоолуур зогсчихлоо'));
  });

  test('a report with nothing typed is still worth sending', () {
    final report = composeBugReport(
      const BugReportContext(
        appVersion: '0.4.0+4',
        screen: 'Тохиргоо',
        platform: 'android',
      ),
    );

    // The facts alone beat no report at all, so an empty description must
    // not produce an empty document — or a dangling blank section that
    // reads as though something failed to load.
    expect(report, contains('0.4.0+4'));
    expect(report.trim(), isNotEmpty);
    expect(report.trimRight().endsWith('Тохиргоо'), isTrue);
  });

  test('whitespace-only text counts as nothing typed', () {
    final report = composeBugReport(
      const BugReportContext(
        appVersion: '0.4.0+4',
        screen: 'Тохиргоо',
        platform: 'android',
        description: '   \n  ',
      ),
    );
    expect(report.trimRight().endsWith('Тохиргоо'), isTrue);
  });
}
