import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const APP_BUNDLE_ID = "com.catharsia.ios";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ActionBody =
  | { action: "register"; device_token: string; apns_environment: "sandbox" | "production"; app_version?: string; build_number?: string }
  | { action: "unregister"; device_token: string; apns_environment: "sandbox" | "production" }
  | { action: "test" }
  | { action: "announcement"; title: string; body: string; destination?: string | null }
  | { action: "like"; entity_id: string }
  | { action: "comment"; entity_id: string };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function adminClient() {
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

async function catharsiaTenantID(admin: ReturnType<typeof adminClient>) {
  const { data, error } = await admin.from("app_config").select("value").eq("key", "kathar.tenant_id").single();
  if (error || !data?.value) throw new Error("Catharsia tenant is not configured");
  return data.value as string;
}

type SenderResult = {
  sent?: number;
  results?: Array<{ device_token_id?: string; status_code?: number; response_body?: string }>;
};

async function sendPushToUser(
  admin: ReturnType<typeof adminClient>,
  userID: string,
  payload: { title: string; body: string; source: "manual" | "auto"; data: Record<string, unknown> },
) {
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  if (!serviceRoleKey || !supabaseURL) return { sent: 0, status: "not_configured" };

  const { data: tokens, error } = await admin.from("push_device_tokens")
    .select("id,device_token,apns_environment")
    .eq("bundle_id", APP_BUNDLE_ID)
    .eq("user_id", userID)
    .eq("enabled", true);
  if (error) throw error;
  if (!tokens?.length) return { sent: 0, status: "no_registered_device" };

  let sent = 0;
  let environmentCorrected = false;
  let rejectedWithBadDeviceToken = false;
  let apnsRateLimited = false;
  for (const token of tokens) {
    if (token.apns_environment !== "sandbox" && token.apns_environment !== "production") continue;
    const deliver = async (environment: "sandbox" | "production", allowEnvironmentOverride = false) => {
      const response = await fetch(`${supabaseURL}/functions/v1/send-push`, {
        method: "POST",
        headers: { Authorization: `Bearer ${serviceRoleKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          bundle_id: APP_BUNDLE_ID,
          title: payload.title,
          body: payload.body,
          environment,
          source: payload.source,
          user_ids: [userID],
          device_tokens: [token.device_token],
          ...(allowEnvironmentOverride ? { allow_environment_override_for_explicit_tokens: true } : {}),
          data: payload.data,
          sound: "default",
        }),
      });
      const result = await response.json().catch(() => ({})) as SenderResult;
      return { ok: response.ok, result };
    };

    const first = await deliver(token.apns_environment);
    sent += Number(first.result.sent ?? 0);
    let retryResult: SenderResult | null = null;
    const hasEnvironmentMismatch = first.result.results?.some((attempt) => {
      if (attempt.status_code !== 403) return false;
      try {
        return JSON.parse(attempt.response_body ?? "{}").reason === "BadEnvironmentKeyInToken";
      } catch {
        return false;
      }
    }) ?? false;

    if (hasEnvironmentMismatch) {
      const correctedEnvironment = token.apns_environment === "sandbox" ? "production" : "sandbox";
      const retry = await deliver(correctedEnvironment, true);
      retryResult = retry.result;
      sent += Number(retry.result.sent ?? 0);
      const retryAccepted = Number(retry.result.sent ?? 0) > 0 || retry.result.results?.some((attempt) => attempt.status_code === 200) === true;
      if (retryAccepted) {
        const { error: updateError } = await admin.from("push_device_tokens")
          .update({ apns_environment: correctedEnvironment, updated_at: new Date().toISOString() })
          .eq("id", token.id)
          .eq("bundle_id", APP_BUNDLE_ID)
          .eq("user_id", userID);
        if (updateError) throw updateError;
        environmentCorrected = true;
      }
    }

    const attempts = [...(first.result.results ?? []), ...(retryResult?.results ?? [])];
    if (attempts.some((attempt) => {
      if (attempt.status_code !== 429) return false;
      try {
        return JSON.parse(attempt.response_body ?? "{}").reason === "TooManyProviderTokenUpdates";
      } catch {
        return false;
      }
    })) {
      apnsRateLimited = true;
    }
    if (attempts.some((attempt) => {
      if (attempt.status_code !== 400) return false;
      try {
        return JSON.parse(attempt.response_body ?? "{}").reason === "BadDeviceToken";
      } catch {
        return false;
      }
    })) {
      rejectedWithBadDeviceToken = true;
      const { error: disableError } = await admin.from("push_device_tokens")
        .update({ enabled: false, updated_at: new Date().toISOString() })
        .eq("id", token.id)
        .eq("bundle_id", APP_BUNDLE_ID)
        .eq("user_id", userID);
      if (disableError) throw disableError;
    }
  }

  return {
    sent,
    status: sent > 0
      ? "sent"
      : rejectedWithBadDeviceToken
      ? "bad_device_token"
      : apnsRateLimited
      ? "apns_rate_limited"
      : environmentCorrected
      ? "environment_corrected"
      : "pending_or_unavailable",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  try {
    const user = await requireUser(req);
    const body = await req.json() as ActionBody;
    const admin = adminClient();

    if (body.action === "register" || body.action === "unregister") {
      if (!/^[0-9a-f]{64}$/i.test(body.device_token)) return json({ error: "Invalid APNs device token" }, 400);
      if (!["sandbox", "production"].includes(body.apns_environment)) return json({ error: "Invalid APNs environment" }, 400);

      if (body.action === "register") {
        const now = new Date().toISOString();
        const deviceToken = body.device_token.toLowerCase();
        // The APNs token's accepted environment is authoritative. Preserve a
        // prior correction instead of replacing it with the build's guess.
        const { data: existingTokens, error: lookupError } = await admin.from("push_device_tokens")
          .select("apns_environment,updated_at")
          .eq("bundle_id", APP_BUNDLE_ID)
          .eq("device_token", deviceToken)
          .eq("enabled", true)
          .order("updated_at", { ascending: false })
          .limit(1);
        if (lookupError) throw lookupError;
        const existingEnvironment = existingTokens?.[0]?.apns_environment;
        const effectiveEnvironment = existingEnvironment === "sandbox" || existingEnvironment === "production"
          ? existingEnvironment
          : body.apns_environment;
        const { error } = await admin.from("push_device_tokens").upsert({
          user_id: user.id,
          bundle_id: APP_BUNDLE_ID,
          device_token: deviceToken,
          apns_environment: effectiveEnvironment,
          platform: "ios",
          app_version: body.app_version?.slice(0, 32) ?? null,
          build_number: body.build_number?.slice(0, 32) ?? null,
          enabled: true,
          last_registered_at: now,
          updated_at: now,
        }, { onConflict: "bundle_id,device_token,apns_environment" });
        if (error) throw error;
        return json({ ok: true, registered: true });
      }

      const { error } = await admin.from("push_device_tokens")
        .update({ enabled: false, user_id: null, updated_at: new Date().toISOString() })
        .eq("bundle_id", APP_BUNDLE_ID)
        .eq("device_token", body.device_token.toLowerCase())
        .eq("user_id", user.id);
      if (error) throw error;
      return json({ ok: true, unregistered: true });
    }

    if (body.action === "test") {
      const result = await sendPushToUser(admin, user.id, {
        title: "Catharsia",
        body: "Push alerts are connected on this device.",
        source: "manual",
        data: { target: "notifications", test: true },
      });
      return json({ ok: true, push: result.status, sent: result.sent });
    }

    if (body.action === "announcement") {
      const title = body.title?.trim();
      const announcementBody = body.body?.trim();
      if (!title || title.length > 60 || !announcementBody || announcementBody.length > 240) {
        return json({ error: "Use a title up to 60 characters and a message up to 240 characters." }, 400);
      }
      const destination = body.destination ?? null;
      const validDestinations = new Set(["explore", "saved", "profile"]);
      if (destination !== null && !validDestinations.has(destination)) {
        return json({ error: "Choose an available Catharsia page destination." }, 400);
      }

      const caller = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } },
      );
      const { data: isAdmin, error: adminError } = await caller.rpc("kathar_is_admin");
      if (adminError || isAdmin !== true) return json({ error: "Catharsia admin access required." }, 403);

      const tenantID = await catharsiaTenantID(admin);
      const { data: profiles, error: profilesError } = await admin
        .from("kathar_profiles")
        .select("id")
        .eq("tenant_id", tenantID);
      if (profilesError) throw profilesError;

      const recipientIDs = [...new Set((profiles ?? []).map((profile) => profile.id as string))];
      if (recipientIDs.length === 0) {
        return json({ ok: true, recipients: 0, push_sent: 0, push_sent_by_environment: { sandbox: 0, production: 0 } });
      }

      const timestamp = new Date().toISOString();
      for (let offset = 0; offset < recipientIDs.length; offset += 500) {
        const rows = recipientIDs.slice(offset, offset + 500).map((recipientID) => ({
          tenant_id: tenantID,
          legacy_base44_id: `announcement:${crypto.randomUUID()}`,
          recipient_user_id: recipientID,
          actor_user_id: user.id,
          kind: "community",
          title,
          detail: announcementBody,
          link: destination ? `catharsia://${destination}` : null,
          entity_id: null,
          read: false,
          created_at: timestamp,
        }));
        const { error } = await admin.from("kathar_notifications").insert(rows);
        if (error) throw error;
      }

      const pushSentByEnvironment: Record<"sandbox" | "production", number> = { sandbox: 0, production: 0 };
      for (const environment of ["sandbox", "production"] as const) {
        const response = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-push`, {
          method: "POST",
          headers: { Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            bundle_id: APP_BUNDLE_ID,
            title,
            body: announcementBody,
            environment,
            source: "manual",
            user_ids: recipientIDs,
            data: {
              target: "notifications",
              announcement: true,
              ...(destination ? { destination } : {}),
            },
            sound: "default",
          }),
        });
        const result = await response.json().catch(() => ({})) as { sent?: number; error?: string };
        if (!response.ok) console.error(`Announcement push (${environment}) failed:`, result.error ?? response.status);
        pushSentByEnvironment[environment] = Number(result.sent ?? 0);
      }
      const pushSent = pushSentByEnvironment.sandbox + pushSentByEnvironment.production;
      return json({
        ok: true,
        recipients: recipientIDs.length,
        push_sent: pushSent,
        push_sent_by_environment: pushSentByEnvironment,
      });
    }

    if (body.action !== "like" && body.action !== "comment") return json({ error: "Unknown action" }, 400);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.entity_id)) {
      return json({ error: "Invalid activity ID" }, 400);
    }

    const tenantID = await catharsiaTenantID(admin);
    let postID = body.entity_id;
    if (body.action === "like") {
      const { data: like, error } = await admin.from("kathar_post_likes")
        .select("post_id")
        .eq("tenant_id", tenantID)
        .eq("post_id", body.entity_id)
        .eq("user_id", user.id)
        .maybeSingle();
      if (error) throw error;
      if (!like) return json({ ok: true, notification_created: false, reason: "like_removed" });
      postID = like.post_id;
    } else {
      const { data: comment, error } = await admin.from("kathar_comments")
        .select("id,post_id")
        .eq("tenant_id", tenantID)
        .eq("id", body.entity_id)
        .eq("author_id", user.id)
        .maybeSingle();
      if (error) throw error;
      if (!comment) return json({ error: "Comment not found" }, 404);
      postID = comment.post_id;
    }

    const { data: post, error: postError } = await admin.from("kathar_posts")
      .select("author_user_id")
      .eq("tenant_id", tenantID)
      .eq("id", postID)
      .maybeSingle();
    if (postError) throw postError;
    const recipientID = post?.author_user_id as string | null | undefined;
    if (!recipientID || recipientID === user.id) return json({ ok: true, notification_created: false, reason: "no_recipient" });

    const kind = body.action;
    const { data: notifications, error: notificationError } = await admin.from("kathar_notifications")
      .select("id,push_sent_at")
      .eq("tenant_id", tenantID)
      .eq("recipient_user_id", recipientID)
      .eq("actor_user_id", user.id)
      .eq("kind", kind)
      .eq("entity_id", postID)
      .order("created_at", { ascending: false })
      .limit(1);
    if (notificationError) throw notificationError;
    const notification = notifications?.[0];
    if (!notification) return json({ error: "The activity notification was not created" }, 409);
    if (notification.push_sent_at) return json({ ok: true, notification_created: true, push: "already_sent" });

    const pushResult = await sendPushToUser(admin, recipientID, {
      title: "Catharsia",
      body: "You have new activity.",
      source: "auto",
      data: { target: "notifications", notification_id: notification.id, post_id: postID },
    });
    const sent = pushResult.sent;

    if (sent > 0) {
      await admin.from("kathar_notifications")
        .update({ push_sent_at: new Date().toISOString() })
        .eq("tenant_id", tenantID)
        .eq("id", notification.id)
        .is("push_sent_at", null);
    }
    return json({ ok: true, notification_created: true, push: sent > 0 ? "sent" : "pending_or_unavailable" });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Catharsia push action failed" }, 500);
  }
});
