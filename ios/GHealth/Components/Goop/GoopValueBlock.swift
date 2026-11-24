import SwiftUI

extension Goop {
    /// True when `value` is the missing-value dash, so its container loses its colour (live-polish-spec §1).
    static func missing(_ value: String) -> Bool { GoopFeature.livePolish && value == "—" }
}

/// The 98×41 value block at the left of an activity row and the live row (live-polish-spec §1.1).
struct GoopValueBlock: View {
    var symbol: String
    var value: String
    var fill: Color
    var dashed = false
    var valueOpacity: Double = 1
    var body: some View {
        let missing = Goop.missing(value)
        HStack(spacing: 10) {
            GoopSymbol(name: symbol, size: 22, color: .white)
            Text(value).goop(.valueBlock).foregroundStyle(missing ? Goop.Color.text2 : Goop.Color.text1).opacity(missing ? 1 : valueOpacity)
        }.frame(width: 98, height: 41)
            .background(missing ? Goop.Color.missingFill : dashed ? .clear : fill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusActivityBlock))
            .overlay { if dashed { RoundedRectangle(cornerRadius: Goop.Metric.radiusActivityBlock).strokeBorder(fill, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
    }
}
