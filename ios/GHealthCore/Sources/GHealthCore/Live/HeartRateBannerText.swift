public enum HeartRateBannerText {
    public static func connected(bpm: Int?) -> String {
        bpm.map { "Live heart rate \($0) bpm" } ?? "Waiting for the first heart rate reading."
    }
}
