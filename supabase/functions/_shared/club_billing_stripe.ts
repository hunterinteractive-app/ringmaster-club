import {
  AnnualPrice,
  BillingLine,
  validatePrice,
} from "./club_billing_pricing.ts";
export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}.`);
  return value;
}
export async function stripeRequest<T>(
  path: string,
  body?: URLSearchParams,
  idempotencyKey?: string,
): Promise<T> {
  const response = await fetch(`https://api.stripe.com${path}`, {
    method: body ? "POST" : "GET",
    headers: {
      Authorization: `Bearer ${requiredEnv("STRIPE_SECRET_KEY")}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Stripe-Version": "2026-08-26.dahlia",
      ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}),
    },
    body: body?.toString(),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload?.error?.message ?? "Stripe request failed.");
  }
  return payload as T;
}
export async function pricedLines(lines: BillingLine[]) {
  return await Promise.all(lines.map(async (line) => {
    const query = new URLSearchParams({
      active: "true",
      "lookup_keys[]": line.lookupKey,
      limit: "1",
    });
    const result = await stripeRequest<{ data: AnnualPrice[] }>(
      `/v1/prices?${query}`,
    );
    return { ...line, price: validatePrice(result.data[0], line) };
  }));
}
