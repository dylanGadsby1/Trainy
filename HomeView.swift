import SwiftUI
import SwiftUI
import MapKit
import SwiftData

// MARK: - My Train Card

struct MyTrainCard: View {
    let train: DarwinServiceAdapter
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: operator logo + status
            HStack {
                OperatorLogoBadge(atocCode: train.atocCode, compact: false)
                if OperatorBrand.from(code: train.atocCode) == nil {
                    Text(train.atocName ?? "Unknown")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                        .lineLimit(1)
                }
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
                            .foregroundColor(train.departureDelayMinutes > 0 ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.secondary.resolve(in: colorScheme))
                            .strikethrough(train.departureDelayMinutes > 0)

                        if train.departureDelayMinutes > 0 {
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
                        if train.arrivalDelayMinutes > 0 {
                            Text(train.userSearchDestinationArrivalTime ?? "--:--")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.orange)
                        }

                        Text(train.userSearchDestinationScheduledArrivalTime ?? train.userSearchDestinationArrivalTime ?? "--:--")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(train.arrivalDelayMinutes > 0 ? AdaptiveColor.tertiary.resolve(in: colorScheme) : AdaptiveColor.secondary.resolve(in: colorScheme))
                            .strikethrough(train.arrivalDelayMinutes > 0)
                    }
                }
            }
            .padding(.bottom, 12)

            // Progress bar — how far between departure and arrival the train is right now
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                GeometryReader { geo in
                    let travelled = geo.size.width * train.progress(at: timeline.date)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdaptiveColor.track.resolve(in: colorScheme))
                            .frame(height: 4)
                        Capsule()
                            .fill(train.trainStatus.color)
                            .frame(width: travelled, height: 4)

                        Image(systemName: "tram.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(train.trainStatus.color)
                            .clipShape(Circle())
                            .offset(x: min(max(0, travelled - 11), geo.size.width - 22), y: -15)
                    }
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
    case compact, mid, full
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

    private let snapAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.86)

    /// The sheet is laid out edge to edge, so its own safe-area insets read as zero; ask the window instead.
    private var statusBarInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let screenH = geo.size.height
            let compactH: CGFloat = screenH * 0.22
            let midH:     CGFloat = screenH * 0.62
            let fullH:    CGFloat = screenH

            let target = detentHeight(currentDetent, compact: compactH, mid: midH, full: fullH)

            // Apply rubber-band resistance at the extremes
            let rawH = target - dragOffset
            let sheetH: CGFloat = {
                if rawH > fullH {
                    // Already covering the screen: nowhere further to go
                    return fullH
                } else if rawH < compactH {
                    // Over-pulling downward: rubber-band
                    let under = compactH - rawH
                    return compactH - under * rubberBandFactor
                }
                return rawH
            }()

            // 0 at the medium detent, 1 when covering the screen. Past medium the card sheds its
            // side margins and rounded corners and grows under the status bar.
            let expansion = min(max((sheetH - midH) / (fullH - midH), 0), 1)
            let margin = sideMargin * (1 - expansion)
            let radius = cornerRadius * (1 - expansion)
            let topInset = statusBarInset * expansion

            let detents: [(SheetDetent, CGFloat)] = [(.compact, compactH), (.mid, midH), (.full, fullH)]

            // The sheet tracks the finger 1:1 while dragging (no animation, so no lag);
            // only the release is animated, from wherever the finger left it.
            let settle: (CGFloat, CGFloat) -> Void = { translation, predicted in
                let next = nextDetent(from: target, translation: translation, predicted: predicted, detents: detents)
                withAnimation(snapAnimation) {
                    dragOffset = 0
                    currentDetent = next
                }
            }

            let handleDragGesture = DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { v in
                    dragOffset = v.translation.height
                }
                .onEnded { v in
                    settle(v.translation.height, v.predictedEndTranslation.height)
                }

            let sheetDragGesture = DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { v in
                    guard currentDetent == .full else { return }
                    if !isDraggingSheet {
                        // Only take over from the scroll view once it is at its top and being pulled down
                        guard scrollOffset >= -1 && v.translation.height > 0 else { return }
                        isDraggingSheet = true
                        sheetDragStartHeight = v.translation.height
                    }
                    dragOffset = max(0, v.translation.height - sheetDragStartHeight)
                }
                .onEnded { v in
                    guard isDraggingSheet else { return }
                    settle(
                        max(0, v.translation.height - sheetDragStartHeight),
                        v.predictedEndTranslation.height - sheetDragStartHeight
                    )
                    isDraggingSheet = false
                    sheetDragStartHeight = 0
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10 + topInset)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
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
                    // Freeze the list while the sheet itself is being pulled down, so the two don't move at once
                    .scrollDisabled(currentDetent != .full || isDraggingSheet)
                }
                .frame(height: max(compactH * 0.4, sheetH))
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: radius, style: .continuous)
                        .fill(Color(red: 1, green: 1, blue: 1))
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: radius, style: .continuous))
                .padding(.horizontal, margin)
                .gesture(handleDragGesture, including: currentDetent == .full ? .subviews : .all)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private func detentHeight(_ d: SheetDetent, compact: CGFloat, mid: CGFloat, full: CGFloat) -> CGFloat {
        switch d {
        case .compact: return compact
        case .mid:     return mid
        case .full:    return full
        }
    }

    /// Snaps to the detent nearest to where the sheet would coast to, so a long drag or a
    /// flick can cross several detents, and a short deliberate drag still moves one step.
    private func nextDetent(from height: CGFloat, translation: CGFloat, predicted: CGFloat, detents: [(SheetDetent, CGFloat)]) -> SheetDetent {
        let released = height - translation
        let projected = height - predicted
        let nearest = { (h: CGFloat) in detents.min { abs($0.1 - h) < abs($1.1 - h) }!.0 }

        let byPosition = nearest(projected)
        if byPosition != currentDetent { return byPosition }

        // Didn't coast far enough to reach another detent: a clear flick still steps one along
        let flick = predicted - translation
        guard abs(flick) > 120, let i = detents.firstIndex(where: { $0.0 == currentDetent }) else { return nearest(released) }
        let step = flick < 0 ? i + 1 : i - 1
        return detents[min(max(step, 0), detents.count - 1)].0
    }
}

// MARK: - Home Sheet Content (used by ContentView tab)

struct HomeSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTrain: DarwinServiceAdapter?
    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false

    // HomeSheetView owns the query so it can delete entries
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == false }) private var mySavedTrains: [SavedTrain]
    private var liveServices: [DarwinServiceAdapter] { mySavedTrains.compactMap { $0.service } }

    @Binding var currentDetent: SheetDetent
    @Binding var selectedTab: Int

    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            homeContent
        }
        .sheet(item: $selectedTrain) { train in
            // Show the saved train as it is now, not as it was when the sheet opened
            let current = liveServices.first { $0.isSameJourney(as: train) } ?? train
            JourneyDashboardView(journey: current.toTrainJourney(), rawService: current)
        }
        .confirmationDialog(
            "Remove Train",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                if let train = trainToDelete {
                    if let service = train.service {
                        LiveActivityManager.shared.endTracking(for: service)
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        modelContext.delete(train)
                        try? modelContext.save()
                    }
                }
                trainToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                trainToDelete = nil
            }
        } message: {
            Text("Are you sure you want to remove this train from My Trains?")
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
                ForEach(mySavedTrains) { savedTrain in
                    if let train = savedTrain.service {
                        ZStack(alignment: .topTrailing) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                selectedTrain = train
                            } label: {
                                MyTrainCard(train: train)
                                    .frame(width: 220)
                            }
                            .buttonStyle(.plain)

                            // Delete button
                            Button {
                                trainToDelete = savedTrain
                                showingDeleteConfirmation = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.regularMaterial)
                                        .frame(width: 24, height: 24)
                                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                        }
                    }
                }

                // Add card — always last, to the right of trains
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
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
            .padding(.vertical, 8) // Give the X button room to not clip
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

            HomeSheetView(currentDetent: $currentDetent, selectedTab: $selectedTab)
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
