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
| 🚂 **Operator Branding** | Logos and brand colours for 26 UK rail operators |
| 💸 **Delay Repay** | Deep links to every operator's Delay Repay compensation page |
| 📍 **Live Activities** | Follow a train from the Lock Screen and Dynamic Island |
| 🔔 **Notifications** | Delay, cancellation and platform alerts for saved trains, and reminders to claim Delay Repay |
| 🚏 **Calling Points** | Every stop on the journey with live times, the route on the map and the train's estimated position |
| ⭐ **Saved Routes** | Star a route to search it in one tap, with a shortcut for the return journey |
| 📤 **Share Journey** | Send someone your train and when it is now due in |
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
│
├── HomeView.swift           # Map view + draggable bottom sheet
├── AddTrainView.swift       # Station picker + live departure search
├── RailHistoryView.swift    # Archived past journeys
├── ProfileView.swift        # Travel stats, notification settings, privacy & about
│
├── DarwinAPI.swift          # Darwin API client, response models & the app's train model
├── TrainSearch.swift        # One search across Darwin and Realtime Trains, merged
├── TrainSync.swift          # Refreshes saved trains and hands them from the timetable to Darwin
├── TrainAlerts.swift        # Delay, platform and Delay Repay notifications
├── TrainyServer.swift       # Optional: push registration and the feeds through server/
├── LiveActivityManager.swift # Starts and updates the Live Activity
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
- [ ] Widget support (Today view / Lock Screen)
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
