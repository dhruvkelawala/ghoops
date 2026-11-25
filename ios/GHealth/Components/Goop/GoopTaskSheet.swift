import SwiftUI

struct GoopCommit {
    var title: String
    var symbol: String
    var identifier: String
    var enabled = true
    var accessibilityLabel: String? = nil
    var action: () -> Void
}

struct GoopTaskSheet<Content: View>: View {
    var title: String
    var back: (() -> Void)? = nil
    var closeIdentifier = "sheet-close"
    var commit: GoopCommit? = nil
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).goop(.labelNav)
                HStack {
                    if let back {
                        Button(action: back) { GoopSymbol(name: "chevron.left", size: 21, color: Goop.Color.text1).frame(width: 44, height: 44) }.accessibilityIdentifier("sheet-back").accessibilityLabel("Back")
                    }
                    Spacer()
                    Button { dismiss() } label: { GoopSymbol(name: "xmark", size: 13).frame(width: 44, height: 44) }.accessibilityIdentifier(closeIdentifier).accessibilityLabel("Close")
                }
            }.frame(height: 50)
            ScrollView { content().padding(.horizontal, 16).padding(.bottom, 16) }.scrollDismissesKeyboard(.interactively).id(title)
        }
        .safeAreaInset(edge: .bottom) {
            if let commit {
                Button(action: commit.action) {
                    HStack(spacing: 10) { GoopSymbol(name: commit.symbol, size: 18, color: Goop.Color.text1); Text(commit.title).goop(.labelCommit) }
                        .frame(maxWidth: .infinity).frame(height: 54).background(Goop.Color.strain, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusButton))
                }.accessibilityIdentifier(commit.identifier).accessibilityLabel(commit.accessibilityLabel ?? commit.title).disabled(!commit.enabled).opacity(commit.enabled ? 1 : Goop.Opacity.disabled)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8).background(Goop.Color.sheetBottom)
            }
        }
        .foregroundStyle(Goop.Color.text1).buttonStyle(.plain).presentationDetents([.large]).presentationDragIndicator(.visible)
        .presentationCornerRadius(Goop.Metric.radiusSheet).presentationBackground(Goop.Gradient.sheet)
    }
}

struct GoopSectionLabel: View {
    var title: String
    var body: some View {
        Text(title).goop(.labelCard).foregroundStyle(Goop.Color.iconMuted).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

struct GoopSearchField: View {
    var prompt: String
    @Binding var text: String
    var identifier: String
    var body: some View {
        HStack(spacing: 10) {
            GoopSymbol(name: "magnifyingglass", size: 15, color: Goop.Color.chevronDial)
            TextField(prompt, text: $text).goop(.bodyMid).tint(Goop.Color.strain).autocorrectionDisabled().accessibilityIdentifier(identifier)
        }.padding(.horizontal, 12).frame(height: 40).background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
    }
}

struct GoopChoiceRow: View {
    var symbol: String
    var title: String
    var note: String? = nil
    var selected: Bool
    var identifier: String
    var number: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if let number { Text(number).goop(.valueRow).foregroundStyle(selected ? Goop.Color.strainLight : Goop.Color.textSoft) }
                    else { GoopSymbol(name: symbol, size: 22, color: selected ? Goop.Color.strainLight : Goop.Color.textSoft) }
                }.frame(width: 34)
                Text(title).goop(.labelStage)
                Spacer(minLength: 0)
                if let note { Text(note).goop(.rowNote).foregroundStyle(Goop.Color.chevronDial) }
                if selected { GoopSymbol(name: "checkmark.circle.fill", size: 20, color: Goop.Color.strain) }
            }.padding(.horizontal, 12).frame(height: 52)
                .background(selected ? Goop.Color.strain.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusChoice))
                .overlay { if selected { RoundedRectangle(cornerRadius: Goop.Metric.radiusChoice).strokeBorder(Goop.Color.strain, lineWidth: 1.5) } }
                .overlay(alignment: .bottom) { if !selected { Rectangle().fill(Goop.Color.contributorBorder).frame(height: 1) } }
        }.accessibilityIdentifier(identifier).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension GoopChoiceRow {
    /// A choice between numbers, such as the effort rating: the number takes the symbol's slot (DESIGN.md, Task controls).
    init(number: String, title: String, selected: Bool, identifier: String, action: @escaping () -> Void) {
        self.init(symbol: "", title: title, selected: selected, identifier: identifier, number: number, action: action)
    }
}
