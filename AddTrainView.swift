import SwiftUI

// MARK: - Add Train View

struct AddTrainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var origin = ""
    @State private var destination = ""
    @FocusState private var originFocused: Bool

    private let quickRoutes: [(String, String, String, String)] = [
        ("LPY", "Long Preston", "EUS", "London Euston"),
        ("MAN", "Manchester Piccadilly", "LDS", "Leeds"),
        ("EUS", "London Euston", "BHM", "Birmingham New St"),
        ("LDS", "Leeds", "MAN", "Manchester Piccadilly"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        AdaptiveColor.bgTop.resolve(in: colorScheme),
                        AdaptiveColor.bgBottom.resolve(in: colorScheme)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Route input card
                        VStack(spacing: 0) {
                            // From
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.20))
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 10, height: 10)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("FROM")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                        .tracking(1)
                                    TextField("Origin station", text: $origin)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                        .focused($originFocused)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            // Divider with swap button
                            HStack {
                                Rectangle()
                                    .fill(AdaptiveColor.divider.resolve(in: colorScheme))
                                    .frame(height: 1)
                                    .padding(.leading, 52)
                                Button {
                                    let temp = origin
                                    origin = destination
                                    destination = temp
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 32, height: 32)
                                            .shadow(color: Color.black.opacity(0.1), radius: 4)
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.appBlue)
                                    }
                                }
                                .padding(.trailing, 16)
                            }

                            // To
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.appBlue.opacity(0.20))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "mappin.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.appBlue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TO")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                        .tracking(1)
                                    TextField("Destination station", text: $destination)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
                        )

                        // Search button
                        Button {
                            // Future: navigate to train list
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Search Trains")
                                    .font(.system(size: 16, weight: .black))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color.appBlue, Color.appBlueBright],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.appBlue.opacity(0.4), radius: 12, y: 4)
                        }

                        // Quick routes
                        VStack(alignment: .leading, spacing: 10) {
                            Text("QUICK ROUTES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                .tracking(1.2)
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(quickRoutes.enumerated()), id: \.offset) { index, route in
                                    Button {
                                        origin = route.1
                                        destination = route.3
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.appBlue.opacity(0.12))
                                                    .frame(width: 36, height: 36)
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(.appBlue)
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 6) {
                                                    Text(route.0)
                                                        .font(.system(size: 14, weight: .black, design: .monospaced))
                                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                                    Image(systemName: "arrow.right")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                                                    Text(route.2)
                                                        .font(.system(size: 14, weight: .black, design: .monospaced))
                                                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                                }
                                                Text("\(route.1) → \(route.3)")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(Color.appBlue.opacity(0.6))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }

                                    if index < quickRoutes.count - 1 {
                                        Divider()
                                            .padding(.leading, 52)
                                            .background(AdaptiveColor.divider.resolve(in: colorScheme))
                                    }
                                }
                            }
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
                            )
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add Train")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appBlue)
                }
            }
        }
    }
}

#Preview {
    AddTrainView()
}
