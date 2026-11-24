import SwiftUI
import UIKit
import GHealthCore

struct GoopNotesField: View {
    @Binding var text: String
    var limit: Int?
    var identifier = "edit-notes"
    @State private var inputWasCut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotesTextView(text: $text, inputWasCut: $inputWasCut, limit: limit, identifier: identifier)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text("Add a note").goop(.bodyMid).foregroundStyle(Goop.Color.text3).allowsHitTesting(false).accessibilityHidden(true) }
                }
                .padding(.horizontal, 12).padding(.vertical, 15).frame(minHeight: 50)
                .background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
            if let limit, text.unicodeScalars.count == limit || inputWasCut {
                Text("Notes can hold up to \(limit) characters.").goop(.bodySmall).foregroundStyle(Goop.Color.text2)
                    .accessibilityIdentifier("edit-notes-limit")
            }
        }
    }
}

private struct NotesTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var inputWasCut: Bool
    var limit: Int?
    var identifier: String
    private static let maxLines: CGFloat = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.scrollsToTop = false
        view.isScrollEnabled = false
        view.accessibilityIdentifier = identifier
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let style = Goop.TextStyle.bodyMid.modifier
        let scale = style.scale(for: context.environment.dynamicTypeSize)
        let font = style.font(scale: scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing(font, scale: scale)
        coordinator.attributes = [.font: font as UIFont, .foregroundColor: UIColor(Goop.Color.bodyText), .paragraphStyle: paragraph, .kern: style.tracking * style.size * scale]
        coordinator.lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        coordinator.lineSpacing = paragraph.lineSpacing
        view.tintColor = UIColor(Goop.Color.strain)
        view.isEditable = context.environment.isEnabled
        let restyle = coordinator.scale != scale
        coordinator.scale = scale
        guard view.markedTextRange == nil else { return }
        if view.text != text {
            view.attributedText = NSAttributedString(string: text, attributes: coordinator.attributes)
            DispatchQueue.main.async { inputWasCut = false }
        } else if restyle {
            let selection = view.selectedRange
            view.attributedText = NSAttributedString(string: view.text, attributes: coordinator.attributes)
            view.selectedRange = selection
        }
        view.typingAttributes = coordinator.attributes
        view.accessibilityLabel = text.isEmpty ? "Add a note" : nil
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        let coordinator = context.coordinator
        guard let width = proposal.width, width.isFinite, width > 0, coordinator.lineHeight > 0 else { return nil }
        let tallest = Self.maxLines * coordinator.lineHeight + (Self.maxLines - 1) * coordinator.lineSpacing
        let content = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        view.isScrollEnabled = content > tallest
        return CGSize(width: width, height: min(max(content, coordinator.lineHeight), tallest))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NotesTextView
        var attributes: [NSAttributedString.Key: Any] = [:]
        var lineHeight: CGFloat = 0
        var lineSpacing: CGFloat = 0
        var scale: CGFloat?
        init(_ parent: NotesTextView) { self.parent = parent }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard parent.limit != nil, view.markedTextRange == nil, let swiftRange = Range(range, in: view.text) else { return true }
            let fitted = EditNotes.fitted(replacement, keeping: view.text.replacingCharacters(in: swiftRange, with: ""), max: parent.limit)
            guard fitted != replacement else { parent.inputWasCut = false; return true }
            if !fitted.isEmpty, let start = view.position(from: view.beginningOfDocument, offset: range.location),
               let end = view.position(from: start, offset: range.length), let target = view.textRange(from: start, to: end) {
                view.replace(target, withText: fitted)
                publish(view)
            }
            parent.inputWasCut = true
            return false
        }
        func textViewDidChange(_ view: UITextView) {
            if let limit = parent.limit, view.markedTextRange == nil, view.text.unicodeScalars.count > limit { trim(view) }
            publish(view)
        }
        private func publish(_ view: UITextView) {
            let note = EditNotes.capped(view.text, max: parent.limit)
            if parent.text != note { parent.text = note }
            view.accessibilityLabel = note.isEmpty ? "Add a note" : nil
        }
        private func trim(_ view: UITextView) {
            let text = view.text ?? ""
            let caret = Range(view.selectedRange, in: text)?.upperBound ?? text.endIndex
            let fit = EditNotes.trimmed(before: String(text[..<caret]), after: String(text[caret...]), max: parent.limit)
            view.attributedText = NSAttributedString(string: fit.before + fit.after, attributes: attributes)
            view.selectedRange = NSRange(location: (fit.before as NSString).length, length: 0)
            parent.inputWasCut = true
        }
    }
}
