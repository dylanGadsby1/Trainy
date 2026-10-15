import SwiftUI

// MARK: - Operator Branding

struct OperatorBrand {
    /// 2-letter ATOC code, e.g. "VT"
    let code: String
    /// Short human-readable name, e.g. "Avanti"
    let shortName: String
    /// Asset catalog image name, e.g. "logo_vt"
    let assetName: String
    /// Fallback brand colour used when the image asset is missing
    let fallbackColor: Color
    /// Whether the logo looks better on a dark background (use white bg for light-background logos)
    let needsDarkBackground: Bool
    /// URL for claiming Delay Repay
    let delayRepayURL: String?
    /// The part of the image the logo itself fills, in unit coordinates. Most fill all of
    /// theirs; a few are drawn inside a margin, which would otherwise make them look small.
    var artwork = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Operators that only pay out from 30 minutes late; the rest pay from 15
    private static let thirtyMinuteSchemes: Set<String> = ["GR", "XC", "SR", "HB", "GC", "CS", "ME", "LO", "XR"]

    /// Minutes late at the destination from which a Delay Repay claim can be made
    var delayRepayThreshold: Int { Self.thirtyMinuteSchemes.contains(code) ? 30 : 15 }

    static let all: [String: OperatorBrand] = {
        let entries: [OperatorBrand] = [
            OperatorBrand(code: "VT", shortName: "Avanti",       assetName: "logo_vt", fallbackColor: Color(red: 0.88, green: 0.08, blue: 0.10), needsDarkBackground: true, delayRepayURL: "https://www.avantiwestcoast.co.uk/help-and-support/delay-repay"),
            OperatorBrand(code: "GW", shortName: "GWR",          assetName: "logo_gw", fallbackColor: Color(red: 0.04, green: 0.42, blue: 0.23), needsDarkBackground: true, delayRepayURL: "https://www.gwr.com/help-and-support/refunds-and-compensation/delay-repay"),
            OperatorBrand(code: "SE", shortName: "SE",           assetName: "logo_se", fallbackColor: Color(red: 0.00, green: 0.60, blue: 0.84), needsDarkBackground: true, delayRepayURL: "https://www.southeasternrailway.co.uk/help-and-contact/refunds-and-compensation/delay-repay"),
            OperatorBrand(code: "TL", shortName: "Thameslink",   assetName: "logo_tl", fallbackColor: Color(red: 0.84, green: 0.00, blue: 0.43), needsDarkBackground: true, delayRepayURL: "https://www.thameslinkrailway.com/help-and-support/journey-problems/delay-repay"),
            OperatorBrand(code: "GN", shortName: "Gt Northern",  assetName: "logo_gn", fallbackColor: Color(red: 0.00, green: 0.16, blue: 0.43), needsDarkBackground: true, delayRepayURL: "https://www.greatnorthernrail.com/help-and-support/journey-problems/delay-repay"),
            OperatorBrand(code: "LE", shortName: "Gt Anglia",    assetName: "logo_le", fallbackColor: Color(red: 0.80, green: 0.10, blue: 0.20), needsDarkBackground: true, delayRepayURL: "https://www.greateranglia.co.uk/about-us/our-performance/delay-repay"),
            OperatorBrand(code: "LM", shortName: "LNR",          assetName: "logo_lm", fallbackColor: Color(red: 0.00, green: 0.20, blue: 0.60), needsDarkBackground: true, delayRepayURL: "https://www.londonnorthwesternrailway.co.uk/about-us/delay-repay"),
            OperatorBrand(code: "LO", shortName: "Overground",   assetName: "logo_lo", fallbackColor: Color(red: 0.91, green: 0.41, blue: 0.00), needsDarkBackground: true, delayRepayURL: "https://tfl.gov.uk/fares/refunds-and-replacements/tube-and-dlr-delays"),
            OperatorBrand(code: "ME", shortName: "Merseyrail",   assetName: "logo_me", fallbackColor: Color(red: 0.93, green: 0.76, blue: 0.00), needsDarkBackground: false, delayRepayURL: "https://www.merseyrail.org/plan-your-journey/refunds-and-compensation.aspx"),
            OperatorBrand(code: "NT", shortName: "Northern",     assetName: "logo_nt", fallbackColor: Color(red: 0.10, green: 0.10, blue: 0.10), needsDarkBackground: true, delayRepayURL: "https://www.northernrailway.co.uk/help/delay-repay"),
            OperatorBrand(code: "SN", shortName: "Southern",     assetName: "logo_sn", fallbackColor: Color(red: 0.00, green: 0.55, blue: 0.26), needsDarkBackground: true, delayRepayURL: "https://www.southernrailway.com/help-and-support/journey-problems/delay-repay"),
            OperatorBrand(code: "SR", shortName: "ScotRail",     assetName: "logo_sr", fallbackColor: Color(red: 0.00, green: 0.33, blue: 0.66), needsDarkBackground: true, delayRepayURL: "https://www.scotrail.co.uk/about-scotrail/our-delay-repay-guarantee"),
            OperatorBrand(code: "SW", shortName: "SWR",          assetName: "logo_sw", fallbackColor: Color(red: 0.73, green: 0.07, blue: 0.15), needsDarkBackground: true, delayRepayURL: "https://www.southwesternrailway.com/contact-and-help/refunds-and-compensation/delay-repay"),
            OperatorBrand(code: "TP", shortName: "TPE",          assetName: "logo_tp", fallbackColor: Color(red: 0.00, green: 0.47, blue: 0.75), needsDarkBackground: true, delayRepayURL: "https://www.tpexpress.co.uk/help/delay-repay-compensation", artwork: CGRect(x: 0.06, y: 0.15, width: 0.89, height: 0.62)),
            OperatorBrand(code: "XC", shortName: "CrossCountry", assetName: "logo_xc", fallbackColor: Color(red: 0.55, green: 0.05, blue: 0.15), needsDarkBackground: true, delayRepayURL: "https://www.crosscountrytrains.co.uk/customer-service/delay-repay"),
            OperatorBrand(code: "GR", shortName: "LNER",         assetName: "logo_gr", fallbackColor: Color(red: 0.69, green: 0.07, blue: 0.13), needsDarkBackground: true, delayRepayURL: "https://www.lner.co.uk/customer-service/contact-us/refund/delay-repay/"),
            OperatorBrand(code: "CC", shortName: "c2c",          assetName: "logo_cc", fallbackColor: Color(red: 0.80, green: 0.05, blue: 0.15), needsDarkBackground: true, delayRepayURL: "https://www.c2c-online.co.uk/help-and-contact/delay-repay/"),
            OperatorBrand(code: "CH", shortName: "Chiltern",     assetName: "logo_ch", fallbackColor: Color(red: 0.00, green: 0.32, blue: 0.60), needsDarkBackground: true, delayRepayURL: "https://www.chilternrailways.co.uk/compensation-due-to-delay", artwork: CGRect(x: 0, y: 0.09, width: 1, height: 0.86)),
            OperatorBrand(code: "EM", shortName: "EMR",          assetName: "logo_em", fallbackColor: Color(red: 0.84, green: 0.22, blue: 0.08), needsDarkBackground: true, delayRepayURL: "https://www.eastmidlandsrailway.co.uk/help-manage/manage/delay-repay"),
            OperatorBrand(code: "AW", shortName: "TfW",          assetName: "logo_aw", fallbackColor: Color(red: 0.81, green: 0.09, blue: 0.13), needsDarkBackground: true, delayRepayURL: "https://tfw.wales/help-and-contact/rail/delay-repay"),
            OperatorBrand(code: "HX", shortName: "Heathrow",     assetName: "logo_hx", fallbackColor: Color(red: 0.55, green: 0.00, blue: 0.20), needsDarkBackground: true, delayRepayURL: "https://www.heathrowexpress.com/about-us/delay-repay"),
            OperatorBrand(code: "CS", shortName: "Caledonian",   assetName: "logo_cs", fallbackColor: Color(red: 0.00, green: 0.29, blue: 0.59), needsDarkBackground: true, delayRepayURL: "https://www.sleeper.scot/delay-repay/"),
            OperatorBrand(code: "XR", shortName: "Elizabeth",    assetName: "logo_xr", fallbackColor: Color(red: 0.41, green: 0.31, blue: 0.63), needsDarkBackground: true, delayRepayURL: "https://tfl.gov.uk/fares/refunds-and-replacements/tube-and-dlr-delays"),
            OperatorBrand(code: "IL", shortName: "Island Line",  assetName: "logo_il", fallbackColor: Color(red: 0.00, green: 0.47, blue: 0.75), needsDarkBackground: true, delayRepayURL: "https://www.southwesternrailway.com/contact-and-help/refunds-and-compensation/delay-repay"),
            OperatorBrand(code: "GC", shortName: "Grand Central",assetName: "logo_gc", fallbackColor: Color(red: 0.20, green: 0.20, blue: 0.20), needsDarkBackground: true, delayRepayURL: "https://www.grandcentralrail.com/help/delay-repay"),
            OperatorBrand(code: "HB", shortName: "Hull Trains",  assetName: "logo_hb", fallbackColor: Color(red: 0.55, green: 0.00, blue: 0.35), needsDarkBackground: true, delayRepayURL: "https://www.hulltrains.co.uk/customer-service/delay-repay", artwork: CGRect(x: 0, y: 0.18, width: 1, height: 0.65)),
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
    }()

    static func from(code: String?) -> OperatorBrand? {
        guard let code = code?.uppercased() else { return nil }
        return all[code]
    }
}

// MARK: - Operator Logo Badge

/// Renders the operator logo image, or a colour-coded text pill if the asset is absent.
struct OperatorLogoBadge: View {
    let atocCode: String?
    /// compact = sized for list rows; non-compact = sized for train cards
    var compact: Bool = false
    /// Sits in a box of one fixed size, logo to the left, so whatever follows it starts in the
    /// same place on every row however wide the logo is
    var inSlot: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var brand: OperatorBrand? { OperatorBrand.from(code: atocCode) }

    /// The size to draw a logo's artwork at. Logos run from a roundel to a long wordmark:
    /// at one height the wordmarks dwarf the rest, so each is given the same area instead,
    /// which is how Southern's logo, in the middle of the range, sat at the old fixed height.
    /// The two limits keep a roundel from standing too tall and a wordmark from crowding its row.
    private static func artworkSize(aspect: CGFloat, compact: Bool) -> CGSize {
        let area: CGFloat = compact ? 750 : 1120
        let maxHeight: CGFloat = compact ? 21 : 26
        let maxWidth: CGFloat = compact ? 80 : 96
        let height = min((area / aspect).squareRoot(), maxHeight, maxWidth / aspect)
        return CGSize(width: height * aspect, height: height)
    }

    /// The box a slotted logo sits in: as wide and tall as the widest and tallest logo may be
    private var slot: CGSize { compact ? CGSize(width: 80, height: 21) : CGSize(width: 96, height: 26) }

    var body: some View {
        if inSlot {
            badge.frame(width: slot.width, height: slot.height, alignment: .leading)
        } else {
            badge
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let brand = brand, let image = UIImage(named: brand.assetName), image.size.width > 0, image.size.height > 0 {
            let art = brand.artwork
            let size = Self.artworkSize(aspect: (image.size.width * art.width) / (image.size.height * art.height), compact: compact)
            // The whole image, scaled so that its artwork comes out at `size` and centred on it
            let canvas = CGSize(width: size.width / art.width, height: size.height / art.height)
            let logo = Image(brand.assetName)
                .resizable()
                .renderingMode(.original)
                .frame(width: canvas.width, height: canvas.height)
                .offset(x: (0.5 - art.midX) * canvas.width, y: (0.5 - art.midY) * canvas.height)
                .frame(width: size.width, height: size.height)
                .accessibilityLabel(brand.shortName)

            // The logos are drawn for a light background, so in dark mode they get one
            if colorScheme == .dark {
                logo
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                logo
            }
        } else {
            fallbackPill
        }
    }

    @ViewBuilder
    private var fallbackPill: some View {
        let label    = brand?.shortName ?? atocCode ?? "Rail"
        // An operator the app has no branding for gets a quiet, readable pill
        let bgColor  = brand?.fallbackColor ?? Color.subtleFill
        let txtColor: Color = brand == nil ? .inkSecondary : (brand?.needsDarkBackground == true ? .white : .black)

        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundColor(txtColor)
            .lineLimit(1)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 3 : 4)
            .background(bgColor)
            .clipShape(Capsule())
    }
}

// MARK: - Operator Summary

/// Who runs a train, or a journey of several: the first operator's logo, and a count of
/// the others when there are more ("+1").
struct OperatorSummary: View {
    struct Operator: Hashable {
        var code: String?
        var name: String?
    }

    let operators: [Operator]
    /// compact = sized for list rows; non-compact = sized for train cards
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if let first = operators.first {
                OperatorLogoBadge(atocCode: first.code, compact: compact)
                if OperatorBrand.from(code: first.code) == nil {
                    Text(first.name ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
            }
            if operators.count > 1 {
                Text("+\(operators.count - 1)")
                    .font((compact ? Font.caption : Font.footnote).weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(operators.count == 2 ? "and 1 other operator" : "and \(operators.count - 1) other operators")
            }
        }
    }
}

extension OperatorSummary.Operator {
    /// Each operator once, in the order their trains are taken.
    static func distinct(_ operators: [OperatorSummary.Operator]) -> [OperatorSummary.Operator] {
        var seen: Set<String> = []
        return operators.filter { seen.insert($0.code ?? $0.name ?? "").inserted }
    }
}

extension Array where Element == DarwinServiceAdapter {
    /// Who runs these trains: each operator once, in the order the trains are taken.
    var operators: [OperatorSummary.Operator] {
        OperatorSummary.Operator.distinct(map { .init(code: $0.atocCode, name: $0.atocName) })
    }
}

