import { createClient } from "npm:@supabase/supabase-js@2";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}.`);
  return value;
}

export function serviceClient() {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

export async function authenticatedUser(request: Request) {
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("Sign in is required.");
  const client = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new Error("Your sign-in session is no longer valid.");
  return data.user;
}

export async function assertCanManageClubPayments(
  admin: ReturnType<typeof serviceClient>,
  clubId: string,
  userId: string,
) {
  const { data: club, error: clubError } = await admin
    .from("clubs")
    .select("id")
    .eq("id", clubId)
    .eq("owner_user_id", userId)
    .maybeSingle();
  if (clubError) throw clubError;
  if (club) return;

  const { data: assignments, error } = await admin
    .from("club_staff_assignments")
    .select("role_id,club_roles!inner(code)")
    .eq("club_id", clubId)
    .eq("user_id", userId)
    .eq("status", "active");
  if (error) throw error;
  const permitted = (assignments ?? []).some((assignment: Record<string, unknown>) => {
    const roles = assignment["club_roles"];
    const role = Array.isArray(roles) ? roles[0] : roles;
    const code = role && typeof role === "object" ? (role as Record<string, unknown>).code : null;
    return code === "club_owner" || code === "club_admin" || code === "treasurer";
  });
  if (!permitted) throw new Error("You do not have permission to manage payment connections for this club.");
}
