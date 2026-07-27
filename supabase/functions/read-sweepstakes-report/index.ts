import "@supabase/functions-js/edge-runtime.d.ts";
import * as pdfjs from "npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs";

type JsonObject = Record<string, unknown>;
type ExhibitorTotal = {
  exhibitorName: string;
  breed: string | null;
  sourcePoints: number;
};
type BreedCount = {
  breed: string;
  rabbitsShown: number;
};
type DetailedAward = {
  exhibitorName: string;
  breed: string | null;
  ruleKey: string;
  shownCount: number;
  placement: string | null;
};
type CalculatedResult = ExhibitorTotal & {
  calculatedPoints: number;
  placement: string | null;
  reviewNotes: string | null;
  awardBreakdowns: AwardBreakdown[];
};
type AwardBreakdown = {
  ruleKey: string;
  ruleLabel: string;
  awardLabel: string;
  calculationType: string;
  pointsPerAward: number;
  shownCount: number | null;
  calculatedPoints: number;
  placement: string | null;
  breed: string | null;
};

type ReportSource = "easy2show" | "ringmaster_show" | "grand_champion" | "standard";

type ReportProfile = {
  key: ReportSource;
  label: string;
  totalsHints: string[];
  awardsHints: string[];
  breedCountHints: string[];
  totalsGuidance: string;
  awardsGuidance: string;
  breedCountGuidance: string;
};

class ReaderServiceError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

const reportProfiles: Record<ReportSource, ReportProfile> = {
  easy2show: {
    key: "easy2show",
    label: "Easy2Show",
    totalsHints: ["exh_total_points", "exh_by_breed"],
    awardsHints: ["details_by_breed"],
    breedCountHints: ["exh_by_breed"],
    totalsGuidance:
      "Use the Exhibitor / Address table and copy only the Total column for each exhibitor.",
    awardsGuidance:
      "Use the details-by-breed report. For # Ent / # Exh values, use the first number as the shown count.",
    breedCountGuidance:
      "Use the report-level Exhibitors by Breed totals, not individual exhibitor rows.",
  },
  ringmaster_show: {
    key: "ringmaster_show",
    label: "RingMaster Show",
    totalsHints: ["ringmaster show", "ringmaster_show", "club reports", "club report", "sweepstakes", "standings", "results", "points", "exhibitor"],
    awardsHints: ["ringmaster show", "ringmaster_show", "club reports", "club report", "results", "details", "awards", "placement"],
    breedCountHints: ["breed counts", "breed count", "rabbits shown", "entries by breed", "breed summary", "breed"],
    totalsGuidance:
      "RingMaster Show reports may call totals Results, Standings, Club Report, or Exhibitor Totals. Use rows that explicitly pair an exhibitor with a total-points value.",
    awardsGuidance:
      "Use only class or award rows that are explicitly printed in the report. Do not convert an exhibitor's total back into individual awards.",
    breedCountGuidance:
      "Use only explicit report-level rabbits shown, entered, or exhibited totals by breed.",
  },
  grand_champion: {
    key: "grand_champion",
    label: "Grand Champion",
    totalsHints: ["grandchampion", "grand_champion", "grand champion", "sweepstakes", "standings", "results", "points", "exhibitor"],
    awardsHints: ["grandchampion", "grand_champion", "grand champion", "results", "details", "awards", "placement"],
    breedCountHints: ["breed counts", "breed count", "rabbits shown", "entries by breed", "breed summary", "breed"],
    totalsGuidance:
      "Grand Champion reports may use standings, points, exhibitor totals, or club results. Use only an explicit exhibitor-and-total table.",
    awardsGuidance:
      "Use only explicitly listed placements, awards, and shown counts. Omit rows when the award facts are not clearly printed.",
    breedCountGuidance:
      "Use only explicit report-level rabbits shown, entered, or exhibited totals by breed.",
  },
  standard: {
    key: "standard",
    label: "standard club report",
    totalsHints: ["sweepstakes", "standings", "results", "points", "exhibitor", "club report"],
    awardsHints: ["results", "details", "awards", "placement", "sweepstakes"],
    breedCountHints: ["breed counts", "breed count", "rabbits shown", "entries by breed", "breed summary", "breed"],
    totalsGuidance:
      "Use only a table that explicitly pairs an exhibitor, owner, or entrant with a total-points or standings value.",
    awardsGuidance:
      "Use only facts printed on the report that directly match an active scoring rule. Never infer placements or shown counts.",
    breedCountGuidance:
      "Use only explicit report-level rabbit totals by breed. Omit uncertain breeds instead of estimating.",
  },
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const geminiApiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
const maxPdfBytes = 15 * 1024 * 1024;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const addressCutoffWords = new Set([
  "st", "street", "rd", "road", "dr", "drive", "ave", "avenue",
  "blvd", "ln", "hwy", "highway", "trail", "trl", "ct", "court",
  "way", "pkwy", "parkway", "cir", "circle", "po", "box", "county",
  "lot", "apt", "unit", "us", "state", "township",
]);

const serviceHeaders = {
  apikey: serviceRoleKey,
  authorization: `Bearer ${serviceRoleKey}`,
  "content-type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !geminiApiKey) {
    return respond({ error: "Secure report reading is not configured yet." }, 503);
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return respond({ error: "Sign in to read a report." }, 401);
  }
  const body = objectValue(await request.json().catch(() => null));
  const importId = stringValue(body.import_id);
  if (!importId) return respond({ error: "A results draft is required." }, 400);

  try {
    // This request deliberately uses the caller's session. Existing row-level
    // security decides whether that user may access this club's result draft.
    const permittedImport = await callerImport(importId, authorization);
    if (!Object.keys(permittedImport).length) {
      return respond({ error: "You do not have access to this results draft." }, 403);
    }

    const packageId = stringValue(permittedImport.report_package_id);
    const clubId = stringValue(permittedImport.club_id);
    const seasonId = stringValue(permittedImport.season_id);
    const expectedReportId = stringValue(permittedImport.expected_report_id);
    if (!packageId || !clubId) throw new Error("This results draft is incomplete.");

    const reportPackage = await serviceSingle(
      "club_sweepstakes_report_packages",
      `select=attachment_manifest,source_subject,extracted_summary&id=eq.${encodeURIComponent(packageId)}`,
    );
    const attachments = arrayValue(reportPackage.attachment_manifest);
    const source = detectReportSource(
      attachments,
      stringValue(reportPackage.source_subject),
      objectValue(reportPackage.extracted_summary),
    );
    const profile = reportProfiles[source];
    const pdfAttachments = attachments.filter(isPdfAttachment);
    const totalsAttachment = findAttachment(attachments, profile.totalsHints) ??
      (source === "easy2show"
        ? findAttachment(attachments, ["exh_by_breed"])
        : pdfAttachments[0]);
    const detailsAttachment = findAttachment(attachments, profile.awardsHints) ??
      (source === "easy2show" ? undefined : totalsAttachment);
    if (!totalsAttachment || !detailsAttachment) {
      return respond({
        error: source === "easy2show"
          ? "This Easy2Show package needs both an exhibitor totals PDF and a details-by-breed PDF before it can create a review draft."
          : `This ${profile.label} package needs at least one PDF before it can create a review draft.`,
      }, 422);
    }

    const bucket = await documentBucket(clubId);
    const totalsPath = stringValue(totalsAttachment.storage_path);
    const detailsPath = stringValue(detailsAttachment.storage_path);
    if (!bucket || !totalsPath || !detailsPath) throw new Error("The report files could not be located.");
    const [totalsPdf, detailsPdf] = await Promise.all([
      downloadPrivateFile(bucket, totalsPath),
      downloadPrivateFile(bucket, detailsPath),
    ]);
    if (totalsPdf.byteLength > maxPdfBytes || detailsPdf.byteLength > maxPdfBytes) {
      return respond({ error: "This PDF is too large for secure automated reading. Please use the manual review option." }, 422);
    }

    const rules = await activeRules(clubId);
    const rawTotals = source === "easy2show"
      ? await readEasy2ShowTotalsFromPdf(totalsPdf)
      : await readTotalsWithGemini(
        totalsPdf,
        stringValue(totalsAttachment.file_name) ?? "exhibitor-totals.pdf",
        profile,
    );
    let totalRows = normalizeTotals(rawTotals, rules);
    if (source === "easy2show") {
      await deleteInvalidEasy2ShowFooterRows(importId);
    }
    // A retry for an existing Easy2Show draft should not consume another AI
    // request merely to recreate award rows that staff already has. Fill only
    // blank source totals; manually supplied source values remain untouched.
    if (source === "easy2show" && totalRows.length) {
      const sourcePointsUpdated = await refreshBlankSourcePoints(importId, totalRows);
      if (sourcePointsUpdated > 0) {
        return respond({
          rows_added: 0,
          source_points_updated: sourcePointsUpdated,
          breed_counts_added: 0,
          breed_counts_note: null,
          source_label: profile.label,
          needs_review: true,
        });
      }
    }
    const detailedAwards = normalizeDetailedAwards(
      await readDetailedAwardsWithGemini(
        detailsPdf,
        stringValue(detailsAttachment.file_name) ?? "details-by-breed.pdf",
        rules,
        profile,
      ),
      rules,
    );
    // Easy2Show's totals table includes address columns and can occasionally
    // be too ambiguous to read safely. A verified detailed award still gives
    // us a useful, review-only row: staff can compare its calculated score
    // against the original PDF before approving anything.
    const usedAwardFallback = !totalRows.length && detailedAwards.length > 0;
    if (usedAwardFallback) {
      totalRows = totalsFromDetailedAwards(detailedAwards);
    }
    const rows = calculateResults(totalRows, detailedAwards, rules, usedAwardFallback);
    if (!rows.length) {
      return respond({
        error: `No class-placement results could be safely identified in this ${profile.label} report. Please add verified results manually.`,
      }, 422);
    }

    // Retrying secure report reading replaces only unreviewed draft rows. It
    // never overwrites staff-approved or rejected work.
    await deletePendingRows(importId);
    await insertRows(importId, clubId, rows);

    // Breed counts are helpful for ISRBA's per-show obligations, but they are
    // never allowed to block the staff-review draft of points. They only write
    // when this report is matched to an expected sanction report.
    let breedCountsAdded = 0;
    let breedCountsNote: string | null = null;
    const breedCountsAttachment = findAttachment(attachments, profile.breedCountHints);
    if (!breedCountsAttachment) {
      breedCountsNote = "This package does not include an Exhibitors by Breed report, so no show counts were added.";
    } else if (!seasonId || !expectedReportId) {
      breedCountsNote = "Match this package to a sanctioned show before its breed counts can be added.";
    } else {
      try {
        const breedCountsPath = stringValue(breedCountsAttachment.storage_path);
        if (!breedCountsPath) throw new Error("The breed-count PDF could not be located.");
        const breedCountsPdf = await downloadPrivateFile(bucket, breedCountsPath);
        if (breedCountsPdf.byteLength > maxPdfBytes) {
          throw new Error("The breed-count PDF is too large to read safely.");
        }
        const breedCounts = normalizeBreedCounts(
          await readBreedCountsWithGemini(
            breedCountsPdf,
            stringValue(breedCountsAttachment.file_name) ?? "exhibitors-by-breed.pdf",
            profile,
          ),
        );
        breedCountsAdded = await importBreedPaybackCounts(
          clubId,
          seasonId,
          expectedReportId,
          breedCounts,
        );
        if (!breedCounts.length) {
          breedCountsNote = "No report-level breed counts could be read safely.";
        } else if (breedCountsAdded == 0) {
          breedCountsNote = "Existing manually confirmed show counts were kept.";
        }
      } catch (error) {
        console.warn("Breed counts were not imported", error);
        breedCountsNote = "Breed counts could not be read safely; add or correct them in Show obligations.";
      }
    }

    return respond({
      rows_added: rows.length,
      breed_counts_added: breedCountsAdded,
      breed_counts_note: breedCountsNote,
      source_type: source,
      source_label: profile.label,
      needs_review: true,
    });
  } catch (error) {
    console.error("Secure report reading failed", error);
    const message = error instanceof Error ? error.message : "The report could not be read.";
    return respond({ error: message }, error instanceof ReaderServiceError ? error.status : 500);
  }
});

async function callerImport(importId: string, authorization: string) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/club_sweepstakes_result_imports?select=club_id,report_package_id,season_id,expected_report_id&id=eq.${encodeURIComponent(importId)}&limit=1`,
    { headers: { apikey: serviceRoleKey, authorization } },
  );
  if (!response.ok) throw new Error("Unable to verify access to this results draft.");
  const rows = await response.json();
  return objectValue(Array.isArray(rows) ? rows[0] : null);
}

async function documentBucket(clubId: string) {
  const club = await serviceSingle("clubs", `select=document_storage_bucket&id=eq.${encodeURIComponent(clubId)}`);
  return stringValue(club.document_storage_bucket);
}

async function activeRules(clubId: string) {
  const url = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_parser_rules`);
  url.searchParams.set("select", "rule_type,match_value,replacement_value,rule_config");
  url.searchParams.set("club_id", `eq.${clubId}`);
  url.searchParams.set("is_active", "eq.true");
  url.searchParams.set("order", "sort_order");
  const response = await fetch(url, { headers: serviceHeaders });
  if (!response.ok) throw new Error("Unable to load Sweepstakes Rules.");
  return (await response.json() as unknown[]).map(objectValue);
}

async function serviceSingle(table: string, query: string) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${table}?${query}&limit=1`, { headers: serviceHeaders });
  if (!response.ok) throw new Error(`Unable to load ${table}.`);
  const rows = await response.json();
  return objectValue(Array.isArray(rows) ? rows[0] : null);
}

async function downloadPrivateFile(bucket: string, path: string) {
  const target = `${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${path.split("/").map(encodeURIComponent).join("/")}`;
  const response = await fetch(target, { headers: serviceHeaders });
  if (!response.ok) throw new Error("Unable to download the selected PDF.");
  return await response.arrayBuffer();
}

async function readEasy2ShowTotalsFromPdf(pdf: ArrayBuffer): Promise<JsonObject[]> {
  const document = await pdfjs.getDocument({ data: new Uint8Array(pdf) }).promise;
  const rows: JsonObject[] = [];
  for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
    const content = await (await document.getPage(pageNumber)).getTextContent();
    const lineFragments = new Map<number, { x: number; text: string }[]>();
    for (const item of content.items) {
      const candidate = item as { str?: unknown; transform?: unknown };
      const text = stringValue(candidate.str);
      const transform = Array.isArray(candidate.transform) ? candidate.transform : [];
      const x = numberValue(transform[4]);
      const y = numberValue(transform[5]);
      if (!text || x == null || y == null) continue;
      const line = Math.round(y);
      lineFragments.set(line, [...(lineFragments.get(line) ?? []), { x, text }]);
    }
    for (const fragments of lineFragments.values()) {
      const name = fragments
        .filter((fragment) => fragment.x >= 35 && fragment.x < 150)
        .sort((a, b) => a.x - b.x)
        .map((fragment) => fragment.text)
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();
      const totalText = fragments
        .filter((fragment) => fragment.x >= 600)
        .sort((a, b) => b.x - a.x)
        .map((fragment) => fragment.text)
        .find((value) => /^\d+(?:\.\d+)?$/.test(value));
      // Easy2Show's real exhibitor-total rows contain an email-column value.
      // Requiring it prevents the footer (© Easy2show / page 2) from being
      // mistaken for an exhibitor named Easy2show with two points.
      const hasEmail = fragments.some((fragment) =>
        fragment.x >= 350 && fragment.x < 600 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fragment.text),
      );
      const sourcePoints = numberValue(totalText);
      if (name && hasEmail && sourcePoints != null && sourcePoints > 0) {
        rows.push({ exhibitor_name: name, source_points: sourcePoints });
      }
    }
  }
  return rows;
}

async function readTotalsWithGemini(
  pdf: ArrayBuffer,
  fileName: string,
  profile: ReportProfile,
  strictEasy2ShowTotals = false,
) {
  const base64 = toBase64(new Uint8Array(pdf));
  const easy2ShowTableGuidance = strictEasy2ShowTotals
    ? `This is specifically an Easy2Show Exhibitor Total Points report. Read its one exhibitor table even though address and email columns appear between the name and points. Each row follows this layout: Exhibitor name | Address, City, State, Country, Zip | Email | Rabbit | Cavy | Fur/Wool | Commercial | Total. Return the final numeric Total for every named exhibitor. For example, a row ending in 225 has source_points 225. Never use the category columns as the total, and do not omit a valid row merely because it includes an address or email.`
    : profile.totalsGuidance;
  const prompt = `Read this ${profile.label} PDF and return only explicit exhibitor total rows.\n\nRules:\n- ${easy2ShowTableGuidance}\n- For each row, return the exhibitor name, breed when explicitly available, and the printed total as source_points.\n- Do not include an address, city, state, ZIP code, animal count, headings, subtotals, or zero/blank totals.\n- Do not infer, combine, or calculate points. Copy only a total explicitly shown for that exhibitor.\n- If a value is uncertain, omit that row instead of guessing.\n- This is a draft for staff review; it must not be treated as final standings.\n- Source filename: ${fileName}`;
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${encodeURIComponent(geminiApiKey)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [
          { inline_data: { mime_type: "application/pdf", data: base64 } },
          { text: prompt },
        ] }],
        generationConfig: {
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              exhibitors: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    exhibitor_name: { type: "STRING" },
                    breed: { type: "STRING" },
                    source_points: { type: "NUMBER" },
                  },
                  required: ["exhibitor_name", "source_points"],
                },
              },
            },
            required: ["exhibitors"],
          },
        },
      }),
    },
  );
  if (!response.ok) throw readerServiceError("report", response.status);
  const payload = objectValue(await response.json());
  const candidates = arrayValue(payload.candidates);
  const content = objectValue(objectValue(candidates[0]).content);
  const text = stringValue(objectValue(arrayValue(content.parts)[0]).text);
  if (!text) throw new Error("Secure report reading service returned no draft.");
  const decoded = objectValue(parseJson(text));
  return arrayValue(decoded.exhibitors);
}

async function readDetailedAwardsWithGemini(
  pdf: ArrayBuffer,
  fileName: string,
  rules: JsonObject[],
  profile: ReportProfile,
) {
  const availableRules = rules
    .filter((rule) => stringValue(rule.rule_type) === "points_rule")
    .map((rule) => ({
      rule_key: stringValue(rule.match_value),
      award_label: stringValue(objectValue(rule.rule_config).award_label),
      calculation_type: stringValue(objectValue(rule.rule_config).calculation_type),
    }))
    .filter((rule) => rule.rule_key && rule.award_label && rule.calculation_type);
  if (!availableRules.length) {
    throw new Error("Add at least one active scoring rule before reading detailed results.");
  }

  const base64 = toBase64(new Uint8Array(pdf));
  const classPlacementRules = availableRules
    .filter((rule) => rule.calculation_type === "class_size_multiplier")
    .map((rule) => ({ rule_key: rule.rule_key, placement: rule.award_label }));
  const prompt = `Read this ${profile.label} report. Return only award or class-placement facts that match one of the club scoring rules below. Never calculate points and never include addresses, email addresses, or any person who is not an exhibitor.

For each result, identify the exhibitor, breed, the exact matching rule_key, and the number shown for the applicable scope. ${profile.awardsGuidance} For class placement rules, use the class's shown count. In Easy2Show, a class heading such as "Jr. Doe (6/2)" or a "# Ent / # Exh" value such as "33 / 5" means use the first number (6 or 33) as shown_count. A numeric placement in the class list maps as 1 → 1st place, 2 → 2nd place, 3 → 3rd place, 4 → 4th place, and 5 → 5th place. For BOV/BOSV use variety shown; for BOB/BOS use breed shown; for BOG/BOSG use group shown; for BIS/RIS/B4C/B6C use total show entries. For flat-point rules, shown_count may be 1.

Class-placement mapping:
${JSON.stringify(classPlacementRules)}

Rules:
${JSON.stringify(availableRules)}

Important:
- Only use rule_key values exactly as supplied above.
- Do not turn a point total, subtotal, or animal ear number into an award.
- Omit a result when its award, exhibitor, or required shown count cannot be read confidently.
- This is a staff-review draft and cannot publish standings.
- Source filename: ${fileName}`;
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${encodeURIComponent(geminiApiKey)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [
          { inline_data: { mime_type: "application/pdf", data: base64 } },
          { text: prompt },
        ] }],
        generationConfig: {
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              awards: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    exhibitor_name: { type: "STRING" },
                    breed: { type: "STRING" },
                    rule_key: { type: "STRING" },
                    shown_count: { type: "NUMBER" },
                    placement: { type: "STRING" },
                  },
                  required: ["exhibitor_name", "rule_key", "shown_count"],
                },
              },
            },
            required: ["awards"],
          },
        },
      }),
    },
  );
  if (!response.ok) throw readerServiceError("detailed report", response.status);
  const payload = objectValue(await response.json());
  const candidates = arrayValue(payload.candidates);
  const content = objectValue(objectValue(candidates[0]).content);
  const text = stringValue(objectValue(arrayValue(content.parts)[0]).text);
  if (!text) throw new Error("Secure detailed report reading service returned no draft.");
  return arrayValue(objectValue(parseJson(text)).awards);
}

async function readBreedCountsWithGemini(
  pdf: ArrayBuffer,
  fileName: string,
  profile: ReportProfile,
) {
  const base64 = toBase64(new Uint8Array(pdf));
  const prompt = `Read this ${profile.label} breed-count PDF and return only the report-level rabbit count for each breed.

Rules:
- ${profile.breedCountGuidance}
- For each breed, return the total rabbits shown/entered for that breed for the entire show.
- Do not use exhibitor counts, point totals, class counts, ear numbers, addresses, or names.
- Do not add together individual exhibitors or classes; use only an explicitly printed breed total.
- If the report has separate Open and Youth totals without an overall breed total, add those two only when they are clearly for the same breed and same show.
- If a breed count is uncertain, omit it instead of guessing.
- This creates a staff-reviewable show obligation, not a payment or published standing.
- Source filename: ${fileName}`;
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=${encodeURIComponent(geminiApiKey)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [
          { inline_data: { mime_type: "application/pdf", data: base64 } },
          { text: prompt },
        ] }],
        generationConfig: {
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              breeds: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    breed: { type: "STRING" },
                    rabbits_shown: { type: "NUMBER" },
                  },
                  required: ["breed", "rabbits_shown"],
                },
              },
            },
            required: ["breeds"],
          },
        },
      }),
    },
  );
  if (!response.ok) throw readerServiceError("breed-count report", response.status);
  const payload = objectValue(await response.json());
  const candidates = arrayValue(payload.candidates);
  const content = objectValue(objectValue(candidates[0]).content);
  const text = stringValue(objectValue(arrayValue(content.parts)[0]).text);
  if (!text) throw new Error("Secure breed-count reading service returned no draft.");
  return arrayValue(objectValue(parseJson(text)).breeds);
}

function normalizeTotals(rows: JsonObject[], rules: JsonObject[]): ExhibitorTotal[] {
  const seen = new Set<string>();
  return rows.flatMap((row) => {
    const originalName = stringValue(row.exhibitor_name);
    const sourcePoints = numberValue(row.source_points);
    if (!originalName || !sourcePoints || sourcePoints <= 0) return [];
    const exhibitorName = applyRules(originalName, rules);
    const breed = stringValue(row.breed);
    const key = `${exhibitorName.toLowerCase()}|${(breed ?? "").toLowerCase()}|${sourcePoints}`;
    return seen.has(key) ? [] : (seen.add(key), [{ exhibitorName, breed, sourcePoints }]);
  });
}

function normalizeDetailedAwards(rows: JsonObject[], rules: JsonObject[]): DetailedAward[] {
  const pointRuleKeys = new Set(
    rules
      .filter((rule) => stringValue(rule.rule_type) === "points_rule")
      .map((rule) => stringValue(rule.match_value))
      .filter((value): value is string => Boolean(value)),
  );
  const seen = new Set<string>();
  return rows.flatMap((row) => {
    const originalName = stringValue(row.exhibitor_name);
    const ruleKey = stringValue(row.rule_key);
    const shownCount = numberValue(row.shown_count);
    if (!originalName || !ruleKey || !pointRuleKeys.has(ruleKey) || shownCount == null || shownCount <= 0) {
      return [];
    }
    const exhibitorName = applyRules(originalName, rules);
    const breed = stringValue(row.breed);
    const placement = stringValue(row.placement);
    const key = `${exhibitorName.toLowerCase()}|${(breed ?? "").toLowerCase()}|${ruleKey}|${shownCount}|${placement ?? ""}`;
    return seen.has(key)
      ? []
      : (seen.add(key), [{ exhibitorName, breed, ruleKey, shownCount, placement }]);
  });
}

function normalizeBreedCounts(rows: JsonObject[]): BreedCount[] {
  const merged = new Map<string, BreedCount>();
  for (const row of rows) {
    const breed = stringValue(row.breed)?.replace(/\s+/g, " ").trim();
    const rabbitsShown = numberValue(row.rabbits_shown);
    if (!breed || rabbitsShown == null || rabbitsShown < 0) continue;
    const key = breed.toLowerCase();
    // The source report should provide one total per breed. If it repeats a
    // breed, retain the largest explicit total rather than guessing a sum.
    const current = merged.get(key);
    if (!current || rabbitsShown > current.rabbitsShown) {
      merged.set(key, { breed, rabbitsShown: Math.round(rabbitsShown) });
    }
  }
  return [...merged.values()];
}

function calculateResults(
  totals: ExhibitorTotal[],
  awards: DetailedAward[],
  rules: JsonObject[],
  usedAwardFallback = false,
): CalculatedResult[] {
  const scoringRules = new Map(
    rules
      .filter((rule) => stringValue(rule.rule_type) === "points_rule")
      .flatMap((rule) => {
        const key = stringValue(rule.match_value);
        const points = numberValue(rule.replacement_value);
        const calculationType = stringValue(objectValue(rule.rule_config).calculation_type);
        return key && points != null && calculationType
          ? [[key, {
            points,
            calculationType,
            label: stringValue(objectValue(rule.rule_config).label) ?? key,
            awardLabel: stringValue(objectValue(rule.rule_config).award_label) ?? key,
          }]]
          : [];
      }),
  );
  const awardsByExhibitor = new Map<string, DetailedAward[]>();
  for (const award of awards) {
    const key = comparableName(award.exhibitorName);
    awardsByExhibitor.set(key, [...(awardsByExhibitor.get(key) ?? []), award]);
  }
  return totals.map((total) => {
    const matchedAwards = awardsByExhibitor.get(comparableName(total.exhibitorName)) ?? [];
    const awardBreakdowns = matchedAwards.flatMap((award) => {
      const rule = scoringRules.get(award.ruleKey);
      if (!rule) return [];
      const calculatedPoints = rule.calculationType.endsWith("_multiplier")
        ? rule.points * award.shownCount
        : rule.points;
      return [{
        ruleKey: award.ruleKey,
        ruleLabel: rule.label,
        awardLabel: rule.awardLabel,
        calculationType: rule.calculationType,
        pointsPerAward: rule.points,
        shownCount: rule.calculationType.endsWith("_multiplier") ? award.shownCount : null,
        calculatedPoints,
        placement: award.placement,
        breed: award.breed,
      }];
    });
    const calculatedPoints = awardBreakdowns.reduce(
      (totalPoints, award) => totalPoints + award.calculatedPoints,
      0,
    );
    const breeds = [
      ...new Set(
        matchedAwards
          .map((award) => award.breed)
          .filter((value): value is string => Boolean(value)),
      ),
    ];
    return {
      ...total,
      breed: total.breed ?? (breeds.length === 1 ? breeds[0] : null),
      calculatedPoints,
      placement: matchedAwards.length === 1 ? matchedAwards[0].placement : null,
      reviewNotes: awardBreakdowns.length
        ? `${awardBreakdowns.length} rule-matched detailed result${awardBreakdowns.length === 1 ? "" : "s"} used for calculation.${usedAwardFallback ? " Source total was not read; verify against the original report." : ""}`
        : "No rule-matched detailed results were found; verify manually.",
      awardBreakdowns,
    };
  });
}

function totalsFromDetailedAwards(awards: DetailedAward[]): ExhibitorTotal[] {
  const seen = new Map<string, ExhibitorTotal>();
  for (const award of awards) {
    const key = comparableName(award.exhibitorName);
    if (!key || seen.has(key)) continue;
    seen.set(key, {
      exhibitorName: award.exhibitorName,
      breed: award.breed,
      sourcePoints: 0,
    });
  }
  return [...seen.values()];
}

function comparableName(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function applyRules(originalName: string, rules: JsonObject[]) {
  const words = originalName.replace(/\s+/g, " ").trim().split(" ");
  const kept: string[] = [];
  for (const word of words) {
    const comparable = word.toLowerCase().replace(/[^a-z0-9]/g, "");
    if (addressCutoffWords.has(comparable) || /^\d/.test(word)) break;
    kept.push(word);
  }
  const cleaned = kept.join(" ").trim() || originalName.trim();
  const comparable = cleaned.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  const nameWords = new Set(comparable.split(" ").filter(Boolean));
  const nameRules = rules.filter((rule) =>
    ["name_alias", "name_pattern"].includes(stringValue(rule.rule_type) ?? "") && stringValue(rule.replacement_value),
  ).sort((a, b) => (stringValue(b.match_value) ?? "").split(" ").length - (stringValue(a.match_value) ?? "").split(" ").length);
  for (const rule of nameRules) {
    const matchWords = (stringValue(rule.match_value) ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").split(" ").filter(Boolean);
    const config = objectValue(rule.rule_config);
    const exact = stringValue(config.match_mode) === "exact";
    if ((exact && comparable === matchWords.join(" ")) || (!exact && matchWords.every((word) => nameWords.has(word)))) {
      return stringValue(rule.replacement_value) ?? cleaned;
    }
  }
  return cleaned;
}

async function deletePendingRows(importId: string) {
  const url = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_result_import_rows`);
  url.searchParams.set("import_id", `eq.${importId}`);
  url.searchParams.set("status", "eq.pending");
  const response = await fetch(url, { method: "DELETE", headers: serviceHeaders });
  if (!response.ok) throw new Error("Unable to replace the earlier unreviewed draft.");
}

async function refreshBlankSourcePoints(importId: string, totals: ExhibitorTotal[]) {
  const url = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_result_import_rows`);
  url.searchParams.set("select", "id,exhibitor_name,source_points");
  url.searchParams.set("import_id", `eq.${importId}`);
  url.searchParams.set("status", "eq.pending");
  const response = await fetch(url, { headers: serviceHeaders });
  if (!response.ok) throw new Error("Unable to load the existing review rows.");
  const pointsByExhibitor = new Map(totals.map((total) => [comparableName(total.exhibitorName), total.sourcePoints]));
  let updated = 0;
  for (const row of (await response.json() as unknown[]).map(objectValue)) {
    const id = stringValue(row.id);
    const existingPoints = numberValue(row.source_points);
    const sourcePoints = pointsByExhibitor.get(comparableName(stringValue(row.exhibitor_name) ?? ""));
    if (!id || existingPoints == null || existingPoints !== 0 || sourcePoints == null) continue;
    const update = await fetch(`${supabaseUrl}/rest/v1/club_sweepstakes_result_import_rows?id=eq.${encodeURIComponent(id)}`, {
      method: "PATCH",
      headers: { ...serviceHeaders, Prefer: "return=minimal" },
      body: JSON.stringify({ source_points: sourcePoints }),
    });
    if (!update.ok) throw new Error("Unable to refresh source points in the review draft.");
    updated += 1;
  }
  return updated;
}

async function deleteInvalidEasy2ShowFooterRows(importId: string) {
  const url = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_result_import_rows`);
  url.searchParams.set("import_id", `eq.${importId}`);
  url.searchParams.set("status", "eq.pending");
  url.searchParams.set("exhibitor_name", "ilike.*easy2show*");
  const response = await fetch(url, { method: "DELETE", headers: serviceHeaders });
  if (!response.ok) throw new Error("Unable to remove an invalid Easy2Show footer row.");
}

async function insertRows(importId: string, clubId: string, rows: CalculatedResult[]) {
  for (const row of rows) {
    const response = await fetch(`${supabaseUrl}/rest/v1/club_sweepstakes_result_import_rows`, {
      method: "POST",
      headers: { ...serviceHeaders, Prefer: "return=representation" },
      body: JSON.stringify({
      import_id: importId,
      club_id: clubId,
      exhibitor_name: row.exhibitorName,
      species: "Rabbit",
      breed: row.breed,
      source_points: row.sourcePoints,
      calculated_points: row.calculatedPoints,
      placement: row.placement,
      review_notes: row.reviewNotes,
      status: "pending",
      }),
    });
    if (!response.ok) throw new Error("Unable to save the report-reading draft.");
    const inserted = objectValue(arrayValue(await response.json())[0]);
    const resultRowId = stringValue(inserted.id);
    if (!resultRowId || !row.awardBreakdowns.length) continue;
    const detailsResponse = await fetch(`${supabaseUrl}/rest/v1/club_sweepstakes_result_awards`, {
      method: "POST",
      headers: { ...serviceHeaders, Prefer: "return=minimal" },
      body: JSON.stringify(row.awardBreakdowns.map((award) => ({
        result_row_id: resultRowId,
        club_id: clubId,
        rule_key: award.ruleKey,
        rule_label: award.ruleLabel,
        award_label: award.awardLabel,
        calculation_type: award.calculationType,
        points_per_award: award.pointsPerAward,
        shown_count: award.shownCount,
        calculated_points: award.calculatedPoints,
        placement: award.placement,
        breed: award.breed,
      }))),
    });
    if (!detailsResponse.ok) throw new Error("Unable to save the calculation breakdown.");
  }
}

async function importBreedPaybackCounts(
  clubId: string,
  seasonId: string,
  expectedReportId: string,
  breedCounts: BreedCount[],
) {
  if (!breedCounts.length) return 0;
  const settings = await serviceSingle(
    "club_sweepstakes_breed_payback_settings",
    `select=is_enabled,collection_cents_per_rabbit,breed_fund_cents_per_rabbit,isrba_allocation_cents_per_rabbit&club_id=eq.${encodeURIComponent(clubId)}`,
  );
  if (settings.is_enabled !== true) return 0;

  const existingUrl = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_breed_payback_obligations`);
  existingUrl.searchParams.set("select", "breed,count_source");
  existingUrl.searchParams.set("expected_report_id", `eq.${expectedReportId}`);
  const existingResponse = await fetch(existingUrl, { headers: serviceHeaders });
  if (!existingResponse.ok) throw new Error("Unable to check existing show obligations.");
  const manuallyCorrectedBreeds = new Set(
    arrayValue(await existingResponse.json())
      .filter((row) => stringValue(row.count_source) !== "report")
      .map((row) => stringValue(row.breed)?.toLowerCase())
      .filter((breed): breed is string => Boolean(breed)),
  );
  const collectionCents = numberValue(settings.collection_cents_per_rabbit) ?? 10;
  const breedFundCents = numberValue(settings.breed_fund_cents_per_rabbit) ?? 8;
  const isrbaCents = numberValue(settings.isrba_allocation_cents_per_rabbit) ?? 2;
  const records = breedCounts
    .filter((count) => !manuallyCorrectedBreeds.has(count.breed.toLowerCase()))
    .map((count) => ({
      club_id: clubId,
      season_id: seasonId,
      expected_report_id: expectedReportId,
      breed: count.breed,
      rabbits_shown: count.rabbitsShown,
      collection_cents_per_rabbit: collectionCents,
      breed_fund_cents_per_rabbit: breedFundCents,
      isrba_allocation_cents_per_rabbit: isrbaCents,
      expected_collection_cents: count.rabbitsShown * collectionCents,
      expected_breed_fund_cents: count.rabbitsShown * breedFundCents,
      expected_isrba_allocation_cents: count.rabbitsShown * isrbaCents,
      count_source: "report",
      notes: "Read from a report package; requires staff review.",
    }));
  if (!records.length) return 0;
  const response = await fetch(
    `${supabaseUrl}/rest/v1/club_sweepstakes_breed_payback_obligations?on_conflict=expected_report_id,breed`,
    {
      method: "POST",
      headers: { ...serviceHeaders, Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(records),
    },
  );
  if (!response.ok) throw new Error("Unable to save the report-read breed counts.");
  return records.length;
}

function findAttachment(files: JsonObject[], fileNameParts: string[]) {
  return files.find((file) => {
    const name = (stringValue(file.file_name) ?? "").toLowerCase();
    return fileNameParts.some((part) => name.includes(part));
  });
}
function isPdfAttachment(file: JsonObject) {
  const name = (stringValue(file.file_name) ?? "").toLowerCase();
  const contentType = (stringValue(file.content_type) ?? "").toLowerCase();
  return name.endsWith(".pdf") || contentType === "application/pdf";
}
function detectReportSource(
  files: JsonObject[],
  subject: string | null,
  extractedSummary: JsonObject,
): ReportSource {
  const sourceGuess = stringValue(extractedSummary.source_guess)?.toLowerCase();
  if (sourceGuess === "easy2show") return "easy2show";
  if (sourceGuess === "ringmaster_show") return "ringmaster_show";
  if (sourceGuess === "grand_champion") return "grand_champion";
  const evidence = [
    subject ?? "",
    ...files.map((file) => stringValue(file.file_name) ?? ""),
  ].join(" ").toLowerCase();
  if (evidence.includes("easy2show") || evidence.includes("exh_total_points") || evidence.includes("details_by_breed")) return "easy2show";
  if (evidence.includes("ringmaster show") || evidence.includes("ringmaster_show") || evidence.includes("ringmastershow") || evidence.includes("sweepstakes_report") || evidence.includes("breed_results_detail_report")) return "ringmaster_show";
  if (evidence.includes("grand champion") || evidence.includes("grand_champion") || evidence.includes("grandchampion") || evidence.includes("specialtyclubpoints")) return "grand_champion";
  return "standard";
}
function arrayValue(value: unknown): JsonObject[] { return Array.isArray(value) ? value.map(objectValue).filter((value) => Object.keys(value).length) : []; }
function objectValue(value: unknown): JsonObject { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {}; }
function stringValue(value: unknown): string | null { return typeof value === "string" && value.trim() ? value.trim() : null; }
function numberValue(value: unknown): number | null { return typeof value === "number" && Number.isFinite(value) ? value : typeof value === "string" && Number.isFinite(Number(value)) ? Number(value) : null; }
function readerServiceError(subject: string, status: number) {
  return new ReaderServiceError(
    status === 429
      ? `The secure ${subject} reader is temporarily busy. Wait a minute and try again; your existing review rows were kept.`
      : `Secure ${subject} reading service returned ${status}.`,
    status,
  );
}
function parseJson(value: string): unknown { try { return JSON.parse(value); } catch (_) { return null; } }
function toBase64(bytes: Uint8Array) { let binary = ""; for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(binary); }
function respond(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
