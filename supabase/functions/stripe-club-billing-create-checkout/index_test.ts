import { strict as assert } from "node:assert";
import { PRICE_AMOUNTS, PriceKey } from "../_shared/club_billing_pricing.ts";

Deno.env.set("SUPABASE_URL", "https://billing-test.supabase.co");
Deno.env.set("SUPABASE_ANON_KEY", "test-anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
Deno.env.set("STRIPE_SECRET_KEY", "sk_test_fixture");
Deno.env.set("CLUB_APP_URL", "https://club.example.com/");
let handler: (request: Request) => Response | Promise<Response>;
const originalServe = Deno.serve;
Deno.serve = ((callback: typeof handler) => {
  handler = callback;
  return {} as Deno.HttpServer;
}) as typeof Deno.serve;
await import("./index.ts");
Deno.serve = originalServe;

async function exercise(
  options: {
    legacy?: boolean;
    renewal?: boolean;
    denied?: boolean;
    badPrice?: boolean;
    members?: number;
    sanctions?: number;
    include?: boolean;
    anonymous?: boolean;
  } = {},
) {
  const originalFetch = globalThis.fetch;
  const posts: Array<{ path: string; form: URLSearchParams }> = [];
  const response = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(
      typeof input === "string"
        ? input
        : input instanceof URL
        ? input.href
        : input.url,
    );
    const path = url.pathname;
    if (url.hostname === "billing-test.supabase.co") {
      if (path === "/auth/v1/user") {
        return response({ id: "user", email: "test@example.com" });
      }
      if (path.endsWith("/rpc/get_club_renewal_preview")) {
        return options.denied
          ? response({ message: "Permission denied", code: "42501" }, 403)
          : response({
            active_member_count: options.members ?? 100,
            sanctions_issued: options.sanctions ?? 100,
            sanctions_sweepstakes_enabled: false,
            pricing: { pricing_version: "base_plus_usage_v1" },
          });
      }
      if (path.endsWith("/club_billing_accounts")) {
        return response({
          stripe_customer_id: "cus_fixture",
          billing_email: null,
        });
      }
      if (path.endsWith("/club_plan_subscriptions")) {
        return response(
          options.legacy || options.renewal
            ? { stripe_subscription_id: "sub_fixture", status: "active" }
            : null,
        );
      }
      if (path.endsWith("/clubs")) {
        return response({ name: "Fixture Club", contact_email: null });
      }
    }
    if (url.hostname === "api.stripe.com") {
      if (path === "/v1/prices") {
        const key = url.searchParams.get("lookup_keys[]") as PriceKey;
        return response({
          data: [{
            id: "price_" + key,
            active: true,
            lookup_key: key,
            unit_amount: options.badPrice ? 1 : PRICE_AMOUNTS[key],
            currency: "usd",
            billing_scheme: "per_unit",
            recurring: {
              interval: "year",
              interval_count: 1,
              usage_type: "licensed",
            },
          }],
        });
      }
      if (init?.method === "POST") {
        posts.push({ path, form: new URLSearchParams(String(init.body)) });
        return path === "/v1/checkout/sessions"
          ? response({
            id: "cs_fixture",
            url: "https://checkout.stripe.com/fixture",
          })
          : response({ id: "sub_fixture" });
      }
      if (path === "/v1/subscriptions/sub_fixture") {
        return response({
          id: "sub_fixture",
          customer: "cus_fixture",
          status: "active",
          metadata: { app: "ringmaster_club" },
          items: {
            data: [{
              id: "si_base",
              price: {
                id: "price_base",
                lookup_key: options.legacy
                  ? null
                  : "rmc_membership_base_annual_v1",
              },
            }],
          },
        });
      }
      if (path === "/v1/subscriptions") return response({ data: [] });
    }
    throw new Error("Unexpected mocked request: " + url);
  }) as typeof fetch;
  try {
    const headers: Record<string, string> = {
      "content-type": "application/json",
    };
    if (!options.anonymous) headers.Authorization = "Bearer fixture";
    const result = await handler(
      new Request("https://edge.example.com/", {
        method: "POST",
        headers,
        body: JSON.stringify({
          club_id: "club_fixture",
          checkout_type: options.renewal ? "renewal" : "plan",
          include_sanctions: options.include ?? true,
          active_member_count: 1,
          sanctions_issued: 1,
          renewal_preview: { pricing: { checkout_annual_price: 1 } },
        }),
      }),
    );
    return { status: result.status, body: await result.json(), posts };
  } finally {
    globalThis.fetch = originalFetch;
  }
}
Deno.test("checkout ignores client quantities and charges server quote with both bases", async () => {
  const r = await exercise();
  assert.equal(r.status, 200);
  assert.equal(r.body.total_annual_cents, 30000);
  const form = r.posts[0].form;
  assert.equal(form.get("line_items[0][quantity]"), "1");
  assert.equal(form.get("line_items[1][quantity]"), "100");
  assert.equal(form.get("line_items[2][quantity]"), "1");
  assert.equal(form.get("line_items[3][quantity]"), "100");
});
Deno.test("optional suite requires selection even when sanctions exist; zero usage keeps bases", async () => {
  const excluded = await exercise({ include: false });
  assert.equal(excluded.body.total_annual_cents, 20000);
  assert.equal(excluded.posts[0].form.has("line_items[2][price]"), false);
  const zero = await exercise({ members: 0, sanctions: 0 });
  assert.equal(zero.body.total_annual_cents, 15000);
  assert.equal(zero.posts[0].form.has("line_items[2][price]"), false);
});
Deno.test("anonymous, unauthorized, and mismatched catalog requests never create checkout", async () => {
  for (
    const options of [{ anonymous: true }, { denied: true }, { badPrice: true }]
  ) {
    const r = await exercise(options);
    assert.equal(r.status, 400);
    assert.equal(r.posts.length, 0);
  }
});
Deno.test("existing flyer subscriptions update without a second checkout or immediate proration", async () => {
  const r = await exercise({ renewal: true });
  assert.equal(r.status, 200);
  assert.equal(r.body.effective, "next_renewal");
  assert.equal(r.posts[0].path, "/v1/subscriptions/sub_fixture");
  assert.equal(r.posts[0].form.get("proration_behavior"), "none");
});
Deno.test("legacy subscription is protected from silent repricing or duplicate checkout", async () => {
  const r = await exercise({ legacy: true });
  assert.equal(r.status, 400);
  assert.match(r.body.error, /legacy/);
  assert.equal(r.posts.length, 0);
});
