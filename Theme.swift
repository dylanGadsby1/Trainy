import SwiftUI
import UIKit

// MARK: - Colours
// One palette for every screen. Each colour carries its own light and dark value, so a view
// names what a colour is for and never has to ask which colour scheme it is in.

extension Color {
    /// Apple's near-black (#1D1D1F). Fixed in both colour schemes: for things drawn on the map.
    static let appleBlack = Color(red: 29/255, green: 29/255, blue: 31/255)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    // Text
    static let ink = adaptive(light: rgb(29, 29, 31), dark: rgb(245, 245, 247))
    /// Text and icons drawn on an `ink` fill
    static let onInk = adaptive(light: .white, dark: rgb(29, 29, 31))
    /// Supporting text. Passes 4.5:1 on both `surface` and `card`.
    static let inkSecondary = adaptive(light: rgb(110, 110, 115), dark: rgb(161, 161, 166))
    /// Icons, chevrons and placeholders only: too faint for small text
    static let inkTertiary = adaptive(light: rgb(134, 134, 139), dark: rgb(134, 134, 139))

    // Brand. The one colour that is the app's own: the main action on a screen, the selected
    // tab, and the small icons that mark a row or a section. A navy (#0E4D90), darker
    // than the blue of `statusArriving`. Lightened in dark mode, where navy would sink into
    // the background.
    /// For icons and text. Passes 4.5:1 on both `surface` and `card`.
    static let brand = adaptive(light: rgb(14, 77, 144), dark: rgb(92, 160, 240))
    /// For filling a button or tile. White on it passes 4.5:1 in both colour schemes.
    static let brandFill = adaptive(light: rgb(14, 77, 144), dark: rgb(30, 105, 190))
    /// Text and icons drawn on a `brandFill`
    static let onBrand = Color.white
    /// A wash of the brand colour behind a `brand` icon
    static let brandTint = brand.opacity(0.13)

    // Surfaces
    /// The background of a sheet or page
    static let surface = adaptive(light: .white, dark: rgb(28, 28, 30))
    /// The background of a card or grouped row, on `surface`
    static let card = adaptive(light: rgb(245, 245, 247), dark: rgb(44, 44, 46))
    static let divider = adaptive(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.14))
    /// A quiet fill for icon tiles and secondary buttons, on `surface` or `card`
    static let subtleFill = adaptive(light: UIColor(white: 0, alpha: 0.06), dark: UIColor(white: 1, alpha: 0.10))
    /// The part of a progress line not yet travelled
    static let track = adaptive(light: UIColor(white: 0, alpha: 0.12), dark: UIColor(white: 1, alpha: 0.18))

    // Train status. Green, orange and red mean on time, delayed and cancelled, and nothing else.
    // The light values are darkened so that status text is readable on a pale background.
    static let statusOnTime = adaptive(light: rgb(36, 138, 61), dark: rgb(48, 209, 88))
    static let statusDelayed = adaptive(light: rgb(179, 92, 0), dark: rgb(255, 159, 10))
    static let statusCancelled = adaptive(light: rgb(215, 0, 21), dark: rgb(255, 69, 58))
    static let statusScheduled = adaptive(light: rgb(94, 107, 126), dark: rgb(154, 166, 184))
    static let statusArriving = adaptive(light: rgb(0, 113, 227), dark: rgb(100, 210, 255))
}

// MARK: - Cards

enum Theme {
    /// Every card, tile and grouped block uses this corner radius
    static let cardRadius: CGFloat = 20
}

extension View {
    /// The one card look. Change it here and every card in the app follows.
    func cardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return background(Color.card, in: shape)
            .contentShape(.contextMenuPreview, shape)
    }

    /// Dresses a system List or Form in the app's surfaces. Rows take `Color.card` through
    /// `listRowBackground`.
    func appListSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.surface)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .cardSurface()
    }
}

// MARK: - Text

/// The small capitals above a screen's title. One per screen at most: it is the only place
/// the app uses capitals and tracking.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Color.brand)
    }
}

/// The title row at the top of a sheet, with room for a control on the right.
struct SheetHeader<Trailing: View>: View {
    let title: String
    var eyebrow: String? = nil
    let trailing: Trailing

    init(_ title: String, eyebrow: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.eyebrow = eyebrow
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Eyebrow(eyebrow)
                }
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// The label that names a card or a group of rows.
struct SectionLabel: View {
    let title: String
    var systemImage: String? = nil

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if let systemImage {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.brand)
                }
            } else {
                Text(title)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.inkSecondary)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A word on a tint of its own colour: a train's status, or a short tag.
struct StatusPill: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    init(_ status: TrainStatus) {
        self.init(status.label, color: status.color)
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Buttons

/// The main action on a screen: full width, filled with the brand colour.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.brandFill.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A full-width action that should not compete with the primary one.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A round icon button with a full 44pt touch target. Give it an accessibility label.
struct IconButtonStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(filled ? Color.onBrand : Color.ink)
            .frame(width: 44, height: 44)
            .background(filled ? Color.brandFill : Color.subtleFill, in: Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
    /// The icon button for a screen's main action
    static var filledIcon: IconButtonStyle { IconButtonStyle(filled: true) }
}
