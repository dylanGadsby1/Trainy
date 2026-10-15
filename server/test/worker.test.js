import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

import { checkTrains, handleRequest } from "../src/worker.js";
import { providerToken, resetProviderToken } from "../src/apns.js";

/** Workers KV, in memory. */
function memoryKV() {
  const store = new Map();
  return {
    store,
    async get(key, type) {
      const value = store.get(key);
      return value === undefined ? null : (type === "json" ? JSON.parse(value) : value);
    },
    async put(key, value) { store.set(key, value); },
    async delete(key) { store.delete(key); },
    async list({ prefix }) {
      return { keys: [...store.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true };
    },
  };
}

const token = "a".repeat(64);
const activityToken = "b".repeat(64);
let env, keys;

beforeEach(async () => {
  resetProviderToken();
  keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", keys.privateKey)).toString("base64");
  env = {
    TRAINY: memoryKV(),
    DARWIN_KEY: "darwin-key",
    RTT_REFRESH_TOKEN: "rtt-refresh",
    APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----`,
    APNS_KEY_ID: "KEY123",
    APNS_TEAM_ID: "TEAM123",
    APNS_TOPIC: "com.dylangadsby.Trainy",
  };
});

const train = (extra = {}) => ({
  key: "2026-10-13-15:30-MKC-EUS", serviceID: "abc",
  origin: "MKC", destination: "EUS",
  originName: "Milton Keynes Central", destinationName: "London Euston",
  departureDate: "2026-10-13", scheduledDeparture: "15:30", scheduledArrival: "16:05", operatorCode: "VT",
  state: { expectedDeparture: "15:30", expectedArrival: "16:05", platform: "TBC", delayMinutes: 0 },
  ...extra,
});

const register = (body, headers = {}) => handleRequest(new Request(`https://server.test/v1/devices/${token}`, {
  method: "PUT", body: JSON.stringify(body), headers,
}), env);

const board = (service) => ({ trainServices: [{
  serviceID: "abc", std: "15:30", etd: "On time", platform: "5", operatorCode: "VT",
  subsequentCallingPoints: [{ callingPoint: [{ crs: "EUS", st: "16:05", et: "On time" }] }],
  ...service,
}] });

/** Answers Darwin with `darwin` and records what is sent to Apple. */
function network(darwin, apns = () => new Response(null, { status: 200 })) {
  const pushes = [];
  const fetcher = async (url, init = {}) => {
    if (url.includes("raildata.org.uk")) {
      assert.equal(init.headers["x-apikey"], "darwin-key");
      return Response.json(darwin);
    }
    if (url.includes("push.apple.com")) {
      pushes.push({ url, headers: init.headers, body: JSON.parse(init.body) });
      return apns(url);
    }
    throw new Error(`unexpected request to ${url}`);
  };
  return { fetcher, pushes };
}

const before = new Date("2026-10-13T14:00:00Z");

test("a device registers its trains", async () => {
  const response = await register({ environment: "development", trains: [train(), { key: "broken" }] });
  assert.deepEqual(await response.json(), { ok: true, watching: 1 });

  const saved = await env.TRAINY.get(`device:${token}`, "json");
  assert.equal(saved.environment, "development");
  assert.deepEqual(saved.alerts, { delays: true, platforms: true, departures: true });
  assert.equal(saved.trains[0].state.platform, "TBC");
});

test("bad tokens and bodies are refused", async () => {
  const bad = await handleRequest(new Request("https://server.test/v1/devices/nope", { method: "PUT", body: "{}" }), env);
  assert.equal(bad.status, 400);
  assert.equal((await register({})).status, 400);
});

test("the app key is required when one is set", async () => {
  env.APP_KEY = "shared";
  assert.equal((await register({ trains: [] })).status, 401);
  assert.equal((await register({ trains: [] }, { "x-trainy-key": "shared" })).status, 200);
});

test("a platform change is pushed as an alert and to the Live Activity", async () => {
  await register({ environment: "development", trains: [train({ liveActivityToken: activityToken })] });
  const { fetcher, pushes } = network(board());

  const done = await checkTrains(env, before, fetcher);
  assert.deepEqual(done, { devices: 1, boards: 1, alerts: 1, liveActivities: 1, dropped: 0 });

  const [alert, activity] = pushes;
  assert.equal(alert.url, `https://api.sandbox.push.apple.com/3/device/${token}`);
  assert.equal(alert.headers["apns-push-type"], "alert");
  assert.equal(alert.headers["apns-topic"], "com.dylangadsby.Trainy");
  assert.equal(alert.headers["apns-collapse-id"], "2026-10-13-15:30-MKC-EUS.platform");
  assert.deepEqual(alert.body.aps.alert, {
    title: "15:30 Milton Keynes Central to London Euston", body: "Platform 5 confirmed.",
  });

  assert.equal(activity.url, `https://api.sandbox.push.apple.com/3/device/${activityToken}`);
  assert.equal(activity.headers["apns-topic"], "com.dylangadsby.Trainy.push-type.liveactivity");
  assert.equal(activity.body.aps.event, "update");
  assert.deepEqual(activity.body.aps["content-state"], {
    scheduledDeparture: "15:30", expectedDeparture: "15:30", delayMinutes: 0, platform: "5", isCancelled: false,
  });

  // Nothing new a minute later, so nothing is sent
  const again = network(board());
  await checkTrains(env, new Date(before.getTime() + 60000), again.fetcher);
  assert.equal(again.pushes.length, 0);
});

test("what the server has already told the user survives the app registering again", async () => {
  await register({ trains: [train()] });
  await checkTrains(env, before, network(board()).fetcher);

  // The app still thinks the platform is unknown
  await register({ trains: [train()] });
  const { fetcher, pushes } = network(board());
  await checkTrains(env, before, fetcher);
  assert.equal(pushes.length, 0);
});

test("switched-off alerts are not sent", async () => {
  await register({ alerts: { delays: true, platforms: false }, trains: [train()] });
  const { fetcher, pushes } = network(board());
  await checkTrains(env, before, fetcher);
  assert.equal(pushes.length, 0);
});

test("arrival ends the Live Activity and drops the train", async () => {
  await register({ trains: [train({ liveActivityToken: activityToken, state: { platform: "5" } })] });
  const arrived = board({ platform: undefined, subsequentCallingPoints: [{ callingPoint: [{ crs: "EUS", st: "16:05", at: "16:06" }] }] });
  const { fetcher, pushes } = network(arrived);

  const done = await checkTrains(env, new Date("2026-10-13T15:07:00Z"), fetcher);
  assert.equal(done.dropped, 1);
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].url, `https://api.push.apple.com/3/device/${activityToken}`);
  assert.equal(pushes[0].body.aps.event, "end");
  assert.deepEqual((await env.TRAINY.get(`device:${token}`, "json")).trains, []);
});

test("a device Apple no longer knows is forgotten", async () => {
  await register({ trains: [train()] });
  const { fetcher } = network(board(), () => Response.json({ reason: "BadDeviceToken" }, { status: 400 }));
  await checkTrains(env, before, fetcher);
  assert.equal(env.TRAINY.store.size, 0);
});

test("trains outside Darwin's reach cost no request, and old ones are dropped", async () => {
  await register({ trains: [train({ key: "far", departureDate: "2026-10-20" }), train({ key: "old", departureDate: "2026-10-10" })] });
  const { fetcher } = network(board());
  const done = await checkTrains(env, before, fetcher);
  assert.equal(done.boards, 0);
  assert.equal(done.dropped, 1);
  assert.deepEqual((await env.TRAINY.get(`device:${token}`, "json")).trains.map((t) => t.key), ["far"]);
});

test("the Darwin relay adds the key and limits what can be asked", async () => {
  let asked;
  const fetcher = async (url, init) => { asked = { url, init }; return Response.json({ trainServices: [] }); };

  const ok = await handleRequest(new Request("https://server.test/darwin/GetDepBoardWithDetails/EUS?numRows=10"), env, fetcher);
  assert.equal(ok.status, 200);
  assert.match(asked.url, /LDBWS\/api\/20220120\/GetDepBoardWithDetails\/EUS\?numRows=10$/);
  assert.equal(asked.init.headers["x-apikey"], "darwin-key");

  const blocked = await handleRequest(new Request("https://server.test/darwin/GetArrivalBoard/EUS"), env, fetcher);
  assert.equal(blocked.status, 404);
});

test("the Realtime Trains relay exchanges the refresh token once", async () => {
  const asked = [];
  const fetcher = async (url, init) => {
    asked.push({ url, authorization: init.headers.authorization });
    return url.endsWith("/api/get_access_token")
      ? Response.json({ token: "access", validUntil: new Date(Date.now() + 20 * 60000).toISOString() })
      : Response.json({ services: [] });
  };

  for (const path of ["/rtt/gb-nr/location?code=EUS", "/rtt/gb-nr/service?identity=Y1"]) {
    const response = await handleRequest(new Request(`https://server.test${path}`), env, fetcher);
    assert.equal(response.status, 200);
  }
  assert.deepEqual(asked.map((a) => a.authorization), ["Bearer rtt-refresh", "Bearer access", "Bearer access"]);
  assert.equal(asked[1].url, "https://data.rtt.io/gb-nr/location?code=EUS");
});

test("the provider token is a valid ES256 signature and is reused", async () => {
  const now = new Date("2026-10-13T14:00:00Z");
  const jwt = await providerToken(env, now);
  const [header, claims, signature] = jwt.split(".");

  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: "KEY123" });
  assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url")), { iss: "TEAM123", iat: 1791900000 });
  assert.equal(await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, keys.publicKey,
    Buffer.from(signature, "base64url"), new TextEncoder().encode(`${header}.${claims}`),
  ), true);

  assert.equal(await providerToken(env, new Date(now.getTime() + 10 * 60000)), jwt);
  assert.notEqual(await providerToken(env, new Date(now.getTime() + 55 * 60000)), jwt);
});

test("reminders are sent once, and even when the board is not read", async () => {
  await register({ trains: [train({ remind: true, state: { platform: "5", platformConfirmed: true } })] });
  // 14:30 UK, an hour before; nothing has changed on the board
  const hourBefore = new Date("2026-10-13T13:30:00Z");
  const { fetcher, pushes } = network(board());
  await checkTrains(env, hourBefore, fetcher);
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].headers["apns-collapse-id"], "2026-10-13-15:30-MKC-EUS.departure.hour");
  assert.equal(pushes[0].body.aps.alert.body, "Leaves in 1 hour, at 15:30, from platform 5.");

  const again = network({ trainServices: [] });
  await checkTrains(env, new Date(hourBefore.getTime() + 60000), again.fetcher);
  assert.equal(again.pushes.length, 0);

  // The app registering again does not forget what was sent
  await register({ trains: [train({ remind: true })] });
  const soon = network({ trainServices: [] });
  await checkTrains(env, new Date("2026-10-13T14:25:00Z"), soon.fetcher);
  assert.deepEqual(soon.pushes.map((p) => p.body.aps.alert.body), ["Leaves in 5 minutes, at 15:30, from platform 5."]);
  assert.deepEqual((await env.TRAINY.get(`device:${token}`, "json")).trains[0].reminded, ["hour", "soon"]);
});

test("no reminders when they are switched off or the app did not ask", async () => {
  await register({ alerts: { departures: false }, trains: [train({ remind: true })] });
  const off = network({ trainServices: [] });
  await checkTrains(env, new Date("2026-10-13T13:30:00Z"), off.fetcher);
  assert.equal(off.pushes.length, 0);

  await register({ trains: [train()] });
  const unasked = network({ trainServices: [] });
  await checkTrains(env, new Date("2026-10-13T13:30:00Z"), unasked.fetcher);
  assert.equal(unasked.pushes.length, 0);
});
