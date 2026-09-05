import "@supabase/functions-js/edge-runtime.d.ts";

type JsonObject = Record<string, unknown>;

type DownloadedAttachment = {
  id: string;
  fileName: string;
  contentType: string;
  size: number | null;
  body: ArrayBuffer;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const resendWebhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET") ?? "";
const inboundDomain = (Deno.env.get("SWEEPSTAKES_REPORT_DOMAIN") ??
  "reports.ringmasterone.com").toLowerCase();
const dbHeaders = {
  apikey: serviceRoleKey,
  authorization: `Bearer ${serviceRoleKey}`,
  "content-type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !resendWebhookSecret) {
    return respond({ error: "Inbound email service is not configured." }, 500);
  }

  const payload = await request.text();
  if (!(await verifyWebhook(request, payload))) {
    return respond({ error: "Invalid webhook signature." }, 401);
  }
  const event = parseJson<JsonObject>(payload);
  const data = objectValue(event?.data);
  const emailId = stringValue(data.email_id);
  if (event?.type !== "email.received" || !emailId) return respond({ received: true, ignored: true });

  const recipient = forwardingSlug(data.to);
  if (!recipient) return respond({ received: true, ignored: true });
  const club = await enabledClub(recipient);
  if (!club) return respond({ received: true, ignored: true });

  const duplicates = await existingPackages(emailId);
  if (duplicates.length) {
    return respond({ received: true, duplicate: true, package_ids: duplicates });
  }

  const email = objectData(await resendJson(`/emails/receiving/${emailId}`));

  const subject = emailSubject(email) ?? emailSubject(data);
  const sender = stringValue(email.from) ?? stringValue(data.from);
  const receivedAt = stringValue(email.created_at) ?? stringValue(data.created_at) ?? new Date().toISOString();
  const packageIds: string[] = [];
  try {
    // Resend can make the attachment list available shortly after the
    // email-received event. The retrieved email itself also contains the
    // attachment metadata, so use it as a fallback rather than dropping files.
    const listedAttachments = arrayData(
      await resendJson(`/emails/receiving/${emailId}/attachments`),
    );
    const attachments = listedAttachments.length
      ? listedAttachments
      : arrayData(email.attachments);
    const downloaded: DownloadedAttachment[] = [];
    for (const attachment of attachments) {
      const attachmentId = stringValue(attachment.id);
      if (!attachmentId) continue;
      const attachmentDetail = objectData(
        await resendJson(`/emails/receiving/${emailId}/attachments/${attachmentId}`),
      );
      const fileName = safeFileName(
        stringValue(attachmentDetail.filename) ??
            stringValue(attachment.filename) ??
          `attachment-${attachmentId}`,
      );
      const downloadUrl =
        stringValue(attachmentDetail.download_url) ??
        stringValue(attachment.download_url);
      if (!downloadUrl) {
        throw new Error(`Resend did not provide a download URL for ${fileName}.`);
      }
      downloaded.push({
        id: attachmentId,
        fileName,
        contentType: stringValue(attachmentDetail.content_type) ??
          stringValue(attachment.content_type) ?? "application/octet-stream",
        size: numberValue(attachmentDetail.size) ?? numberValue(attachment.size),
        body: await downloadResendFile(downloadUrl),
      });
    }

    // A single forwarded email can contain multiple shows. Keep files for a
    // show together, so each group can be matched and drafted independently.
    for (const [groupKey, groupAttachments] of attachmentGroups(downloaded)) {
      const packageId = await createPackage({
        clubId: club.id,
        emailId,
        groupKey,
        subject: subjectForGroup(subject, groupKey),
        sender,
        receivedAt,
      });
      packageIds.push(packageId);
      const basePath = `sweepstakes-reports/${packageId}`;
      await uploadJson(club.bucket, `${basePath}/source-email.json`, retainedEmail(email));
      const manifest: JsonObject[] = [];
      for (const attachment of groupAttachments) {
        const storagePath = `${basePath}/attachments/${attachment.fileName}`;
        await uploadFile(club.bucket, storagePath, attachment.body, attachment.contentType);
        manifest.push({
          provider_attachment_id: attachment.id,
          file_name: attachment.fileName,
          content_type: attachment.contentType,
          size: attachment.size,
          storage_path: storagePath,
        });
      }
      await updatePackage(packageId, {
        storage_path: `${basePath}/source-email.json`,
        attachment_manifest: manifest,
      });
    }
    return respond({ received: true, package_ids: packageIds, attachments: downloaded.length });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await Promise.all(packageIds.map((packageId) => updatePackage(packageId, {
      status: "needs_review",
      review_notes: `Inbound retrieval needs attention: ${message}`.slice(0, 1800),
    })));
    return respond({ received: true, package_ids: packageIds, needs_review: true });
  }
});

async function enabledClub(slug: string) {
  const clubUrl = new URL(`${supabaseUrl}/rest/v1/clubs`);
  clubUrl.searchParams.set("select", "id,document_storage_bucket");
  clubUrl.searchParams.set("slug", `eq.${slug}`);
  clubUrl.searchParams.set("limit", "1");
  const clubRows = await databaseJson(clubUrl);
  const club = Array.isArray(clubRows) ? objectValue(clubRows[0]) : {};
  const id = stringValue(club.id);
  const bucket = stringValue(club.document_storage_bucket);
  if (!id || !bucket) return null;

  const settingsUrl = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_settings`);
  settingsUrl.searchParams.set("select", "club_id");
  settingsUrl.searchParams.set("club_id", `eq.${id}`);
  settingsUrl.searchParams.set("report_intake_enabled", "eq.true");
  settingsUrl.searchParams.set("limit", "1");
  const settings = await databaseJson(settingsUrl);
  return Array.isArray(settings) && settings.length ? { id, bucket } : null;
}

async function existingPackages(emailId: string) {
  const url = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_report_packages`);
  url.searchParams.set("select", "id");
  url.searchParams.set("source_provider_message_id", `eq.${emailId}`);
  const rows = await databaseJson(url);
  return Array.isArray(rows)
    ? rows.map(objectValue).map((row) => stringValue(row.id)).filter((id): id is string => Boolean(id))
    : [];
}

async function createPackage(input: { clubId: string; emailId: string; groupKey: string; subject: string | null; sender: string | null; receivedAt: string }) {
  const response = await fetch(`${supabaseUrl}/rest/v1/club_sweepstakes_report_packages`, {
    method: "POST",
    headers: { ...dbHeaders, Prefer: "return=representation" },
    body: JSON.stringify({
      club_id: input.clubId,
      source_type: "forwarded_email",
      source_subject: input.subject,
      source_sender_email: input.sender,
      source_received_at: input.receivedAt,
      source_provider_message_id: input.emailId,
      source_provider_group_key: input.groupKey,
      status: "pending",
    }),
  });
  if (!response.ok) throw new Error(await response.text());
  const rows = await response.json();
  const id = stringValue(objectValue(Array.isArray(rows) ? rows[0] : null).id);
  if (!id) throw new Error("The report package could not be created.");
  return id;
}

async function updatePackage(id: string, values: JsonObject) {
  const url = new URL(`${supabaseUrl}/rest/v1/club_sweepstakes_report_packages`);
  url.searchParams.set("id", `eq.${id}`);
  const response = await fetch(url, {
    method: "PATCH",
    headers: dbHeaders,
    body: JSON.stringify({ ...values, updated_at: new Date().toISOString() }),
  });
  if (!response.ok) throw new Error(await response.text());
}

async function databaseJson(url: URL) {
  const response = await fetch(url, { headers: dbHeaders });
  if (!response.ok) throw new Error(await response.text());
  return await response.json();
}

async function resendJson(path: string) {
  const response = await fetch(`https://api.resend.com${path}`, { headers: { authorization: `Bearer ${resendApiKey}` } });
  if (!response.ok) throw new Error(await response.text());
  return await response.json();
}

async function downloadResendFile(url: string) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(await response.text());
  return await response.arrayBuffer();
}

async function uploadJson(bucket: string, path: string, value: JsonObject) {
  // Club document buckets intentionally allow report files and plain text, not
  // arbitrary JSON. The retained metadata is a human-readable audit record.
  await uploadFile(bucket, path, new TextEncoder().encode(JSON.stringify(value, null, 2)).buffer, "text/plain");
}

async function uploadFile(bucket: string, path: string, body: ArrayBuffer, contentType: string) {
  const target = `${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${path.split("/").map(encodeURIComponent).join("/")}`;
  const response = await fetch(target, { method: "POST", headers: { ...dbHeaders, "content-type": contentType, "x-upsert": "false" }, body });
  if (!response.ok) throw new Error(await response.text());
}

function forwardingSlug(value: unknown) {
  const recipients = Array.isArray(value) ? value : typeof value === "string" ? [value] : [];
  for (const item of recipients) {
    const match = item.trim().toLowerCase().match(new RegExp(`^([a-z0-9-]+)@${escapeRegex(inboundDomain)}$`));
    if (match) return match[1];
  }
  return null;
}

function retainedEmail(email: JsonObject) {
  const allowed = ["id", "from", "to", "cc", "subject", "created_at", "text", "html", "headers"];
  return Object.fromEntries(allowed.filter((key) => key in email).map((key) => [key, email[key]]));
}

function emailSubject(email: JsonObject) {
  const directSubject = stringValue(email.subject);
  if (directSubject) return directSubject;

  const headers = email.headers;
  if (Array.isArray(headers)) {
    for (const header of headers) {
      const item = objectValue(header);
      const name = stringValue(item.name) ?? stringValue(item.key);
      if (name?.toLowerCase() === "subject") {
        const subject = stringValue(item.value);
        if (subject) return subject;
      }
    }
    return null;
  }

  const headerMap = objectValue(headers);
  for (const [name, value] of Object.entries(headerMap)) {
    if (name.toLowerCase() === "subject") return stringValue(value);
  }
  return null;
}

function objectData(value: unknown) {
  const valueObject = objectValue(value);
  const data = objectValue(valueObject.data);
  return Object.keys(data).length ? data : valueObject;
}
function arrayData(value: unknown) {
  const valueObject = objectValue(value);
  const data = Array.isArray(valueObject.data) ? valueObject.data : value;
  return Array.isArray(data) ? data.map(objectValue).filter((item) => Object.keys(item).length) : [];
}
function objectValue(value: unknown): JsonObject { return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {}; }
function parseJson<T>(value: string): T | null { try { return JSON.parse(value) as T; } catch (_) { return null; } }
function stringValue(value: unknown) { return typeof value === "string" && value.trim() ? value.trim() : null; }
function numberValue(value: unknown) { return typeof value === "number" && Number.isFinite(value) ? value : null; }
function safeFileName(value: string) { return value.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-180) || "attachment"; }

function attachmentGroups(attachments: DownloadedAttachment[]) {
  const groups = new Map<string, DownloadedAttachment[]>();
  for (const attachment of attachments) {
    const key = attachmentGroupKey(attachment.fileName);
    const existing = groups.get(key) ?? [];
    existing.push(attachment);
    groups.set(key, existing);
  }
  if (!groups.size) return new Map([["email", []]]);
  // Ordinary messages are still a single package. Only create a separate
  // catch-all package when the email contains two or more identifiable shows.
  const identified = [...groups.keys()].filter((key) => key !== "email");
  if (identified.length < 2 && groups.has("email")) {
    const combined = [...groups.values()].flat();
    return new Map([["email", combined]]);
  }
  return groups;
}

function attachmentGroupKey(fileName: string) {
  const name = fileName.toUpperCase();
  // Sanction IDs are the most precise signal and cover Grand Champion files.
  const sanction = name.match(/(?:^|[_\-. ])([A-Z]{2,6}\d{3,})(?:[_\-. ]|$)/);
  if (sanction) return `sanction-${sanction[1]}`.toLowerCase();
  // RingMaster Show commonly uses report names such as OPEN_A or YOUTH_B.
  const divisionShow = name.match(/(?:^|[_\-. ])(OPEN|YOUTH)[_\-. ]([A-F])(?:[_\-. ]|$)/);
  if (divisionShow) return `${divisionShow[1]}-${divisionShow[2]}`.toLowerCase();
  return "email";
}

function subjectForGroup(subject: string | null, groupKey: string) {
  if (!subject || groupKey === "email") return subject;
  return `${subject} — ${groupKey.replace(/^sanction-/, "").toUpperCase()}`;
}
function escapeRegex(value: string) { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

async function verifyWebhook(request: Request, payload: string) {
  const id = request.headers.get("svix-id");
  const timestamp = request.headers.get("svix-timestamp");
  const signature = request.headers.get("svix-signature");
  if (!id || !timestamp || !signature || !resendWebhookSecret.startsWith("whsec_")) return false;
  const key = Uint8Array.from(atob(resendWebhookSecret.slice(6)), (char) => char.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(`${id}.${timestamp}.${payload}`)));
  const expected = btoa(String.fromCharCode(...signed));
  return signature.split(" ").some((part) => {
    const [, candidate] = part.split(",", 2);
    return candidate ? safeEqual(expected, candidate) : false;
  });
}
function safeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index++) mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return mismatch === 0;
}
function respond(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
}
