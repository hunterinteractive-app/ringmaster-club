export const squareScopes = [
  "MERCHANT_PROFILE_READ",
  "PAYMENTS_READ",
  "PAYMENTS_WRITE",
  "PAYMENTS_WRITE_ADDITIONAL_RECIPIENTS",
  "ORDERS_READ",
  "ORDERS_WRITE",
] as const;

const squareEnvironment = (Deno.env.get("SQUARE_ENVIRONMENT") ?? "sandbox").toLowerCase();
export const squareConnectBase = squareEnvironment === "production"
  ? "https://connect.squareup.com"
  : "https://connect.squareupsandbox.com";
const squareApiVersion = Deno.env.get("SQUARE_API_VERSION")?.trim() || "2026-05-20";

export function squareEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing Square server configuration: ${name}.`);
  return value;
}

async function squareJson(response: Response): Promise<Record<string, unknown>> {
  const data = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) {
    const errors = Array.isArray(data.errors) ? data.errors : [];
    const detail = errors.length && typeof errors[0] === "object"
      ? String((errors[0] as Record<string, unknown>).detail ?? "")
      : "";
    throw new Error(detail || `Square request failed (${response.status}).`);
  }
  return data;
}

export async function obtainSquareToken(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  return squareJson(await fetch(`${squareConnectBase}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Square-Version": squareApiVersion },
    body: JSON.stringify({
      client_id: squareEnv("SQUARE_APPLICATION_ID"),
      client_secret: squareEnv("SQUARE_APPLICATION_SECRET"),
      ...body,
    }),
  }));
}

export async function squareGet(path: string, accessToken: string): Promise<Record<string, unknown>> {
  return squareJson(await fetch(`${squareConnectBase}${path}`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      "Square-Version": squareApiVersion,
    },
  }));
}

export function normalizeSquareScopes(value: unknown): string[] {
  const values = Array.isArray(value) ? value : typeof value === "string" ? value.split(/[\s,]+/) : [];
  return [...new Set(values.map(String).map((scope) => scope.trim()).filter(Boolean))];
}

export function publicMerchant(data: Record<string, unknown>): Record<string, unknown> {
  const merchant = data.merchant && typeof data.merchant === "object"
    ? data.merchant as Record<string, unknown>
    : {};
  return {
    id: String(merchant.id ?? ""),
    business_name: String(merchant.business_name ?? ""),
    status: String(merchant.status ?? ""),
    country: String(merchant.country ?? ""),
    currency: String(merchant.currency ?? ""),
  };
}

export function usableLocations(data: Record<string, unknown>): Record<string, unknown>[] {
  const locations = Array.isArray(data.locations) ? data.locations : [];
  return locations.flatMap((raw) => {
    if (!raw || typeof raw !== "object") return [];
    const location = raw as Record<string, unknown>;
    const capabilities = Array.isArray(location.capabilities) ? location.capabilities.map(String) : [];
    if (!location.id || location.status !== "ACTIVE" || !capabilities.includes("CREDIT_CARD_PROCESSING")) return [];
    return [{ id: String(location.id), name: String(location.name ?? "Square location") }];
  });
}
