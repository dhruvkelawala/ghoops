import SwiftUI

struct GoopWordmark: View {
    var size: CGFloat
    var color: Color = .white
    var body: some View {
        HStack(spacing: 0) {
            Text("gh")
            HStack(spacing: size * 0.035) {
                Circle().strokeBorder(color, lineWidth: size * 0.5 * 0.17)
                Circle().fill(color)
            }.frame(width: size * 1.035, height: size * 0.5)
                .padding(.horizontal, size * 0.015).offset(y: size * 0.03)
            Text("ps")
        }.font(Font(GoopFont.nunito(size, weight: 750))).tracking(-size * 0.01) // goop-lint: allow rawfont: wordmark is drawn at its own size
            .foregroundStyle(color).frame(height: size).fixedSize()
            .accessibilityElement(children: .ignore).accessibilityLabel("ghoops")
    }
}

struct GoopMark: Shape {
    func path(in rect: CGRect) -> Path {
        let ring = Path(ellipseIn: CGRect(x: 38.5, y: 58, width: 140, height: 140)).strokedPath(StrokeStyle(lineWidth: 22))
        let cut = Path(ellipseIn: CGRect(x: 90.5, y: 52, width: 152, height: 152))
        var path = ring.subtracting(cut).path(in: CGRect(x: 0, y: 0, width: 256, height: 256))
        path.addEllipse(in: CGRect(x: 104.5, y: 66, width: 124, height: 124))
        return path.applying(CGAffineTransform(scaleX: rect.width / 256, y: rect.height / 256).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
