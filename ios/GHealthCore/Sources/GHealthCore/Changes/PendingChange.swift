import Foundation

public struct PendingChange: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case edit, merge, delete, undo, restore, name, add, sleep, rate, journal }
    public enum State: String, Codable, Sendable { case sending, waiting, accepted }
    public enum Request: Codable, Sendable {
        case putSleepEdit(String, SleepEditBody)
        case deleteSleepEdit(String)
        case putEdit(String, EditBody)
        case deleteEdit(String)
        case postActivity(ActivityUpload)
        case putRating(String, RatingBody)
        case putJournal(String, JournalBody)
    }
    public var id: UUID
    public var kind: Kind
    public var request: Request
    public var targets: [String]
    public var cycleDates: [String]
    public var name: String
    public var patch: WorkoutPatch
    public var sleepPatch: SleepPatch?
    public var journalPatch: JournalPatch?
    public var kept: Workout?
    public var serverURL: String
    var profileId: String?
    public var createdAt: Date
    public var acceptedAt: Date?
    public var attempts: Int
    public var state: State
    public var undoRequested: Bool
    public var acceptedEdit: WorkoutEdit?
    public var replayBeforeUndo: Request?

    private enum CodingKeys: String, CodingKey {
        case id, kind, request, targets, cycleDates, name, patch, sleepPatch, journalPatch, kept, createdAt, acceptedAt, attempts, state, undoRequested, acceptedEdit, replayBeforeUndo, profileId
        case serverURL = "serverUrl"
    }

    public init(id: UUID = UUID(), kind: Kind, request: Request, targets: [String], cycleDates: [String], name: String, patch: WorkoutPatch = WorkoutPatch(), sleepPatch: SleepPatch? = nil, journalPatch: JournalPatch? = nil, kept: Workout? = nil, serverURL: String, createdAt: Date) {
        self.id = id; self.kind = kind; self.request = request; self.targets = targets
        self.sleepPatch = sleepPatch; self.journalPatch = journalPatch
        self.cycleDates = cycleDates; self.name = name; self.patch = patch; self.kept = kept
        self.serverURL = serverURL; self.createdAt = createdAt
        acceptedAt = nil; attempts = 0; state = .sending; undoRequested = false
        acceptedEdit = nil; replayBeforeUndo = nil
    }

    var mac: PairedMac { PairedMac(url: serverURL, name: "", profile: profileId) }

    mutating func bind(to mac: PairedMac) {
        serverURL = mac.url
        profileId = profileId ?? mac.profile
    }
}

public struct WorkoutPatch: Codable, Sendable {
    public var remove: [String]
    public var upsert: [Workout]
    public var updating: [String]
    public init(remove: [String] = [], upsert: [Workout] = [], updating: [String] = []) {
        self.remove = remove; self.upsert = upsert; self.updating = updating
    }
}
