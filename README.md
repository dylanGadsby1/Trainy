# Trainy

A native iOS app for following UK trains in real time. Save the trains you're catching, watch their live times on a map, get told when something changes, and keep a record of every journey you've made.

![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-black?style=flat-square&logo=apple)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue?style=flat-square)
![SwiftData](https://img.shields.io/badge/storage-SwiftData-purple?style=flat-square)

---

## What it does

**Finding a train**
- Search any origin and destination, for now or any future date. Live and timetabled trains come back as one list with no duplicates.
- Routes that need a change are found too, and every train on them is followed as one journey.
- Star a route to search it again in one tap, with a shortcut for the return trip.

**Following it**
- My Trains sits on a full-screen map in a draggable bottom sheet. Each card shows the operator, times, platform and an On time / Delayed / Cancelled / Scheduled status, refreshed every minute.
- The journey page lists every calling point with live times, draws the route along the real tracks and shows where the train probably is right now.
- Live Activities on the Lock Screen and Dynamic Island, for one train or a whole journey from train to train.
- A Next Train widget for the Home Screen (small and medium) and Lock Screen.
- Share a train with someone: when it's now due in, and a link to follow it live.

**When things go wrong**
- Alerts for delays, cancellations, platform confirmations and platform changes, plus reminders an hour and five minutes before departure.
- If a delay puts a change at risk, Trainy warns you and lists the later ways to finish the journey, with a one-tap switch that keeps it as one journey.
- When a train is cancelled or running late, Other Trains shows the services that would get you there sooner.
- At a change: the platform you arrive on and leave from, Tube status across London, and a reminder five minutes before you arrive.

**Afterwards**
- Finished and cancelled trains move to Rail History automatically.
- Stats: journeys, punctuality, minutes delayed, miles, favourite routes and operators, and journeys by month.
- Delay Repay: Trainy works out which journeys qualify (a journey with a change is judged by how late it finished), links to the right operator's claim page and reminds you before the window closes.

**Commute Mode**
- Mark a saved route as a commute, with its days and usual departure time. Trainy then follows that train (or the journey with a change) for you from 12 hours before.

**Optional extras**
- **iCloud sync** of saved trains, Rail History, saved routes, your name and journey options across your devices, with no sign-up.
- **A small server** that pushes alerts and Live Activity updates while the app is closed and keeps the feed keys out of the app. See [server/README.md](server/README.md).

---

## Where the data comes from

| Source | Used for | Notes |
|---|---|---|
| [Darwin Live Departure Boards](https://raildata.org.uk/) (National Rail, via the Rail Data Marketplace) | Live times, platforms, cancellations | Only lists trains from about 4 hours before departure. Needs a key |
| [Realtime Trains](https://www.realtimetrains.co.uk/) | The timetable for any date, and trains Darwin has dropped | Needs a refresh token. Limited to 10 requests a minute |
| [Transitous](https://transitous.org/) | Planning routes with a change, and the track shape drawn on the map | Free, no key. Credited wherever its routes appear |
| [TfL Unified API](https://api.tfl.gov.uk/) | Tube line status at a London change | Free, no key |

### How a saved train moves between feeds

[TrainSync.swift](TrainSync.swift) decides which feed each saved train is read from:

| When | Feed | How often |
|---|---|---|
| More than ~4 hours before departure | Realtime Trains | Every half hour |
| ~4 hours before until Darwin drops it | Darwin | Every minute |
| After Darwin drops it | Realtime Trains | Until it's seen arriving |

Darwin and Realtime Trains share no ID, so a train saved from the timetable is matched to its Darwin entry by origin, destination, date, scheduled departure and operator, then switched over.

---

## Getting started

### Requirements

- Xcode 16 or later
- iOS 18 or later for the app. The widget extension (widgets and Live Activities) is currently set to iOS 26.2.

### 1. Clone

```bash
git clone https://github.com/dylanGadsby1/Trainy.git
```

### 2. Add your API keys

1. Sign up at [raildata.org.uk](https://raildata.org.uk) and subscribe to **Live Departure Board**.
2. Get a Realtime Trains **refresh token** from [api-portal.rtt.io](https://api-portal.rtt.io).
3. Copy the template and fill in both values:

```bash
cp Secrets.swift.example Secrets.swift
```

```swift
enum Secrets {
    static let railDataKey = "YOUR_RAIL_DATA_API_KEY"
    static let rttRefreshToken = "YOUR_RTT_REFRESH_TOKEN"
}
```

`Secrets.swift` is git-ignored.

> Realtime Trains doesn't allow its token to ship inside an app distributed to other people. That's fine for your own device, but a public release should read the feeds through the [server](server/README.md) instead.

### 3. Run

```bash
open Trainy.xcodeproj
```

Pick the **Trainy** scheme, choose a simulator or device and press ⌘R.

A free Personal Team can build and run the app, but can't use iCloud or push notifications. Both need a paid Apple Developer Program membership.

### 4. Optional: iCloud sync

Without the iCloud capability, everything stays on the device. To turn sync on:

1. In Xcode, select the **Trainy** target → **Signing & Capabilities** → **+ Capability** → **iCloud**.
2. Tick **CloudKit** and add a container, such as `iCloud.com.dylangadsby.Trainy`.
3. Run the app. It finds the container on its own, and Profile → Privacy then shows **iCloud Sync**.

The `remote-notification` background mode CloudKit needs is already in `Info.plist`. Before a release, deploy the CloudKit schema to production in the CloudKit Console once the app has run with the container.

### 5. Optional: the server

Without a server, Trainy raises its own alerts, which only happens while it's open or when iOS wakes it for a background refresh. With one, alerts and Live Activity updates arrive while the app is closed.

The server is a Cloudflare Worker in [server/](server/). Deploy it as described in [server/README.md](server/README.md), add the **Push Notifications** capability, and set `TrainyServerURL` (and `TrainyServerKey` if you chose one) in `Info.plist`.

---

## How the code is organised

The app sources sit at the repository root. Xcode's **Trainy** target compiles them, and **Trainy RTT API Live Activities** is the widget extension.

### App and screens

| File | What it holds |
|---|---|
| [TrainyApp.swift](TrainyApp.swift) | Entry point, the SwiftData container and the background refresh task |
| [ContentView.swift](ContentView.swift) | The map, the floating tab bar (My Trains, Rail History), the journey page and sharing |
| [HomeView.swift](HomeView.swift) | My Trains cards and `MapBottomSheet`, the custom draggable sheet with four snap points |
| [AddTrainView.swift](AddTrainView.swift) | Search form, station picker, results and the button that saves a train |
| [JourneyViews.swift](JourneyViews.swift) | Journeys with a change: connections, results, legs and missed-connection options |
| [AlternativeTrains.swift](AlternativeTrains.swift) | Other Trains, for when a followed train is cancelled or late |
| [CommuteMode.swift](CommuteMode.swift) | Commute Mode and its editor |
| [RailHistoryView.swift](RailHistoryView.swift) | Rail History and Delay Repay claims |
| [RailStatsView.swift](RailStatsView.swift) | Travel stats and the monthly chart |
| [ProfileView.swift](ProfileView.swift) | Profile, notification settings, privacy and about |
| [Theme.swift](Theme.swift) | Colours for light and dark mode, cards, labels and button styles |
| [OperatorBranding.swift](OperatorBranding.swift) | Logos, brand colours and Delay Repay links for each operator |

### Data and services

| File | What it holds |
|---|---|
| [DarwinAPI.swift](DarwinAPI.swift) | Darwin client and models, plus `DarwinServiceAdapter`, the train model the whole app uses |
| [RTTService.swift](RTTService.swift) | Realtime Trains client |
| [RTTModels.swift](RTTModels.swift) | Realtime Trains models, `TrainStatus` and the UK station list |
| [TrainSearch.swift](TrainSearch.swift) | One search over both feeds, merged |
| [TrainSync.swift](TrainSync.swift) | Refreshes saved trains, hands them between feeds, archives finished ones, feeds the widget and schedules background refresh |
| [JourneyPlanner.swift](JourneyPlanner.swift) | Transitous route planning, journey search options and Tube status |
| [RouteLine.swift](RouteLine.swift) | The track shape of a journey, stored as an encoded polyline |
| [SavedTrain.swift](SavedTrain.swift) | SwiftData models for saved trains and saved routes, and Delay Repay eligibility |
| [TrainAlerts.swift](TrainAlerts.swift) | Local notifications and reminders |
| [LiveActivityManager.swift](LiveActivityManager.swift) | Starts, updates and ends Live Activities |
| [CloudSync.swift](CloudSync.swift) | Optional iCloud store, merging duplicates made on two devices, synced preferences |
| [TrainyServer.swift](TrainyServer.swift) | Optional server: push registration and reading the feeds through it |
| [TrainyWidgetData.swift](TrainyWidgetData.swift), [TrainyActivityAttributes.swift](TrainyActivityAttributes.swift) | Shared with the widget extension through the App Group `group.com.dylangadsby.Trainy` |

### Widget extension

[Trainy RTT API Live Activities/](Trainy%20RTT%20API%20Live%20Activities/) contains the Live Activity and Dynamic Island layouts and [NextTrainWidget.swift](Trainy%20RTT%20API%20Live%20Activities/NextTrainWidget.swift).

### Server

[server/](server/) is a Cloudflare Worker with no dependencies. A cron trigger checks every followed train against Darwin once a minute and sends APNs pushes; device records live in Workers KV. Tests run with `npm test` on Node 20+.

### Other files in the repo

The Python and Ruby scripts at the root (`test_*.py`, `fetch_stations*.py`, `scratch*.py`, `add_*.rb`), `rtt_openapi.yml`, `rtt_response.json`, the `ukStations_*generated.swift` files and the Swift files inside `Trainy.xcodeproj/` are leftovers from early API exploration. None of them are part of the build.

---

## Design notes

- **SwiftUI and SwiftData throughout**, with async/await for every network call.
- **Every stored property is optional or has a default, and none is unique.** CloudKit sync needs both, so keep it that way when adding fields to `SavedTrain` or `SavedRoute`.
- **Few requests per search.** Darwin boards are requested with calling points included, and a Realtime Trains search takes two requests however many trains it returns, which keeps it under the 10-a-minute limit.
- **No server required.** The app works fully on its own; the server only improves alerts while the app is closed.

---

## Roadmap

- [x] Home Screen and Lock Screen widgets
- [x] iCloud sync
- [x] Push alerts while the app is closed (needs the optional server)
- [ ] Apple Watch app
- [ ] Ticket wallet integration
- [ ] App Attest or similar on the server before any public release

---

## Acknowledgements

- Live data from [National Rail](https://www.nationalrail.co.uk/) via the Rail Data Marketplace
- Timetable data from [Realtime Trains](https://www.realtimetrains.co.uk/)
- Journey planning by [Transitous](https://transitous.org/), built on [open timetable data](https://transitous.org/sources/)
- Tube status from [Transport for London](https://tfl.gov.uk/)
- Operator logos are trademarks of their owners
