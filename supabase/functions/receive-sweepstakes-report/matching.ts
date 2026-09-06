export type ExpectedReportCandidate = {
  id: string;
  seasonId: string | null;
  arbaSanctionNumber: string | null;
  status: string;
};

export type ReportMatch = {
  sanctionNumbers: string[];
  expectedReportId: string | null;
  seasonId: string | null;
  reason: string;
};

export function extractArbaSanctionNumbers(values: Array<string | null>) {
  const numbers = new Set<string>();
  const pattern = /(?:^|[^A-Z0-9])([A-Z]{2,6})[- ]?(\d{3,})(?=$|[^A-Z0-9])/gi;
  for (const value of values) {
    if (!value) continue;
    for (const match of value.toUpperCase().matchAll(pattern)) {
      numbers.add(`${match[1]}${match[2]}`.toUpperCase());
    }
  }
  return [...numbers].sort();
}

export function extractContextualArbaSanctionNumbers(text: string | null) {
  if (!text) return [];
  const values: string[] = [];
  const pattern =
    /ARBA\s+SANCTION(?:\s+(?:NUMBER|NO\.?))?\s*[:#-]?\s*([A-Z]{2,6}[- ]?\d{3,})/gi;
  for (const match of text.matchAll(pattern)) values.push(match[1]);
  return extractArbaSanctionNumbers(values);
}

export function resolveReportMatch(
  reportSignals: Array<string | null>,
  expectedReports: ExpectedReportCandidate[],
): ReportMatch {
  const sanctionNumbers = extractArbaSanctionNumbers(reportSignals);
  if (!sanctionNumbers.length) {
    return {
      sanctionNumbers,
      expectedReportId: null,
      seasonId: null,
      reason: "No ARBA sanction number was found.",
    };
  }
  if (sanctionNumbers.length !== 1) {
    return {
      sanctionNumbers,
      expectedReportId: null,
      seasonId: null,
      reason: "Conflicting ARBA sanction numbers were found.",
    };
  }

  const sanctionNumber = sanctionNumbers[0];
  const matches = expectedReports.filter((expected) =>
    expected.status !== "processed" &&
    expected.status !== "waived" &&
    extractArbaSanctionNumbers([expected.arbaSanctionNumber]).includes(
      sanctionNumber,
    )
  );
  if (matches.length !== 1) {
    return {
      sanctionNumbers,
      expectedReportId: null,
      seasonId: null,
      reason: matches.length
        ? `More than one expected report matches ARBA sanction ${sanctionNumber}.`
        : `No open expected report matches ARBA sanction ${sanctionNumber}.`,
    };
  }

  return {
    sanctionNumbers,
    expectedReportId: matches[0].id,
    seasonId: matches[0].seasonId,
    reason: `Matched by ARBA sanction ${sanctionNumber}.`,
  };
}
