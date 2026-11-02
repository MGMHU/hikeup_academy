// Invite un nouvel utilisateur par e-mail. Réservé aux administrateurs.
// Le profil est créé automatiquement par le déclencheur handle_new_user ; on complète ensuite son poste.
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "Non connecté." }, 401);
    const { data: isAdmin } = await caller.rpc("has_role", { r: "admin" });
    if (!isAdmin) return json({ error: "Réservé aux administrateurs." }, 403);

    const { email, full_name, job_title, redirect_to } = await req.json();
    const mail = String(email || "").trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(mail)) return json({ error: "Adresse e-mail invalide." }, 400);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: existing } = await admin.from("profiles").select("id").eq("email", mail).maybeSingle();
    if (existing) return json({ error: "Un compte existe déjà pour cette adresse." }, 409);

    const { data, error } = await admin.auth.admin.inviteUserByEmail(mail, {
      data: { full_name: full_name || null },
      redirectTo: redirect_to || undefined,
    });
    if (error || !data?.user) return json({ error: error?.message || "Invitation impossible." }, 400);
    await admin.from("profiles").update({ full_name: full_name || mail.split("@")[0], job_title: job_title || null }).eq("id", data.user.id);
    return json({ id: data.user.id });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
