// Ayan Residences: sends phone notifications (Firebase Cloud Messaging).
//
// The database calls this when something happens (a notice, a chat message,
// a payment proof...). It reads the row again itself, decides who should
// hear about it, and sends to their phones. Each event is sent once only
// (push_log), so a forged or repeated call can't spam anyone.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   FCM_SERVICE_ACCOUNT  the Firebase service account JSON
// Supabase provides SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY itself.
//
// Body: { "table": "chat_messages", "op": "INSERT", "record": {...} }

import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type Note = { to: "admin" | number; title: string; body: string };

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const money = (amount: number, currency: string) =>
  `${currency} ${Number(amount).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

async function tenantName(id: number | null): Promise<string> {
  if (!id) return "A tenant";
  const { data } = await db.from("tenants").select("full_name").eq("id", id).maybeSingle();
  return data?.full_name ?? "A tenant";
}

// What to send for each event (null = nothing).
async function decide(table: string, op: string, r: Record<string, any>): Promise<{ key: string; note: Note } | null> {
  switch (table) {
    case "notice_recipients": {
      const { data: n } = await db.from("notices").select("title, body").eq("id", r.notice_id).maybeSingle();
      if (!n) return null;
      return { key: `notice:${r.notice_id}:${r.tenant_id}`, note: { to: r.tenant_id, title: n.title, body: n.body } };
    }
    case "chat_messages": {
      const { data: m } = await db.from("chat_messages").select("*").eq("id", r.id).maybeSingle();
      if (!m) return null;
      const text = m.body ?? (m.image_path ? "Sent a photo" : "Sent a file");
      return m.sender === "admin"
        ? { key: `chat:${m.id}`, note: { to: m.tenant_id, title: "Message from management", body: text } }
        : { key: `chat:${m.id}`, note: { to: "admin", title: `Message from ${await tenantName(m.tenant_id)}`, body: text } };
    }
    case "payments": {
      const { data: p } = await db.from("payments").select("*").eq("id", r.id).maybeSingle();
      if (!p || p.source !== "tenant_proof") return null;
      if (op === "INSERT") {
        return {
          key: `payment:${p.id}:new`,
          note: {
            to: "admin",
            title: "Payment proof to verify",
            body: `${await tenantName(p.tenant_id)} sent ${money(p.amount, p.currency)} · ${p.title}`,
          },
        };
      }
      if (p.status === "verified") {
        return {
          key: `payment:${p.id}:verified`,
          note: { to: p.tenant_id, title: "Payment verified", body: `${p.title}: ${money(p.amount, p.currency)}. Thank you!` },
        };
      }
      if (p.status === "rejected") {
        return {
          key: `payment:${p.id}:rejected`,
          note: {
            to: p.tenant_id,
            title: "Payment not accepted",
            body: `${p.title}${p.reject_reason ? `: ${p.reject_reason}` : ""}. Please check and send it again.`,
          },
        };
      }
      return null;
    }
    case "reports": {
      const { data: rep } = await db.from("reports").select("*").eq("id", r.id).maybeSingle();
      if (!rep) return null;
      if (op === "INSERT") {
        if (!rep.tenant_id) return null; // filed by the admin
        return {
          key: `report:${rep.id}:new`,
          note: { to: "admin", title: "New report", body: `${await tenantName(rep.tenant_id)}: ${rep.issue}` },
        };
      }
      if (!rep.tenant_id || rep.status === "pending") return null;
      const status = rep.status === "approved" ? "approved" : "under review";
      return {
        key: `report:${rep.id}:${rep.status}`,
        note: { to: rep.tenant_id, title: "Report update", body: `${rep.issue} is now ${status}.` },
      };
    }
    case "report_updates": {
      const { data: u } = await db.from("report_updates").select("*, reports(tenant_id, issue)").eq("id", r.id).maybeSingle();
      const tenant = u?.reports?.tenant_id;
      if (!u || !tenant) return null;
      return { key: `report_update:${u.id}`, note: { to: tenant, title: `Update: ${u.reports.issue}`, body: u.body } };
    }
    case "complaints": {
      const { data: c } = await db.from("complaints").select("*").eq("id", r.id).maybeSingle();
      if (!c) return null;
      if (op === "INSERT") {
        return {
          key: `complaint:${c.id}:new`,
          note: { to: "admin", title: `Complaint: ${c.category}`, body: `${await tenantName(c.tenant_id)}: ${c.body}` },
        };
      }
      if (!c.response) return null;
      return {
        key: `complaint:${c.id}:reply:${c.response.length}`,
        note: { to: c.tenant_id, title: "Reply to your complaint", body: c.response },
      };
    }
    case "tenant_documents": {
      const { data: d } = await db.from("tenant_documents").select("*").eq("id", r.id).maybeSingle();
      if (!d || d.state !== "to_review") return null;
      return {
        key: `document:${d.id}:${d.file_path}`,
        note: { to: "admin", title: "Document to check", body: `${await tenantName(d.tenant_id)} uploaded their ${d.kind}.` },
      };
    }
    case "lease_requests": {
      const { data: q } = await db.from("lease_requests").select("*").eq("id", r.id).maybeSingle();
      if (!q) return null;
      return {
        key: `request:${q.id}`,
        note: { to: "admin", title: "New lease request", body: `${await tenantName(q.tenant_id)}: ${q.details || q.kind}` },
      };
    }
  }
  return null;
}

// ------------------------------------------------------------ Firebase

let cachedToken: { value: string; expires: number } | null = null;

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function accessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires > now + 60) return cachedToken.value;
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const input = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(input)));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${input}.${b64url(sig)}`,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`Google sign-in failed: ${JSON.stringify(json)}`);
  cachedToken = { value: json.access_token, expires: now + (json.expires_in ?? 3600) };
  return json.access_token;
}

async function phonesOf(to: Note["to"]): Promise<string[]> {
  let profiles: string[] = [];
  if (to === "admin") {
    const { data } = await db.from("profiles").select("id").eq("role", "admin");
    profiles = (data ?? []).map((p) => p.id);
  } else {
    const { data } = await db.from("tenants").select("profile_id").eq("id", to).maybeSingle();
    if (data?.profile_id) profiles = [data.profile_id];
  }
  if (profiles.length === 0) return [];
  const { data } = await db.from("push_tokens").select("token").in("profile_id", profiles);
  return (data ?? []).map((t) => t.token);
}

async function send(note: Note, table: string): Promise<number> {
  const tokens = await phonesOf(note.to);
  if (tokens.length === 0) return 0;
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
  if (!sa.private_key) throw new Error("FCM_SERVICE_ACCOUNT secret is missing.");
  const token = await accessToken(sa);
  let sent = 0;
  for (const t of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: t,
          notification: { title: note.title.slice(0, 120), body: note.body.slice(0, 400) },
          data: { kind: table },
          android: { priority: "high", notification: { sound: "default" } },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else {
      const err = await res.text();
      // The app was uninstalled or the token expired: forget this phone.
      if (res.status === 404 || err.includes("UNREGISTERED") || err.includes("registration-token-not-registered")) {
        await db.from("push_tokens").delete().eq("token", t);
      } else {
        console.error("FCM:", res.status, err);
      }
    }
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "Use POST" });
  let body: { table?: string; op?: string; record?: Record<string, any> };
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Send JSON." });
  }
  if (!body.table || !body.op || !body.record) return reply(400, { error: "table, op and record are required." });

  try {
    const event = await decide(body.table, body.op, body.record);
    if (!event) return reply(200, { ok: true, sent: 0 });
    // Once per event, however many times this is called.
    const { error: dup } = await db.from("push_log").insert({ key: event.key });
    if (dup) return reply(200, { ok: true, sent: 0, duplicate: true });
    const sent = await send(event.note, body.table);
    return reply(200, { ok: true, sent });
  } catch (e) {
    console.error(e);
    return reply(500, { error: String(e) });
  }
});
