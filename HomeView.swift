import SwiftUI
import MapKit

// MARK: - Train Status Colors

enum TrainStatus {
    case onTime, delayed, cancelled, arriving

    var label: String {
        switch self {
        case .onTime:   return "ON TIME"
        case .delayed:  return "DELAYED"
        case .cancelled: return "CANCELLED"
        case .arriving: return "ARRIVING"
        }
    }

    var color: Color {
        switch self {
        case .onTime:   return .green
        case .delayed:  return .orange
        case .cancelled: return Color(red: 0.95, green: 0.25, blue: 0.25)
        case .arriving: return Color(red: 0.35, green: 0.75, blue: 1.0)
        }
    }
}


// MARK: - My Train Card

struct MyTrainCard: View {
    let train: RTTAPIService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: operator + status
            HStack {
                Text(train.atocName ?? "Unknown")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    .lineLimit(1)
                Spacer()
                Text(train.trainStatus.label)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(train.trainStatus.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(train.trainStatus.color.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 10)

            // Route
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(train.userSearchOriginCRS ?? (train.originCRS.isEmpty ? "UNK" : train.originCRS))
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Text(train.realtimeDeparture)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(train.userSearchDestinationCRS ?? (train.destinationCRS.isEmpty ? "UNK" : train.destinationCRS))
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Text(train.userSearchDestinationArrivalTime ?? train.scheduledDeparture)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(train.delayMinutes > 0 ? .orange : AdaptiveColor.secondary.resolve(in: colorScheme))
                }
            }
            .padding(.bottom, 12)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AdaptiveColor.track.resolve(in: colorScheme))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [train.trainStatus.color.opacity(0.7), train.trainStatus.color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        // Mocking progress for live departure boards
                        .frame(width: geo.size.width * 0.1, height: 4)

                    Image(systemName: "tram.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(train.trainStatus.color)
                        .clipShape(Circle())
                        .shadow(color: train.trainStatus.color.opacity(0.5), radius: 4)
                        .offset(x: max(0, geo.size.width * 0.1 - 11), y: -15)
                }
            }
            .frame(height: 28)

            // Platform
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "signpost.right.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    Text("Platform \(train.platform)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                }
            }
        }
        .padding(16)
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }
}

// MARK: - Shared Bottom Sheet Container

private enum SheetDetent {
    case compact, peek, mid, full
}

/// A generic draggable bottom sheet that floats above the map with side margins.
struct MapBottomSheet<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    @State private var currentDetent: SheetDetent = .compact
    @State private var dragOffset: CGFloat = 0

    private let sideMargin: CGFloat = 10
    private let cornerRadius: CGFloat = 38

    // Rubber-band resistance factor — smaller = more resistance at extremes
    private let rubberBandFactor: CGFloat = 0.35

    var body: some View {
        GeometryReader { geo in
            let screenH = geo.size.height
            let compactH: CGFloat = screenH * 0.22
            let peekH:    CGFloat = screenH * 0.38
            let midH:     CGFloat = screenH * 0.62
            let fullH:    CGFloat = screenH * 0.90

            let target = detentHeight(currentDetent, compact: compactH, peek: peekH, mid: midH, full: fullH)

            // Apply rubber-band resistance at the extremes
            let rawH = target - dragOffset
            let sheetH: CGFloat = {
                if rawH > fullH {
                    // Over-pulling upward: rubber-band
                    let over = rawH - fullH
                    return fullH + over * rubberBandFactor
                } else if rawH < compactH {
                    // Over-pulling downward: rubber-band
                    let under = compactH - rawH
                    return compactH - under * rubberBandFactor
                }
                return rawH
            }()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    // Content — scrollable only when fully expanded
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            content
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollDisabled(currentDetent != .full)
                }
                .frame(height: max(compactH * 0.4, sheetH))
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.22), radius: 28, y: -8)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.horizontal, sideMargin)
                .padding(.bottom, sideMargin)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in
                            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                                dragOffset = v.translation.height
                            }
                        }
                        .onEnded { v in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.70)) {
                                dragOffset = 0
                                currentDetent = nextDetent(
                                    currentDetent,
                                    translation: v.translation.height,
                                    velocity: v.predictedEndTranslation.height
                                )
                            }
                        }
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func detentHeight(_ d: SheetDetent, compact: CGFloat, peek: CGFloat, mid: CGFloat, full: CGFloat) -> CGFloat {
        switch d {
        case .compact: return compact
        case .peek:    return peek
        case .mid:     return mid
        case .full:    return full
        }
    }

    private func nextDetent(_ current: SheetDetent, translation: CGFloat, velocity: CGFloat) -> SheetDetent {
        // Use predicted end translation for snapping decision
        let gesture = velocity

        // Swiping up (negative translation = growing)
        if gesture < -100 {
            switch current {
            case .compact: return .peek
            case .peek:    return .mid
            case .mid:     return .full
            case .full:    return .full
            }
        }
        // Swiping down
        if gesture > 100 {
            switch current {
            case .compact: return .compact
            case .peek:    return .compact
            case .mid:     return .peek
            case .full:    return .mid
            }
        }
        // Small movement — snap based on drag distance threshold
        if translation < -60 {
            switch current {
            case .compact: return .peek
            case .peek:    return .mid
            case .mid:     return .full
            case .full:    return .full
            }
        }
        if translation > 60 {
            switch current {
            case .compact: return .compact
            case .peek:    return .compact
            case .mid:     return .peek
            case .full:    return .mid
            }
        }
        return current
    }
}

// MARK: - Home Sheet Content (used by ContentView tab)

struct HomeSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingProfile = false

    @Binding var liveServices: [RTTAPIService]
    @State private var isLoading = false

    var body: some View {
        MapBottomSheet {
            homeContent
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        // Header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MY TRAINS")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                    .tracking(1.5)
                Text(liveServices.isEmpty ? "No Trains Added" : "My Departures")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            }
            Spacer()
            HStack(spacing: 10) {

                Button { showingProfile = true } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 38, height: 38)
                            .shadow(color: Color.black.opacity(0.12), radius: 6)
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)

        // Horizontal train cards
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if liveServices.isEmpty {
                    VStack {
                        Text("No trains added yet.")
                            .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(width: 220, height: 148)
                } else {
                    ForEach(liveServices) { train in
                        MyTrainCard(train: train)
                    }
                }

                // "Add" card
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.appBlue.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.appBlue)
                    }
                    Text("Add Train")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appBlue)
                }
                .frame(width: 120, height: 148)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.appBlue.opacity(0.30),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
            }
            .padding(.horizontal, 20)
        }

        // Quick stats
        let activeCount = liveServices.count
        let onTimeCount = liveServices.filter { $0.trainStatus == .onTime }.count

        HStack(spacing: 12) {
            QuickStatTile(icon: "tram.fill",             label: "Departures",  value: "\(activeCount)", color: .appBlue)
            QuickStatTile(icon: "checkmark.circle.fill", label: "On Time",     value: "\(onTimeCount)", color: .green)
            QuickStatTile(icon: "clock.arrow.circlepath", label: "Today",      value: "3", color: Color(red: 0.35, green: 0.75, blue: 1.0))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - HomeView (standalone, for preview / Profile navigation)

struct HomeView: View {
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.8, longitude: -1.6),
            span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 5.5)
        )
    )

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                // Show departure pins for each known station
                ForEach(Array(knownStationCoordinates.keys), id: \.self) { crs in
                    if let coord = knownStationCoordinates[crs] {
                        Marker(crs, systemImage: "tram.fill", coordinate: coord)
                            .tint(.white)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            HomeSheetView(liveServices: .constant([]))
        }
    }
}

// MARK: - Quick Stat Tile

struct QuickStatTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.20), lineWidth: 1)
        )
    }
}

#Preview {
    HomeView()
}
