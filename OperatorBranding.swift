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

    static let all: [String: OperatorBrand] = {
        let entries: [OperatorBrand] = [
            OperatorBrand(code: "VT", shortName: "Avanti",       assetName: "logo_vt", fallbackColor: Color(red: 0.88, green: 0.08, blue: 0.10), needsDarkBackground: true),
            OperatorBrand(code: "GW", shortName: "GWR",          assetName: "logo_gw", fallbackColor: Color(red: 0.04, green: 0.42, blue: 0.23), needsDarkBackground: true),
            OperatorBrand(code: "SE", shortName: "SE",           assetName: "logo_se", fallbackColor: Color(red: 0.00, green: 0.60, blue: 0.84), needsDarkBackground: true),
            OperatorBrand(code: "TL", shortName: "Thameslink",   assetName: "logo_tl", fallbackColor: Color(red: 0.84, green: 0.00, blue: 0.43), needsDarkBackground: true),
            OperatorBrand(code: "GN", shortName: "Gt Northern",  assetName: "logo_gn", fallbackColor: Color(red: 0.00, green: 0.16, blue: 0.43), needsDarkBackground: true),
            OperatorBrand(code: "LE", shortName: "Gt Anglia",    assetName: "logo_le", fallbackColor: Color(red: 0.80, green: 0.10, blue: 0.20), needsDarkBackground: true),
            OperatorBrand(code: "LM", shortName: "LNR",          assetName: "logo_lm", fallbackColor: Color(red: 0.00, green: 0.20, blue: 0.60), needsDarkBackground: true),
            OperatorBrand(code: "LO", shortName: "Overground",   assetName: "logo_lo", fallbackColor: Color(red: 0.91, green: 0.41, blue: 0.00), needsDarkBackground: true),
            OperatorBrand(code: "ME", shortName: "Merseyrail",   assetName: "logo_me", fallbackColor: Color(red: 0.93, green: 0.76, blue: 0.00), needsDarkBackground: false),
            OperatorBrand(code: "NT", shortName: "Northern",     assetName: "logo_nt", fallbackColor: Color(red: 0.10, green: 0.10, blue: 0.10), needsDarkBackground: true),
            OperatorBrand(code: "SN", shortName: "Southern",     assetName: "logo_sn", fallbackColor: Color(red: 0.00, green: 0.55, blue: 0.26), needsDarkBackground: true),
            OperatorBrand(code: "SR", shortName: "ScotRail",     assetName: "logo_sr", fallbackColor: Color(red: 0.00, green: 0.33, blue: 0.66), needsDarkBackground: true),
            OperatorBrand(code: "SW", shortName: "SWR",          assetName: "logo_sw", fallbackColor: Color(red: 0.73, green: 0.07, blue: 0.15), needsDarkBackground: true),
            OperatorBrand(code: "TP", shortName: "TPE",          assetName: "logo_tp", fallbackColor: Color(red: 0.00, green: 0.47, blue: 0.75), needsDarkBackground: true),
            OperatorBrand(code: "XC", shortName: "CrossCountry", assetName: "logo_xc", fallbackColor: Color(red: 0.55, green: 0.05, blue: 0.15), needsDarkBackground: true),
            OperatorBrand(code: "GR", shortName: "LNER",         assetName: "logo_gr", fallbackColor: Color(red: 0.69, green: 0.07, blue: 0.13), needsDarkBackground: true),
            OperatorBrand(code: "CC", shortName: "c2c",          assetName: "logo_cc", fallbackColor: Color(red: 0.80, green: 0.05, blue: 0.15), needsDarkBackground: true),
            OperatorBrand(code: "CH", shortName: "Chiltern",     assetName: "logo_ch", fallbackColor: Color(red: 0.00, green: 0.32, blue: 0.60), needsDarkBackground: true),
            OperatorBrand(code: "EM", shortName: "EMR",          assetName: "logo_em", fallbackColor: Color(red: 0.84, green: 0.22, blue: 0.08), needsDarkBackground: true),
            OperatorBrand(code: "AW", shortName: "TfW",          assetName: "logo_aw", fallbackColor: Color(red: 0.81, green: 0.09, blue: 0.13), needsDarkBackground: true),
            OperatorBrand(code: "HX", shortName: "Heathrow",     assetName: "logo_hx", fallbackColor: Color(red: 0.55, green: 0.00, blue: 0.20), needsDarkBackground: true),
            OperatorBrand(code: "CS", shortName: "Caledonian",   assetName: "logo_cs", fallbackColor: Color(red: 0.00, green: 0.29, blue: 0.59), needsDarkBackground: true),
            OperatorBrand(code: "XR", shortName: "Elizabeth",    assetName: "logo_xr", fallbackColor: Color(red: 0.41, green: 0.31, blue: 0.63), needsDarkBackground: true),
            OperatorBrand(code: "IL", shortName: "Island Line",  assetName: "logo_il", fallbackColor: Color(red: 0.00, green: 0.47, blue: 0.75), needsDarkBackground: true),
            OperatorBrand(code: "GC", shortName: "Grand Central",assetName: "logo_gc", fallbackColor: Color(red: 0.20, green: 0.20, blue: 0.20), needsDarkBackground: true),
            OperatorBrand(code: "HB", shortName: "Hull Trains",  assetName: "logo_hb", fallbackColor: Color(red: 0.55, green: 0.00, blue: 0.35), needsDarkBackground: true),
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

    private var brand: OperatorBrand? { OperatorBrand.from(code: atocCode) }

    var body: some View {
        if let brand = brand, UIImage(named: brand.assetName) != nil {
            let height: CGFloat = compact ? 18 : 22
            Image(brand.assetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(height: height)
        } else {
            fallbackPill
        }
    }

    @ViewBuilder
    private var fallbackPill: some View {
        let label    = brand?.shortName ?? atocCode ?? "Rail"
        let bgColor  = brand?.fallbackColor ?? Color.gray.opacity(0.35)
        let txtColor: Color = (brand?.needsDarkBackground ?? true) ? .white : .black

        Text(label)
            .font(.system(size: compact ? 9 : 10, weight: .bold))
            .foregroundColor(txtColor)
            .lineLimit(1)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 3 : 4)
            .background(bgColor)
            .clipShape(Capsule())
    }
}
