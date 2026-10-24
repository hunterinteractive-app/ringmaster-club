// supabase/functions/stripe-club-billing-subscription-webhook/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "npm:stripe@16.12.0";
import {
  annualTotal,
  billingLines,
  BillingQuote,
  PLAN_KEY,
  PRICING_VERSION,
  subscriptionItemChanges,
} from "../_shared/club_billing_pricing.ts";
import { pricedLines, stripeRequest } from "../_shared/club_billing_stripe.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-06-20",
});

const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET_CLUB_BILLING") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const baseStorageBytes = 104857600; // 100 MB
const storage20GbBytes = 21474836480; // 20 GB

const planPriceIds: Record<string, string | undefined> = {
  small_club_base: Deno.env.get("STRIPE_PRICE_SMALL_CLUB_BASE_YEARLY"),
  standard_club_base: Deno.env.get(
    "STRIPE_PRICE_STANDARD_CLUB_BASE_ACTIVE_YEARLY",
  ),
  standard_club_complete: Deno.env.get(
    "STRIPE_PRICE_STANDARD_CLUB_COMPLETE_YEARLY",
  ),
};

const addonPriceIds: Record<string, string | undefined> = {
  membership_management: Deno.env.get(
    "STRIPE_PRICE_ADDON_MEMBERSHIP_MANAGEMENT_YEARLY",
  ),
  sanction_requests: Deno.env.get(
    "STRIPE_PRICE_ADDON_SANCTION_REQUESTS_YEARLY",
  ),
  events_meetings: Deno.env.get(
    "STRIPE_PRICE_ADDON_EVENTS_MEETINGS_YEARLY",
  ),
  email: Deno.env.get("STRIPE_PRICE_ADDON_EMAIL_YEARLY"),
  sweepstakes: Deno.env.get("STRIPE_PRICE_ADDON_SWEEPSTAKES_YEARLY"),
  storage_20gb: Deno.env.get("STRIPE_PRICE_ADDON_STORAGE_20GB_YEARLY"),
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function priceIdToPlanKey(priceId: string | null | undefined) {
  if (!priceId) return null;

  for (const [planKey, configuredPriceId] of Object.entries(planPriceIds)) {
    if (configuredPriceId && configuredPriceId === priceId) {
      return planKey;
    }
  }

  return null;
}

function priceIdToAddonKey(priceId: string | null | undefined) {
  if (!priceId) return null;

  for (const [addOnKey, configuredPriceId] of Object.entries(addonPriceIds)) {
    if (configuredPriceId && configuredPriceId === priceId) {
      return addOnKey;
    }
  }

  return null;
}

function unixToIso(value: number | null | undefined) {
  if (!value) return null;
  return new Date(value * 1000).toISOString();
}

function subscriptionPeriodStart(subscription: Stripe.Subscription) {
  return unixToIso(
    (subscription as Stripe.Subscription & { current_period_start?: number })
      .current_period_start,
  );
}

function subscriptionPeriodEnd(subscription: Stripe.Subscription) {
  return unixToIso(
    (subscription as Stripe.Subscription & { current_period_end?: number })
      .current_period_end,
  );
}

function itemPeriodStart(
  item: Stripe.SubscriptionItem | null | undefined,
  subscription: Stripe.Subscription,
) {
  const itemStart = (item as
    | (Stripe.SubscriptionItem & { current_period_start?: number })
    | null
    | undefined)?.current_period_start;

  return unixToIso(itemStart) ?? subscriptionPeriodStart(subscription);
}

function itemPeriodEnd(
  item: Stripe.SubscriptionItem | null | undefined,
  subscription: Stripe.Subscription,
) {
  const itemEnd = (item as
    | (Stripe.SubscriptionItem & { current_period_end?: number })
    | null
    | undefined)?.current_period_end;

  return unixToIso(itemEnd) ?? subscriptionPeriodEnd(subscription);
}

function memberLimitForPlan(planKey: string | null) {
  switch (planKey) {
    case "small_club_base":
      return 20;
    case "standard_club_base":
    case "standard_club_complete":
      return null;
    default:
      return null;
  }
}

function planEntitlements(planKey: string | null) {
  if (planKey === "standard_club_base") {
    return {
      show_token_discount_enabled: true,
      show_token_discount_percent: 30,
      show_token_pack_discount_percent: 30,
      show_unlimited_discount_percent: 15,
    };
  }

  if (planKey === "standard_club_complete") {
    return {
      show_token_discount_enabled: true,
      show_token_discount_percent: 50,
      show_token_pack_discount_percent: 50,
      show_unlimited_discount_percent: 15,
    };
  }

  return {
    show_token_discount_enabled: false,
    show_token_discount_percent: 0,
    show_token_pack_discount_percent: 0,
    show_unlimited_discount_percent: 0,
  };
}

function addOnFlagsFromActiveAddOns(
  activeAddOns: Set<string>,
  planKey: string | null,
) {
  const complete = planKey === "standard_club_complete";

  return {
    membership_management_addon_enabled: complete ||
      activeAddOns.has("membership_management"),
    sanction_requests_addon_enabled: complete ||
      activeAddOns.has("sanction_requests"),
    events_meetings_addon_enabled: complete ||
      activeAddOns.has("events_meetings"),
    email_addon_enabled: complete || activeAddOns.has("email"),
    sweepstakes_addon_enabled: complete || activeAddOns.has("sweepstakes"),
    storage_limit_bytes: complete || activeAddOns.has("storage_20gb")
      ? storage20GbBytes
      : baseStorageBytes,
  };
}

async function getClubIdFromSubscription(subscription: Stripe.Subscription) {
  const customerId = typeof subscription.customer === "string"
    ? subscription.customer
    : subscription.customer?.id;

  if (!customerId) return null;

  const { data, error } = await supabase
    .from("club_billing_accounts")
    .select("club_id")
    .eq("stripe_customer_id", customerId)
    .maybeSingle();

  if (error) {
    console.error("Unable to resolve club from customer", error);
    return null;
  }

  return data?.club_id ?? subscription.metadata?.club_id ?? null;
}

async function retrieveExpandedSubscription(subscriptionId: string) {
  return await stripe.subscriptions.retrieve(subscriptionId, {
    expand: ["items.data.price", "latest_invoice"],
  });
}

async function syncSubscription(rawSubscription: Stripe.Subscription) {
  const subscription = await retrieveExpandedSubscription(rawSubscription.id);
  if (
    subscription.items.data.some((item) =>
      item.price.lookup_key === "rmc_membership_base_annual_v1"
    )
  ) {
    await syncFlyerSubscription(subscription);
    return;
  }
  if (
    !subscription.items.data.some((item) => priceIdToPlanKey(item.price.id))
  ) return;
  const clubId = await getClubIdFromSubscription(subscription);

  if (!clubId) {
    console.error("No club_id found for subscription", subscription.id);
    return;
  }

  const status = subscription.status;
  const cancelAtPeriodEnd = subscription.cancel_at_period_end === true;

  let planKey: string | null = null;
  let planItem: Stripe.SubscriptionItem | null = null;
  const activeAddOns = new Set<string>();
  const seenAddonKeys = new Set<string>();

  for (const item of subscription.items.data) {
    const priceId = item.price?.id;
    const itemPlanKey = priceIdToPlanKey(priceId);
    const itemAddonKey = priceIdToAddonKey(priceId);

    if (itemPlanKey) {
      planKey = itemPlanKey;
      planItem = item;
    }

    if (itemAddonKey) {
      seenAddonKeys.add(itemAddonKey);
      if (status === "active" || status === "trialing") {
        activeAddOns.add(itemAddonKey);
      }
    }
  }

  const currentPeriodStart = itemPeriodStart(planItem, subscription);
  const currentPeriodEnd = itemPeriodEnd(planItem, subscription);

  if (!currentPeriodEnd) {
    console.warn("No current_period_end found for subscription", {
      subscription_id: subscription.id,
      plan_item_id: planItem?.id ?? null,
      status,
    });
  }

  const activeBilling = status === "active" || status === "trialing";
  const effectivePlanKey = activeBilling ? planKey : null;
  const entitlements = planEntitlements(effectivePlanKey);
  const addOnFlags = addOnFlagsFromActiveAddOns(activeAddOns, effectivePlanKey);

  await supabase
    .from("clubs")
    .update({
      billing_plan_key: effectivePlanKey ?? "none",
      billing_status: status,
      billing_member_limit: memberLimitForPlan(effectivePlanKey),
      billing_current_period_end: currentPeriodEnd,
      ...entitlements,
      ...addOnFlags,
    })
    .eq("id", clubId);

  if (planKey && planItem) {
    await supabase.from("club_plan_subscriptions").upsert(
      {
        club_id: clubId,
        plan_key: planKey,
        status,
        stripe_subscription_id: subscription.id,
        stripe_subscription_item_id: planItem.id,
        stripe_price_id: planItem.price.id,
        current_period_start: itemPeriodStart(planItem, subscription),
        current_period_end: itemPeriodEnd(planItem, subscription),
        cancel_at_period_end: cancelAtPeriodEnd,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "club_id" },
    );
  }

  for (const item of subscription.items.data) {
    const addOnKey = priceIdToAddonKey(item.price?.id);
    if (!addOnKey) continue;

    await supabase.from("club_addon_subscriptions").upsert(
      {
        club_id: clubId,
        add_on_key: addOnKey,
        status,
        stripe_subscription_id: subscription.id,
        stripe_subscription_item_id: item.id,
        stripe_price_id: item.price.id,
        current_period_start: itemPeriodStart(item, subscription),
        current_period_end: itemPeriodEnd(item, subscription),
        cancel_at_period_end: cancelAtPeriodEnd,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "club_id,add_on_key" },
    );
  }

  for (const addOnKey of Object.keys(addonPriceIds)) {
    if (seenAddonKeys.has(addOnKey)) continue;

    await supabase
      .from("club_addon_subscriptions")
      .update({
        status: "inactive",
        cancel_at_period_end: false,
        updated_at: new Date().toISOString(),
      })
      .eq("club_id", clubId)
      .eq("add_on_key", addOnKey);
  }
}

async function syncFlyerSubscription(subscription: Stripe.Subscription) {
  const clubId = await getClubIdFromSubscription(subscription);
  if (!clubId) {
    throw new Error("No club is linked to the subscription customer.");
  }
  const base = subscription.items.data.find((item) =>
    item.price.lookup_key === "rmc_membership_base_annual_v1"
  )!;
  const suite = subscription.items.data.find((item) =>
    item.price.lookup_key === "rmc_sanctions_base_annual_v1"
  );
  const members =
    subscription.items.data.find((item) =>
      item.price.lookup_key === "rmc_member_annual_v1"
    )?.quantity ?? 0;
  const sanctions =
    subscription.items.data.find((item) =>
      item.price.lookup_key === "rmc_sanction_annual_v1"
    )?.quantity ?? 0;
  const latestInvoice = subscription.latest_invoice;
  const paid = typeof latestInvoice === "object" &&
    latestInvoice?.status === "paid";
  const active = subscription.status === "trialing" ||
    (subscription.status === "active" && paid);
  const status = subscription.status === "active" && !active
    ? "incomplete"
    : subscription.status;
  const isStorage = subscription.items.data.some((item) =>
    item.price.id === addonPriceIds.storage_20gb
  );
  const isEmail = subscription.items.data.some((item) =>
    item.price.id === addonPriceIds.email
  );
  const currentPeriodEnd = itemPeriodEnd(base, subscription);
  const snapshot = {
    pricing_version: PRICING_VERSION,
    active_member_count: members,
    sanctions_issued: sanctions,
    membership_annual_price: 100 + members,
    sanctions_annual_price: suite ? 50 + sanctions * 0.50 : 0,
  };
  const { error: clubError } = await supabase.from("clubs").update({
    billing_plan_key: active ? PLAN_KEY : "none",
    billing_status: status,
    billing_member_limit: null,
    billing_current_period_end: currentPeriodEnd,
    billing_active_member_count: members,
    billing_rolling_12_month_sanction_count: sanctions,
    billing_pricing_snapshot: snapshot,
    membership_management_addon_enabled: active,
    events_meetings_addon_enabled: active,
    sanction_requests_addon_enabled: active && !!suite,
    sweepstakes_addon_enabled: active && !!suite,
    email_addon_enabled: active && isEmail,
    storage_limit_bytes: active && isStorage ? storage20GbBytes : 1073741824,
  }).eq("id", clubId);
  if (clubError) throw clubError;
  const { error: planError } = await supabase.from("club_plan_subscriptions")
    .upsert({
      club_id: clubId,
      plan_key: PLAN_KEY,
      status,
      stripe_subscription_id: subscription.id,
      stripe_subscription_item_id: base.id,
      stripe_price_id: base.price.id,
      current_period_start: itemPeriodStart(base, subscription),
      current_period_end: currentPeriodEnd,
      cancel_at_period_end: subscription.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    }, { onConflict: "club_id" });
  if (planError) throw planError;
  for (const key of ["sanction_requests", "sweepstakes"]) {
    const { error } = await supabase.from("club_addon_subscriptions").upsert({
      club_id: clubId,
      add_on_key: key,
      status: suite ? status : "inactive",
      stripe_subscription_id: subscription.id,
      stripe_subscription_item_id: suite?.id ?? null,
      stripe_price_id: suite?.price.id ?? null,
      current_period_start: itemPeriodStart(suite, subscription),
      current_period_end: currentPeriodEnd,
      cancel_at_period_end: subscription.cancel_at_period_end,
      updated_at: new Date().toISOString(),
    }, { onConflict: "club_id,add_on_key" });
    if (error) throw error;
  }
}

async function refreshFlyerRenewal(subscriptionId: string) {
  const subscription = await retrieveExpandedSubscription(subscriptionId);
  if (
    !subscription.items.data.some((item) =>
      item.price.lookup_key === "rmc_membership_base_annual_v1"
    )
  ) return;
  if (subscription.cancel_at_period_end) return;
  const clubId = await getClubIdFromSubscription(subscription);
  if (!clubId) throw new Error("Renewal club not found.");
  const { data, error } = await supabase.rpc("get_club_renewal_preview", {
    p_club_id: clubId,
  });
  if (error) throw error;
  const quote = data as BillingQuote;
  const includeSanctions = subscription.items.data.some((item) =>
    item.price.lookup_key === "rmc_sanctions_base_annual_v1"
  );
  const lines = await pricedLines(billingLines(quote, includeSanctions));
  annualTotal(lines);
  const form = new URLSearchParams({
    proration_behavior: "none",
    "metadata[active_member_count]": String(quote.active_member_count),
    "metadata[sanctions_issued]": String(quote.sanctions_issued),
  });
  subscriptionItemChanges(subscription.items.data, lines).forEach(
    (change, index) => {
      for (const [key, value] of Object.entries(change)) {
        form.set(`items[${index}][${key}]`, String(value));
      }
    },
  );
  await stripeRequest(`/v1/subscriptions/${subscription.id}`, form);
}

function invoiceSubscriptionId(invoice: unknown): string | null {
  const value = invoice as {
    subscription?: string;
    parent?: { subscription_details?: { subscription?: string } };
  };
  return value.parent?.subscription_details?.subscription ??
    value.subscription ?? null;
}

async function handleCheckoutSessionCompleted(
  session: Stripe.Checkout.Session,
) {
  if (session.metadata?.app !== "ringmaster_club") return;
  const clubId = session.metadata?.club_id;
  const customerId = typeof session.customer === "string"
    ? session.customer
    : session.customer?.id;

  if (clubId && customerId) {
    await supabase.from("club_billing_accounts").upsert(
      {
        club_id: clubId,
        stripe_customer_id: customerId,
        billing_email: session.customer_details?.email ??
          session.customer_email,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "club_id" },
    );
  }

  if (typeof session.subscription === "string") {
    const subscription = await retrieveExpandedSubscription(
      session.subscription,
    );
    await syncSubscription(subscription);
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    if (!webhookSecret) {
      return jsonResponse(
        { error: "Missing STRIPE_WEBHOOK_SECRET_CLUB_BILLING" },
        500,
      );
    }

    const signature = req.headers.get("stripe-signature");

    if (!signature) {
      return jsonResponse({ error: "Missing Stripe signature" }, 400);
    }

    const rawBody = await req.text();

    const event = await stripe.webhooks.constructEventAsync(
      rawBody,
      signature,
      webhookSecret,
    );

    // This account also serves Show and Breeder. Ignore their events before
    // retrieving a subscription or changing any Club billing records.
    const resource = event.data.object as {
      metadata?: Record<string, string>;
      customer?: string | { id: string };
    };
    if (resource.metadata?.app !== "ringmaster_club") {
      const customerId = typeof resource.customer === "string"
        ? resource.customer
        : resource.customer?.id;
      if (!customerId) return jsonResponse({ received: true });
      const { data, error } = await supabase.from("club_billing_accounts")
        .select("club_id").eq("stripe_customer_id", customerId).maybeSingle();
      if (error) throw error;
      if (!data) return jsonResponse({ received: true });
    }

    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutSessionCompleted(
          event.data.object as Stripe.Checkout.Session,
        );
        break;

      case "invoice.upcoming": {
        const id = invoiceSubscriptionId(event.data.object);
        if (id) await refreshFlyerRenewal(id);
        break;
      }
      case "invoice.paid":
      case "invoice.payment_failed": {
        const id = invoiceSubscriptionId(event.data.object);
        if (id) await syncSubscription(await retrieveExpandedSubscription(id));
        break;
      }
      case "checkout.session.async_payment_succeeded":
        await handleCheckoutSessionCompleted(
          event.data.object as Stripe.Checkout.Session,
        );
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
        await syncSubscription(event.data.object as Stripe.Subscription);
        break;

      default:
        console.log(`Unhandled Stripe event: ${event.type}`);
    }

    return jsonResponse({ received: true });
  } catch (error) {
    console.error("stripe-club-billing-subscription-webhook error", error);
    return jsonResponse(
      {
        error: error instanceof Error ? error.message : String(error),
      },
      400,
    );
  }
});
