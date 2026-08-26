import { errorMessage } from "../_shared/http.ts";
import { encryptToken, sha256 } from "../_shared/token_crypto.ts";
import { normalizeSquareScopes, obtainSquareToken, publicMerchant, squareEnv, squareGet, squareScopes, usableLocations } from "../_shared/square.ts";
import { assertCanManageClubPayments, serviceClient } from "../_shared/supabase.ts";

function redirect(clubId: string | null, status: "connected" | "error", message?: string): Response {
  const appUrl = squareEnv("RINGMASTER_CLUB_APP_URL").replace(/\/$/, "");
  const url = new URL(`${appUrl}/`);
  if (clubId) url.searchParams.set("clubId", clubId);
  url.searchParams.set("square", status);
  if (message) url.searchParams.set("message", message.slice(0, 180));
  return Response.redirect(url, 302);
}

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const rawState = url.searchParams.get("state") ?? "";
  const code = url.searchParams.get("code") ?? "";
  const denied = url.searchParams.get("error");
  let clubId: string | null = null;

  try {
    if (!rawState) throw new Error("Square did not return a valid connection state.");
    const admin = serviceClient();
    const { data: state, error: stateError } = await admin
      .from("club_payment_provider_oauth_states")
      .select("id,club_id,user_id,expires_at,consumed_at")
      .eq("provider", "square")
      .eq("state_hash", await sha256(rawState))
      .maybeSingle();
    if (stateError) throw stateError;
    if (!state || state.consumed_at || new Date(state.expires_at).getTime() <= Date.now()) {
      throw new Error("This Square connection link has expired. Please start again.");
    }
    const connectedClubId = state.club_id as string;
    clubId = connectedClubId;
    if (denied) throw new Error("Square connection was cancelled.");
    if (!code) throw new Error("Square did not return an authorization code.");

    await assertCanManageClubPayments(admin, connectedClubId, state.user_id);
    const { data: consumed, error: consumeError } = await admin
      .from("club_payment_provider_oauth_states")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", state.id)
      .is("consumed_at", null)
      .select("id")
      .maybeSingle();
    if (consumeError) throw consumeError;
    if (!consumed) throw new Error("This Square connection link was already used.");

    const token = await obtainSquareToken({
      grant_type: "authorization_code",
      code,
      redirect_uri: squareEnv("SQUARE_REDIRECT_URI"),
    });
    const accessToken = String(token.access_token ?? "");
    const refreshToken = String(token.refresh_token ?? "");
    if (!accessToken || !refreshToken) throw new Error("Square did not return connection credentials.");
    const merchantData = await squareGet("/v2/merchants/me", accessToken);
    const locationsData = await squareGet("/v2/locations", accessToken);
    const merchant = publicMerchant(merchantData);
    const locations = usableLocations(locationsData);
    const grantedScopes = normalizeSquareScopes(token.scopes);
    const allScopesGranted = squareScopes.every((scope) => grantedScopes.includes(scope));
    const isReady = locations.length === 1 && allScopesGranted;
    const expiresAt = typeof token.expires_at === "string" ? token.expires_at : null;

    const { data: account, error: accountError } = await admin
      .from("club_payment_accounts")
      .upsert({
        club_id: connectedClubId,
        provider: "square",
        provider_account_id: merchant.id || null,
        provider_location_id: locations.length === 1 ? locations[0].id : null,
        authorization_expires_at: expiresAt,
        metadata: { merchant, available_locations: locations, granted_scopes: grantedScopes },
        account_status: isReady ? "ready" : "restricted",
        charges_enabled: isReady,
        payouts_enabled: false,
        details_submitted: true,
        updated_at: new Date().toISOString(),
      }, { onConflict: "club_id,provider" })
      .select("id")
      .single();
    if (accountError) throw accountError;

    const { error: credentialError } = await admin
      .from("club_payment_provider_credentials")
      .upsert({
        club_payment_account_id: account.id,
        provider: "square",
        access_token_encrypted: await encryptToken(accessToken),
        refresh_token_encrypted: await encryptToken(refreshToken),
        token_expires_at: expiresAt,
        granted_scopes: grantedScopes,
        credential_metadata: { merchant_id: merchant.id, location_count: locations.length },
        updated_at: new Date().toISOString(),
      }, { onConflict: "club_payment_account_id,provider" });
    if (credentialError) throw credentialError;
    return redirect(connectedClubId, "connected", isReady ? "Square is connected." : "Square connected, but needs a location or permissions review.");
  } catch (error) {
    return redirect(clubId, "error", errorMessage(error));
  }
});
