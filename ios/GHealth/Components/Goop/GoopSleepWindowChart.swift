import SwiftUI
import GHealthCore

struct GoopSleepWindowChart: View {
    var draft: SleepEditDraft
    var heartRate: [HeartRatePoint] = []
    var heartRateMessage: String? = nil
    var onChange: (SleepEditDraft) -> Void
    @State private var snap: Date?
    var body: some View {
        GeometryReader { geometry in
            GoopSleepChart(sleep: SleepPatch(draft).apply(to: draft.sleep), visibleRange: draft.bounds.span, googleWindow: draft.google.window, heartRate: heartRate, heartRateMessage: heartRateMessage)
            handle(start: true, width: geometry.size.width)
            handle(start: false, width: geometry.size.width)
        }.frame(height: 268).coordinateSpace(name: "sleep-window")
            .accessibilityElement(children: .contain).accessibilityIdentifier("sleep-edit-chart")
    }
    private func handle(start: Bool, width: CGFloat) -> some View {
        let date = start ? draft.window.start : draft.window.end
        let plotWidth = max(1, width - 60)
        let range = draft.bounds.span
        let x = 60 + date.timeIntervalSince(range.start) / max(60, range.duration) * plotWidth
        return Color.clear.frame(width: 44, height: 224).contentShape(Rectangle()).position(x: x, y: 112)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("sleep-window")).onChanged { value in
                let fraction = min(1, max(0, (value.location.x - 60) / plotWidth))
                move(start: start, to: range.start.addingTimeInterval(fraction * range.duration))
            }.onEnded { _ in snap = nil })
            .accessibilityElement().accessibilityLabel("\(start ? "Bedtime" : "Wake"), \(GoopFormat.time(date))")
            .accessibilityIdentifier("sleep-edit-handle-\(start ? "start" : "end")")
            .accessibilityAdjustableAction { direction in move(start: start, to: date.addingTimeInterval(direction == .increment ? 60 : -60)) }
    }
    private func move(start: Bool, to date: Date) {
        var next = draft
        if start { next.moveStart(to: date) } else { next.moveEnd(to: date) }
        let minute = start ? next.window.start : next.window.end
        if snap != minute { UISelectionFeedbackGenerator().selectionChanged(); snap = minute }
        onChange(next)
    }
}
