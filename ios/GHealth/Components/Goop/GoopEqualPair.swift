import SwiftUI

struct GoopEqualPair: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = max(ideal * 2 + spacing, proposal.width ?? 0)
        let child = ProposedViewSize(width: (width - spacing) / 2, height: proposal.height)
        return CGSize(width: width, height: subviews.map { $0.sizeThatFits(child).height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = (bounds.width - spacing) / 2
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}
