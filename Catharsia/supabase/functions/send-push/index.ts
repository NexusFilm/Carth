import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type PushRequest = {
  bundle_id: string;
  title: string;
  body: string;
  environment?: "sandbox" | "production";
  source?: "manual" | "auto";
  schedule_id?: string;
  user_ids?: string[];
  device_tokens?: string[];
  allow_environment_override_for_explicit_tokens?: boolean;
  data?: Record<string, unknown>;
  sound?: string;
};

type DeviceTokenRow = {
  id: string;
  user_id: string | null;
  bundle_id: string;
  device_token: string;
  apns_environment: "sandbox" | "production";
};

type UserPushPreferenceRow = {
  user_id: string;
  manual_push_enabled: boolean;
  auto_push_enabled: boolean;
};

type PushSettingsRow = {
  notifications_enabled: boolean;
  production_enabled: boolean;
  sandbox_enabled: boolean;
  broadcast_enabled: boolean;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-admin-secret",
};

const apnsTokenCache = new Map<string, { token: string; issuedAt: number }>();
const apnsTokenGeneration = new Map<string, Promise<string>>();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const pushAdminSecret = Deno.env.get("PUSH_ADMIN_SECRET");
  const authHeader = req.headers.get("Authorization") ?? "";
  const pushAdminHeader = req.headers.get("x-push-admin-secret") ?? "";
  const isServiceRoleAuthorized = Boolean(serviceRoleKey && authHeader === `Bearer ${serviceRoleKey}`);
  const isPushAdminAuthorized = Boolean(pushAdminSecret && pushAdminHeader === pushAdminSecret);

  if (!serviceRoleKey || (!isServiceRoleAuthorized && !isPushAdminAuthorized)) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const payload = await req.json() as PushRequest;
    const validationError = validatePayload(payload);
    if (validationError) {
      return json({ error: validationError }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!supabaseUrl) {
      return json({ error: "Missing SUPABASE_URL" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const environment = payload.environment ?? "production";
    const source = payload.source ?? "manual";

    const gate = await checkPushGate(supabase, payload.bundle_id, environment);
    if (!gate.ok) {
      return json({ error: gate.error }, 409);
    }

    const notificationData = normalizeNotificationData(payload.data);
    const bypassPreferencesForTest = isServiceRoleAuthorized &&
      payload.bundle_id === "com.catharsia.ios" && notificationData.test === true;
    const tokens = await fetchDeviceTokens(
      supabase,
      payload,
      environment,
      source,
      isServiceRoleAuthorized &&
        payload.bundle_id === "com.catharsia.ios" &&
        payload.allow_environment_override_for_explicit_tokens === true &&
        payload.device_tokens?.length === 1,
      bypassPreferencesForTest,
    );

    if (tokens.length === 0) {
      return json({ ok: true, sent: 0, failed: 0, campaign_id: null });
    }

    const { data: campaign, error: campaignError } = await supabase
      .from("push_campaigns")
      .insert({
        bundle_id: payload.bundle_id,
        title: payload.title,
        body: payload.body,
        data: notificationData,
        target_environment: environment,
        source,
        schedule_id: payload.schedule_id ?? null,
        target_user_ids: payload.user_ids ?? null,
      })
      .select("id")
      .single();

    if (campaignError) {
      return json({ error: campaignError.message }, 500);
    }

    // Insert into app_notifications for in-app history
    await supabase.from("app_notifications").insert({
      bundle_id: payload.bundle_id,
      title: payload.title,
      body: payload.body,
      target: notificationData.target,
      source,
    });

    // Truncate to keep only the last 5 notifications per bundle_id
    const { data: recentNotifications } = await supabase
      .from("app_notifications")
      .select("id, created_at")
      .eq("bundle_id", payload.bundle_id)
      .order("created_at", { ascending: false })
      .limit(6);

    if (recentNotifications && recentNotifications.length >= 6) {
      const cutoffTimestamp = recentNotifications[4].created_at as string;
      await supabase
        .from("app_notifications")
        .delete()
        .eq("bundle_id", payload.bundle_id)
        .lt("created_at", cutoffTimestamp);
    }

    const jwt = await createAPNsJWT(environment, payload.bundle_id);
    const results = [];

    for (const token of tokens) {
      results.push(await sendToAPNs({
        token,
        campaignId: campaign.id,
        jwt,
        title: payload.title,
        body: payload.body,
        data: notificationData,
        sound: payload.sound ?? "default",
      }));
    }

    await supabase.from("push_deliveries").insert(results.map((result) => result.delivery));

    const sent = results.filter((result) => result.delivery.success).length;
    return json({
      ok: true,
      campaign_id: campaign.id,
      targeted: tokens.length,
      sent,
      failed: tokens.length - sent,
      results: results.map((result) => result.summary),
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

function normalizeNotificationData(data?: Record<string, unknown>): Record<string, unknown> {
  return {
    target: "home",
    ...data,
  };
}

async function checkPushGate(
  supabase: ReturnType<typeof createClient>,
  bundleId: string,
  environment: "sandbox" | "production",
): Promise<{ ok: true } | { ok: false; error: string }> {
  const { data: app, error: appError } = await supabase
    .from("push_app_configs")
    .select("enabled")
    .eq("bundle_id", bundleId)
    .maybeSingle();

  if (appError) {
    throw appError;
  }

  if (!app || app.enabled === false) {
    return { ok: false, error: "This app is disabled in push_app_configs." };
  }

  const { data: settings, error: settingsError } = await supabase
    .from("push_app_settings")
    .select("notifications_enabled,production_enabled,sandbox_enabled,broadcast_enabled")
    .eq("bundle_id", bundleId)
    .maybeSingle();

  if (settingsError) {
    // Keep backward compatibility if settings table is unavailable.
    return { ok: true };
  }

  const resolved = settings as PushSettingsRow | null;
  if (!resolved) {
    return { ok: true };
  }

  if (resolved.notifications_enabled === false) {
    return { ok: false, error: "Notifications are disabled for this app." };
  }
  if (resolved.broadcast_enabled === false) {
    return { ok: false, error: "Broadcast pushes are disabled for this app." };
  }
  if (environment === "production" && resolved.production_enabled === false) {
    return { ok: false, error: "Production pushes are disabled for this app." };
  }
  if (environment === "sandbox" && resolved.sandbox_enabled === false) {
    return { ok: false, error: "Sandbox pushes are disabled for this app." };
  }

  return { ok: true };
}

function validatePayload(payload: PushRequest): string | null {
  if (!payload.bundle_id?.trim()) return "bundle_id is required";
  if (!payload.title?.trim()) return "title is required";
  if (!payload.body?.trim()) return "body is required";
  if (payload.environment && !["sandbox", "production"].includes(payload.environment)) {
    return "environment must be sandbox or production";
  }
  if (payload.source && !["manual", "auto"].includes(payload.source)) {
    return "source must be manual or auto";
  }
  return null;
}

async function fetchDeviceTokens(
  supabase: ReturnType<typeof createClient>,
  payload: PushRequest,
  environment: "sandbox" | "production",
  source: "manual" | "auto",
  allowEnvironmentOverrideForExplicitTokens: boolean,
  bypassPreferencesForTest: boolean,
): Promise<DeviceTokenRow[]> {
  const canOverrideEnvironment = allowEnvironmentOverrideForExplicitTokens && payload.device_tokens?.length === 1;
  let query = supabase
    .from("push_device_tokens")
    .select("id,user_id,bundle_id,device_token,apns_environment")
    .eq("bundle_id", payload.bundle_id)
    .eq("enabled", true);

  if (!canOverrideEnvironment) {
    query = query.eq("apns_environment", environment);
  }

  if (payload.user_ids?.length) {
    query = query.in("user_id", payload.user_ids);
  }

  if (payload.device_tokens?.length) {
    query = query.in("device_token", payload.device_tokens);
  }

  const { data, error } = await query;
  if (error) throw error;

  const tokens = ((data as DeviceTokenRow[]) ?? []).map((token) =>
    canOverrideEnvironment ? { ...token, apns_environment: environment } : token
  );
  const userIds = [...new Set(tokens.map((token) => token.user_id).filter(Boolean) as string[])];
  if (bypassPreferencesForTest) return tokens;
  const catharsia = payload.bundle_id === "com.catharsia.ios";
  if (userIds.length === 0) return catharsia ? [] : tokens;

  const preferencesTable = catharsia ? "catharsia_push_preferences" : "user_push_preferences";
  const { data: prefsData, error: prefsError } = await supabase
    .from(preferencesTable)
    .select("user_id,manual_push_enabled,auto_push_enabled")
    .in("user_id", userIds);

  if (prefsError) {
    throw prefsError;
  }

  const prefsByUser = new Map<string, UserPushPreferenceRow>();
  for (const row of (prefsData as UserPushPreferenceRow[]) ?? []) {
    prefsByUser.set(row.user_id, row);
  }

  return tokens.filter((token) => {
    if (!token.user_id) return !catharsia;
    const pref = prefsByUser.get(token.user_id);
    if (!pref) return !catharsia;
    return source === "auto" ? pref.auto_push_enabled : pref.manual_push_enabled;
  });
}

async function createAPNsJWT(environment: "sandbox" | "production", bundleID: string): Promise<string> {
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const environmentPrefix = environment === "sandbox" ? "APNS_SANDBOX" : "APNS_PRODUCTION";
  const requiresCatharsiaKey = bundleID === "com.catharsia.ios";
  const keyPrefix = requiresCatharsiaKey ? `CATHARSIA_${environmentPrefix}` : environmentPrefix;
  const environmentKeyId = Deno.env.get(`${keyPrefix}_KEY_ID`);
  const environmentPrivateKey = Deno.env.get(`${keyPrefix}_PRIVATE_KEY`);
  if (Boolean(environmentKeyId) !== Boolean(environmentPrivateKey)) {
    throw new Error(`Both ${environmentPrefix}_KEY_ID and ${environmentPrefix}_PRIVATE_KEY are required together`);
  }
  if (requiresCatharsiaKey && (!environmentKeyId || !environmentPrivateKey)) {
    throw new Error(`Catharsia requires its own ${environmentPrefix} APNs key; shared app keys are not used`);
  }
  const keyId = environmentKeyId || (requiresCatharsiaKey ? undefined : Deno.env.get("APNS_KEY_ID"));
  const privateKey = (environmentPrivateKey || (requiresCatharsiaKey ? undefined : Deno.env.get("APNS_PRIVATE_KEY")))?.replace(/\\n/g, "\n");

  if (!teamId || !keyId || !privateKey) {
    throw new Error("Missing APNS_TEAM_ID or an APNs signing key for the selected environment");
  }

  const cacheKey = `${teamId}:${keyId}`;
  const now = Math.floor(Date.now() / 1000);
  const cached = apnsTokenCache.get(cacheKey);
  if (cached && now - cached.issuedAt < 50 * 60) return cached.token;

  const pending = apnsTokenGeneration.get(cacheKey);
  if (pending) return await pending;

  const generation = (async () => {
    const header = base64UrlEncode(JSON.stringify({ alg: "ES256", kid: keyId }));
    const claims = base64UrlEncode(JSON.stringify({ iss: teamId, iat: now }));
    const signingInput = `${header}.${claims}`;
    const key = await importPrivateKey(privateKey);
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    );
    const token = `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
    apnsTokenCache.set(cacheKey, { token, issuedAt: now });
    return token;
  })();

  apnsTokenGeneration.set(cacheKey, generation);
  try {
    return await generation;
  } finally {
    if (apnsTokenGeneration.get(cacheKey) === generation) apnsTokenGeneration.delete(cacheKey);
  }
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function sendToAPNs(params: {
  token: DeviceTokenRow;
  campaignId: string;
  jwt: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  sound: string;
}) {
  const host = params.token.apns_environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);

  let response: Response;
  try {
    response = await fetch(`${host}/3/device/${params.token.device_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${params.jwt}`,
        "apns-topic": params.token.bundle_id,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: {
            title: params.title,
            body: params.body,
          },
          sound: params.sound,
        },
        ...params.data,
      }),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(timeout);
    const msg = err instanceof Error ? err.message : String(err);
    return {
      delivery: {
        campaign_id: params.campaignId,
        device_token_id: params.token.id,
        bundle_id: params.token.bundle_id,
        apns_environment: params.token.apns_environment,
        apns_id: null,
        status_code: 0,
        success: false,
        response_body: `fetch error: ${msg}`,
      },
      summary: {
        device_token_id: params.token.id,
        status_code: 0,
        success: false,
        apns_id: null,
        response_body: `fetch error: ${msg}`,
      },
    };
  }
  clearTimeout(timeout);

  const responseBody = await response.text();
  const apnsId = response.headers.get("apns-id");
  return {
    delivery: {
      campaign_id: params.campaignId,
      device_token_id: params.token.id,
      bundle_id: params.token.bundle_id,
      apns_environment: params.token.apns_environment,
      apns_id: apnsId,
      status_code: response.status,
      success: response.ok,
      response_body: responseBody,
    },
    summary: {
      device_token_id: params.token.id,
      status_code: response.status,
      success: response.ok,
      apns_id: apnsId,
      response_body: responseBody,
    },
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
    },
  });
}

function base64UrlEncode(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}
