import SwiftUI
import GHealthCore

struct GoopSymbol: View {
    let name: String
    var size: CGFloat = 16
    var color: Color = Goop.Color.iconMuted
    var weight: Font.Weight = .light
    var body: some View {
        Image(systemName: name).symbolRenderingMode(.monochrome).font(.system(size: size, weight: weight)).foregroundStyle(color).accessibilityHidden(true)
    }
}

struct GoopDateControl: View {
    var date: String
    var defaultDate: String
    var oldestDate: String?
    var select: (String) -> Void
    var body: some View {
        HStack(spacing: 4) {
            dayButton("chevron.left", identifier: "date-prev", label: "Previous day", enabled: oldestDate.map { date > $0 } ?? false) { select(GoopFormat.addingDays(-1, to: date)) }
            Button { if date != defaultDate { select(defaultDate) } } label: {
                Text(GoopFormat.dateControl(date, defaultDate: defaultDate)).goop(.labelDate).lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 5)
                    .frame(width: 84, height: 24).background(Goop.Color.dateInner, in: Capsule()).frame(height: 44)
            }.accessibilityIdentifier("date-label")
                .accessibilityLabel(date == defaultDate ? "Showing today" : "Showing " + GoopFormat.dateLabel(date, format: "EEEE d MMMM"))
                .accessibilityHint(date == defaultDate ? "" : "Double-tap to return to today")
            dayButton("chevron.right", identifier: "date-next", label: "Next day", enabled: date < defaultDate) { select(GoopFormat.addingDays(1, to: date)) }
        }.padding(.horizontal, 6).background { Capsule().fill(Goop.Color.dateOuter).frame(height: 30) }.buttonStyle(.plain)
    }
    private func dayButton(_ symbol: String, identifier: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GoopSymbol(name: symbol, size: 11, color: enabled ? .white : Goop.Color.disabledChevron, weight: .semibold)
                .frame(width: 16, height: 44).contentShape(Rectangle().inset(by: -14))
        }.disabled(!enabled).accessibilityIdentifier(identifier).accessibilityLabel(label)
    }
}

struct GoopHomeHeader: View {
    var date: String
    var defaultDate: String
    var oldestDate: String?
    var battery: Int?
    var select: (String) -> Void
    var more: () -> Void
    var body: some View {
        ZStack {
            GoopDateControl(date: date, defaultDate: defaultDate, oldestDate: oldestDate, select: select)
            HStack {
                Button(action: more) { GoopSymbol(name: "person.crop.circle.fill", size: 28, color: Goop.Color.avatar).frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -8)) }.accessibilityLabel("More and settings")
                Spacer()
                if let battery {
                    HStack(spacing: 7) {
                        Text("\(battery)%").goop(.battery).foregroundStyle(Goop.Color.text2)
                        GoopSymbol(name: "battery.\(battery < 13 ? 0 : battery < 38 ? 25 : battery < 63 ? 50 : battery < 88 ? 75 : 100)percent", size: 15, color: Goop.Color.battery)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("Band battery \(battery) percent")
                } else { Color.clear.frame(width: 28) }
            }.allowsHitTesting(true)
        }.frame(height: 30).padding(.horizontal, 20).padding(.top, 6).buttonStyle(.plain)
    }
}

struct GoopHeaderButton {
    var symbol: String
    var size: CGFloat
    var label: String
    var identifier: String
    var action: () -> Void
    static func info(_ action: @escaping () -> Void) -> Self { .init(symbol: "info.circle", size: 25, label: "How this works", identifier: "info-button", action: action) }
    static func edit(_ action: @escaping () -> Void) -> Self { .init(symbol: "pencil", size: 21, label: "Edit activity", identifier: "edit-button", action: action) }
    fileprivate var button: some View {
        Button(action: action) { GoopSymbol(name: symbol, size: size).frame(width: 44, height: 44) }.accessibilityIdentifier(identifier).accessibilityLabel(label)
    }
}

struct GoopDetailHeader: View {
    var title: String
    var back: (() -> Void)? = nil
    var trailing: GoopHeaderButton? = nil
    var body: some View {
        ZStack {
            Text(title).goop(.labelNav)
            HStack {
                if let back { Button(action: back) { GoopSymbol(name: "chevron.left", size: 21, color: .white).frame(width: 44, height: 44) }.accessibilityIdentifier("back-button").accessibilityLabel("Back") }
                Spacer()
                if let trailing { trailing.button }
            }
        }.frame(height: 50).padding(.horizontal, 18).buttonStyle(.plain)
    }
}

struct GoopWorkoutHeader: View {
    var symbol: String
    var title: String
    var subtitle: String
    var back: () -> Void
    var trailing: GoopHeaderButton? = nil
    var body: some View {
        HStack(spacing: 16) {
            Button(action: back) { GoopSymbol(name: "chevron.left", size: 21, color: .white).frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -8)) }.accessibilityIdentifier("back-button").accessibilityLabel("Back")
            GoopSymbol(name: symbol, size: 30, color: .white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).goop(.labelWorkoutTitle)
                Text(subtitle).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft)
            }
            Spacer(minLength: 0)
            if let trailing { trailing.button }
        }.frame(minHeight: 50).padding(.horizontal, 16).buttonStyle(.plain)
    }
}

enum GoopTab: String, CaseIterable, Identifiable {
    case home, health, trends, more
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { switch self { case .home: "house"; case .health: "heart"; case .trends: "chart.xyaxis.line"; case .more: "line.3.horizontal" } }
}

struct GoopTabBar: View {
    @Binding var selected: GoopTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(GoopTab.allCases) { tab in
                Button { selected = tab } label: {
                    VStack(spacing: 4) {
                        GoopSymbol(name: tab.symbol, size: tab == .home ? 22 : tab == .more ? 17 : 21, color: selected == tab ? Goop.Color.text1 : Goop.Color.text3).frame(height: 24)
                        Text(tab.title).goop(.tab)
                    }.foregroundStyle(selected == tab ? Goop.Color.text1 : Goop.Color.text3).frame(width: 70).frame(maxWidth: .infinity).contentShape(Rectangle().inset(by: -3))
                }.accessibilityIdentifier("tab-\(tab.rawValue)").accessibilityLabel(tab.title).accessibilityAddTraits(selected == tab ? .isSelected : [])
            }
        }.padding(.top, 12).padding(.bottom, 8).background(Goop.Gradient.tab.ignoresSafeArea(edges: .bottom)).buttonStyle(.plain)
    }
}

enum GoopButtonRole { case outline, primary, destructive }

struct GoopButton: View {
    var title: String
    var role: GoopButtonRole = .outline
    var busy = false
    var identifier: String? = nil
    var action: () -> Void
    var body: some View {
        if let identifier { button.accessibilityIdentifier(identifier) }
        else { button }
    }
    private var ink: Color {
        role == .primary ? Goop.Color.backgroundHomeBase : role == .destructive ? Goop.Color.zone5 : Goop.Color.text1
    }
    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) { Text(title).goop(.labelCard); if busy { ProgressView().tint(ink) } }.frame(maxWidth: .infinity).frame(minHeight: 50).foregroundStyle(ink)
                .background(role == .primary ? Goop.Color.text1 : .clear, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusButton))
                .overlay { if role != .primary { RoundedRectangle(cornerRadius: Goop.Metric.radiusButton).strokeBorder(role == .destructive ? Goop.Color.zone5 : Goop.Color.outlineBorder, lineWidth: 1.5) } }
        }.buttonStyle(.plain)
    }
}

extension View {
    func goopDestructiveAlert(_ title: String, isPresented: Binding<Bool>, verb: String, message: String, perform: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button(verb, role: .destructive, action: perform)
            Button("Cancel", role: .cancel) {}
        } message: { Text(message) }
    }
}

enum GoopBannerTone {
    case neutral, strain, positive, caution, muted
    var color: Color {
        switch self {
        case .neutral: .clear
        case .strain: Goop.Color.strain
        case .positive: Goop.Color.positive
        case .caution: Goop.Color.caution
        case .muted: Goop.Color.text2
        }
    }
    var ink: Color { self == .strain ? Goop.Color.strainLight : color }
}

struct GoopBannerAction {
    var title: String
    var identifier: String
    var perform: () -> Void
}

struct GoopBanner<Accessory: View>: View {
    var text: String
    var title: String? = nil
    var symbol: String = "clock"
    var tone: GoopBannerTone = .neutral
    var symbolColor: Color = Goop.Color.caution
    var action: GoopBannerAction? = nil
    var dismiss: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory
    private var neutral: Bool { tone == .neutral }
    private var ink: Color { neutral ? symbolColor : tone.ink }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: neutral ? 10 : 11) {
                GoopSymbol(name: symbol, size: neutral ? 15 : 18, color: ink, weight: neutral ? .light : .semibold)
                VStack(alignment: .leading, spacing: 3) {
                    if let title { Text(title).goop(.labelStatus).foregroundStyle(ink) }
                    Text(text).goop(neutral ? .bodyMid : .bodySmall).foregroundStyle(neutral ? Goop.Color.legendText : Goop.Color.textSoft).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let action {
                    Button(action: action.perform) { Text(action.title).goop(.labelCard).foregroundStyle(Goop.Color.text1).frame(minHeight: 44).contentShape(Rectangle().inset(by: -8)) }.accessibilityIdentifier(action.identifier)
                }
                if let dismiss { Button(action: dismiss) { GoopSymbol(name: "xmark", size: 13).frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -8)) }.accessibilityLabel("Dismiss: \(text)") }
            }
            accessory()
        }.padding(.vertical, neutral ? 12 : 11).padding(.horizontal, neutral ? 14 : 13).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if neutral { RoundedRectangle(cornerRadius: Goop.Metric.radiusBanner).fill(Goop.Gradient.tile) }
                else { RoundedRectangle(cornerRadius: Goop.Metric.radiusBannerTinted).fill(tone.color.opacity(0.12)) }
            }
            .overlay {
                if !neutral { RoundedRectangle(cornerRadius: Goop.Metric.radiusBannerTinted).strokeBorder(tone.color.opacity(0.25), lineWidth: 1) }
            }.buttonStyle(.plain)
    }
}

extension GoopBanner where Accessory == EmptyView {
    init(text: String, title: String? = nil, symbol: String = "clock", tone: GoopBannerTone = .neutral,
         symbolColor: Color = Goop.Color.caution, action: GoopBannerAction? = nil, dismiss: (() -> Void)? = nil) {
        self.init(text: text, title: title, symbol: symbol, tone: tone, symbolColor: symbolColor, action: action, dismiss: dismiss) { EmptyView() }
    }
}

struct GoopFullState: View {
    var title: String
    var text: String
    var button: String?
    var action: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            GoopMark().fill(.white.opacity(0.4)).frame(width: 56, height: 56)
            Text(title).goop(.heading).multilineTextAlignment(.center).padding(.top, 20)
            Text(text).goop(.bodyMid).foregroundStyle(Goop.Color.text2).multilineTextAlignment(.center).frame(maxWidth: 300).padding(.top, 8)
            if let button { GoopButton(title: button, action: action).frame(width: 240).padding(.top, 20) }
        }.frame(maxWidth: .infinity)
    }
}

struct GoopLoading: View {
    var body: some View {
        VStack(spacing: 12) { ProgressView().tint(Goop.Color.text2); Text("Loading from your Mac").goop(.bodySmall).foregroundStyle(Goop.Color.text2) }.frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct GoopPlaceholder: View {
    var text: String
    var alignment: Alignment = .center
    var body: some View { Text(text).goop(.bodyMid).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, minHeight: 120, alignment: alignment) }
}

struct GoopSheet<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            ZStack {
                Text(title).goop(.labelNav)
                HStack { Spacer(); Button { dismiss() } label: { GoopSymbol(name: "xmark", size: 13).frame(width: 44, height: 44) }.accessibilityIdentifier("sheet-close").accessibilityLabel("Close") }
            }.frame(height: 50)
            content().padding(.horizontal, 16).padding(.bottom, 30)
        }.foregroundStyle(.white).presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Goop.Color.sheetFill).buttonStyle(.plain)
    }
}
