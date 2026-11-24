import Foundation

public struct HeartRateSample: Codable, Sendable, Equatable {
    public var t: Date
    public var bpm: Double
    public init(t: Date, bpm: Double) { self.t = t; self.bpm = bpm }
}
public struct HeartRateDevice: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
public enum HeartRateConnection: Sendable, Equatable {
    case searching, connected(String, Int?), notFound, poweredOff, denied
    case choosing([HeartRateDevice])
}
@MainActor public protocol HeartRateSource: AnyObject {
    var state: HeartRateConnection { get }
    var onSample: ((HeartRateSample) -> Void)? { get set }
    var onState: ((HeartRateConnection) -> Void)? { get set }
    func start()
    func stop()
    func connect(id: UUID)
}

public enum HeartRateMeasurement {
    public static func parse(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        let wide = flags & 1 != 0
        let needed = (wide ? 3 : 2) + (flags & 8 != 0 ? 2 : 0)
        guard bytes.count >= needed else { return nil }
        if flags & 4 != 0 && flags & 2 == 0 { return nil }
        let bpm = wide ? Int(bytes[1]) | Int(bytes[2]) << 8 : Int(bytes[1])
        return (1...250).contains(bpm) ? bpm : nil
    }
}

#if DEBUG
@MainActor public final class FixtureHeartRateSource: HeartRateSource {
    public private(set) var state: HeartRateConnection = .searching { didSet { onState?(state) } }
    public var onSample: ((HeartRateSample) -> Void)?
    public var onState: ((HeartRateConnection) -> Void)?
    private let series: [Double]
    private var task: Task<Void, Never>?
    public init(series: [Double]) { self.series = series }
    public func start() {
        guard task == nil else { return }
        guard !series.isEmpty else { state = .notFound; return }
        state = .connected("Fitbit Air", Int(series[0]))
        task = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                guard let self else { return }
                let bpm = self.series[i % self.series.count]
                self.state = .connected("Fitbit Air", Int(bpm))
                self.onSample?(HeartRateSample(t: .now, bpm: bpm))
                i += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    public func stop() { task?.cancel(); task = nil }
    public func connect(id: UUID) { start() }
}
#endif
