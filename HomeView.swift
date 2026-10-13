import SwiftUI
import MapKit
import SwiftData

// MARK: - My Train Card

struct MyTrainCard: View {
    let train: DarwinServiceAdapter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: operator logo + status
            HStack {
                OperatorLogoBadge(atocCode: train.atocCode, compact: false)
                if OperatorBrand.from(code: train.atocCode) == nil {
                    Text(train.atocName ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(train.trainStatus)
            }
            .padding(.bottom, 10)

            // Route
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(train.userSearchOriginCRS ?? (train.originCRS.isEmpty ? "UNK" : train.originCRS))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.ink)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(train.scheduledDeparture)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.inkSecondary)
                            .strikethrough(train.departureDelayMinutes > 0)

                        if train.departureDelayMinutes > 0 {
                            Text(train.realtimeDeparture)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.statusDelayed)
                        }
                    }
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(train.userSearchDestinationCRS ?? (train.destinationCRS.isEmpty ? "UNK" : train.destinationCRS))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.ink)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        if train.arrivalDelayMinutes > 0 {
                            Text(train.userSearchDestinationArrivalTime ?? "--:--")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.statusDelayed)
                        }

                        Text(train.userSearchDestinationScheduledArrivalTime ?? train.userSearchDestinationArrivalTime ?? "--:--")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.inkSecondary)
                            .strikethrough(train.arrivalDelayMinutes > 0)
                    }
                }
            }
            .monospacedDigit()
            .padding(.bottom, 12)

            // Progress bar — how far between departure and arrival the train is right now
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                GeometryReader { geo in
                    let travelled = geo.size.width * train.progress(at: timeline.date)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.track)
                            .frame(height: 4)
                        Capsule()
                            .fill(train.trainStatus.color)
                            .frame(width: travelled, height: 4)

                        Image(systemName: "tram.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(train.trainStatus.color, in: Circle())
                            .offset(x: min(max(0, travelled - 11), geo.size.width - 22), y: -15)
                    }
                }
            }
            .frame(height: 28)

            // Platform
            HStack {
                Spacer()
                Label("Platform \(train.platform)", systemImage: "signpost.right.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(16)
        .cardSurface()
        // Codes and struck-through times make little sense read one by one
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(train.spokenSummary)
    }
}

// MARK: - Shared Bottom Sheet Container

enum SheetDetent {
    case compact, mid, full

    var larger: SheetDetent { self == .compact ? .mid : .full }
    var smaller: SheetDetent { self == .full ? .mid : .compact }

    fileprivate var spokenName: String {
        switch self {
        case .compact: return "Small"
        case .mid:     return "Half"
        case .full:    return "Full screen"
        }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A generic draggable bottom sheet that floats above the map with side margins.
struct MapBottomSheet<Peek: View, Content: View>: View {
    let peek: Peek
    let content: Content

    /// - Parameters:
    ///   - peek: What the sheet shows at its smallest height. That height is fitted to it.
    ///   - content: Everything below, reached by pulling the sheet up.
    ///   - publishing: Receives the height of this sheet's peek, for another sheet to borrow.
    ///   - borrowedPeekHeight: Another sheet's peek height. The smallest height is fitted to it
    ///     instead, so the two sheets stand equally far out; the content fills the difference.
    init(
        detent: Binding<SheetDetent>,
        publishing publishedPeekHeight: Binding<CGFloat>? = nil,
        borrowedPeekHeight: CGFloat? = nil,
        @ViewBuilder peek: () -> Peek,
        @ViewBuilder content: () -> Content
    ) {
        self._currentDetent = detent
        self.publishedPeekHeight = publishedPeekHeight
        self.borrowedPeekHeight = borrowedPeekHeight
        self.peek = peek()
        self.content = content()
    }

    @Binding var currentDetent: SheetDetent
    private let publishedPeekHeight: Binding<CGFloat>?
    private let borrowedPeekHeight: CGFloat?
    @State private var dragOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isDraggingSheet: Bool = false
    @State private var sheetDragStartHeight: CGFloat = 0
    /// Height of the peek content, once it has been laid out
    @State private var peekHeight: CGFloat = 0

    private let sideMargin: CGFloat = 10
    private let cornerRadius: CGFloat = 38

    /// The drag handle with its padding
    private let handleHeight: CGFloat = 22
    /// UIKit's tab bar, which floats over the bottom of the sheet
    private let tabBarHeight: CGFloat = 49

    // Rubber-band resistance factor — smaller = more resistance at extremes
    private let rubberBandFactor: CGFloat = 0.35

    private let snapAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.86)

    /// The sheet is laid out edge to edge, so its own safe-area insets read as zero; ask the window instead.
    private var windowInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow?.safeAreaInsets ?? .zero
    }

    var body: some View {
        GeometryReader { geo in
            let screenH = geo.size.height
            let insets = windowInsets
            // What the tab bar covers at the bottom of the sheet
            let coveredH = tabBarHeight + insets.bottom

            // Fitted to the peek content, so none of it is cut off behind the tab bar. A share
            // of the screen until that has been measured, and never more than half of it.
            let borrowed = borrowedPeekHeight ?? 0
            let fittedPeekH = borrowed > 0 ? borrowed : peekHeight
            let compactH: CGFloat = fittedPeekH > 0
                ? min(handleHeight + fittedPeekH + 12 + coveredH, screenH * 0.5)
                : screenH * 0.22
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
            let topInset = insets.top * expansion

            // At its smallest the sheet is the peek alone. The rest fades in as the sheet
            // opens, so it is never seen in pieces around the floating tab bar.
            // A sheet at a borrowed height has room to spare under its peek, which the rest fills.
            let reveal = borrowed > 0 ? 1 : min(max((sheetH - compactH) / 60, 0), 1)

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
                        .fill(Color.inkTertiary.opacity(0.5))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10 + topInset)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle()) // Make it easily draggable
                        .gesture(handleDragGesture)
                        // Dragging is not open to everyone: VoiceOver steps through the heights
                        .accessibilityElement()
                        .accessibilityLabel("Panel height")
                        .accessibilityValue(currentDetent.spokenName)
                        .accessibilityAdjustableAction { direction in
                            withAnimation(snapAnimation) {
                                currentDetent = direction == .increment ? currentDetent.larger : currentDetent.smaller
                            }
                        }

                    // Content — scrollable only when fully expanded
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .top) {
                            GeometryReader { proxy in
                                Color.clear.preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("bottomSheetScroll")).minY)
                            }.frame(height: 0)

                            VStack(alignment: .leading, spacing: 20) {
                                VStack(alignment: .leading, spacing: 20) {
                                    peek
                                }
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    // The first measurement sets the height; later ones (a train
                                    // added, a larger text size) move the sheet to it
                                    publishedPeekHeight?.wrappedValue = height
                                    if peekHeight == 0 {
                                        peekHeight = height
                                    } else {
                                        withAnimation(snapAnimation) { peekHeight = height }
                                    }
                                }

                                content
                                    .opacity(reveal)
                                    .accessibilityHidden(reveal == 0)
                            }
                            // Clear of the tab bar when scrolled to the end
                            .padding(.bottom, coveredH + 16)
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
                        .fill(Color.surface)
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
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTrain: DarwinServiceAdapter?
    @State private var trainToDelete: SavedTrain?
    @State private var showingDeleteConfirmation = false

    // HomeSheetView owns the query so it can delete entries
    @Query(filter: #Predicate<SavedTrain> { $0.isPast == false }) private var mySavedTrains: [SavedTrain]
    private var liveServices: [DarwinServiceAdapter] { mySavedTrains.compactMap { $0.service } }

    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 220

    @Binding var currentDetent: SheetDetent
    /// Height of the title and train cards, which Rail History fits its smallest height to
    @Binding var peekHeight: CGFloat
    /// Opens Add Train
    var onAddTrain: () -> Void

    var body: some View {
        MapBottomSheet(detent: $currentDetent, publishing: $peekHeight) {
            header
            trainCards
        } content: {
            quickStats
        }
        .sheet(item: $selectedTrain) { train in
            // Show the saved train as it is now, not as it was when the sheet opened
            let current = liveServices.first { $0.isSameJourney(as: train) } ?? train
            JourneyDashboardView(journey: current.toTrainJourney(), rawService: current, onRemove: {
                selectedTrain = nil
                if let saved = mySavedTrains.first(where: { $0.service?.isSameJourney(as: train) == true }) {
                    remove(saved)
                }
            })
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Remove Train",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let train = trainToDelete {
                    remove(train)
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

    private func remove(_ train: SavedTrain) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let service = train.service {
            LiveActivityManager.shared.endTracking(for: service)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            modelContext.delete(train)
            try? modelContext.save()
        }
    }

    private var header: some View {
        SheetHeader("My Trains") {
            Button(action: onAddTrain) {
                Label("Add train", systemImage: "plus")
            }
            .buttonStyle(.filledIcon)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var trainCards: some View {
        if liveServices.isEmpty {
            Button(action: onAddTrain) {
                HStack(spacing: 14) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.subtleFill, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your first train")
                            .font(.headline)
                            .foregroundStyle(Color.ink)
                        Text("Follow it live, with its platform and any delay.")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.inkTertiary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .cardSurface()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        } else {
            // Horizontal train cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(mySavedTrains) { savedTrain in
                        if let train = savedTrain.service {
                            Button {
                                selectedTrain = train
                            } label: {
                                MyTrainCard(train: train)
                                    // A lone train has the row to itself
                                    .containerRelativeFrame(.horizontal) { width, _ in
                                        liveServices.count == 1 ? width - 40 : cardWidth
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows the journey")
                            .contextMenu {
                                Button("Remove Train", systemImage: "trash", role: .destructive) {
                                    trainToDelete = savedTrain
                                    showingDeleteConfirmation = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var quickStats: some View {
        let activeCount = liveServices.count
        let onTimeCount = liveServices.filter { $0.trainStatus == .onTime }.count
        let delayedCount = liveServices.filter { $0.trainStatus == .delayed }.count
        let cancelledCount = liveServices.filter { $0.trainStatus == .cancelled }.count

        let onTimeStr = activeCount == 0 ? "-" : "\(onTimeCount)"
        let delayedStr = activeCount == 0 ? "-" : "\(delayedCount)"
        let cancelledStr = activeCount == 0 ? "-" : "\(cancelledCount)"

        return HStack(spacing: 12) {
            QuickStatTile(icon: "checkmark.circle.fill", label: "On time",   value: onTimeStr,    color: .statusOnTime)
            QuickStatTile(icon: "exclamationmark.triangle.fill", label: "Delayed",   value: delayedStr,   color: .statusDelayed)
            QuickStatTile(icon: "xmark.octagon.fill",    label: "Cancelled", value: cancelledStr, color: .statusCancelled)
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

            HomeSheetView(currentDetent: $currentDetent, peekHeight: .constant(0), onAddTrain: {})
        }
    }
}

// MARK: - Quick Stat Tile

struct QuickStatTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == "-" ? "none" : value)")
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [SavedTrain.self, SavedRoute.self], inMemory: true)
}
