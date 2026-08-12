import SwiftUI

// MARK: - Profile View

struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showingSample = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 1, green: 1, blue: 1)
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Profile header
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.appleBlack)
                                    .frame(width: 86, height: 86)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 38, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            VStack(spacing: 4) {
                                Text("Dylan Gadsby")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                                Text("Trainy Member")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                            }

                            // Stats row
                            HStack(spacing: 0) {
                                ProfileStatView(value: "47", label: "Journeys")
                                Divider()
                                    .frame(height: 32)
                                    .background(AdaptiveColor.divider.resolve(in: colorScheme))
                                ProfileStatView(value: "2.4k", label: "Miles")
                                Divider()
                                    .frame(height: 32)
                                    .background(AdaptiveColor.divider.resolve(in: colorScheme))
                                ProfileStatView(value: "£38", label: "Saved")
                            }
                            .padding(.vertical, 16)
                            .background(Color(red: 1, green: 1, blue: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
                            )
                        }
                        .padding(.top, 8)

                        // Samples section
                        ProfileSectionView(title: "EXPLORE") {
                            ProfileRowButton(
                                icon: "sparkles",
                                iconColor: Color(red: 0.55, green: 0.35, blue: 1.0),
                                label: "View Sample Dashboard",
                                subtitle: "See Trainy's predictive intelligence"
                            ) {
                                showingSample = true
                            }
                        }

                        // Settings section
                        ProfileSectionView(title: "SETTINGS") {
                            ProfileRowButton(
                                icon: "bell.badge.fill",
                                iconColor: .appBlue,
                                label: "Notifications",
                                subtitle: "Delay alerts, platform changes"
                            ) {}
                            Divider()
                                .padding(.leading, 52)
                                .background(AdaptiveColor.divider.resolve(in: colorScheme))
                            ProfileRowButton(
                                icon: "creditcard.fill",
                                iconColor: .green,
                                label: "Delay Repay",
                                subtitle: "Auto-claim compensation"
                            ) {}
                            Divider()
                                .padding(.leading, 52)
                                .background(AdaptiveColor.divider.resolve(in: colorScheme))
                            ProfileRowButton(
                                icon: "lock.shield.fill",
                                iconColor: Color(red: 0.2, green: 0.6, blue: 1.0),
                                label: "Privacy",
                                subtitle: "Location data & permissions"
                            ) {}
                        }

                        // About section
                        ProfileSectionView(title: "ABOUT") {
                            ProfileRowButton(
                                icon: "star.fill",
                                iconColor: .yellow,
                                label: "Rate Trainy",
                                subtitle: "Love the app? Leave a review"
                            ) {}
                            Divider()
                                .padding(.leading, 52)
                                .background(AdaptiveColor.divider.resolve(in: colorScheme))
                            ProfileRowButton(
                                icon: "info.circle.fill",
                                iconColor: Color(red: 0.35, green: 0.75, blue: 1.0),
                                label: "About",
                                subtitle: "Version 1.0 · Build 1"
                            ) {}
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appBlue)
                }
            }
        }
        .sheet(isPresented: $showingSample) {
            JourneyDashboardView(journey: mockJourney)
        }
    }
}

// MARK: - Profile Stat View

struct ProfileStatView: View {
    @Environment(\.colorScheme) private var colorScheme
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Profile Section Container

struct ProfileSectionView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
                .tracking(1.2)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(red: 1, green: 1, blue: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AdaptiveColor.cardStroke.resolve(in: colorScheme), lineWidth: 1)
            )
        }
    }
}

// MARK: - Profile Row Button

struct ProfileRowButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let iconColor: Color
    let label: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AdaptiveColor.primary.resolve(in: colorScheme))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AdaptiveColor.secondary.resolve(in: colorScheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdaptiveColor.tertiary.resolve(in: colorScheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    ProfileView()
}
