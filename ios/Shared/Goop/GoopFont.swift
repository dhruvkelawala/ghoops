import CoreText
import SwiftUI
import UIKit

enum GoopFont {
    static func sofia(_ size: CGFloat) -> CTFont {
        make("SofiaSansCondensed-Regular", size: size, axes: [2003265652: 750])
    }

    static func nunito(_ size: CGFloat, weight: CGFloat) -> CTFont {
        make("NunitoSans-12ptExtraLight", size: size, axes: [2003265652: weight, 2003072104: 100, 1869640570: 12, 1498696771: 500])
    }

    private static func make(_ name: String, size: CGFloat, axes: [Int: CGFloat]) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name,
            kCTFontVariationAttribute: axes
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    #if DEBUG
    static var check: String {
        func weight(_ font: CTFont, expected: Int) -> String {
            let axes = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
            let actual = axes?[NSNumber(value: 2003265652)]?.intValue
            return actual == expected ? "wght=\(expected) OK" : "wght=\(actual.map(String.init) ?? "missing") FAIL"
        }
        return weight(sofia(30), expected: 750) + ", " + weight(nunito(22, weight: 650), expected: 650)
    }
    #endif
}

struct GoopTextStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    var size: CGFloat
    var weight: CGFloat = 550
    var sofia = false
    var tracking: CGFloat = 0
    var cap: CGFloat = 1.6
    var lineHeight: CGFloat? = nil

    func body(content: Content) -> some View {
        let factor = scale(for: typeSize)
        let ctFont = font(scale: factor)
        content.font(Font(ctFont)).tracking(tracking * size * factor).lineSpacing(lineSpacing(ctFont, scale: factor))
    }
    func scale(for typeSize: DynamicTypeSize) -> CGFloat {
        min(cap, UIFontMetrics(forTextStyle: .body).scaledValue(for: 1, compatibleWith: UITraitCollection(preferredContentSizeCategory: typeSize.contentSizeCategory)))
    }
    func font(scale: CGFloat) -> CTFont { sofia ? GoopFont.sofia(size * scale) : GoopFont.nunito(size * scale, weight: weight) }
    func lineSpacing(_ font: CTFont, scale: CGFloat) -> CGFloat {
        max(0, (lineHeight ?? 0) * scale - CTFontGetAscent(font) - CTFontGetDescent(font) - CTFontGetLeading(font))
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
