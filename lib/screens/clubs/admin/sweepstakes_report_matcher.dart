class SweepstakesExpectedReportMatchCandidate {
  const SweepstakesExpectedReportMatchCandidate({
    required this.id,
    required this.seasonId,
    required this.arbaSanctionNumber,
    required this.status,
  });

  final String id;
  final String? seasonId;
  final String? arbaSanctionNumber;
  final String status;
}

class SweepstakesReportMatch {
  const SweepstakesReportMatch({
    required this.sanctionNumbers,
    required this.reason,
    this.expectedReportId,
    this.seasonId,
  });

  final List<String> sanctionNumbers;
  final String reason;
  final String? expectedReportId;
  final String? seasonId;

  bool get isMatched => expectedReportId != null;
}

List<String> extractArbaSanctionNumbers(Iterable<String?> values) {
  final numbers = <String>{};
  final pattern = RegExp(
    r'(?:^|[^A-Z0-9])([A-Z]{2,6})[- ]?(\d{3,})(?=$|[^A-Z0-9])',
    caseSensitive: false,
  );
  for (final value in values) {
    if (value == null) continue;
    for (final match in pattern.allMatches(value.toUpperCase())) {
      numbers.add('${match.group(1)}${match.group(2)}'.toUpperCase());
    }
  }
  return numbers.toList()..sort();
}

SweepstakesReportMatch resolveSweepstakesReportMatch({
  required Iterable<String?> reportSignals,
  required Iterable<SweepstakesExpectedReportMatchCandidate> expectedReports,
}) {
  final sanctionNumbers = extractArbaSanctionNumbers(reportSignals);
  if (sanctionNumbers.isEmpty) {
    return const SweepstakesReportMatch(
      sanctionNumbers: [],
      reason: 'No ARBA sanction number was found.',
    );
  }
  if (sanctionNumbers.length != 1) {
    return SweepstakesReportMatch(
      sanctionNumbers: sanctionNumbers,
      reason: 'Conflicting ARBA sanction numbers were found.',
    );
  }

  final sanctionNumber = sanctionNumbers.single;
  final matches = expectedReports.where((expected) {
    if (expected.status == 'processed' || expected.status == 'waived') {
      return false;
    }
    return extractArbaSanctionNumbers([
      expected.arbaSanctionNumber,
    ]).contains(sanctionNumber);
  }).toList();
  if (matches.length != 1) {
    return SweepstakesReportMatch(
      sanctionNumbers: sanctionNumbers,
      reason: matches.isEmpty
          ? 'No open expected report matches ARBA sanction $sanctionNumber.'
          : 'More than one expected report matches ARBA sanction $sanctionNumber.',
    );
  }

  return SweepstakesReportMatch(
    sanctionNumbers: sanctionNumbers,
    expectedReportId: matches.single.id,
    seasonId: matches.single.seasonId,
    reason: 'Matched by ARBA sanction $sanctionNumber.',
  );
}
