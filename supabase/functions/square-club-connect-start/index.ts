import { corsHeaders, errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import { randomState, sha256 } from "../_shared/token_crypto.ts";
import { squareConnectBase, squareEnv, squareScopes } from "../_shared/square.ts";
import { assertCanManageClubPayments, authenticatedUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const body = await request.json().catch(() => ({}));
    const clubId = typeof body.club_id === "string" ? body.club_id.trim() : "";
    if (!clubId) throw new Error("A club is required.");

    const user = await authenticatedUser(request);
    const admin = serviceClient();
    await assertCanManageClubPayments(admin, clubId, user.id);

    const state = randomState();
    const { error } = await admin.from("club_payment_provider_oauth_states").insert({
      state_hash: await sha256(state),
      provider: "square",
      club_id: clubId,
      user_id: user.id,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });
    if (error) throw error;

    const authorizationUrl = new URL(`${squareConnectBase}/oauth2/authorize`);
    authorizationUrl.searchParams.set("client_id", squareEnv("SQUARE_APPLICATION_ID"));
    authorizationUrl.searchParams.set("scope", squareScopes.join(" "));
    authorizationUrl.searchParams.set("session", "false");
    authorizationUrl.searchParams.set("state", state);
    authorizationUrl.searchParams.set("redirect_uri", squareEnv("SQUARE_REDIRECT_URI"));
    return jsonResponse({ authorization_url: authorizationUrl.toString() });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});

export { corsHeaders };
