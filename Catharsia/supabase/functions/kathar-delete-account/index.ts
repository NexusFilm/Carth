import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function serviceClient() {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
}

async function requireUser(req: Request) {
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } },
  );
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new Error("Sign in required");
  return data.user;
}

async function katharTenantId(admin: ReturnType<typeof serviceClient>) {
  const { data, error } = await admin.from("app_config").select("value").eq("key", "kathar.tenant_id").single();
  if (error || !data?.value) throw new Error("Catharsia tenant is not configured");
  return data.value as string;
}

async function removeTree(admin: ReturnType<typeof serviceClient>, bucket: string, prefix: string) {
  const { data: entries, error } = await admin.storage.from(bucket).list(prefix, { limit: 1000, offset: 0 });
  if (error) throw error;
  const files: string[] = [];
  const folders: string[] = [];
  for (const entry of entries ?? []) {
    const path = `${prefix}/${entry.name}`;
    if (entry.id || entry.metadata) files.push(path);
    else folders.push(path);
  }
  if (files.length) {
    const { error: removeError } = await admin.storage.from(bucket).remove(files);
    if (removeError) throw removeError;
  }
  for (const folder of folders) await removeTree(admin, bucket, folder);
}

async function deleteRows(query: PromiseLike<{ error: { message: string } | null }>) {
  const { error } = await query;
  if (error) throw error;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    if (body.confirmation !== "DELETE") return json({ error: "Type DELETE to confirm Catharsia data deletion." }, 400);

    const admin = serviceClient();
    const tenantId = await katharTenantId(admin);

    // Clear tenant-scoped media and verification documents before removing rows.
    await removeTree(admin, "kathar-media", `${tenantId}/${user.id}`);
    await removeTree(admin, "kathar-profile-avatars", `${tenantId}/${user.id}`);
    await removeTree(admin, "kathar-identity-documents", `${tenantId}/${user.id}`);

    const { data: ownedCommunities, error: communitiesError } = await admin
      .from("kathar_communities").select("id").eq("tenant_id", tenantId).eq("owner_user_id", user.id);
    if (communitiesError) throw communitiesError;
    const communityIDs = (ownedCommunities ?? []).map((row) => row.id);
    if (communityIDs.length) {
      await deleteRows(admin.from("kathar_community_posts").delete().eq("tenant_id", tenantId).in("community_id", communityIDs));
      await deleteRows(admin.from("kathar_community_members").delete().eq("tenant_id", tenantId).in("community_id", communityIDs));
      await deleteRows(admin.from("kathar_communities").delete().eq("tenant_id", tenantId).in("id", communityIDs));
    }

    await deleteRows(admin.from("kathar_comments").delete().eq("tenant_id", tenantId).eq("author_id", user.id));
    await deleteRows(admin.from("kathar_posts").delete().eq("tenant_id", tenantId).eq("author_user_id", user.id));
    await deleteRows(admin.from("kathar_community_posts").delete().eq("tenant_id", tenantId).eq("author_user_id", user.id));
    await deleteRows(admin.from("kathar_community_members").delete().eq("tenant_id", tenantId).eq("user_id", user.id));
    await deleteRows(admin.from("kathar_post_likes").delete().eq("tenant_id", tenantId).eq("user_id", user.id));
    await deleteRows(admin.from("kathar_saved_items").delete().eq("tenant_id", tenantId).eq("viewer_id", user.id));
    await deleteRows(admin.from("kathar_poll_votes").delete().eq("tenant_id", tenantId).eq("user_id", user.id));
    await deleteRows(admin.from("kathar_notification_reads").delete().eq("tenant_id", tenantId).eq("user_id", user.id));
    await deleteRows(admin.from("kathar_user_blocks").delete().eq("tenant_id", tenantId).eq("blocker_id", user.id));
    await deleteRows(admin.from("kathar_user_blocks").delete().eq("tenant_id", tenantId).eq("blocked_user_id", user.id));
    await deleteRows(admin.from("kathar_reports").delete().eq("tenant_id", tenantId).eq("reporter_id", user.id));
    await deleteRows(admin.from("kathar_notifications").delete().eq("tenant_id", tenantId).eq("recipient_user_id", user.id));
    await deleteRows(admin.from("kathar_notifications").delete().eq("tenant_id", tenantId).eq("actor_user_id", user.id));
    await deleteRows(admin.from("kathar_verification_applications").delete().eq("tenant_id", tenantId).eq("applicant_user_id", user.id));
    await deleteRows(admin.from("kathar_professional_access_grants").delete().eq("tenant_id", tenantId).eq("granted_by", user.id));
    await deleteRows(admin.from("kathar_professionals").delete().eq("tenant_id", tenantId).eq("user_id", user.id));
    await deleteRows(admin.from("kathar_profiles").delete().eq("tenant_id", tenantId).eq("id", user.id));
    await deleteRows(admin.from("tenant_members").delete().eq("tenant_id", tenantId).eq("user_id", user.id));

    // Supabase Auth is shared by the other Viewfinder tenants, so keep the
    // cross-app identity and remove only this user's Catharsia membership/data.
    return json({ success: true, sharedIdentityRetained: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Catharsia data deletion failed" }, 500);
  }
});
