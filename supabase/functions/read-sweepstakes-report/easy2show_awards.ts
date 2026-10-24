export type Easy2ShowLineFragment = {
  x: number;
  text: string;
};

export type Easy2ShowTextLine = {
  y: number;
  fragments: Easy2ShowLineFragment[];
};

export type Easy2ShowPointRule = {
  matchValue: string;
  awardLabel: string;
  calculationType: string;
};

export type Easy2ShowAward = {
  exhibitor_name: string;
  rule_key: string;
  shown_count: number;
  placement: string;
};

type PlacementRule = {
  matchValue: string;
  usesClassSize: boolean;
};

const columns = [
  {
    pageStart: 0,
    pageEnd: 300,
    placeStart: 25,
    placeEnd: 80,
    nameStart: 170,
    nameEnd: 295,
  },
  {
    pageStart: 300,
    pageEnd: Number.POSITIVE_INFINITY,
    placeStart: 300,
    placeEnd: 350,
    nameStart: 440,
    nameEnd: 590,
  },
] as const;

/**
 * Reads Easy2Show's two-column class table after PDF text extraction.
 *
 * The class heading carries the "entries / exhibitors" pair while each
 * following placement row carries only the placement and exhibitor. Keep the
 * latest entry count independently for the left and right tables so a
 * class-size scoring rule receives the correct multiplier.
 */
export function parseEasy2ShowClassAwards(
  lines: Easy2ShowTextLine[],
  pointRules: Easy2ShowPointRule[],
): Easy2ShowAward[] {
  const placementRules = new Map<string, PlacementRule>();
  for (const rule of pointRules) {
    const placement = rule.awardLabel.trim().toLowerCase();
    if (!/^([1-5])(st|nd|rd|th) place$/.test(placement)) continue;
    if (
      rule.calculationType !== "flat_points" &&
      rule.calculationType !== "class_size_multiplier"
    ) {
      continue;
    }
    // Rules arrive in their configured sort order. If duplicate active rules
    // exist for one placement, preserve the first one instead of applying both.
    if (!placementRules.has(placement)) {
      placementRules.set(placement, {
        matchValue: rule.matchValue,
        usesClassSize: rule.calculationType === "class_size_multiplier",
      });
    }
  }

  const shownCounts: Array<number | null> = [null, null];
  const awards: Easy2ShowAward[] = [];
  const orderedLines = [...lines].sort((a, b) => b.y - a.y);

  for (const line of orderedLines) {
    const ordered = [...line.fragments].sort((a, b) => a.x - b.x);
    for (let index = 0; index < columns.length; index += 1) {
      const column = columns[index];
      const tableText = ordered
        .filter((fragment) =>
          fragment.x >= column.pageStart && fragment.x < column.pageEnd
        )
        .map((fragment) => fragment.text)
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();
      const classCount = tableText.match(
        /\(\s*(\d+)\s*\/\s*\d+\s*\)/,
      );
      if (classCount) shownCounts[index] = Number(classCount[1]);

      const place = ordered
        .filter((fragment) =>
          fragment.x >= column.placeStart && fragment.x < column.placeEnd
        )
        .map((fragment) => fragment.text)
        .find((value) => /^[1-5]$/.test(value));
      const exhibitorName = ordered
        .filter((fragment) =>
          fragment.x >= column.nameStart && fragment.x < column.nameEnd
        )
        .map((fragment) => fragment.text)
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();
      if (!place || !exhibitorName || !/[a-z]/i.test(exhibitorName)) continue;

      const suffix = place === "1"
        ? "st"
        : place === "2"
        ? "nd"
        : place === "3"
        ? "rd"
        : "th";
      const placement = `${place}${suffix} place`;
      const rule = placementRules.get(placement.toLowerCase());
      if (!rule) continue;
      const shownCount = rule.usesClassSize ? shownCounts[index] : 1;
      // A multiplier without a readable class heading cannot be calculated
      // safely. Omit it so review shows the missing result instead of a
      // plausible but incorrect flat score.
      if (shownCount == null || shownCount <= 0) continue;

      awards.push({
        exhibitor_name: exhibitorName,
        rule_key: rule.matchValue,
        shown_count: shownCount,
        placement,
      });
    }
  }

  return awards;
}
