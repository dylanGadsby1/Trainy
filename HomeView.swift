import SwiftUI
import MapKit
import SwiftData

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

enum SheetDetent: CaseIterable {
    case compact, peek, mid, full

    /// Share of the available height the sheet occupies when resting here.
    var fraction: CGFloat {
        switch self {
        case .compact: return 0.22
        case .peek:    return 0.38
        case .mid:     return 0.62
        case .full:    return 0.90
        }
    }
}

/// A generic draggable bottom sheet that floats above the map with side margins.
///
/// Motion model:
/// • The sheet is laid out once at its tallest size and slid with `offset`, so
///   dragging never relayouts the content.
/// • While a finger is down the sheet tracks it 1:1 — no animation lag.
/// • Grabbing the sheet mid-flight catches it exactly where it is on screen.
/// • On release we project where the fling would coast to, snap to the nearest
///   detent and hand the finger's velocity to a lively spring, so the motion
///   carries straight through and lands with a little bounce.
struct MapBottomSheet<Content: View>: View {
    let content: Content
    init(detent: Binding<SheetDetent>, @ViewBuilder content: () -> Content) {
        self._currentDetent = detent
        self.content = content()
    }

    @Binding var currentDetent: SheetDetent

    /// Height the sheet rests at, or is springing towards. nil until first layout.
    @State private var restHeight: CGFloat?
    /// Finger travel since the sheet was grabbed (+ = downwards).
    @State private var dragTranslation: CGFloat = 0
    /// Gesture translation at the moment the sheet was grabbed; nil when not dragging.
    @State private var dragOrigin: CGFloat?
    /// Gesture translation at which the list handed a pull-down over to the sheet.
    @State private var handoffStart: CGFloat?
    @State private var isScrolledToTop = true
    @State private var availableHeight: CGFloat = 0
    @State private var inFlight: SettleSpring?

    // Reset by SwiftUI when a gesture ends *or* is cancelled, so we never get stuck mid-drag.
    @GestureState private var isHandleGestureActive = false
    @GestureState private var isScrollGestureActive = false

    private let sideMargin: CGFloat = 10
    private let cornerRadius: CGFloat = 38
    /// Sheet that hangs below the screen edge so overshoot never reveals a gap.
    private let bottomOverhang: CGFloat = 160
    /// Snappy with a small overshoot — the "ping" when the sheet lands.
    private let spring = Spring(duration: 0.42, bounce: 0.24)
    /// How far ahead (in seconds of coasting) a fling is projected when picking a detent.
    private let flingProjection: CGFloat = 0.2
    private let maxFlingVelocity: CGFloat = 2400

    private struct SettleSpring {
        let from: CGFloat
        let to: CGFloat
        let velocity: CGFloat // points/s, + = growing
        let start: Date
    }

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.height
            let sheetShape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: cornerRadius, style: .continuous)

            VStack(spacing: 0) {
                grabber
                    .gesture(handleDrag)
                    .onTapGesture { cycleDetent() }

                // Content — scrollable only when fully expanded
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding(.bottom, 40 + bottomOverhang)
                    .visualEffect { effect, proxy in
                        // Pulling down at the top of the list moves the sheet, so cancel
                        // the scroll view's own bounce there to keep content pinned to it.
                        effect.offset(x: 0, y: -max(0, proxy.frame(in: .scrollView).minY))
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { scroll in
                    scroll.contentOffset.y + scroll.contentInsets.top <= 0.5
                } action: { _, atTop in
                    isScrolledToTop = atTop
                }
                .scrollDisabled(currentDetent != .full)
                .simultaneousGesture(scrollPullDrag, including: currentDetent == .full ? .all : .none)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height(of: .full, in: available) + bottomOverhang, alignment: .top)
            .background(sheetShape.fill(Color(red: 1, green: 1, blue: 1)))
            .clipShape(sheetShape)
            .padding(.horizontal, sideMargin)
            .gesture(handleDrag, including: currentDetent == .full ? .subviews : .all)
            .offset(y: available - visibleHeight(in: available))
            .onChange(of: available, initial: true) { _, newHeight in
                availableHeight = newHeight
                if dragOrigin == nil {
                    restHeight = height(of: currentDetent, in: newHeight)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: currentDetent) { _, newDetent in
            // Detent changed from outside (another tab, a button) — glide there.
            guard dragOrigin == nil, let current = restHeight else { return }
            let target = height(of: newDetent, in: availableHeight)
            guard abs(target - current) > 0.5 else { return }
            settle(from: current, to: target, velocity: 0)
        }
        .onChange(of: isHandleGestureActive) { _, active in
            if !active { finishCancelledDrag() }
        }
        .onChange(of: isScrollGestureActive) { _, active in
            if !active { finishCancelledDrag() }
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle()) // Whole top strip is grabbable
            .accessibilityElement()
            .accessibilityLabel("Resize sheet")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: Gestures

    /// Drags the sheet from the grabber, or from anywhere when not fully expanded.
    private var handleDrag: some Gesture {
        // Global space: the sheet moves under the finger, so local coordinates would feed back.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($isHandleGestureActive) { _, active, _ in active = true }
            .onChanged { v in
                track(v.translation.height)
            }
            .onEnded { v in
                release(velocity: v.velocity.height)
            }
    }

    /// When fully expanded, a pull-down that starts with the list at its top drags the sheet.
    private var scrollPullDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($isScrollGestureActive) { _, active, _ in active = true }
            .onChanged { v in
                guard currentDetent == .full else { return }
                if handoffStart == nil {
                    guard isScrolledToTop, v.translation.height > 0 else { return }
                    handoffStart = v.translation.height
                }
                // Pushing back up past the hand-off point returns control to the list.
                track(max(0, v.translation.height - (handoffStart ?? 0)))
            }
            .onEnded { v in
                guard handoffStart != nil else { return }
                handoffStart = nil
                release(velocity: v.velocity.height)
            }
    }

    // MARK: Motion

    private func track(_ translation: CGFloat) {
        if dragOrigin == nil {
            // Catch the sheet exactly where it is on screen, even mid-spring.
            // Setting it without animation also stops the spring in flight.
            let caught = presentedHeight()
            var grab = Transaction(animation: nil)
            grab.disablesAnimations = true
            withTransaction(grab) {
                restHeight = caught
                dragTranslation = 0
                dragOrigin = translation
                inFlight = nil
            }
            return
        }
        dragTranslation = translation - (dragOrigin ?? 0)
    }

    private func release(velocity fingerVelocity: CGFloat) {
        guard dragOrigin != nil else { return }
        let from = visibleHeight(in: availableHeight)

        // Finger moving down shrinks the sheet; dampen it while rubber-banding.
        var velocity = -fingerVelocity
        if from > height(of: .full, in: availableHeight) || from < height(of: .compact, in: availableHeight) {
            velocity *= 0.35
        }
        velocity = min(max(velocity, -maxFlingVelocity), maxFlingVelocity)

        let target = targetDetent(from: from, velocity: velocity)
        if target != currentDetent {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        dragOrigin = nil
        settle(from: from, to: height(of: target, in: availableHeight), velocity: velocity)
        currentDetent = target
    }

    /// A drag that was cancelled (never got `onEnded`) still has to land somewhere.
    private func finishCancelledDrag() {
        guard !isHandleGestureActive, !isScrollGestureActive else { return }
        handoffStart = nil
        if dragOrigin != nil { release(velocity: 0) }
    }

    private func settle(from: CGFloat, to: CGFloat, velocity: CGFloat) {
        let distance = to - from
        // SwiftUI wants velocity relative to the distance being animated.
        let relativeVelocity = abs(distance) > 1 ? velocity / distance : 0
        inFlight = SettleSpring(from: from, to: to, velocity: relativeVelocity * distance, start: Date())
        withAnimation(.interpolatingSpring(spring, initialVelocity: Double(relativeVelocity))) {
            restHeight = to
            dragTranslation = 0
        }
    }

    private func targetDetent(from current: CGFloat, velocity: CGFloat) -> SheetDetent {
        let detents = SheetDetent.allCases
        let projected = current + velocity * flingProjection
        var target = detents.min {
            abs(height(of: $0, in: availableHeight) - projected) < abs(height(of: $1, in: availableHeight) - projected)
        } ?? currentDetent

        // A deliberate flick never snaps back against its own direction.
        if velocity > 300, height(of: target, in: availableHeight) < current {
            target = detents.first { height(of: $0, in: availableHeight) > current } ?? .full
        } else if velocity < -300, height(of: target, in: availableHeight) > current {
            target = detents.last { height(of: $0, in: availableHeight) < current } ?? .compact
        }
        return target
    }

    private func cycleDetent() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch currentDetent {
        case .compact: currentDetent = .peek
        case .peek:    currentDetent = .mid
        case .mid:     currentDetent = .full
        case .full:    currentDetent = .peek
        }
    }

    // MARK: Geometry

    private func height(of detent: SheetDetent, in available: CGFloat) -> CGFloat {
        available * detent.fraction
    }

    /// The height the sheet is laid out at for the current state (animations aside).
    private func visibleHeight(in available: CGFloat) -> CGFloat {
        let base = restHeight ?? height(of: currentDetent, in: available)
        return rubberBand(base - dragTranslation,
                          lower: height(of: .compact, in: available),
                          upper: height(of: .full, in: available))
    }

    /// Where the sheet actually is on screen right now — including a spring in flight.
    private func presentedHeight() -> CGFloat {
        if let s = inFlight {
            let elapsed = Date().timeIntervalSince(s.start)
            if elapsed < 1.5 {
                return CGFloat(spring.value(fromValue: Double(s.from),
                                            toValue: Double(s.to),
                                            initialVelocity: Double(s.velocity),
                                            time: elapsed))
            }
        }
        return visibleHeight(in: availableHeight)
    }

    /// UIScrollView-style resistance past the ends: gives easily, then stiffens.
    private func rubberBand(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        func resist(_ overshoot: CGFloat) -> CGFloat {
            let limit: CGFloat = 120
            return (1 - 1 / (overshoot * 0.55 / limit + 1)) * limit
        }
        if value > upper { return upper + resist(value - upper) }
        if value < lower { return lower - resist(lower - value) }
        return value
    }
}

// MARK: - Home Sheet Content (used by ContentView tab)

struct HomeSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTrain: RTTAPIService?
    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false

    // HomeSheetView owns the query so it can delete entries
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == false }) private var mySavedTrains: [SavedTrain]
    private var liveServices: [RTTAPIService] { mySavedTrains.compactMap { $0.service } }

    @Binding var currentDetent: SheetDetent
    @Binding var selectedTab: Int

    var body: some View {
        MapBottomSheet(detent: $currentDetent) {
            homeContent
        }
        .sheet(item: $selectedTrain) { train in
            JourneyDashboardView(journey: train.toTrainJourney(), rawService: train)
        }
        .confirmationDialog(
            "Remove Train",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                if let train = trainToDelete {
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
    @State private var currentDetent: SheetDetent = .peek
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
