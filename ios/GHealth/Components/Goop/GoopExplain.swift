import SwiftUI
import GHealthCore

/// A window between two clock times: each time sits above its end of a filled block that names the window's length.
struct GoopWindowBar: View {
    var start: Date?
    var startLabel: String
    var end: Date?
    var endLabel: String
    var value: String
    var unit: String
    var fill: Color
    var ink: Color
    var accessibility: String

    var body: some View {
        let missing = Goop.missing(value)
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                clock(start, startLabel, alignment: .leading)
                Spacer(minLength: 0)
                clock(end, endLabel, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text(value).goop(.valueSmall)
                Text(unit).goop(.labelMicro)
            }.foregroundStyle(missing ? Goop.Color.text2 : ink).padding(.vertical, 5).frame(maxWidth: .infinity, minHeight: 26)
                .background(missing ? Goop.Color.missingFill : fill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusBar))
                .overlay(alignment: .leading) { edge }.overlay(alignment: .trailing) { edge }
        }.padding(.top, 6).accessibilityElement(children: .ignore).accessibilityLabel(accessibility)
    }

    private func clock(_ date: Date?, _ label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(GoopFormat.time(date)).goop(.valueZone).foregroundStyle(date == nil ? Goop.Color.text2 : Goop.Color.text1)
            Text(label).goop(.labelTiny).foregroundStyle(Goop.Color.textSoft).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var edge: some View { Rectangle().fill(Goop.Color.text1).frame(width: 2).padding(.vertical, -6) }
}

/// The panel on a sheet that adds parts up to a total.
struct GoopBreakdown<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLegend))
    }
}

/// One part of a breakdown: an optional swatch, a label with an optional note under it, and the part's value.
struct GoopBreakdownRow: View {
    var label: String
    var note: String? = nil
    var value: String
    var swatch: GoopSwatch? = nil
    var dimmed = false
    var identifier = ""
    var body: some View {
        HStack(spacing: 10) {
            if let swatch { swatch }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).goop(.legend).foregroundStyle(Goop.Color.legendText)
                if let note { Text(note).goop(.rowNote).foregroundStyle(Goop.Color.text2) }
            }
            Spacer(minLength: 12)
            Text(value).goop(.valueSmall).foregroundStyle(value == "—" ? Goop.Color.text2 : Goop.Color.text1).opacity(dimmed ? Goop.Opacity.stale : 1)
        }.padding(.vertical, 5)
            .accessibilityElement(children: .ignore).accessibilityLabel(label + (note.map { ", " + $0 } ?? "")).accessibilityValue(value).accessibilityIdentifier(identifier)
    }
}

/// A breakdown's sum. The result at the bottom is larger than a subtotal.
struct GoopBreakdownTotal: View {
    var label: String
    var spoken: String
    var value: String
    var result = false
    var identifier = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).goop(.labelCard).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 12)
            Text(value).goop(result ? .valueHours : .valueRow)
        }.foregroundStyle(Goop.Color.text1)
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityValue(value).accessibilityIdentifier(identifier)
    }
}

/// A hairline between groups of parts; `strong` is the rule above the result.
struct GoopBreakdownRule: View {
    var strong = false
    var body: some View {
        Rectangle().fill(strong ? Goop.Color.bodyText : Goop.Color.cardDivider).frame(height: strong ? 1.5 : 1)
            .padding(.vertical, strong ? 9 : 7).accessibilityHidden(true)
    }
}

/// The 13pt key that ties a breakdown row to its segment of a bar.
struct GoopSwatch: View {
    var fill: AnyShapeStyle
    var dashed = false
    init(_ color: Color, dashed: Bool = false) { fill = AnyShapeStyle(color); self.dashed = dashed }
    var body: some View {
        RoundedRectangle(cornerRadius: Goop.Metric.radiusMark).fill(fill).frame(width: 13, height: 13)
            .overlay { if dashed { RoundedRectangle(cornerRadius: Goop.Metric.radiusMark).strokeBorder(Goop.Color.naCredit, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) } }
            .accessibilityHidden(true)
    }
}

/// Sleep need as a bar: baseline, strain and debt side by side, with nap credit dashed over the end.
struct GoopNeedBar: View {
    var baseline: Int
    var strain: Int
    var debt: Int
    var naps: Int
    var scale: Double
    var body: some View {
        GeometryReader { geometry in
            let parts = [(baseline, 0), (strain, 1), (debt, 2)].filter { $0.0 > 0 }
            let gaps = CGFloat(max(0, parts.count - 1)) * 2
            ZStack(alignment: .trailing) {
                HStack(spacing: 2) {
                    ForEach(parts, id: \.1) { minutes, index in
                        Rectangle().fill(index == 0 ? AnyShapeStyle(Goop.Gradient.baselineNeedBar) : AnyShapeStyle(index == 1 ? Goop.Color.strain : Goop.Color.sufficient)).frame(width: max(0, geometry.size.width - gaps) * Double(minutes) / scale)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if naps > 0 {
                    Rectangle().fill(Goop.Color.legendFill.opacity(0.7)).overlay { Rectangle().strokeBorder(Goop.Color.naCredit, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }.frame(width: geometry.size.width * Double(naps) / scale)
                        .offset(x: -geometry.size.width * max(0, 1 - Double(baseline + strain + debt) / scale))
                }
            }.clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusBar))
        }.frame(height: 16).accessibilityHidden(true)
    }
}

/// The four parts of sleep need as breakdown rows keyed to `GoopNeedBar`.
struct GoopNeedParts: View {
    var baseline: Int
    var strain: Int?
    var debt: Int
    var naps: Int
    var debtNightsUsed: Int
    var dimmed = false
    var body: some View {
        VStack(spacing: 0) {
            GoopBreakdownRow(label: "Baseline need", value: GoopFormat.duration(baseline), swatch: GoopSwatch(Goop.Color.dialSegmentOff), dimmed: dimmed)
            GoopBreakdownRow(label: "Recent strain", value: strain.map { GoopFormat.signedDuration($0) } ?? "—", swatch: GoopSwatch(Goop.Color.strain), dimmed: dimmed, identifier: "need-strain")
            GoopBreakdownRow(label: "Sleep debt", note: "From \(debtNightsUsed) nights", value: GoopFormat.signedDuration(debt), swatch: GoopSwatch(Goop.Color.sufficient), dimmed: dimmed, identifier: "need-debt")
            GoopBreakdownRow(label: "Nap credit", value: GoopFormat.signedDuration(naps, credit: true), swatch: GoopSwatch(.clear, dashed: true), dimmed: dimmed)
        }
    }
}

/// The band names above one or more `GoopLevelScale`s.
struct GoopLevelHeader: View {
    var scale: LevelScale
    var body: some View {
        HStack(spacing: 4) {
            ForEach(scale.bands, id: \.name) { band in
                Text(band.name).goop(.labelMicro).foregroundStyle(Goop.Color.textSoft).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityHidden(true)
    }
}

/// A score's bands as equal segments with their ranges; the band today's value is in is lit, the others dimmed.
struct GoopLevelScale: View {
    var title: String? = nil
    var value: String? = nil
    var scale: LevelScale
    var current: Int?
    var identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).goop(.bodyMid).foregroundStyle(Goop.Color.legendText)
                    Spacer(minLength: 12)
                    Text(value ?? "—").goop(.valueMid).foregroundStyle(value == nil ? Goop.Color.text2 : Goop.Color.text1)
                }.padding(.bottom, 7)
            }
            HStack(spacing: 4) {
                ForEach(Array(scale.bands.enumerated()), id: \.offset) { index, band in
                    RoundedRectangle(cornerRadius: Goop.Metric.radiusHairline).fill(Goop.levelColor(band.tone)).frame(height: 4)
                        .opacity(index == current ? 1 : Goop.Opacity.otherBand)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(scale.bands.enumerated()), id: \.offset) { index, band in
                    Text(band.range).goop(.valueTiny).foregroundStyle(index == current ? Goop.Color.text1 : Goop.Color.text2)
                        .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 5)
        }.accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityIdentifier(identifier)
    }

    private var spoken: String {
        let lead = title.map { "\($0), \(value ?? "no value"). " } ?? ""
        let bands = scale.bands.map { "\($0.name.capitalized) \($0.range)" }.joined(separator: ", ")
        return lead + bands + (current.map { ". Today: \(scale.bands[$0].name.capitalized)" } ?? "")
    }
}

/// Two to four values side by side, split by short rules, as on the Live Activity. Stacks as rows at accessibility sizes.
struct GoopStatCells: View {
    struct Cell {
        var label: String
        var spoken: String
        var value: String
        var unit: String
    }
    var cells: [Cell]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(cells, id: \.label) { cell in GoopSheetRow(label: cell.spoken, value: cell.value, unit: cell.unit) }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    if index > 0 { Rectangle().fill(Goop.Color.plotGrid).frame(width: 1, height: 23).accessibilityHidden(true) }
                    VStack(spacing: 3) {
                        Text(cell.label).goop(.labelTiny).foregroundStyle(Goop.Color.textSoft).lineLimit(1).minimumScaleFactor(0.75)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(cell.value).goop(.valueMid).foregroundStyle(cell.value == "—" ? Goop.Color.text2 : Goop.Color.text1)
                            if cell.value != "—" { Text(cell.unit).goop(.unitSmall).foregroundStyle(Goop.Color.text2) }
                        }
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore).accessibilityLabel(cell.spoken).accessibilityValue(cell.value == "—" ? "no data" : "\(cell.value) \(cell.unit)")
                }
            }.padding(.vertical, 4)
        }
    }
}

/// The rule or source behind a sheet's numbers, in one or two short sentences.
struct GoopFootnote: View {
    var text: String
    static var recalculation: Self { Self(text: "Past days are recalculated when Google updates your data or a Mac setting changes.") }
    static var wristHeartRate: Self { Self(text: "Wrist heart rate can read low in boxing and weightlifting, so Strain and zones may be low.") }
    var body: some View {
        Text(text).goop(.bodySmall).foregroundStyle(Goop.Color.iconMuted).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Metadata at the end of a sheet, such as the score version.
struct GoopFinePrint: View {
    var text: String
    var body: some View { Text(text).goop(.captionDial).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading) }
}

extension Goop {
    static func levelColor(_ tone: LevelScale.Tone) -> SwiftUI.Color {
        switch tone {
        case .caution: Color.caution
        case .neutral: Color.neutral
        case .positive: Color.positive
        case .recoveryLow: Color.recoveryLow
        case .recoveryMedium: Color.recoveryMedium
        case .recoveryHigh: Color.recoveryHigh
        case .strain: Color.strain
        }
    }
}
