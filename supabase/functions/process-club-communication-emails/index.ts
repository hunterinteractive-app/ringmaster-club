type CommunicationRow = {
  id: string;
  batch_id: string | null;
  club_id: string;
  template_key: string | null;
  recipient_email: string | null;
  recipient_name: string | null;
  subject: string | null;
  body: string | null;
  message: string | null;
  channel: string;
  status: string;
};

type ClubRow = {
  communication_sender_name: string | null;
  communication_reply_to_email: string | null;
};

type TemplateEnabledRow = {
  club_id: string | null;
  is_enabled: boolean | null;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const DEFAULT_FROM_EMAIL =
  Deno.env.get("COMMUNICATION_FROM_EMAIL") ??
  Deno.env.get("CLUB_COMMUNICATION_FROM_EMAIL") ??
  "noreply@ringmasterone.com";

const headers = {
  apikey: SERVICE_ROLE_KEY,
  authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  "content-type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return json({ error: "Supabase service credentials are not configured." }, 500);
  }

  if (!RESEND_API_KEY) {
    return json({ error: "RESEND_API_KEY is not configured." }, 500);
  }

  const body = await safeJson(request);
  const limit = Math.min(Math.max(Number(body?.limit ?? 25), 1), 100);
  const communicationId =
    typeof body?.communication_id === "string" ? body.communication_id.trim() : "";
  const rows = await selectQueuedCommunications({
    limit,
    communicationId: communicationId || undefined,
  });
  const results = [];

  for (const row of rows) {
    results.push(await processRow(row));
  }

  return json({ processed: results.length, results });
});

async function processRow(row: CommunicationRow) {
  try {
    if (!row.recipient_email) {
      await markFailed(row.id, "Missing recipient email.");
      return { id: row.id, status: "failed", error: "Missing recipient email." };
    }

    if (row.template_key) {
      const enabled = await templateStillEnabled(row.club_id, row.template_key);
      if (!enabled) {
        await markFailed(row.id, "Template is disabled.");
        return { id: row.id, status: "failed", error: "Template is disabled." };
      }
    }

    const latest = await selectCommunication(row.id);
    if (!latest || latest.status !== "queued" || latest.sent_at) {
      return { id: row.id, status: "skipped" };
    }

    const club = await selectClub(row.club_id);
    const senderName = club?.communication_sender_name?.trim() || "RingMaster Club";
    const replyTo =
      club?.communication_reply_to_email?.trim() ||
      Deno.env.get("COMMUNICATION_REPLY_TO_EMAIL") ||
      undefined;
    const from = DEFAULT_FROM_EMAIL.includes("<")
      ? DEFAULT_FROM_EMAIL
      : `${senderName} <${DEFAULT_FROM_EMAIL}>`;

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${RESEND_API_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [row.recipient_email],
        reply_to: replyTo,
        subject: row.subject ?? "RingMaster Club update",
        text: row.body ?? row.message ?? "",
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      await markFailed(row.id, errorText);
      return { id: row.id, status: "failed", error: errorText };
    }

    await patchTable("club_communications", row.id, {
      status: "sent",
      sent_at: new Date().toISOString(),
      failed_at: null,
      error_message: null,
      updated_at: new Date().toISOString(),
    });
    if (row.batch_id) {
      await patchTable("club_communication_batches", row.batch_id, {
        status: "sent",
        sent_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    }
    return { id: row.id, status: "sent" };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await markFailed(row.id, message);
    return { id: row.id, status: "failed", error: message };
  }
}

async function selectQueuedCommunications({
  limit,
  communicationId,
}: {
  limit: number;
  communicationId?: string;
}): Promise<CommunicationRow[]> {
  const url = new URL(`${SUPABASE_URL}/rest/v1/club_communications`);
  url.searchParams.set(
    "select",
    "id,batch_id,club_id,template_key,recipient_email,recipient_name,subject,body,message,channel,status",
  );
  url.searchParams.set("status", "eq.queued");
  url.searchParams.set("channel", "in.(email,both)");
  url.searchParams.set("recipient_email", "not.is.null");
  url.searchParams.set("sent_at", "is.null");
  if (communicationId) {
    url.searchParams.set("id", `eq.${communicationId}`);
  }
  url.searchParams.set("order", "created_at.asc");
  url.searchParams.set("limit", String(limit));

  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(await response.text());
  return await response.json();
}

async function selectCommunication(id: string) {
  const url = new URL(`${SUPABASE_URL}/rest/v1/club_communications`);
  url.searchParams.set("select", "id,status,sent_at");
  url.searchParams.set("id", `eq.${id}`);
  url.searchParams.set("limit", "1");

  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(await response.text());
  const rows = await response.json();
  return rows[0] ?? null;
}

async function selectClub(clubId: string): Promise<ClubRow | null> {
  const url = new URL(`${SUPABASE_URL}/rest/v1/clubs`);
  url.searchParams.set(
    "select",
    "communication_sender_name,communication_reply_to_email",
  );
  url.searchParams.set("id", `eq.${clubId}`);
  url.searchParams.set("limit", "1");

  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(await response.text());
  const rows = await response.json();
  return rows[0] ?? null;
}

async function templateStillEnabled(clubId: string, templateKey: string) {
  const url = new URL(`${SUPABASE_URL}/rest/v1/club_communication_templates`);
  url.searchParams.set("select", "club_id,is_enabled");
  url.searchParams.set("template_key", `eq.${templateKey}`);
  url.searchParams.set("or", `(club_id.is.null,club_id.eq.${clubId})`);

  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error(await response.text());
  const rows = (await response.json()) as TemplateEnabledRow[];
  const clubOverride = rows.find((row) => row.club_id === clubId);
  if (clubOverride) return clubOverride.is_enabled !== false;
  const globalDefault = rows.find((row) => row.club_id === null);
  return globalDefault?.is_enabled === true;
}

async function markFailed(id: string, errorMessage: string) {
  await patchTable("club_communications", id, {
    status: "failed",
    failed_at: new Date().toISOString(),
    error_message: errorMessage.slice(0, 2000),
    updated_at: new Date().toISOString(),
  });
}

async function patchTable(table: string, id: string, payload: Record<string, unknown>) {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${table}`);
  url.searchParams.set("id", `eq.${id}`);
  const response = await fetch(url, {
    method: "PATCH",
    headers,
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error(await response.text());
}

async function safeJson(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const value = await request.json();
    return value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : null;
  } catch (_) {
    return null;
  }
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
