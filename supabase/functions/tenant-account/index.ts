// Ayan Residences: creates, updates and removes tenant logins.
//
// Only the admin can call it (checked below). It needs the secret key to
// manage logins, which is why this runs on the server and never in the app.
// Supabase provides SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY automatically.
//
// Body:
//   { "action": "upsert", "tenant_id": 12, "username": "kelra", "password": "optional" }
//   { "action": "delete", "tenant_id": 12 }

import { createClient } from "npm:@supabase/supabase-js@2";

const TENANT_DOMAIN = "accounts.ayan.app";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Who is calling? Only the admin login may manage tenant logins.
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const { data: caller, error: callerError } = await admin.auth.getUser(jwt);
  if (callerError || caller.user?.app_metadata?.role !== "admin") {
    return reply(403, { error: "Only the admin can manage tenant logins." });
  }

  let body: { action?: string; tenant_id?: number; username?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Send JSON." });
  }
  const tenantId = Number(body.tenant_id);
  if (!Number.isInteger(tenantId)) return reply(400, { error: "tenant_id is required." });

  const { data: tenant, error: tenantError } = await admin
    .from("tenants")
    .select("id, profile_id")
    .eq("id", tenantId)
    .single();
  if (tenantError || !tenant) return reply(404, { error: "Tenant not found." });

  // ---------------------------------------------------------------- delete
  if (body.action === "delete") {
    if (tenant.profile_id) {
      // Unlink first (the tenant row points to the login), then remove it.
      await admin.from("tenants").update({ profile_id: null }).eq("id", tenantId);
      const { error } = await admin.auth.admin.deleteUser(tenant.profile_id);
      if (error) return reply(400, { error: error.message });
    }
    return reply(200, { ok: true });
  }

  if (body.action !== "upsert") return reply(400, { error: "Unknown action." });

  // ---------------------------------------------------------------- upsert
  const username = (body.username ?? "").trim();
  if (!/^[A-Za-z0-9._-]{3,40}$/.test(username)) {
    return reply(400, { error: "Username must be 3-40 letters, numbers, dots, dashes or underscores." });
  }
  const password = body.password ?? "";
  if (password && password.length < 6) {
    return reply(400, { error: "Password must be at least 6 characters." });
  }
  const email = `${username.toLowerCase()}@${TENANT_DOMAIN}`;
  const appMetadata = { role: "tenant", username };

  if (!tenant.profile_id) {
    if (!password) return reply(400, { error: "A new login needs a password." });
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: appMetadata,
    });
    if (data?.user) {
      const { error: linkError } = await admin.from("tenants").update({ profile_id: data.user.id }).eq("id", tenantId);
      if (linkError) return reply(400, { error: `Login made, but not linked: ${linkError.message}` });
      return reply(200, { ok: true, created: true });
    }

    // A login with this username is already there (e.g. left from an
    // earlier try, or from a tenant who was removed). Reuse it, unless a
    // current tenant is using it.
    const { data: profile } = await admin
      .from("profiles")
      .select("id, role")
      .ilike("username", username)
      .maybeSingle();
    if (!profile) return reply(400, { error: error?.message ?? "Could not create the login." });
    if (profile.role !== "tenant") return reply(400, { error: `The username "${username}" can't be used.` });
    const { data: owner } = await admin
      .from("tenants")
      .select("id, full_name")
      .eq("profile_id", profile.id)
      .eq("status", "active")
      .maybeSingle();
    if (owner && owner.id !== tenantId) {
      return reply(400, { error: `The username "${username}" is already used by ${owner.full_name}.` });
    }
    const { error: reuseError } = await admin.auth.admin.updateUserById(profile.id, {
      email,
      password,
      email_confirm: true,
      app_metadata: appMetadata,
    });
    if (reuseError) return reply(400, { error: reuseError.message });
    await admin.from("tenants").update({ profile_id: null }).eq("profile_id", profile.id);
    const { error: linkError } = await admin.from("tenants").update({ profile_id: profile.id }).eq("id", tenantId);
    if (linkError) return reply(400, { error: `Login found, but not linked: ${linkError.message}` });
    return reply(200, { ok: true, created: false });
  }

  const changes: Record<string, unknown> = { email, email_confirm: true, app_metadata: appMetadata };
  if (password) changes.password = password;
  const { error } = await admin.auth.admin.updateUserById(tenant.profile_id, changes);
  if (error) return reply(400, { error: error.message });
  await admin.from("profiles").update({ username }).eq("id", tenant.profile_id);
  return reply(200, { ok: true, created: false });
});
