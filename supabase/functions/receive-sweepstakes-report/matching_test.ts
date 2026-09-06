import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractContextualArbaSanctionNumbers,
  resolveReportMatch,
} from "./matching.ts";

const expected = [{
  id: "expected-1",
  seasonId: "season-1",
  arbaSanctionNumber: "YOA-4499",
  status: "expected",
}];

Deno.test("matches one expected report by filename sanction", () => {
  const result = resolveReportMatch([
    "HTRC_SpecialtyClubPlacement_Standard_Chinchilla_YOA4499.pdf",
  ], expected);
  assertEquals(result.expectedReportId, "expected-1");
  assertEquals(result.seasonId, "season-1");
});

Deno.test("conflicting sanction numbers stay unmatched", () => {
  const result = resolveReportMatch(
    ["show_YOA4498.pdf", "show_YOA4499.pdf"],
    expected,
  );
  assertEquals(result.expectedReportId, null);
  assertStringIncludes(result.reason, "Conflicting");
});

Deno.test("duplicate expected matches stay unmatched", () => {
  const result = resolveReportMatch(["show_YOA4499.pdf"], [
    ...expected,
    { ...expected[0], id: "expected-2", status: "overdue" },
  ]);
  assertEquals(result.expectedReportId, null);
  assertStringIncludes(result.reason, "More than one");
});

Deno.test("processed reports are not automatically matched", () => {
  const result = resolveReportMatch(["show_YOA4499.pdf"], [
    { ...expected[0], status: "processed" },
  ]);
  assertEquals(result.expectedReportId, null);
});

Deno.test("extracts only a contextual ARBA sanction from report text", () => {
  assertEquals(
    extractContextualArbaSanctionNumbers(
      "ARBA Sanction Number: YOA4499 Exhibitor ARBA ID Z123456",
    ),
    ["YOA4499"],
  );
});
