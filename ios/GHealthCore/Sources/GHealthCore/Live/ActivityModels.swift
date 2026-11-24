import Foundation

public struct ActivitySport: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let symbol: String
    public static let all: [Self] = [
        .init(id: "BOXING", name: "Boxing", symbol: "figure.boxing"),
        .init(id: "KICKBOXING", name: "Kickboxing", symbol: "figure.kickboxing"),
        .init(id: "MARTIAL_ARTS", name: "Martial Arts", symbol: "figure.martial.arts"),
        .init(id: "WALKING", name: "Walking", symbol: "figure.walk"),
        .init(id: "RUNNING", name: "Running", symbol: "figure.run"),
        .init(id: "WEIGHTLIFTING", name: "Weightlifting", symbol: "figure.strengthtraining.traditional"),
        .init(id: "BIKING", name: "Cycling", symbol: "figure.outdoor.cycle"),
        .init(id: "HIIT", name: "HIIT", symbol: "figure.highintensity.intervaltraining"),
        .init(id: "YOGA", name: "Yoga", symbol: "figure.yoga"),
        .init(id: "SWIMMING", name: "Swimming", symbol: "figure.pool.swim"),
        .init(id: "HIKING", name: "Hiking", symbol: "figure.hiking"),
        .init(id: "OTHER", name: "Other", symbol: "figure.mixed.cardio")
    ]
    public static func sport(_ type: String) -> Self { all.first { $0.id == type } ?? all[11] }
    public static func category(for type: String) -> String {
        let sport = sport(type)
        if ["BOXING", "KICKBOXING", "MARTIAL_ARTS"].contains(sport.id) { return "combat" }
        if sport.id == "WEIGHTLIFTING" { return "strength" }
        if ["WALKING", "HIKING"].contains(sport.id) { return "walking" }
        if ["YOGA", "OTHER"].contains(sport.id) { return "other" }
        return "cardio"
    }
}

public struct ActivityPause: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date?
    public init(start: Date, end: Date? = nil) { self.start = start; self.end = end }
}

public struct ActivityLiveValues: Codable, Sendable {
    public var strainEstimate: Double?
    public var avgHrBpm: Int?
    public var maxHrBpm: Int?
    public var samples: Int
    public init(strainEstimate: Double?, avgHrBpm: Int?, maxHrBpm: Int?, samples: Int) {
        self.strainEstimate = strainEstimate; self.avgHrBpm = avgHrBpm; self.maxHrBpm = maxHrBpm; self.samples = samples
    }
}

public struct ActivityUpload: Codable, Sendable {
    public var id: String
    public var exerciseType: String
    public var displayName: String
    public var start: Date
    public var end: Date
    public var pauses: [ActivityPause]
    public var live: ActivityLiveValues?
    public var origin: String?
    public var notes: String?
    public init(id: String, exerciseType: String, displayName: String, start: Date, end: Date, pauses: [ActivityPause] = [], live: ActivityLiveValues? = nil, origin: String? = nil, notes: String? = nil) {
        self.id = id; self.exerciseType = exerciseType; self.displayName = displayName
        self.start = start; self.end = end; self.pauses = pauses; self.live = live; self.origin = origin; self.notes = notes
    }
}

public struct ActivityRecord: Codable, Sendable {
    public var id: String
    public var exerciseType: String
    public var displayName: String
    public var start: Date
    public var end: Date
    public var pauses: [ActivityPause]
    public var createdAt: Date
    public var origin: String?
    public var notes: String?
}
public struct ActivityResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var activity: ActivityRecord
}
public struct ActivityDeleted: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var id: String
}

public enum ActivityUploadState: String, Codable, Sendable { case pending, uploaded, rejected }
public struct LocalActivity: Codable, Sendable, Identifiable {
    public var upload: ActivityUpload
    public let cycleDate: String
    public var zonesMinutes: Zones?
    public var hrSeries: [HeartRatePoint]
    public var uploadState: ActivityUploadState
    /// The Mac this activity was saved for; nil for rows written before pairing isolation.
    public var mac: PairedMac?
    public var id: String { upload.id }
    public init(upload: ActivityUpload, cycleDate: String? = nil, zonesMinutes: Zones? = nil, hrSeries: [HeartRatePoint] = [], uploadState: ActivityUploadState = .pending, mac: PairedMac? = nil) {
        self.upload = upload; self.zonesMinutes = zonesMinutes; self.hrSeries = hrSeries; self.uploadState = uploadState; self.mac = mac
        self.cycleDate = cycleDate ?? GoopFormat.dateKey(upload.start)
    }
    private enum CodingKeys: String, CodingKey { case upload, cycleDate, zonesMinutes, hrSeries, uploadState, mac }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(upload: try c.decode(ActivityUpload.self, forKey: .upload), cycleDate: try c.decodeIfPresent(String.self, forKey: .cycleDate), zonesMinutes: try c.decodeIfPresent(Zones.self, forKey: .zonesMinutes), hrSeries: try c.decode([HeartRatePoint].self, forKey: .hrSeries), uploadState: try c.decode(ActivityUploadState.self, forKey: .uploadState), mac: try c.decodeIfPresent(PairedMac.self, forKey: .mac))
    }
    public func isFinal(_ workout: Workout, now: Date) -> Bool {
        workout.confidence == .high || now.timeIntervalSince(upload.end) > 6 * 3600
    }
    public func workout() -> Workout {
        let category = ActivitySport.category(for: upload.exerciseType)
        let paused = upload.pauses.reduce(0) { $0 + ($1.end ?? upload.end).timeIntervalSince($1.start) }
        return Workout(pausedMinutes: Int(ceil(paused / 60)), kind: "goop", id: "goop-\(id)", exerciseType: upload.exerciseType, displayName: upload.displayName, category: category, cycleDate: cycleDate, start: upload.start, end: upload.end, elapsedMinutes: upload.end.timeIntervalSince(upload.start) / 60, activeMinutes: (upload.end.timeIntervalSince(upload.start) - paused) / 60, strain: upload.live?.strainEstimate, avgHrBpm: upload.live?.avgHrBpm, peakHrBpm: upload.live?.maxHrBpm, zonesMinutes: zonesMinutes, source: .goop, hasGps: false, hrSeries: hrSeries)
    }
}

public enum ActivityMerge {
    public static func workouts(server: [Workout], local: [LocalActivity], now: Date) -> [Workout] {
        var rows = server
        for entry in local {
            let index = rows.firstIndex { $0.id == "goop-\(entry.id)" }
            if let index, entry.isFinal(rows[index], now: now) { continue }
            if let index { rows[index] = entry.workout() } else { rows.append(entry.workout()) }
        }
        return rows.sorted { $0.start < $1.start }
    }
}
