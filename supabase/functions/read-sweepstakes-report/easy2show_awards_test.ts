import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type Easy2ShowPointRule,
  parseEasy2ShowClassAwards,
} from "./easy2show_awards.ts";

const multiplierRules: Easy2ShowPointRule[] = [
  ["1st", 6],
  ["2nd", 4],
  ["3rd", 3],
  ["4th", 2],
  ["5th", 1],
].map(([ordinal]) => ({
  matchValue: `class_placement_multiplier:${ordinal} place`,
  awardLabel: `${ordinal} place`,
  calculationType: "class_size_multiplier",
}));

Deno.test("uses each Easy2Show class entry count as the placement multiplier", () => {
  const awards = parseEasy2ShowClassAwards([
    {
      y: 700,
      fragments: [
        { x: 25, text: "Sr. Buck (" },
        { x: 60, text: "5 / 3" },
        { x: 90, text: ")" },
        { x: 300, text: "Jr. Doe (6/4)" },
      ],
    },
    {
      y: 680,
      fragments: [
        { x: 30, text: "1" },
        { x: 175, text: "Raines Nickie" },
        { x: 305, text: "1" },
        { x: 445, text: "Raines Jack" },
      ],
    },
    {
      y: 660,
      fragments: [
        { x: 30, text: "2" },
        { x: 175, text: "Raines Jack" },
        { x: 305, text: "2" },
        { x: 445, text: "Raines Nickie" },
      ],
    },
  ], multiplierRules);

  assertEquals(awards, [
    {
      exhibitor_name: "Raines Nickie",
      rule_key: "class_placement_multiplier:1st place",
      shown_count: 5,
      placement: "1st place",
    },
    {
      exhibitor_name: "Raines Jack",
      rule_key: "class_placement_multiplier:1st place",
      shown_count: 6,
      placement: "1st place",
    },
    {
      exhibitor_name: "Raines Jack",
      rule_key: "class_placement_multiplier:2nd place",
      shown_count: 5,
      placement: "2nd place",
    },
    {
      exhibitor_name: "Raines Nickie",
      rule_key: "class_placement_multiplier:2nd place",
      shown_count: 6,
      placement: "2nd place",
    },
  ]);
});

Deno.test("keeps flat placement rules at one point unit", () => {
  const awards = parseEasy2ShowClassAwards([
    {
      y: 680,
      fragments: [
        { x: 30, text: "1" },
        { x: 175, text: "Raines Nickie" },
      ],
    },
  ], [{
    matchValue: "class_placement_flat:1st place",
    awardLabel: "1st place",
    calculationType: "flat_points",
  }]);

  assertEquals(awards, [{
    exhibitor_name: "Raines Nickie",
    rule_key: "class_placement_flat:1st place",
    shown_count: 1,
    placement: "1st place",
  }]);
});

Deno.test("does not invent a multiplier when the class count is missing", () => {
  const awards = parseEasy2ShowClassAwards([
    {
      y: 680,
      fragments: [
        { x: 30, text: "1" },
        { x: 175, text: "Raines Nickie" },
      ],
    },
  ], multiplierRules);

  assertEquals(awards, []);
});

Deno.test("reproduces the reported Standard Chinchilla show totals", () => {
  const classLines = (
    y: number,
    shown: number,
    exhibitors: string[],
  ) => [
    {
      y,
      fragments: [{ x: 25, text: `Class (${shown}/${exhibitors.length})` }],
    },
    ...exhibitors.map((exhibitor, index) => ({
      y: y - index - 1,
      fragments: [
        { x: 30, text: String(index + 1) },
        { x: 175, text: exhibitor },
      ],
    })),
  ];
  const awards = parseEasy2ShowClassAwards([
    ...classLines(800, 5, [
      "Raines Nickie",
      "Raines Jack",
      "Raines Nickie",
      "Raines Nickie",
      "Hand Levi",
    ]),
    ...classLines(700, 3, [
      "Raines Nickie",
      "Bailey Christine",
      "Raines Nickie",
    ]),
    ...classLines(600, 5, [
      "Raines Nickie",
      "Bailey Christine",
      "Raines Nickie",
      "Raines Jack",
      "Raines Nickie",
    ]),
    ...classLines(500, 6, [
      "Raines Jack",
      "Raines Nickie",
      "Bailey Christine",
      "Raines Nickie",
      "Hand Katie",
    ]),
  ], multiplierRules);
  const pointValues: Record<string, number> = {
    "1st place": 6,
    "2nd place": 4,
    "3rd place": 3,
    "4th place": 2,
    "5th place": 1,
  };
  const totals = new Map<string, number>();
  for (const award of awards) {
    totals.set(
      award.exhibitor_name,
      (totals.get(award.exhibitor_name) ?? 0) +
        pointValues[award.placement] * award.shown_count,
    );
  }

  assertEquals(Object.fromEntries(totals), {
    "Raines Nickie": 168,
    "Raines Jack": 66,
    "Hand Levi": 5,
    "Bailey Christine": 50,
    "Hand Katie": 6,
  });
});
