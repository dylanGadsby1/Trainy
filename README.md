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

Data is powered by the **[Realtime Trains (RTT)](https://www.realtimetrains.co.uk/)** Next Generation API, giving you accurate live running information across the entire National Rail network.

---

## Features

| Feature | Description |
|---|---|
| 🗺️ **Map-first Home** | Interactive UK map with a draggable bottom sheet showing your saved trains |
| 🚆 **My Trains** | Pin upcoming departures and see live status cards with operator branding |
| 🔍 **Add Journey** | Search any origin → destination pair with date/time picker and live departure feed |
| ⏱️ **Live Status** | On time / Delayed / Cancelled / Arriving badges updated via the RTT API |
| 📊 **Journey Dashboard** | Per-train detail view with scheduled vs realtime times and platform info |
| 📜 **Rail History** | Automatic archiving of completed and cancelled journeys |
| 🚂 **Operator Branding** | Logos and brand colours for 26 UK rail operators |
| 💸 **Delay Repay** | Deep links to every operator's Delay Repay compensation page |
| 🔄 **Multi-leg Routing** | Support for journeys that require connections and interchanges |
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
├── ProfileView.swift        # User profile & stats
│
├── RTTService.swift         # Realtime Trains API client (async/await)
├── RTTModels.swift          # Codable response models
├── OperatorBranding.swift   # ATOC operator logos & brand colours
├── SavedTrain.swift         # SwiftData model for persisted trains
└── ukStations_generated.swift  # Complete UK station list (CRS codes)
```

### Key Design Decisions

- **SwiftUI + SwiftData** — fully declarative UI with native persistence
- **Async/await** — all network calls use structured concurrency; no callbacks
- **Token auth** — RTT Next Generation API uses a JWT refresh/access token flow cached in memory
- **Custom bottom sheet** — `MapBottomSheet` is a hand-crafted draggable overlay with four snap detents (compact → peek → mid → full) and rubber-band overscroll physics, rather than the stock `.sheet()` modifier

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 17.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ |

---

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/dylanGadsby1/Trainy.git
cd Trainy
```

### 2. RTT API credentials

Trainy uses the **Realtime Trains Next Generation API**. You'll need your own credentials:

1. Sign up at [https://api-portal.rtt.io](https://api-portal.rtt.io)
2. Obtain a **refresh token** (JWT)
3. Open `RTTService.swift` and replace the placeholder token:

```swift
// RTTService.swift
private let refreshToken = "YOUR_RTT_REFRESH_TOKEN_HERE"
```

> ⚠️ **Never commit your refresh token to a public repository.** Consider loading it from a `.xcconfig` file or environment variable for production use.

### 3. Open in Xcode

```bash
open Trainy/Trainy.xcodeproj
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

- Live train data provided by [Realtime Trains](https://www.realtimetrains.co.uk/)
- Operator logos are trademarks of their respective owners
- Built with ❤️ using SwiftUI, MapKit, and SwiftData
