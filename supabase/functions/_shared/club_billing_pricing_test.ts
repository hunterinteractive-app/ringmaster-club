import { strict as assert } from "node:assert";
import {
  AnnualPrice,
  annualTotal,
  billingLines,
  BillingQuote,
  subscriptionItemChanges,
  validatePrice,
} from "./club_billing_pricing.ts";
const quote = (members: number, sanctions: number): BillingQuote => ({
  active_member_count: members,
  sanctions_issued: sanctions,
  sanctions_sweepstakes_enabled: false,
  pricing: { pricing_version: "base_plus_usage_v1" },
});
Deno.test("flyer totals include both annual bases and exact individual quantities", () => {
  for (
    const [members, sanctions, total] of [
      [0, 0, 15000],
      [50, 30, 21500],
      [100, 100, 30000],
      [150, 75, 33750],
      [600, 500, 100000],
    ]
  ) {
    assert.equal(
      annualTotal(billingLines(quote(members, sanctions), true)),
      total,
    );
  }
  assert.equal(annualTotal(billingLines(quote(100, 500), false)), 20000);
  assert.equal(
    annualTotal(billingLines(quote(50, 31), true)) -
      annualTotal(billingLines(quote(50, 30), true)),
    50,
  );
});
Deno.test("zero usage retains both bases and optional suite is not enabled by prior sanctions", () => {
  assert.equal(billingLines(quote(0, 0), true).length, 2);
  assert.equal(billingLines(quote(0, 9000), false).length, 1);
});
Deno.test("reject invalid quantities and stale pricing rather than undercharging", () => {
  for (const members of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => billingLines(quote(members, 0), true));
  }
  assert.throws(() =>
    billingLines({ ...quote(1, 1), pricing: { pricing_version: "old" } }, true)
  );
});
const price: AnnualPrice = {
  id: "price_member",
  active: true,
  lookup_key: "rmc_member_annual_v1",
  currency: "usd",
  unit_amount: 100,
  billing_scheme: "per_unit",
  recurring: { interval: "year", interval_count: 1, usage_type: "licensed" },
};
Deno.test("Stripe catalog must match annual USD amount and licensed recurrence", () => {
  const line = billingLines(quote(10, 0), false)[1];
  assert.equal(validatePrice(price, line).id, "price_member");
  for (
    const invalid of [
      { ...price, unit_amount: 1 },
      { ...price, currency: "eur" },
      { ...price, recurring: { interval: "month" } },
      { ...price, active: false },
    ]
  ) assert.throws(() => validatePrice(invalid, line));
});
Deno.test("renewal updates quantities in place, removes zero usage, and preserves unrelated upgrades", () => {
  const existing = [{
    id: "member",
    price: { id: "price_member", lookup_key: "rmc_member_annual_v1" },
  }, { id: "storage", price: { id: "price_storage", lookup_key: null } }];
  const line = billingLines(quote(20, 0), false)[1];
  assert.deepEqual(subscriptionItemChanges(existing, [{ ...line, price }]), [{
    id: "member",
    price: "price_member",
    quantity: 20,
  }]);
  assert.deepEqual(subscriptionItemChanges(existing, []), [{
    id: "member",
    deleted: true,
  }]);
});
