import SwiftUI
import GHealthCore

enum GoopRowDisclosure { case none, push }

struct GoopRow<Trailing: View>: View {
    var label: String
    var disclosure: GoopRowDisclosure = .none
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var trailing: () -> Trailing
    init(_ label: String, disclosure: GoopRowDisclosure = .none, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.disclosure = disclosure
        self.alignment = alignment
        self.trailing = trailing
    }
    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(label).goop(.labelCard).layoutPriority(1)
            Spacer(minLength: 0)
            HStack(alignment: alignment, spacing: 8) {
                trailing().multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                switch disclosure {
                case .none: EmptyView()
                case .push: GoopSymbol(name: "chevron.right", size: 12, color: Goop.Color.textSoft)
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 48)
            .background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
    }
}

struct GoopRowValue: View {
    var text: String
    var body: some View { Text(text).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft) }
}

extension GoopRow where Trailing == GoopRowValue {
    init(_ label: String, value: String, disclosure: GoopRowDisclosure = .none) {
        self.init(label, disclosure: disclosure) { GoopRowValue(text: value) }
    }
}

struct GoopTimeRow: View {
    var label: String
    @Binding var time: Date
    var range: ClosedRange<Date>
    var identifier: String
    var date: String?
    init(_ label: String, time: Binding<Date>, range: ClosedRange<Date>, identifier: String, date: String? = nil) {
        self.label = label
        self._time = time
        self.range = range
        self.identifier = identifier
        self.date = date
    }
    var body: some View {
        GoopRow(label, alignment: .center) {
            if let date {
                Text(date).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft).accessibilityIdentifier("\(identifier)-date")
            }
            DatePicker(label, selection: $time, in: range, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact).labelsHidden().tint(Goop.Color.strain)
                .environment(\.timeZone, GoopFormat.london).accessibilityIdentifier(identifier)
                .accessibilityLabel(date == nil ? label.capitalized : "\(label.capitalized), \(ActivityTime.spokenDate(time))")
        }
    }
}
