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
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(train.scheduledDeparture)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(train.delayMinutes > 0 ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.secondary.resolve(in: colorScheme))
                            .strikethrough(train.delayMinutes > 0)
                        
                        if train.delayMinutes > 0 {
                            Text(train.realtimeDeparture)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(train.userSearchDestinationCRS ?? (train.destinationCRS.isEmpty ? "UNK" : train.destinationCRS))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        if train.delayMinutes > 0 {
                            Text(train.userSearchDestinationArrivalTime ?? train.realtimeDeparture)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        
                        Text(train.userSearchDestinationScheduledArrivalTime ?? train.userSearchDestinationArrivalTime ?? train.scheduledDeparture)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(train.delayMinutes > 0 ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.secondary.resolve(in: colorScheme))
                            .strikethrough(train.delayMinutes > 0)
                    }
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
                        .fill(train.trainStatus.color)
                        // Mocking progress for live departure boards
                        .frame(width: geo.size.width * 0.1, height: 4)

                    Image(systemName: "tram.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(train.trainStatus.color)
                        .clipShape(Circle())
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
        .background(Color(red: 1, green: 1, blue: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.appleBlack.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Shared Bottom Sheet Container

enum SheetDetent {
    case compact, peek, mid, full
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A generic draggable bottom sheet that floats above the map with side margins.
struct MapBottomSheet<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    init(detent: Binding<SheetDetent>, @ViewBuilder content: () -> Content) { 
        self._currentDetent = detent
        self.content = content() 
    }

    @Binding var currentDetent: SheetDetent
    @State private var dragOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isDraggingSheet: Bool = false
    @State private var sheetDragStartHeight: CGFloat = 0

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

            let handleDragGesture = DragGesture(minimumDistance: 4)
                .onChanged { v in
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.65)) {
                        dragOffset = v.translation.height
                    }
                }
                .onEnded { v in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                        dragOffset = 0
                        currentDetent = nextDetent(
                            currentDetent,
                            translation: v.translation.height,
                            velocity: v.predictedEndTranslation.height
                        )
                    }
                }

            let sheetDragGesture = DragGesture(minimumDistance: 4)
                .onChanged { v in
                    guard currentDetent == .full else { return }
                    if scrollOffset >= -1 && v.translation.height > 0 {
                        if !isDraggingSheet {
                            isDraggingSheet = true
                            sheetDragStartHeight = v.translation.height
                        }
                        let effectiveTranslation = v.translation.height - sheetDragStartHeight
                        if effectiveTranslation > 0 {
                            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.65)) {
                                dragOffset = effectiveTranslation
                            }
                        }
                    } else if isDraggingSheet {
                        let effectiveTranslation = v.translation.height - sheetDragStartHeight
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.65)) {
                            dragOffset = max(0, effectiveTranslation)
                        }
                    }
                }
                .onEnded { v in
                    guard currentDetent == .full else { return }
                    if isDraggingSheet {
                        let effectiveTranslation = v.translation.height - sheetDragStartHeight
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                            dragOffset = 0
                            currentDetent = nextDetent(
                                currentDetent,
                                translation: effectiveTranslation,
                                velocity: v.predictedEndTranslation.height
                            )
                        }
                    }
                    isDraggingSheet = false
                    sheetDragStartHeight = 0
                }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .contentShape(Rectangle()) // Make it easily draggable
                        .gesture(handleDragGesture)

                    // Content — scrollable only when fully expanded
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .top) {
                            GeometryReader { proxy in
                                Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("bottomSheetScroll")).minY)
                            }.frame(height: 0)
                            
                            VStack(alignment: .leading, spacing: 20) {
                                content
                            }
                            .padding(.bottom, 40)
                        }
                    }
                    .coordinateSpace(name: "bottomSheetScroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { value in
                        scrollOffset = value
                    }
                    .simultaneousGesture(sheetDragGesture, including: currentDetent == .full ? .all : .none)
                    .scrollDisabled(currentDetent != .full)
                }
                .frame(height: max(compactH * 0.4, sheetH))
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 1, green: 1, blue: 1))
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: cornerRadius, style: .continuous))
                .padding(.horizontal, sideMargin)
                .gesture(handleDragGesture, including: currentDetent == .full ? .subviews : .all)
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

    @State private var selectedTrain: RTTAPIService?

    var liveServices: [RTTAPIService]
    @Binding var currentDetent: SheetDetent
    @Binding var selectedTab: Int

    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            homeContent
        }
        .sheet(item: $selectedTrain) { train in
            JourneyDashboardView(journey: train.toTrainJourney())
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
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            }
            Spacer()
            HStack(spacing: 10) {
                // Profile button moved to top left of Map
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)

        // Horizontal train cards
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                // Live train cards
                ForEach(liveServices) { train in
                    Button {
                        selectedTrain = train
                    } label: {
                        MyTrainCard(train: train)
                            .frame(width: 220)
                    }
                    .buttonStyle(.plain)
                }

                // Add card — always last, to the right of trains
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                        selectedTab = 2
                        currentDetent = .full
                    }
                } label: {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.appleBlack.opacity(0.08))
                                .frame(width: 48, height: 48)
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Color.appleBlack)
                        }
                        Text("Add Train")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.appleBlack)
                    }
                    .frame(width: 120, height: 148)
                    .background(Color(red: 1, green: 1, blue: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.appleBlack.opacity(0.18),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }

        // Quick stats
        let activeCount = liveServices.count
        let onTimeCount = liveServices.filter { $0.trainStatus == .onTime }.count
        let delayedCount = liveServices.filter { $0.trainStatus == .delayed }.count
        let cancelledCount = liveServices.filter { $0.trainStatus == .cancelled }.count
        
        let onTimeStr = activeCount == 0 ? "-" : "\(onTimeCount)"
        let delayedStr = activeCount == 0 ? "-" : "\(delayedCount)"
        let cancelledStr = activeCount == 0 ? "-" : "\(cancelledCount)"

        HStack(spacing: 12) {
            QuickStatTile(icon: "checkmark.circle.fill", label: "On Time",   value: onTimeStr,    color: .green)
            QuickStatTile(icon: "exclamationmark.triangle.fill", label: "Delayed",   value: delayedStr,   color: .orange)
            QuickStatTile(icon: "xmark.octagon.fill",    label: "Cancelled", value: cancelledStr, color: Color(red: 0.95, green: 0.25, blue: 0.25))
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
    @State private var currentDetent: SheetDetent = .compact
    @State private var selectedTab: Int = 0

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

            HomeSheetView(liveServices: [], currentDetent: $currentDetent, selectedTab: $selectedTab)
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
                .font(.system(size: 28, weight: .black))
                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(red: 1, green: 1, blue: 1))
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
