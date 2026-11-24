public enum HealthText {
    public static func attentionSpoken(_ c: ScoreConstants?) -> String {
        guard let nights = c?.vitals?.attentionNights else { return "outside your typical range on recent nights" }
        return "outside your typical range for \(nights) nights in a row"
    }

    /// The weekly HRV tile's title, or nil when the Mac sends no `hrv_trend` constants.
    public static func hrvTrendTitle(_ c: ScoreConstants?) -> String? {
        c?.hrvTrend.map { "HRV \($0.days)-day average" }
    }

    /// The weekly HRV tile's chip when the week has too few nights for an average.
    public static func nightsChip(nights: Int, days: Int) -> String {
        "\(nights) of \(days) nights"
    }
}
