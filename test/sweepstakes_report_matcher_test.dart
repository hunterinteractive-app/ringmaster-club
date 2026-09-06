import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_club/screens/clubs/admin/sweepstakes_report_matcher.dart';

void main() {
  const openReport = SweepstakesExpectedReportMatchCandidate(
    id: 'expected-1',
    seasonId: 'season-1',
    arbaSanctionNumber: 'YOA-4499',
    status: 'expected',
  );

  test('matches one open expected report from an attachment filename', () {
    final result = resolveSweepstakesReportMatch(
      reportSignals: const [
        'HTRC_SpecialtyClubPlacement_Standard_Chinchilla_YOA4499.pdf',
      ],
      expectedReports: const [openReport],
    );

    expect(result.expectedReportId, 'expected-1');
    expect(result.seasonId, 'season-1');
    expect(result.sanctionNumbers, ['YOA4499']);
  });

  test('leaves conflicting attachment numbers unmatched', () {
    final result = resolveSweepstakesReportMatch(
      reportSignals: const ['show_YOA4498.pdf', 'show_YOA4499.pdf'],
      expectedReports: const [openReport],
    );

    expect(result.isMatched, isFalse);
    expect(result.reason, contains('Conflicting'));
  });

  test('does not match a processed expected report', () {
    final result = resolveSweepstakesReportMatch(
      reportSignals: const ['show_YOA4499.pdf'],
      expectedReports: const [
        SweepstakesExpectedReportMatchCandidate(
          id: 'processed-1',
          seasonId: 'season-1',
          arbaSanctionNumber: 'YOA4499',
          status: 'processed',
        ),
      ],
    );

    expect(result.isMatched, isFalse);
  });

  test('leaves duplicate expected report numbers unmatched', () {
    final result = resolveSweepstakesReportMatch(
      reportSignals: const ['show_YOA4499.pdf'],
      expectedReports: const [
        openReport,
        SweepstakesExpectedReportMatchCandidate(
          id: 'expected-2',
          seasonId: 'season-1',
          arbaSanctionNumber: 'YOA4499',
          status: 'overdue',
        ),
      ],
    );

    expect(result.isMatched, isFalse);
    expect(result.reason, contains('More than one'));
  });
}
