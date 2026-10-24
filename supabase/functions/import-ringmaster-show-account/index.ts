// supabase/functions/import-ringmaster-show-account/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type RequestBody = {
  action?: "lookup" | "import";
  exhibitor_ids?: string[];
};

type ShowExhibitor = {
  _lookup_source?: string;
  imported_from?: string;
  imported_source_id?: string;
  id: string;
  type: string | null;
  display_name: string | null;
  first_name: string | null;
  last_name: string | null;
  showing_name: string | null;
  email: string | null;
  phone: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  birth_date: string | null;
  arba_number: string | null;
  exhibitor_number: string | number | null;
  is_public_entry: boolean | null;
  print_phone_on_reports: boolean | null;
  group_members: unknown;
  is_active: boolean | null;
  is_test: boolean | null;
  is_merged: boolean | null;
  updated_at: string | null;
};

type ClubExhibitorResult = {
  id: string;
  imported_source_id: string | null;
  showing_name: string | null;
  display_name: string | null;
};

type ResolvedRequiredValues = {
  first_name: string | null;
  last_name: string | null;
  showing_name: string | null;
  email: string;
  phone: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
};

function json(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function clean(value: unknown): string | null {
  const text = (value ?? "").toString().trim();
  return text.length === 0 ? null : text;
}

function normalizeEmail(value: unknown): string | null {
  return clean(value)?.toLowerCase() ?? null;
}

function nameFor(source: ShowExhibitor): string | null {
  const generated = [
    clean(source.first_name),
    clean(source.last_name),
  ]
    .filter((value): value is string => value != null)
    .join(" ")
    .trim();

  return (
    clean(source.display_name) ??
    clean(source.showing_name) ??
    clean(generated)
  );
}

function showingNameFor(source: ShowExhibitor): string | null {
  const generated = [
    clean(source.first_name),
    clean(source.last_name),
  ]
    .filter((value): value is string => value != null)
    .join(" ")
    .trim();

  return (
    clean(source.showing_name) ??
    clean(source.display_name) ??
    clean(generated)
  );
}

function phoneLastFour(value: unknown): string | null {
  const digits = clean(value)?.replace(/\D/g, "") ?? "";

  if (digits.length < 4) {
    return null;
  }

  return digits.slice(-4);
}

function isUuid(value: unknown): value is string {
  if (typeof value !== "string") return false;

  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value.trim());
}

function hasCompleteMailingAddress(
  source: ShowExhibitor,
): boolean {
  const state = clean(source.state)?.toUpperCase() ?? null;

  return (
    clean(source.address_line1) != null &&
    clean(source.city) != null &&
    state != null &&
    state.length === 2 &&
    clean(source.zip) != null
  );
}

function resolveRequiredValues(
  source: ShowExhibitor,
  sharedContactSource: ShowExhibitor | null,
  verifiedEmail: string,
): ResolvedRequiredValues {
  return {
    first_name: clean(source.first_name),
    last_name: clean(source.last_name),
    showing_name: showingNameFor(source),

    email:
      normalizeEmail(source.email) ??
      normalizeEmail(sharedContactSource?.email) ??
      verifiedEmail,

    phone:
      clean(source.phone) ??
      clean(sharedContactSource?.phone),

    address_line1:
      clean(source.address_line1) ??
      clean(sharedContactSource?.address_line1),

    address_line2:
      clean(source.address_line2) ??
      clean(sharedContactSource?.address_line2),

    city:
      clean(source.city) ??
      clean(sharedContactSource?.city),

    state:
      (
        clean(source.state) ??
        clean(sharedContactSource?.state)
      )?.toUpperCase() ?? null,

    zip:
      clean(source.zip) ??
      clean(sharedContactSource?.zip),
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return json(
      {
        status: "error",
        message: "Method not allowed.",
      },
      405,
    );
  }

  const clubUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const clubAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const clubServiceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const showUrl = Deno.env.get("SHOW_SUPABASE_URL") ?? "";
  const showServiceRoleKey =
    Deno.env.get("SHOW_SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (
    !clubUrl ||
    !clubAnonKey ||
    !clubServiceRoleKey ||
    !showUrl ||
    !showServiceRoleKey
  ) {
    return json(
      {
        status: "error",
        message:
          "Required Supabase environment variables are missing.",
      },
      500,
    );
  }

  const authorization = req.headers.get("Authorization");

  if (!authorization) {
    return json(
      {
        status: "unauthorized",
        message: "An authorization header is required.",
      },
      401,
    );
  }

  let body: RequestBody = {};

  try {
    const parsed = await req.json();

    if (
      parsed != null &&
      typeof parsed === "object" &&
      !Array.isArray(parsed)
    ) {
      body = parsed as RequestBody;
    }
  } catch {
    // Empty request body means lookup.
  }

  const action = body.action ?? "lookup";

  if (action !== "lookup" && action !== "import") {
    return json(
      {
        status: "error",
        message: "Unsupported action.",
      },
      400,
    );
  }

  try {
    const clubUserClient = createClient(
      clubUrl,
      clubAnonKey,
      {
        global: {
          headers: {
            Authorization: authorization,
          },
        },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const {
      data: { user },
      error: userError,
    } = await clubUserClient.auth.getUser();

    if (userError || !user) {
      return json(
        {
          status: "unauthorized",
          message:
            userError?.message ??
            "No authenticated Club user was found.",
        },
        401,
      );
    }

    const verifiedEmail = normalizeEmail(user.email);

    if (!verifiedEmail || !user.email_confirmed_at) {
      return json(
        {
          status: "missing_email",
          message:
            "The authenticated account does not have an email address.",
        },
        400,
      );
    }

    const clubAdmin = createClient(
      clubUrl,
      clubServiceRoleKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const showAdmin = createClient(
      showUrl,
      showServiceRoleKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const {
      data: existingClubRows,
      error: existingClubError,
    } = await clubAdmin
      .from("exhibitors")
      .select(
        "id, imported_source_id, showing_name, display_name",
      )
      .eq("owner_user_id", user.id)
      .eq("is_active", true);

    if (existingClubError) {
      throw existingClubError;
    }

    const existingClubAccounts =
      (existingClubRows ?? []) as ClubExhibitorResult[];

    if (
      action === "lookup" &&
      existingClubAccounts.length > 0
    ) {
      return json({
        status: "already_exists",
        exhibitor_count: existingClubAccounts.length,
        exhibitor_ids: existingClubAccounts.map(
          (row) => row.id,
        ),
      });
    }

    const {
      data: showRows,
      error: showError,
    } = await showAdmin.rpc(
      "find_exhibitors_for_club_import",
      {
        p_email: verifiedEmail,
      },
    );

    if (showError) {
      throw showError;
    }

    const matches = (showRows ?? []) as ShowExhibitor[];
    const breederUrl = Deno.env.get("BREEDER_SUPABASE_URL");
    const breederKey = Deno.env.get("BREEDER_SUPABASE_SERVICE_ROLE_KEY");
    if (breederUrl && breederKey) {
      const breeder = createClient(breederUrl, breederKey, {auth:{persistSession:false}});
      const exported = await breeder.rpc("find_exhibitors_for_breeder_export", {p_email:verifiedEmail});
      if (exported.error) throw exported.error;
      for (const item of exported.data ?? []) {
        const p = item.profile;
        // Skip profiles originally copied from the same Show record.
        if (matches.some(m =>
          (p.origin_app === "ringmaster_show" && m.id === p.origin_source_id) ||
          (m.imported_from === "ringmaster_breeder" && m.imported_source_id === item.id))) continue;
        matches.push({...p, id:item.id, type:p.type ?? p.account_type, _lookup_source:"ringmaster_breeder"} as ShowExhibitor);
      }
    }

    if (matches.length === 0) {
      return json({
        status: "not_found",
      });
    }

    if (action === "lookup") {
      return json({
        status: "link_confirmation_required",
        exhibitor_count: matches.length,
        matches: matches.map((source) => ({
          id: source.id,
          source_app: source._lookup_source === "ringmaster_breeder" ? "RingMaster Breeder" : "RingMaster Show",
          display_name: nameFor(source),
          city: clean(source.city),
          state:
            clean(source.state)?.toUpperCase() ?? null,
          phone_last_four: phoneLastFour(source.phone),
          account_type: clean(source.type),
          has_complete_address:
            hasCompleteMailingAddress(source),
        })),
      });
    }

    const requestedIds = Array.isArray(body.exhibitor_ids)
      ? [
          ...new Set(
            body.exhibitor_ids
              .map((value) => clean(value))
              .filter(
                (value): value is string =>
                  value != null && isUuid(value),
              ),
          ),
        ]
      : [];

    if (requestedIds.length === 0) {
      return json(
        {
          status: "invalid_import",
          message:
            "At least one valid exhibitor ID is required.",
        },
        400,
      );
    }

    const allowedIds = new Set(
      matches.map((source) => source.id),
    );

    const invalidIds = requestedIds.filter(
      (id) => !allowedIds.has(id),
    );

    if (invalidIds.length > 0) {
      return json(
        {
          status: "link_not_allowed",
          message:
            "One or more selected RingMaster accounts are not available to this user.",
        },
        403,
      );
    }

    const selectedMatches = matches.filter(
      (source) => requestedIds.includes(source.id),
    );

    /*
     * Youth/dependent records may not have their own address.
     *
     * First use a selected record with a complete mailing address.
     * If none exists, use any eligible Show record returned for the
     * authenticated account.
     */
    const sharedContactSource =
      selectedMatches.find(hasCompleteMailingAddress) ??
      matches.find(hasCompleteMailingAddress) ??
      null;

    const incompleteRecords: Array<{
      exhibitor_id: string;
      display_name: string | null;
      missing_fields: string[];
    }> = [];

    const resolvedValuesById = new Map<
      string,
      ResolvedRequiredValues
    >();

    for (const source of selectedMatches) {
      const requiredValues = resolveRequiredValues(
        source,
        sharedContactSource,
        verifiedEmail,
      );

      resolvedValuesById.set(
        source.id,
        requiredValues,
      );

      /*
       * Address line 2 is optional and should not cause validation
       * to fail.
       */
      const requiredFieldValues = {
        first_name: requiredValues.first_name,
        last_name: requiredValues.last_name,
        showing_name: requiredValues.showing_name,
        email: requiredValues.email,
        phone: requiredValues.phone,
        address_line1: requiredValues.address_line1,
        city: requiredValues.city,
        state: requiredValues.state,
        zip: requiredValues.zip,
      };

      const missingFields = Object.entries(
        requiredFieldValues,
      )
        .filter(([, value]) => value == null)
        .map(([key]) => key);

      if (
        requiredValues.state != null &&
        requiredValues.state.length !== 2
      ) {
        missingFields.push("state");
      }

      if (missingFields.length > 0) {
        incompleteRecords.push({
          exhibitor_id: source.id,
          display_name: nameFor(source),
          missing_fields: [
            ...new Set(missingFields),
          ],
        });
      }
    }

    if (incompleteRecords.length > 0) {
      return json({
        status: "incomplete_match",
        records: incompleteRecords,
      });
    }

    const now = new Date().toISOString();

    const importedRows: ClubExhibitorResult[] = [];
    const alreadyImportedRows: ClubExhibitorResult[] = [];

    for (const source of selectedMatches) {
      const existingImported = existingClubAccounts.find(
        (row) =>
          row.imported_source_id === source.id,
      );

      if (existingImported) {
        alreadyImportedRows.push(existingImported);
        continue;
      }

      const requiredValues =
        resolvedValuesById.get(source.id);

      if (!requiredValues) {
        throw new Error(
          `Resolved import values were not found for exhibitor ${source.id}.`,
        );
      }

      const showingName =
        requiredValues.showing_name!;

      const displayName =
        nameFor(source) ?? showingName;

      const importValues = {
        owner_user_id: user.id,

        first_name:
          requiredValues.first_name!,

        last_name:
          requiredValues.last_name!,

        showing_name: showingName,
        display_name: displayName,

        email:
          requiredValues.email,

        phone:
          requiredValues.phone!,

        address_line1:
          requiredValues.address_line1!,

        address_line2:
          requiredValues.address_line2,

        city:
          requiredValues.city!,

        state:
          requiredValues.state!,

        zip:
          requiredValues.zip!,

        account_type:
          clean(source.type),

        birth_date:
          clean(source.birth_date),

        arba_number:
          clean(source.arba_number),

        source_exhibitor_number:
          source.exhibitor_number == null
            ? null
            : source.exhibitor_number
              .toString()
              .trim(),

        is_public_entry:
          source.is_public_entry ?? false,

        print_phone_on_reports:
          source.print_phone_on_reports ?? false,

        group_members:
          source.group_members ?? null,

        is_active: true,

        imported_from:
          source._lookup_source === "ringmaster_breeder" ? "ringmaster_breeder" : "ringmaster_show",

        imported_source_id:
          source.id,

        imported_at:
          now,

        created_at:
          now,

        updated_at:
          now,
      };

      const {
        data: inserted,
        error: insertError,
      } = await clubAdmin
        .from("exhibitors")
        .insert(importValues)
        .select(
          "id, imported_source_id, showing_name, display_name",
        )
        .single();

      if (insertError) {
        if (insertError.code === "23505") {
          const {
            data: racedExisting,
            error: racedExistingError,
          } = await clubAdmin
            .from("exhibitors")
            .select(
              "id, imported_source_id, showing_name, display_name",
            )
            .eq(
              "owner_user_id",
              user.id,
            )
            .eq(
              "imported_from",
              "ringmaster_show",
            )
            .eq(
              "imported_source_id",
              source.id,
            )
            .maybeSingle();

          if (racedExistingError) {
            throw racedExistingError;
          }

          if (!racedExisting) {
            throw insertError;
          }

          alreadyImportedRows.push(
            racedExisting as ClubExhibitorResult,
          );

          continue;
        }

        throw insertError;
      }

      importedRows.push(
        inserted as ClubExhibitorResult,
      );
    }

    const allLinkedRows = [
      ...alreadyImportedRows,
      ...importedRows,
    ];

    if (allLinkedRows.length === 0) {
      throw new Error(
        "No RingMaster Show exhibitor records were linked.",
      );
    }

    const primaryRow =
      importedRows[0] ??
      alreadyImportedRows[0] ??
      null;

    const primaryDisplayName =
      clean(primaryRow?.display_name) ??
      clean(primaryRow?.showing_name) ??
      nameFor(selectedMatches[0]) ??
      verifiedEmail.split("@")[0];

    const {
      error: profileError,
    } = await clubAdmin
      .from("profiles")
      .upsert(
        {
          user_id: user.id,
          email: verifiedEmail,
          display_name:
            primaryDisplayName,
          updated_at: now,
        },
        {
          onConflict: "user_id",
        },
      );

    if (profileError) {
      throw profileError;
    }

    return json({
      status:
        importedRows.length > 0
          ? "imported"
          : "already_exists",

      imported_count:
        importedRows.length,

      already_imported_count:
        alreadyImportedRows.length,

      exhibitor_count:
        allLinkedRows.length,

      exhibitor_ids:
        allLinkedRows.map(
          (row) => row.id,
        ),

      display_name:
        primaryDisplayName,
    });
  } catch (error) {
    console.error(
      "import-ringmaster-show-account failed",
      error,
    );

    return json(
      {
        status: "error",
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
      500,
    );
  }
});
