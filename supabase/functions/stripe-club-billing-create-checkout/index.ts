import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import {
  annualTotal,
  billingLines,
  BillingQuote,
  PLAN_KEY,
  PRICING_VERSION,
  subscriptionItemChanges,
} from "../_shared/club_billing_pricing.ts";
import {
  pricedLines,
  requiredEnv,
  stripeRequest,
} from "../_shared/club_billing_stripe.ts";

function returnUrl(): URL {
  const url = new URL(
    Deno.env.get("CLUB_APP_URL") || Deno.env.get("RINGMASTER_CLUB_APP_URL") ||
      "https://club.ringmasterone.com/",
  );
  if (url.protocol !== "https:" && url.hostname !== "localhost") {
    throw new Error("Club return URL must use HTTPS.");
  }
  return url;
}

type Subscription = {
  id: string;
  status: string;
  customer: string;
  metadata: Record<string, string>;
  items: {
    data: Array<
      { id: string; price: { id: string; lookup_key: string | null } }
    >;
  };
};

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method === "GET") {
    // Public readiness exposes only catalog availability, never credentials or club data.
    try {
      await pricedLines(
        billingLines({
          active_member_count: 1,
          sanctions_issued: 1,
          sanctions_sweepstakes_enabled: true,
          pricing: { pricing_version: PRICING_VERSION },
        }, true),
      );
      return jsonResponse({ ready: true, pricing_version: PRICING_VERSION });
    } catch (error) {
      const secret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
      console.error(
        "Billing catalog readiness:",
        errorMessage(error).replaceAll(secret || "__no_secret__", "[redacted]"),
      );
      return jsonResponse({
        ready: false,
        pricing_version: PRICING_VERSION,
        stripe_mode: /^(sk|rk)_live_/.test(secret)
          ? "live"
          : /^(sk|rk)_test_/.test(secret)
          ? "test"
          : secret
          ? "unknown"
          : "unconfigured",
      }, 503);
    }
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  try {
    await authenticatedUser(request);
    const body = await request.json();
    const clubId = typeof body.club_id === "string" ? body.club_id.trim() : "";
    if (!clubId || !["plan", "renewal"].includes(body.checkout_type)) {
      throw new Error("A club and valid checkout type are required.");
    }
    if (
      body.include_sanctions !== undefined &&
      typeof body.include_sanctions !== "boolean"
    ) throw new Error("Invalid sanctions selection.");
    const caller = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_ANON_KEY"),
      {
        global: {
          headers: { Authorization: request.headers.get("Authorization")! },
        },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    // This RPC enforces payments.manage and measures covered people and issued numbers.
    const { data, error } = await caller.rpc("get_club_renewal_preview", {
      p_club_id: clubId,
    });
    if (error) throw error;
    const quote = data as BillingQuote;
    const includeSanctions = body.include_sanctions ??
      quote.sanctions_sweepstakes_enabled;
    const lines = await pricedLines(billingLines(quote, includeSanctions));
    const total = annualTotal(lines);
    const admin = serviceClient();
    const { data: account, error: accountError } = await admin.from(
      "club_billing_accounts",
    ).select("stripe_customer_id,billing_email").eq("club_id", clubId)
      .maybeSingle();
    if (accountError) throw accountError;
    const { data: plan, error: planError } = await admin.from(
      "club_plan_subscriptions",
    ).select("stripe_subscription_id,status").eq("club_id", clubId)
      .maybeSingle();
    if (planError) throw planError;
    const metadata = {
      app: "ringmaster_club",
      club_id: clubId,
      plan_key: PLAN_KEY,
      pricing_version: PRICING_VERSION,
      include_sanctions: String(includeSanctions),
      active_member_count: String(quote.active_member_count),
      sanctions_issued: String(quote.sanctions_issued),
    };
    if (plan?.stripe_subscription_id) {
      const subscription = await stripeRequest<Subscription>(
        `/v1/subscriptions/${encodeURIComponent(plan.stripe_subscription_id)}`,
      );
      if (!["canceled", "incomplete_expired"].includes(subscription.status)) {
        if (subscription.customer !== account?.stripe_customer_id) {
          throw new Error("Subscription customer does not match this club.");
        }
        if (
          !subscription.items.data.some((item) =>
            item.price.lookup_key === "rmc_membership_base_annual_v1"
          )
        ) {
          throw new Error(
            "This club has a legacy subscription. Contact support to switch pricing at renewal; a second subscription will not be created.",
          );
        }
        // Keep the existing annual period; do not create a second subscription or charge a proration.
        const form = new URLSearchParams({ proration_behavior: "none" });
        subscriptionItemChanges(subscription.items.data, lines).forEach(
          (change, index) => {
            for (const [key, value] of Object.entries(change)) {
              form.set(`items[${index}][${key}]`, String(value));
            }
          },
        );
        for (const [key, value] of Object.entries(metadata)) {
          form.set(`metadata[${key}]`, value);
        }
        await stripeRequest(`/v1/subscriptions/${subscription.id}`, form);
        return jsonResponse({
          updated: true,
          total_annual_cents: total,
          effective: "next_renewal",
        });
      }
    }
    const { data: club, error: clubError } = await admin.from("clubs").select(
      "name,contact_email",
    ).eq("id", clubId).single();
    if (clubError) throw clubError;
    let customerId = account?.stripe_customer_id;
    if (!customerId) {
      const form = new URLSearchParams({
        name: club.name,
        "metadata[club_id]": clubId,
        "metadata[app]": "ringmaster_club",
      });
      if (account?.billing_email || club.contact_email) {
        form.set("email", account?.billing_email || club.contact_email);
      }
      const customer = await stripeRequest<{ id: string }>(
        "/v1/customers",
        form,
        `rmc-customer-${clubId}`,
      );
      customerId = customer.id;
      const { error } = await admin.from("club_billing_accounts").upsert({
        club_id: clubId,
        stripe_customer_id: customerId,
        billing_email: account?.billing_email || club.contact_email,
      }, { onConflict: "club_id" });
      if (error) throw error;
    }
    // Also detect subscriptions missing from our database (for example, a delayed webhook).
    const existing = await stripeRequest<{ data: Subscription[] }>(
      `/v1/subscriptions?customer=${
        encodeURIComponent(customerId)
      }&status=all&limit=100`,
    );
    if (
      existing.data.some((s) =>
        s.metadata?.app === "ringmaster_club" &&
        s.metadata?.club_id === clubId &&
        !["canceled", "incomplete_expired"].includes(s.status)
      )
    ) {
      throw new Error(
        "This club already has a Stripe subscription. Refresh billing or contact support.",
      );
    }
    const success = returnUrl();
    success.searchParams.set("billing_checkout", "success");
    const cancel = returnUrl();
    cancel.searchParams.set("billing_checkout", "cancelled");
    const fingerprint =
      `${clubId}-${quote.active_member_count}-${quote.sanctions_issued}-${includeSanctions}-${
        Math.floor(Date.now() / 600000)
      }`;
    const digest = new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(fingerprint),
      ),
    );
    const suffix = Array.from(
      digest.slice(0, 8),
      (byte) => String.fromCharCode(97 + byte % 26),
    ).join("");
    const form = new URLSearchParams({
      mode: "subscription",
      customer: customerId,
      success_url: success.toString(),
      cancel_url: cancel.toString(),
      client_reference_id: clubId,
      integration_identifier: "ringmaster_club_" + suffix,
    });
    for (const [key, value] of Object.entries(metadata)) {
      form.set(`metadata[${key}]`, value);
      form.set(`subscription_data[metadata][${key}]`, value);
    }
    lines.forEach((line, i) => {
      form.set(`line_items[${i}][price]`, line.price.id);
      form.set(`line_items[${i}][quantity]`, String(line.quantity));
    });
    // Identical quantities within this window reuse a single checkout session.
    const session = await stripeRequest<{ id: string; url: string }>(
      "/v1/checkout/sessions",
      form,
      `rmc-checkout-${fingerprint}`,
    );
    return jsonResponse({
      url: session.url,
      session_id: session.id,
      total_annual_cents: total,
    });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});
