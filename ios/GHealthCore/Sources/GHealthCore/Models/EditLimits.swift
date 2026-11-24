import Foundation

/// The Mac's request limits (contract §5.11). Missing limits stay unknown.
public struct EditLimits: Codable, Sendable, Equatable {
    public var sleepMinMinutes: Int?
    public var horizonDays: Int
    public var shiftMinutes: Int
    public var mergeGapMinutes: Int
    public var mergeMaxIds: Int
    public var notesMaxChars: Int
    public var activeMinMinutes: Int
    public var activeMaxMinutes: Int
    public var heartRateSpanMaxMinutes: Int
    /// The scale ratings use (`"cr10"`), or nil when the Mac takes no ratings.
    public var rpeScale: String?

    public init(horizonDays: Int, shiftMinutes: Int, mergeGapMinutes: Int, mergeMaxIds: Int, notesMaxChars: Int, activeMinMinutes: Int, activeMaxMinutes: Int, heartRateSpanMaxMinutes: Int, sleepMinMinutes: Int? = nil, rpeScale: String? = nil) {
        self.sleepMinMinutes = sleepMinMinutes; self.rpeScale = rpeScale
        self.horizonDays = horizonDays; self.shiftMinutes = shiftMinutes
        self.mergeGapMinutes = mergeGapMinutes; self.mergeMaxIds = mergeMaxIds
        self.notesMaxChars = notesMaxChars; self.activeMinMinutes = activeMinMinutes
        self.activeMaxMinutes = activeMaxMinutes; self.heartRateSpanMaxMinutes = heartRateSpanMaxMinutes
    }
    public static func editable(cycleDate: String, defaultDate: String, limits: EditLimits?) -> Bool {
        limits.map { cycleDate >= $0.firstEditableDate(defaultDate: defaultDate) } ?? true
    }
    public func firstEditableDate(defaultDate: String) -> String { GoopFormat.addingDays(1 - horizonDays, to: defaultDate) }
    public func earliestStart(now: Date) -> Date { now.addingTimeInterval(-Double(horizonDays) * 86400) }
}

public enum EditNotes {
    /// The longest whole-Character prefix within the Unicode scalar limit; unchanged when nil.
    public static func capped(_ value: String, max: Int?) -> String {
        guard let max else { return value }
        var count = 0
        return String(value.prefix { character in
            count += character.unicodeScalars.count
            return count <= max
        })
    }
    /// The part of `insertion` that fits beside `kept`, the text that stays. Empty when the note is full.
    public static func fitted(_ insertion: String, keeping kept: String, max: Int?) -> String {
        guard let max else { return insertion }
        return capped(insertion, max: Swift.max(0, max - kept.unicodeScalars.count))
    }
    /// Cuts the end of `before`, the text just entered before the caret, until the note fits.
    public static func trimmed(before: String, after: String, max: Int?) -> (before: String, after: String) {
        guard let max else { return (before, after) }
        let after = capped(after, max: max)
        return (fitted(before, keeping: after, max: max), after)
    }
}
