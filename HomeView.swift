import SwiftUI
import MapKit

// MARK: - Mock Saved Train Models

struct SavedTrain: Identifiable {
    let id = UUID()
    let originCode: String
    let originName: String
    let destinationCode: String
    let destinationName: String
    let operator_: String
    let departureTime: String
    let arrivalTime: String
    let delayMinutes: Int
    let status: TrainStatus
    let progressFraction: Double
    let platform: Int
}

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

let mockSavedTrains: [SavedTrain] = [
    SavedTrain(
        originCode: "LPY", originName: "Long Preston",
        destinationCode: "EUS", destinationName: "London Euston",
        operator_: "Avanti West Coast",
        departureTime: "11:00", arrivalTime: "13:01",
        delayMinutes: 16, status: .delayed,
        progressFraction: 0.72, platform: 12
    ),
    SavedTrain(
        originCode: "MAN", originName: "Manchester Piccadilly",
        destinationCode: "LDS", destinationName: "Leeds",
        operator_: "Northern Rail",
        departureTime: "14:30", arrivalTime: "15:15",
        delayMinutes: 0, status: .onTime,
        progressFraction: 0.30, platform: 3
    ),
    SavedTrain(
        originCode: "EUS", originName: "London Euston",
        destinationCode: "BHM", destinationName: "Birmingham New St",
        operator_: "Avanti West Coast",
        departureTime: "16:00", arrivalTime: "17:10",
        delayMinutes: 0, status: .arriving,
        progressFraction: 0.95, platform: 7
    ),
]

// MARK: - Train Station Map Annotations

struct TrainStationAnnotation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

let mapAnnotations: [TrainStationAnnotation] = [
    TrainStationAnnotation(name: "London Euston",        coordinate: CLLocationCoordinate2D(latitude: 51.5284, longitude: -0.1331)),
    TrainStationAnnotation(name: "Manchester Piccadilly", coordinate: CLLocationCoordinate2D(latitude: 53.4772, longitude: -2.2309)),
    TrainStationAnnotation(name: "Birmingham New St",     coordinate: CLLocationCoordinate2D(latitude: 52.4778, longitude: -1.8997)),
    TrainStationAnnotation(name: "Leeds",                 coordinate: CLLocationCoordinate2D(latitude: 53.7955, longitude: -1.5491)),
    TrainStationAnnotation(name: "Long Preston",          coordinate: CLLocationCoordinate2D(latitude: 54.0004, longitude: -2.2407)),
]

// MARK: - My Train Card

struct MyTrainCard: View {
    let train: SavedTrain
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: operator + status
            HStack {
                Text(train.operator_)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                    .lineLimit(1)
                Spacer()
                Text(train.status.label)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(train.status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(train.status.color.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 10)

            // Route
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(train.originCode)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Text(train.departureTime)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(train.destinationCode)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Text(train.arrivalTime)
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
                                colors: [train.status.color.opacity(0.7), train.status.color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * train.progressFraction, height: 4)

                    Image(systemName: "tram.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(train.status.color)
                        .clipShape(Circle())
                        .shadow(color: train.status.color.opacity(0.5), radius: 4)
                        .offset(x: max(0, geo.size.width * train.progressFraction - 11), y: -15)
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
    case peek, mid, full
}

/// A generic draggable bottom sheet that floats above the map with side margins.
struct MapBottomSheet<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    @State private var currentDetent: SheetDetent = .peek
    @State private var dragOffset: CGFloat = 0

    private let sideMargin: CGFloat = 10
    private let cornerRadius: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let screenH = geo.size.height
            let peekH:   CGFloat = screenH * 0.48
            let midH:    CGFloat = screenH * 0.72
            let fullH:   CGFloat = screenH * 0.92

            let target = detentHeight(currentDetent, peek: peekH, mid: midH, full: fullH)
            let sheetH = min(fullH, max(peekH, target - dragOffset))

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.20))
                        .frame(width: 40, height: 5)
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
                .frame(height: sheetH)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: Color.black.opacity(0.20), radius: 24, y: -6)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.horizontal, sideMargin)
                .gesture(
                    DragGesture()
                        .onChanged { v in dragOffset = v.translation.height }
                        .onEnded { v in
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                                dragOffset = 0
                                currentDetent = nextDetent(currentDetent, velocity: v.predictedEndTranslation.height)
                            }
                        }
                )
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: dragOffset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func detentHeight(_ d: SheetDetent, peek: CGFloat, mid: CGFloat, full: CGFloat) -> CGFloat {
        switch d {
        case .peek: return peek
        case .mid:  return mid
        case .full: return full
        }
    }

    private func nextDetent(_ current: SheetDetent, velocity: CGFloat) -> SheetDetent {
        if velocity < -200 {
            switch current { case .peek: return .mid; case .mid: return .full; case .full: return .full }
        }
        if velocity > 200 {
            switch current { case .peek: return .peek; case .mid: return .peek; case .full: return .mid }
        }
        return current
    }
}

// MARK: - Home Sheet Content (used by ContentView tab)

struct HomeSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingProfile = false

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
                Text("Active journeys")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            }
            Spacer()
            HStack(spacing: 10) {
                Button(action: {}) {
                    Text("See all")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.appBlue)
                }
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
                ForEach(mockSavedTrains) { train in
                    MyTrainCard(train: train)
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
        HStack(spacing: 12) {
            QuickStatTile(icon: "tram.fill",             label: "Active",  value: "1", color: .appBlue)
            QuickStatTile(icon: "checkmark.circle.fill", label: "On Time", value: "2", color: .green)
            QuickStatTile(icon: "clock.arrow.circlepath", label: "Today",  value: "3", color: Color(red: 0.35, green: 0.75, blue: 1.0))
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
                ForEach(mapAnnotations) { annotation in
                    Annotation(annotation.name, coordinate: annotation.coordinate) {
                        ZStack {
                            Circle()
                                .fill(Color.appBlue)
                                .frame(width: 28, height: 28)
                                .shadow(color: Color.appBlue.opacity(0.5), radius: 6)
                            Image(systemName: "tram.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            HomeSheetView()
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
