import Foundation

public enum SuggestionText {
    public static func note(effortStart: Date) -> String {
        "Usual on \(GoopFormat.weekdayShort(effortStart))"
    }

    public static func accessibility(sport: String, effortStart: Date) -> String {
        "\(sport), usual on \(GoopFormat.weekdayLong(effortStart))"
    }
}
