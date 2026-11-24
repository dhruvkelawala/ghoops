import Foundation

/// How hard a session felt, on Foster's modified CR-10 scale (effort-rating-spec.md §4.3, §5).
/// The range and the words are schema, like Strain's 0 to 21; the Mac names the scale in `edit_limits.rpe_scale`.
public enum EffortScale {
    public static let cr10 = "cr10"
    public static let values = Array(0...10)

    public static func supported(_ limits: EditLimits?) -> Bool { limits?.rpeScale == cr10 }

    /// Foster's word for a rating; 6, 8 and 9 have none.
    public static func word(_ rpe: Int) -> String? {
        switch rpe {
        case 0: "Rest"
        case 1: "Very, very easy"
        case 2: "Easy"
        case 3: "Moderate"
        case 4: "Somewhat hard"
        case 5: "Hard"
        case 7: "Very hard"
        case 10: "Maximal"
        default: nil
        }
    }

    public static func rowValue(_ rpe: Int) -> String { word(rpe).map { "\(rpe) · \($0)" } ?? "\(rpe)" }
    public static func spoken(_ rpe: Int) -> String { word(rpe).map { "\(rpe), \($0.lowercased())" } ?? "\(rpe)" }
}
