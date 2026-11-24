/// Features that ship dark: on in Debug, off in Release until their last step removes the flag.
enum GoopFeature {
    #if DEBUG
    static let journal = true
    static let effortRating = true
    static let livePolish = true
    #else
    static let journal = false
    static let effortRating = false
    static let livePolish = false
    #endif
}
