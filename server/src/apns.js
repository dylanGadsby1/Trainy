// Sends pushes through Apple Push Notification service with token-based authentication.

const HOSTS = {
  production: "https://api.push.apple.com",
  development: "https://api.sandbox.push.apple.com",
};

const encoder = new TextEncoder();

function base64url(bytes) {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Apple accepts a provider token for an hour and objects to a new one more than every 20 minutes. */
const TOKEN_LIFETIME = 50 * 60;
let cached = { token: null, issuedAt: 0, keyId: null };

/** The signed provider token. `env.APNS_KEY` is the text of the .p8 file from Apple. */
export async function providerToken(env, now = new Date()) {
  const issuedAt = Math.floor(now.getTime() / 1000);
  if (cached.token && cached.keyId === env.APNS_KEY_ID && issuedAt - cached.issuedAt < TOKEN_LIFETIME) {
    return cached.token;
  }

  const der = Uint8Array.from(atob(env.APNS_KEY.replace(/-----[A-Z ]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);

  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: issuedAt })));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(`${header}.${claims}`));

  cached = { token: `${header}.${claims}.${base64url(signature)}`, issuedAt, keyId: env.APNS_KEY_ID };
  return cached.token;
}

/**
 * Sends one push. `type` is "alert" or "liveactivity".
 * Resolves to { ok, status, gone }: `gone` means Apple no longer knows the token.
 */
export async function send(env, fetcher, { token, environment, type, payload, collapseId, now = new Date() }) {
  const headers = {
    authorization: `bearer ${await providerToken(env, now)}`,
    "apns-push-type": type,
    "apns-topic": type === "liveactivity" ? `${env.APNS_TOPIC}.push-type.liveactivity` : env.APNS_TOPIC,
    "apns-priority": "10",
    "content-type": "application/json",
  };
  // A newer alert about the same thing replaces the older one on the Lock Screen
  if (collapseId) headers["apns-collapse-id"] = collapseId.slice(0, 64);

  const response = await fetcher(`${HOSTS[environment] ?? HOSTS.production}/3/device/${token}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  let reason = null;
  if (!response.ok) reason = (await response.json().catch(() => ({}))).reason ?? null;
  return {
    ok: response.ok,
    status: response.status,
    reason,
    gone: response.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered",
  };
}

/** A notification about a train. */
export function alertPayload(title, body, thread) {
  return { aps: { alert: { title, body }, sound: "default", "thread-id": thread } };
}

/** A Live Activity update, or its end when `event` is "end". */
export function liveActivityPayload(contentState, event = "update", now = new Date()) {
  const timestamp = Math.floor(now.getTime() / 1000);
  const aps = { timestamp, event, "content-state": contentState };
  if (event === "end") aps["dismissal-date"] = timestamp;
  return { aps };
}

/** Forget the cached provider token (for tests). */
export function resetProviderToken() {
  cached = { token: null, issuedAt: 0, keyId: null };
}
