<h1 align="center">
  🚆 Trainy
</h1>

<p align="center">
  <strong>A beautiful real-time train tracker for the UK National Rail network</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS-black?style=flat-square&logo=apple" />
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square&logo=swift" />
  <img src="https://img.shields.io/badge/SwiftUI-✓-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/SwiftData-✓-purple?style=flat-square" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
</p>

---

## Overview

Trainy is a native iOS app that lets you track your UK train journeys in real time. Pin the trains you care about, watch live departure and arrival updates, and review your complete Rail History — all wrapped in a clean, map-first interface.

Data comes from two feeds. National Rail's **Darwin Live Departure Boards** API, from the [Rail Data Marketplace](https://raildata.org.uk/), gives live times for trains leaving within about four hours. **[Realtime Trains](https://www.realtimetrains.co.uk/)** gives the timetable for anything later. A train saved from the timetable switches to Darwin automatically once Darwin lists it.

---

## Features

| Feature | Description |
|---|---|
| 🗺️ **Map-first Home** | Interactive UK map with a draggable bottom sheet showing your saved trains |
| 🚆 **My Trains** | Pin upcoming departures and see live status cards with operator branding |
| 🔍 **Add Journey** | Search any origin → destination pair, from now to any future date, as one list with no duplicates |
| ⏱️ **Live Status** | On time / Delayed / Cancelled badges refreshed every minute, and Scheduled for trains not yet live |
| 📊 **Journey Dashboard** | Per-train detail view with scheduled vs realtime times and platform info |
| 📜 **Rail History** | Automatic archiving of completed and cancelled journeys |
| 📈 **Travel Stats** | Journeys, punctuality, minutes delayed, miles, most-used routes, operators and Delay Repay, with journeys by month |
| 🚂 **Operator Branding** | Logos and brand colours for 26 UK rail operators |
| 💸 **Delay Repay** | Deep links to every operator's Delay Repay compensation page, with a journey of several trains claimed for by how late it ended |
| 📲 **Widgets** | Your next saved train on the Home Screen (small and medium) and Lock Screen: when it leaves, a countdown, its platform and whether it is on time, moving on to the next train once one leaves |
| 📍 **Live Activities** | Follow a train, or a whole journey from train to train, from the Lock Screen and Dynamic Island |
| 🔔 **Notifications** | Delay and cancellation alerts, an alert when the platform is confirmed and whenever it changes, reminders an hour and five minutes before the train leaves, and reminders to claim Delay Repay |
| 🚏 **Calling Points** | Every stop on the journey with live times, the route on the map and the train's estimated position |
| ⭐ **Saved Routes** | Star a route to search it in one tap, with a shortcut for the return journey |
| 🔁 **Journeys with a Change** | Search finds routes that need a change, follows every train on them as one journey, and warns when a delay puts a change at risk |
| 🧭 **Missed Connections** | When a change is in doubt, the later ways to finish the journey, with a one-tap switch that keeps it one journey |
| 🚉 **At the Change** | Platform to platform, how the Tube is running across London, and a reminder five minutes before you arrive |
| 🧳 **Commute Mode** | Mark a saved route as a commute, with its days and usual time, and the train (or the journey with a change) is followed for you from 12 hours before |
| 🔀 **Other Trains** | When a followed train is cancelled or running late, the trains that would get you there sooner, with a one-tap switch |
| 📤 **Share Journey** | Send someone your train, when it is now due in, and a link to follow it live |
| ☁️ **Optional Server** | A Cloudflare Worker that pushes changes while the app is closed and keeps the feed keys out of the app ([server/](server/README.md)) |
| 📱 **SwiftData Persistence** | Saved trains and history survive app restarts |

---

## Screenshots

> _Coming soon — run the app and add your trains!_

---

## Architecture

```
Trainy/
├── TrainyApp.swift          # App entry point & SwiftData model container
├── ContentView.swift        # Tab bar + top-level navigation
├── Theme.swift              # Colours (light and dark), the card style, shared buttons and labels
│
├── HomeView.swift           # Map view + draggable bottom sheet
├── AddTrainView.swift       # Station picker + live departure search
├── RailHistoryView.swift    # Archived past journeys
├── RailStatsView.swift      # What the Rail History adds up to, and the stats page
├── CommuteMode.swift        # Follows a commute's usual train, and the commute editor
├── AlternativeTrains.swift  # Other trains to switch to when one is cancelled or late
├── JourneyPlanner.swift     # Routes with a change, planned by Transitous; search options; Tube status
├── RouteLine.swift          # A train's path along the tracks, for drawing on the map
├── JourneyViews.swift       # Route results, the legs of a journey and the changes between them
├── ProfileView.swift        # Travel stats, notification settings, privacy & about
│
├── DarwinAPI.swift          # Darwin API client, response models & the app's train model
├── TrainSearch.swift        # One search across Darwin and Realtime Trains, merged
├── TrainSync.swift          # Refreshes saved trains and hands them from the timetable to Darwin
├── TrainAlerts.swift        # Delay, platform and Delay Repay notifications
├── TrainyServer.swift       # Optional: push registration and the feeds through server/
├── LiveActivityManager.swift # Starts and updates the Live Activity
├── TrainyWidgetData.swift   # What the widgets show, shared with the extension through an App Group
├── RTTService.swift         # Realtime Trains API client (timetable search and fallback updates)
├── RTTModels.swift          # Train status, UK station list & legacy RTT models
├── OperatorBranding.swift   # ATOC operator logos & brand colours
├── SavedTrain.swift         # SwiftData models for saved trains and saved routes
└── Secrets.swift            # Your API keys (git-ignored, see Getting Started)
```

### Key Design Decisions

- **SwiftUI + SwiftData** — fully declarative UI with native persistence
- **Async/await** — all network calls use structured concurrency; no callbacks
- **Two feeds, one train** — Darwin and Realtime Trains share no ID, so a train is matched across them by origin, destination, date, scheduled departure and operator
- **Few requests per search** — Darwin boards are requested with calling points, and Realtime Trains needs two requests whatever the number of trains, which keeps it inside its limit of 10 requests a minute
- **Custom bottom sheet** — `MapBottomSheet` is a hand-crafted draggable overlay with four snap detents (compact → peek → mid → full) and rubber-band overscroll physics, rather than the stock `.sheet()` modifier

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 18.0+ |
| Xcode | 16.0+ |
| Swift | 5.9+ |

---

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/dylanGadsby1/Trainy.git
cd Trainy
```

### 2. API keys

Trainy needs a key for each feed:

1. Sign up at [https://raildata.org.uk](https://raildata.org.uk) and subscribe to **Live Departure Board**
2. Sign up at [https://api-portal.rtt.io](https://api-portal.rtt.io) for a Realtime Trains **refresh token**
3. Copy the template and add both:

```bash
cp Secrets.swift.example Secrets.swift
```

```swift
// Secrets.swift
static let railDataKey = "YOUR_RAIL_DATA_API_KEY"
static let rttRefreshToken = "YOUR_RTT_REFRESH_TOKEN"
```

`Secrets.swift` is git-ignored, so your keys stay out of the repository.

> ⚠️ Realtime Trains does not allow its token to be shipped inside an app that is distributed to other people. That is fine for running Trainy on your own device, but a public release would need to send those requests through your own server.

### 3. Open in Xcode

```bash
open Trainy.xcodeproj
```

Select your target device or simulator and press **Run** (⌘R).

---

## Supported Rail Operators

Trainy ships with branding for the following operators:

| Code | Operator | Code | Operator |
|---|---|---|---|
| VT | Avanti West Coast | GW | Great Western Railway |
| SE | Southeastern | TL | Thameslink |
| GN | Great Northern | LE | Greater Anglia |
| LM | London Northwestern | LO | London Overground |
| ME | Merseyrail | NT | Northern |
| SN | Southern | SR | ScotRail |
| SW | South Western Railway | TP | TransPennine Express |
| XC | CrossCountry | GR | LNER |
| CC | c2c | CH | Chiltern Railways |
| EM | East Midlands Railway | AW | Transport for Wales |
| HX | Heathrow Express | CS | Caledonian Sleeper |
| XR | Elizabeth Line | IL | Island Line |
| GC | Grand Central | HB | Hull Trains |

---

## Roadmap

- [ ] Live push notifications for delays and cancellations
- [ ] Apple Watch companion app
- [x] Widget support (Home Screen / Lock Screen)
- [ ] Social journey sharing with friends
- [ ] Ticket wallet integration
- [ ] iCloud sync across devices

---

## Contributing

Contributions are welcome! Please open an issue to discuss changes before submitting a pull request.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## Acknowledgements

- Live train data provided by [National Rail](https://www.nationalrail.co.uk/) via the Rail Data Marketplace
- Timetable data provided by [Realtime Trains](https://www.realtimetrains.co.uk/)
- Operator logos are trademarks of their respective owners
- Built with ❤️ using SwiftUI, MapKit, and SwiftData
