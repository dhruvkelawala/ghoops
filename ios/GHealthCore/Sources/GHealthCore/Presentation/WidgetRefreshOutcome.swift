public enum WidgetRefreshOutcome: Equatable, Sendable {
    case keepCache, unpaired, revoke

    public init(error: any Error) {
        switch error as? ClientError {
        case .unauthorized: self = .revoke
        case .profileMismatch: self = .unpaired
        default: self = .keepCache
        }
    }
}
