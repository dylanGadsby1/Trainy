// Trainy's server, as a Cloudflare Worker.
//
//   PUT    /v1/devices/:token   the trains a device wants watched (replaces what was there)
//   DELETE /v1/devices/:token   stop watching for a device
//   GET    /darwin/…            National Rail's departure boards, with the key added here
//   GET    /rtt/…               Realtime Trains, with the token added here
//
// Once a minute it re-reads every watched train from Darwin and pushes what changed:
// an alert to the device, and an update to the train's Live Activity if it has one. It also
// sends the reminders an hour and five minutes before each train leaves.

import { changes, contentState, departureReminder, journeyName } from "./alerts.js";
import { alertPayload, liveActivityPayload, send } from "./apns.js";
import { DARWIN_BASE, boardOffset, boardURL, departureAt, findService, stateFrom } from "./darwin.js";

const RTT_BASE = "https://data.rtt.io";

/** A device registers again whenever its trains change, so a record idle this long is dead. */
const DEVICE_TTL = 30 * 24 * 3600;

/** A train is dropped this long after it was due to leave, whatever became of it. */
const TRAIN_LIFETIME = 6 * 3600 * 1000;

/** Darwin boards read in one run, to stay inside the Worker's subrequest allowance. */
const MAX_BOARDS = 20;

const DEVICE_TOKEN = /^[0-9a-f]{64,200}$/;
const DARWIN_PATH = /^\/(GetDepartureBoard|GetDepBoardWithDetails)\/[A-Za-z]{3}$/;
const RTT_PATH = /^\/[a-z-]+\/(location|service)$/;

export default {
  fetch(request, env) {
    return handleRequest(request, env);
  },
  scheduled(event, env, context) {
    context.waitUntil(checkTrains(env, new Date(event.scheduledTime)));
  },
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// MARK: - Requests

export async function handleRequest(request, env, fetcher = fetch) {
  const url = new URL(request.url);

  if (url.pathname === "/v1/health") return json({ ok: true });

  // Not a secret that can be kept, since it ships in the app, but it turns away anyone
  // who only has the address
  if (env.APP_KEY && request.headers.get("x-trainy-key") !== env.APP_KEY) {
    return json({ error: "unauthorised" }, 401);
  }

  const device = url.pathname.match(/^\/v1\/devices\/([^/]+)$/);
  if (device) {
    const token = device[1].toLowerCase();
    if (!DEVICE_TOKEN.test(token)) return json({ error: "invalid device token" }, 400);
    if (request.method === "PUT") return registerDevice(env, token, await request.json().catch(() => null));
    if (request.method === "DELETE") {
      await env.TRAINY.delete(`device:${token}`);
      return json({ ok: true });
    }
    return json({ error: "method not allowed" }, 405);
  }

  if (request.method === "GET" && url.pathname.startsWith("/darwin/")) {
    const path = url.pathname.slice("/darwin".length);
    if (!DARWIN_PATH.test(path)) return json({ error: "not found" }, 404);
    return relay(await fetcher(`${DARWIN_BASE}${path}${url.search}`, {
      headers: { "x-apikey": env.DARWIN_KEY, accept: "application/json" },
    }));
  }

  if (request.method === "GET" && url.pathname.startsWith("/rtt/")) {
    const path = url.pathname.slice("/rtt".length);
    if (!RTT_PATH.test(path)) return json({ error: "not found" }, 404);
    return relay(await fetchRTT(env, fetcher, `${RTT_BASE}${path}${url.search}`));
  }

  return json({ error: "not found" }, 404);
}

/** Passes a feed's answer back as it came, status and all. */
function relay(response) {
  const headers = { "content-type": response.headers.get("content-type") ?? "application/json" };
  const retryAfter = response.headers.get("retry-after");
  if (retryAfter) headers["retry-after"] = retryAfter;
  return new Response(response.body, { status: response.status, headers });
}

// MARK: - Realtime Trains

let rttAccess = { token: null, expires: 0 };

/** Realtime Trains hands out short-lived access tokens in exchange for the refresh token. */
async function rttAccessToken(env, fetcher) {
  if (rttAccess.token && rttAccess.expires - Date.now() > 60_000) return rttAccess.token;

  const response = await fetcher(`${RTT_BASE}/api/get_access_token`, {
    headers: { authorization: `Bearer ${env.RTT_REFRESH_TOKEN}`, accept: "application/json" },
  });
  if (!response.ok) return null;

  const { token, validUntil } = await response.json();
  rttAccess = { token, expires: Date.parse(validUntil) || Date.now() + 10 * 60_000 };
  return token;
}

async function fetchRTT(env, fetcher, url, retrying = false) {
  const token = await rttAccessToken(env, fetcher);
  if (!token) return json({ error: "Realtime Trains refused the token" }, 502);

  const response = await fetcher(url, { headers: { authorization: `Bearer ${token}`, accept: "application/json" } });
  if (response.status === 401 && !retrying) {
    // The access token expired early: get a new one and try once more
    rttAccess = { token: null, expires: 0 };
    return fetchRTT(env, fetcher, url, true);
  }
  return response;
}

// MARK: - Devices

const text = (value, max = 80) => (typeof value === "string" && value.length <= max ? value : null);
const flag = (value) => value === true;

/** One watched train, reduced to the fields this server understands. */
function cleanTrain(input) {
  const train = {
    key: text(input?.key, 120),
    serviceID: text(input?.serviceID, 120),
    origin: text(input?.origin, 3),
    destination: text(input?.destination, 3),
    originName: text(input?.originName),
    destinationName: text(input?.destinationName),
    departureDate: text(input?.departureDate, 10),
    scheduledDeparture: text(input?.scheduledDeparture, 5),
    scheduledArrival: text(input?.scheduledArrival, 5),
    operatorCode: text(input?.operatorCode, 4),
    liveActivityToken: text(input?.liveActivityToken, 400),
    remind: flag(input?.remind),
    state: {
      expectedDeparture: text(input?.state?.expectedDeparture, 5) ?? text(input?.scheduledDeparture, 5),
      expectedArrival: text(input?.state?.expectedArrival, 5),
      platform: text(input?.state?.platform, 8) ?? "TBC",
      // Null from an app too old to say, which counts a known platform as confirmed
      platformConfirmed: typeof input?.state?.platformConfirmed === "boolean" ? input.state.platformConfirmed : null,
      delayMinutes: Number.isInteger(input?.state?.delayMinutes) ? input.state.delayMinutes : 0,
      isCancelled: flag(input?.state?.isCancelled),
      hasUnknownDelay: flag(input?.state?.hasUnknownDelay),
      hasArrived: flag(input?.state?.hasArrived),
    },
  };
  const valid = train.key && train.origin && train.destination
    && /^\d{4}-\d{2}-\d{2}$/.test(train.departureDate ?? "") && /^\d{2}:\d{2}$/.test(train.scheduledDeparture ?? "");
  return valid ? train : null;
}

async function registerDevice(env, token, body) {
  if (!body || !Array.isArray(body.trains)) return json({ error: "invalid body" }, 400);

  const existing = await env.TRAINY.get(`device:${token}`, "json");
  const known = new Map((existing?.trains ?? []).map((train) => [train.key, train]));

  const trains = body.trains.slice(0, 20).map(cleanTrain).filter(Boolean).map((train) => {
    // What this server has already seen and said about a train outranks the app's copy,
    // so a change the app noticed first is still pushed
    const before = known.get(train.key);
    return before ? { ...train, state: before.state, alertedDelay: before.alertedDelay, reminded: before.reminded } : train;
  });

  const record = {
    token,
    environment: body.environment === "development" ? "development" : "production",
    alerts: {
      delays: body.alerts?.delays !== false,
      platforms: body.alerts?.platforms !== false,
      departures: body.alerts?.departures !== false,
    },
    trains,
  };
  await env.TRAINY.put(`device:${token}`, JSON.stringify(record), { expirationTtl: DEVICE_TTL });
  return json({ ok: true, watching: trains.length });
}

async function allDevices(env) {
  const devices = [];
  let cursor;
  do {
    const page = await env.TRAINY.list({ prefix: "device:", cursor });
    for (const { name } of page.keys) {
      const device = await env.TRAINY.get(name, "json");
      if (device) devices.push(device);
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return devices;
}

// MARK: - The Minute Check

/** Re-reads every watched train and pushes what changed. Returns a count of each thing done. */
export async function checkTrains(env, now = new Date(), fetcher = fetch) {
  const done = { devices: 0, boards: 0, alerts: 0, liveActivities: 0, dropped: 0 };
  const boards = new Map();

  /** Each board is fetched once however many devices are watching trains on it. */
  async function board(train, offset) {
    const url = boardURL(train.origin, train.destination, offset);
    if (!boards.has(url)) {
      if (boards.size >= MAX_BOARDS) return null;
      boards.set(url, fetcher(url, { headers: { "x-apikey": env.DARWIN_KEY, accept: "application/json" } })
        .then((response) => (response.ok ? response.json() : null))
        .catch(() => null));
      done.boards += 1;
    }
    return boards.get(url);
  }

  for (const device of await allDevices(env)) {
    done.devices += 1;
    let changed = false;
    let gone = false;
    const kept = [];

    for (const train of device.trains) {
      if (now - departureAt(train) > TRAIN_LIFETIME) {
        changed = true;
        done.dropped += 1;
        continue;
      }
      kept.push(train);

      const alert = async (kind, body) => {
        const result = await send(env, fetcher, {
          token: device.token,
          environment: device.environment,
          type: "alert",
          payload: alertPayload(journeyName(train), body, train.key),
          collapseId: `${train.key}.${kind}`,
          now,
        });
        done.alerts += 1;
        gone ||= result.gone;
      };

      const offset = boardOffset(train, now);
      const service = offset === null ? null : findService(await board(train, offset), train);
      const old = train.state;
      const next = service ? stateFrom(service, train, old) : old;

      if (JSON.stringify(next) !== JSON.stringify(old)) {
        const { alerts, alertedDelay } = changes(train, old, next, now);
        train.state = next;
        train.alertedDelay = alertedDelay;
        changed = true;

        for (const { kind, body } of alerts) {
          if (kind === "delay" ? !device.alerts.delays : !device.alerts.platforms) continue;
          await alert(kind, body);
        }

        const shown = contentState(train, next);
        if (train.liveActivityToken && (next.hasArrived || JSON.stringify(shown) !== JSON.stringify(contentState(train, old)))) {
          const result = await send(env, fetcher, {
            token: train.liveActivityToken,
            environment: device.environment,
            type: "liveactivity",
            payload: liveActivityPayload(shown, next.hasArrived ? "end" : "update", now),
            now,
          });
          done.liveActivities += 1;
          // The activity has ended, or the user dismissed it
          if (next.hasArrived || result.gone) train.liveActivityToken = null;
        }

        // Nothing more to say about a train that has arrived
        if (next.hasArrived) {
          kept.pop();
          done.dropped += 1;
          continue;
        }
      }

      // From the stored times when Darwin's board was not read this run
      const reminder = device.alerts.departures === false ? null : departureReminder(train, now);
      if (reminder) {
        train.reminded = [...(train.reminded ?? []), reminder.kind];
        changed = true;
        await alert(`departure.${reminder.kind}`, reminder.body);
      }
    }

    if (gone) {
      // Apple no longer knows this device: the app was removed, or notifications reset
      await env.TRAINY.delete(`device:${device.token}`);
    } else if (changed) {
      device.trains = kept;
      await env.TRAINY.put(`device:${device.token}`, JSON.stringify(device), { expirationTtl: DEVICE_TTL });
    }
  }

  return done;
}
