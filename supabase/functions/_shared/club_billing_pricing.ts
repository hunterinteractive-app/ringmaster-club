// Annual licensed quantities. All money is in USD cents.
export const PRICING_VERSION = "base_plus_usage_v1";
export const PLAN_KEY = "membership_plus";
export const PRICE_AMOUNTS = {
  rmc_membership_base_annual_v1: 10000,
  rmc_member_annual_v1: 100,
  rmc_sanctions_base_annual_v1: 5000,
  rmc_sanction_annual_v1: 50,
} as const;
export type PriceKey = keyof typeof PRICE_AMOUNTS;
export type BillingQuote = {
  active_member_count: number;
  sanctions_issued: number;
  sanctions_sweepstakes_enabled: boolean;
  pricing: { pricing_version: string };
};
export type BillingLine = {
  lookupKey: PriceKey;
  quantity: number;
  unitAmount: number;
};
function count(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error("Invalid server-calculated billing quantity.");
  }
  return value;
}
export function billingLines(
  quote: BillingQuote,
  includeSanctions: boolean,
): BillingLine[] {
  if (quote.pricing?.pricing_version !== PRICING_VERSION) {
    throw new Error("Billing pricing is out of date.");
  }
  const members = count(quote.active_member_count);
  const sanctions = count(quote.sanctions_issued);
  const lines: BillingLine[] = [{
    lookupKey: "rmc_membership_base_annual_v1",
    quantity: 1,
    unitAmount: 10000,
  }];
  if (members > 0) {
    lines.push({
      lookupKey: "rmc_member_annual_v1",
      quantity: members,
      unitAmount: 100,
    });
  }
  if (includeSanctions) {
    lines.push({
      lookupKey: "rmc_sanctions_base_annual_v1",
      quantity: 1,
      unitAmount: 5000,
    });
    if (sanctions > 0) {
      lines.push({
        lookupKey: "rmc_sanction_annual_v1",
        quantity: sanctions,
        unitAmount: 50,
      });
    }
  }
  return lines;
}
export function annualTotal(lines: BillingLine[]): number {
  const cents = lines.reduce(
    (total, line) => total + line.unitAmount * line.quantity,
    0,
  );
  if (!Number.isSafeInteger(cents)) {
    throw new Error("Annual billing total is too large.");
  }
  return cents;
}
export type AnnualPrice = {
  id: string;
  active: boolean;
  lookup_key: string | null;
  currency: string;
  unit_amount: number | null;
  billing_scheme: string;
  recurring?: {
    interval?: string;
    interval_count?: number;
    usage_type?: string;
  };
};
export function validatePrice(
  price: AnnualPrice | undefined,
  line: BillingLine,
): AnnualPrice {
  if (
    !price || !price.active || price.lookup_key !== line.lookupKey ||
    price.currency !== "usd" ||
    price.unit_amount !== line.unitAmount ||
    price.billing_scheme !== "per_unit" ||
    price.recurring?.interval !== "year" ||
    price.recurring?.interval_count !== 1 ||
    price.recurring?.usage_type !== "licensed"
  ) {
    throw new Error(
      `Annual Stripe price does not match the flyer: ${line.lookupKey}.`,
    );
  }
  return price;
}

export type SubscriptionItem = {
  id: string;
  price: { id: string; lookup_key: string | null };
};
export function subscriptionItemChanges(
  existing: SubscriptionItem[],
  desired: Array<BillingLine & { price: AnnualPrice }>,
) {
  const changes: Array<
    { id?: string; price?: string; quantity?: number; deleted?: boolean }
  > = [];
  for (const item of existing) {
    if (!item.price.lookup_key || !(item.price.lookup_key in PRICE_AMOUNTS)) {
      continue;
    }
    const line = desired.find((line) =>
      line.lookupKey === item.price.lookup_key
    );
    changes.push(
      line
        ? { id: item.id, price: line.price.id, quantity: line.quantity }
        : { id: item.id, deleted: true },
    );
  }
  for (const line of desired) {
    if (!existing.some((item) => item.price.lookup_key === line.lookupKey)) {
      changes.push({ price: line.price.id, quantity: line.quantity });
    }
  }
  return changes;
}
