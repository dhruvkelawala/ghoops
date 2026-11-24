import SwiftUI
import GHealthCore

enum GoopScore: String, CaseIterable {
    case sleep = "Sleep", recovery = "Recovery", strain = "Strain"
    var maximum: Double { self == .strain ? 21 : 100 }
    func color(band: Band3?) -> Color {
        switch self {
        case .sleep: Goop.Color.sleep
        case .strain: Goop.Color.strain
        case .recovery: Goop.recoveryColor(band)
        }
    }
    func label(value: Double?, band: Band3? = nil, strainBand: StrainBand? = nil, inProgress: Bool = false) -> String {
        guard let value else { return "\(rawValue), no data" }
        let amount = self == .strain ? "\(GoopFormat.number(value, decimals: 1)) of 21" : "\(GoopFormat.number(value)) percent" // goop-lint: allow enginenumber: schema: Strain is 0 to 21, contract §5.4
        let band = self == .recovery ? band?.rawValue : self == .strain ? strainBand?.rawValue.replacingOccurrences(of: "_", with: " ") : nil
        return ([rawValue, amount] + [band, inProgress && self == .strain ? "so far" : nil].compactMap { $0 }).joined(separator: ", ")
    }
}

struct ScoreRing: View {
    enum Variant: CaseIterable {
        case home, detail, widgetSmall, widgetMedium, widgetList, lock
        var diameter: CGFloat {
            switch self { case .home: 92; case .detail: 262; case .widgetSmall: 100; case .widgetMedium: 76; case .widgetList: 30; case .lock: 54 }
        }
        var stroke: CGFloat {
            switch self { case .home, .widgetSmall: 6.5; case .detail: 16; case .widgetMedium: 5.5; case .widgetList: 3.5; case .lock: 4 }
        }
        var widget: Bool { self != .home && self != .detail }
    }
    var value: Double?
    var maximum: Double = 100
    var color: Color
    var variant: Variant = .home
    var diameter: CGFloat? = nil
    var strokeWidth: CGFloat? = nil
    var fixture = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var fraction: Double { min(1, max(0, (value ?? 0) / maximum)) }
    var body: some View {
        let size = diameter ?? variant.diameter
        let stroke = strokeWidth ?? (variant == .lock ? size * 4 / 54 : variant.stroke)
        ZStack {
            Circle().strokeBorder(variant == .lock ? .white.opacity(0.25) : Goop.Color.ringTrack, lineWidth: stroke)
            Circle().inset(by: stroke / 2).trim(from: 0, to: appeared || fixture || variant.widget || reduceMotion ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .butt)).rotationEffect(.degrees(-90))
        }.frame(width: size, height: size).accessibilityHidden(true)
            .onAppear {
                guard !appeared else { return }
                if fixture || variant.widget || reduceMotion { appeared = true }
                else { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
            }
    }
}

struct ScoreText: View {
    var value: Double?
    var percent = true
    var size: CGFloat = 30
    var color: Color = Goop.Color.text1
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(GoopFormat.number(value, decimals: percent ? 0 : 1)).font(Font(GoopFont.sofia(size))) // goop-lint: allow rawfont: ring numerals are sized by the ring variant
            if percent && value != nil { Text("%").font(Font(GoopFont.sofia(size * 0.62))) } // goop-lint: allow rawfont: ring numerals are sized by the ring variant
        }.foregroundStyle(value == nil ? Goop.Color.text2 : color).fixedSize().accessibilityHidden(true)
    }
}

extension Goop {
    static func recoveryColor(_ band: Band3?) -> SwiftUI.Color {
        switch band { case .high: Color.recoveryHigh; case .medium: Color.recoveryMedium; case .low: Color.recoveryLow; default: Color.text2 }
    }
    static func color(_ role: GoopColorRole) -> SwiftUI.Color {
        switch role {
        case .positive: Color.positive
        case .caution: Color.caution
        case .neutral: Color.neutral
        case .healthOK: Color.healthOK
        case .recovery: Color.recoveryHigh
        case .strain: Color.strain
        case .sleep: Color.sleep
        case .trendLine: Color.trendLine
        case .zone2: Color.zone2
        case .zone4: Color.zone4
        case .stageREM: Color.stageREM
        }
    }
    static var zones: [SwiftUI.Color] { [Color.zone0, Color.zone1, Color.zone2, Color.zone3, Color.zone4, Color.zone5] }
}
