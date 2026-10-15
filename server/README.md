# Trainy server

A small Cloudflare Worker that does two things the app cannot do on its own:

- **Pushes changes while the app is closed.** Once a minute it re-reads every followed
  train from Darwin and sends what changed: a notification to the phone, and an update to
  the train's Live Activity.
- **Keeps the feed keys out of the app.** The app reads Darwin and Realtime Trains through
  it, so the keys live here as secrets instead of shipping inside the app.

The app works without it. With no server address set it reads the feeds itself and raises
its own alerts, which only happens while it is open or when iOS wakes it.

## What you need

| | |
|---|---|
| A Cloudflare account | The free plan is enough for a handful of devices |
| Apple Developer Program membership | Push notifications are not available to free teams |
| An APNs key | developer.apple.com → Certificates, IDs & Profiles → Keys → **+** → Apple Push Notifications service. Download the `.p8` file and note the Key ID and your Team ID |
| Your Darwin key and Realtime Trains refresh token | The ones in `Secrets.swift` |

## Deploy

From this folder:

```bash
npx wrangler login
```

```bash
npx wrangler kv namespace create TRAINY
```

Paste the id it prints into `wrangler.toml`, then set each secret. `APNS_KEY` is the whole
text of the `.p8` file, including the BEGIN and END lines.

```bash
npx wrangler secret put DARWIN_KEY
```

```bash
npx wrangler secret put RTT_REFRESH_TOKEN
```

```bash
npx wrangler secret put APNS_KEY
```

```bash
npx wrangler secret put APNS_KEY_ID
```

```bash
npx wrangler secret put APNS_TEAM_ID
```

`APP_KEY` is optional: any string you choose, which the app must then send with every
request. It ships inside the app, so it only turns away people who have nothing but the
address.

```bash
npx wrangler secret put APP_KEY
```

```bash
npx wrangler deploy
```

## Point the app at it

1. In Xcode, select the Trainy target → **Signing & Capabilities** → **+ Capability** →
   **Push Notifications**.
2. In `Info.plist`, set `TrainyServerURL` to the address `wrangler deploy` printed, and
   `TrainyServerKey` to your `APP_KEY` if you set one.

That is all. The app then registers for push, tells the server which trains it is
following, and stops raising its own delay and platform alerts and its reminders an hour and
five minutes before each train leaves: the server sends those from live times. Delay Repay
reminders are still scheduled on the phone.

## How it works

| Request | |
|---|---|
| `PUT /v1/devices/:token` | The trains a device is following. Replaces what was there |
| `DELETE /v1/devices/:token` | Stop watching for a device |
| `GET /darwin/…` | A Darwin departure board, with the key added |
| `GET /rtt/…` | Realtime Trains, with the token added |
| `GET /v1/health` | `{"ok":true}` |

Each device is one record in KV: its push address, its alert switches, and for each train
the last state the server saw and the last delay it told the user about. The record
lapses after a month without a change, and a train is removed when it arrives.

The rules for what is worth an alert, and the wording, are in `src/alerts.js`. They match
`TrainAlerts.swift`, which does the same job when there is no server.

## Limits

- A train is only checked while Darwin lists it: from about four hours before it leaves
  until it arrives. Earlier than that nothing is pushed.
- The free plan allows 50 outgoing requests per run and 1,000 KV writes a day. That is
  plenty for personal use; a public release needs the paid plan.
- There is no per-device rate limit, and `APP_KEY` is not real authentication. Before a
  public release, add App Attest or similar so only the genuine app can use the relay.
- APNs needs HTTP/2, which a Worker's `fetch` speaks. Node's built-in `fetch` does not, so
  hosting this anywhere else means changing `send` in `src/apns.js`.

## Tests

No dependencies; Node 20 or later.

```bash
npm test
```
