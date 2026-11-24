import Foundation
import Testing
@testable import GHealthCore

private let editID = "7300000000000000101"
private let neighbourID = "7300000000000000102"
private func editSnapshot(_ state: String = "edited") throws -> Snapshot { try fixture("edits/snapshot_\(state).json", as: Snapshot.self) }
private func editWorkout(_ state: String = "edited") throws -> Workout { try #require(editSnapshot(state).workouts.workouts.first { $0.id == editID }) }
private func editHeartRate() throws -> HeartRateBody { try fixture("edits/heart_rate_tue.json", as: HeartRateBody.self) }
private func at(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private func zones(_ value: Zones?) -> [Int]? { value.map { [$0.below, $0.z1, $0.z2, $0.z3, $0.z4, $0.z5] } }

@Test func editModelsDecodeNewAndLegacyBodies() throws {
    let workout = try editWorkout("merged")
    #expect(workout.edited == true && workout.edit?.exerciseType == "BOXING")
    #expect(workout.original?.exerciseType == "KICKBOXING")
    #expect(workout.merged.first?.id == neighbourID)
    #expect(workout.notes == "Sparring, 6 rounds of 3 minutes.")
    var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(workout)) as? [String: Any])
    for key in ["original", "edit", "edited", "merged", "notes", "origin", "pauses"] { object.removeValue(forKey: key) }
    let old = try JSONCoding.decoder().decode(Workout.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.original == nil && old.edit == nil && old.edited == nil && old.notes == nil && old.origin == nil)
    #expect(old.merged.isEmpty && old.pauses.isEmpty)
    let aliases = try editSnapshot("alias").scoreConfig?.sportAliases
    #expect(aliases == ["KICKBOXING": "BOXING"])
    let legacyConfig = Data(#"{"sleep_base_need_minutes":450,"trimp_profile":"banister_b192"}"#.utf8)
    #expect(try JSONCoding.decoder().decode(ScoreConfig.self, from: legacyConfig).sportAliases.isEmpty)
    let upload: ActivityUpload = try fixture("activities/valid.json", as: ActivityUpload.self)
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(upload)) as? [String: Any])
    #expect(encoded["origin"] == nil && encoded["notes"] == nil)
}

@Test func windowEstimatorMatchesEveryGoPreviewCase() throws {
    struct Parity: Decodable {
        struct Case: Decodable {
            struct Expected: Decodable {
                var strain: Double?; var trimp: Double?; var avgHrBpm: Int?; var peakHrBpm: Int?
                var zonesMinutes: Zones?; var hrCoverage: Double?; var elapsedMinutes: Double; var pausedMinutes: Int
            }
            var name: String; var heartRate: HeartRateBody; var window: ActivityWindow; var pauses: [ActivityPause]; var expected: Expected
        }
        var cases: [Case]
    }
    for c in try fixture("edits/preview_parity.json", as: Parity.self).cases {
        let result = WindowEstimator(heartRate: c.heartRate).estimate(start: c.window.start, end: c.window.end, pauses: c.pauses)
        #expect(result.strain == c.expected.strain, "\(c.name)")
        #expect(result.trimp == c.expected.trimp, "\(c.name)")
        #expect(result.avgHrBpm == c.expected.avgHrBpm && result.peakHrBpm == c.expected.peakHrBpm, "\(c.name)")
        #expect(zones(result.zonesMinutes) == zones(c.expected.zonesMinutes), "\(c.name)")
        #expect(result.hrCoverage == c.expected.hrCoverage, "\(c.name)")
        #expect(result.elapsedMinutes == c.expected.elapsedMinutes && result.pausedMinutes == c.expected.pausedMinutes, "\(c.name)")
    }
}

@Test func windowEstimatorMatchesGoStrainVectors() throws {
    struct Vectors: Decodable {
        struct Case: Decodable {
            struct Input: Decodable { var restingHr: Int; var maxHr: Int; var minuteAvgBpm: [Double]; var expectedMinutes: Int }
            struct Expected: Decodable { var trimp: Double; var strain: Double?; var hrCoverage: Double; var zonesMinutes: Zones }
            var name: String; var input: Input; var expected: Expected
        }
        struct Scale: Decodable { var trimp: Double; var strain: Double }
        var cases: [Case]; var trimpToStrain: [Scale]
    }
    let vectors = try fixture("scores/strain.json", as: Vectors.self)
    for c in vectors.cases {
        var hr = try editHeartRate()
        hr.restingHrBpm = c.input.restingHr; hr.maxHrBpm = c.input.maxHr
        hr.minutes = c.input.minuteAvgBpm.enumerated().map { HeartRateMinute(t: hr.start.addingTimeInterval(Double($0.offset) * 60), avgBpm: $0.element, maxBpm: Int($0.element.rounded())) }
        let result = WindowEstimator(heartRate: hr).estimate(start: hr.start, end: hr.start.addingTimeInterval(Double(c.input.expectedMinutes) * 60))
        #expect(result.strain == c.expected.strain, "\(c.name)")
        #expect(result.hrCoverage == c.expected.hrCoverage, "\(c.name)")
        if !hr.minutes.isEmpty {
            #expect(result.trimp == c.expected.trimp, "\(c.name)")
            #expect(zones(result.zonesMinutes) == zones(c.expected.zonesMinutes), "\(c.name)")
        } else { #expect(result.trimp == nil && result.zonesMinutes == nil) }
    }
    for c in vectors.trimpToStrain { #expect(StrainMath.strain(trimp: c.trimp, scale: try engineConstants().strain.scale) == c.strain) }
}

@Test func editDraftPreservesStoredEditsForDeleteAndUndo() throws {
    for state in ["unedited", "edited", "merged", "alias"] {
        let snapshot = try editSnapshot(state)
        let workout = try editWorkout(state)
        var draft = EditDraft(workout: workout, workouts: snapshot.workouts.workouts, heartRate: try editHeartRate(), limits: try reportedEditLimits(), now: at("2026-03-12T20:30:00Z"))
        #expect(!draft.hasChanges, "\(state)")
        draft.sport = "RUNNING"; draft.notes = " Unsaved "
        draft.window.start = draft.window.start.addingTimeInterval(-60)
        #expect(draft.hasChanges)
        #expect(draft.deleteBody == EditBody(workout.edit, hidden: true))
        #expect(draft.undoRequest == (workout.edit.map { .put(EditBody($0)) } ?? .delete))
        #expect(draft.restore == .delete)
        if let original = workout.original {
            draft.sport = original.exerciseType; draft.window = ActivityWindow(start: original.start, end: original.end)
            #expect(draft.body.exerciseType == nil && draft.body.start == nil && draft.body.end == nil)
        }
    }
    var draft = EditDraft(workout: try editWorkout("unedited"), workouts: [], heartRate: try editHeartRate(), limits: try reportedEditLimits(), now: at("2026-03-12T20:30:00Z"))
    draft.notes = " \n Sparring \n "
    #expect(draft.body.notes == "Sparring")
    draft.notes = " \n "
    #expect(draft.body.notes == nil)
    draft.notes = String(repeating: "a", count: 501)
    #expect(draft.notes.count == 500)
    let object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(draft.body)) as? [String: Any])
    #expect(object.count == 6)
    #expect(object["exercise_type"] is NSNull && object["start"] is NSNull && object["end"] is NSNull)
}

@Test func mergeCandidatesUseSavedWindowAndInclusiveGap() throws {
    let target = try editWorkout()
    for kind in ["recorded", "goop", "detected"] {
        var candidate = target; candidate.id = neighbourID; candidate.kind = kind
        candidate.start = target.end.addingTimeInterval(15 * 60); candidate.end = candidate.start.addingTimeInterval(600)
        var draft = EditDraft(workout: target, workouts: [target, candidate], heartRate: try editHeartRate(), limits: try reportedEditLimits(), now: at("2026-03-12T20:30:00Z"))
        #expect(draft.next?.id == neighbourID)
        draft.window.start = target.start.addingTimeInterval(-600)
        let merge = draft.mergeBody(candidate)
        #expect(merge.start == draft.window.start && merge.end == candidate.end)
        #expect(merge.mergeWith == (kind == "detected" ? [] : [neighbourID]))
        candidate.start = candidate.start.addingTimeInterval(1)
        #expect(EditDraft.candidates(for: target, workouts: [candidate], gapMinutes: try reportedEditLimits().mergeGapMinutes).next == nil)
        candidate.end = target.start.addingTimeInterval(-15 * 60); candidate.start = candidate.end.addingTimeInterval(-600)
        #expect(EditDraft.candidates(for: target, workouts: [candidate], gapMinutes: try reportedEditLimits().mergeGapMinutes).previous?.id == neighbourID)
        candidate.end = candidate.end.addingTimeInterval(-1)
        #expect(EditDraft.candidates(for: target, workouts: [candidate], gapMinutes: try reportedEditLimits().mergeGapMinutes).previous == nil)
        candidate.start = target.start; candidate.end = target.end
        #expect(EditDraft.candidates(for: target, workouts: [candidate], gapMinutes: try reportedEditLimits().mergeGapMinutes).next?.id == neighbourID)
        candidate.cycleDate = "2026-03-09"
        #expect(EditDraft.candidates(for: target, workouts: [candidate], gapMinutes: try reportedEditLimits().mergeGapMinutes).next == nil)
    }
    var effort = target; effort.kind = "detected"
    #expect(EditDraft.candidates(for: effort, workouts: [target], gapMinutes: try reportedEditLimits().mergeGapMinutes).next == nil)
    var unknown = target; unknown.id = "other"; unknown.kind = "future"
    #expect(EditDraft.candidates(for: target, workouts: [unknown], gapMinutes: try reportedEditLimits().mergeGapMinutes).next == nil)
}

@Test func addDraftDefaultsSnapsAndKeepsRetryIdentity() throws {
    let snapshot = try editSnapshot()
    var draft = AddDraft(defaultDate: "2026-03-12", workouts: snapshot.workouts.workouts, now: snapshot.generatedAt, limits: try reportedEditLimits(), id: "retry-id")
    #expect(draft.days == ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12"])
    #expect(draft.day == "2026-03-12" && draft.sport == nil)
    draft.sport = "WALKING"
    draft.snap(to: try #require(draft.efforts.first))
    #expect(draft.effortLabel == "07:10 to 07:41")
    #expect(draft.hint == "Snapped to an effort ghoops found today. Drag a dashed edge to adjust.")
    draft.selectDay("2026-03-11")
    #expect(draft.effortLabel == "18:04 to 19:04")
    #expect(draft.hint.contains("on Wednesday"))
    draft.window.start = draft.window.start.addingTimeInterval(-60)
    #expect(draft.effortLabel == "1 found" && draft.hint == "Drag a dashed edge, or set the times below.")
    draft.selectDay("2026-03-09")
    #expect(draft.effortLabel == "None found")
    #expect(GoopFormat.time(draft.window.start) == "18:00" && GoopFormat.time(draft.window.end) == "19:00")
    #expect(draft.hint == "ghoops found no untracked effort on Monday. Drag a dashed edge, or set the times below.")
    #expect(draft.upload?.id == "retry-id" && draft.upload?.origin == "added" && draft.upload?.live == nil && draft.upload?.pauses.isEmpty == true)
    draft.didSave(); #expect(draft.upload?.id != "retry-id")
    let empty = AddDraft(defaultDate: "2026-03-12", workouts: [], now: snapshot.generatedAt.addingTimeInterval(42), limits: try reportedEditLimits())
    #expect(empty.sport == nil && empty.day == "2026-03-12")
    #expect(GoopFormat.time(empty.window.start) == "19:30" && GoopFormat.time(empty.window.end) == "20:30")
}

@Test func timePickerMapsAcrossMidnightAndWindowRespectsLimits() throws {
    let span = DateInterval(start: at("2026-03-10T21:00:00Z"), end: at("2026-03-11T05:00:00Z"))
    #expect(ActivityTime.picker(at("2026-11-12T01:15:00Z"), within: span) == at("2026-03-11T01:15:00Z"))
    #expect(ActivityTime.picker(at("2026-11-12T20:30:00Z"), within: span) == span.start)
    #expect(ActivityTime.picker(at("2026-11-12T06:00:00Z"), within: span) == span.end)
    let limits = try reportedEditLimits()
    func bounds(_ span: DateInterval) -> EditBounds { EditBounds(span: span, activeMin: Double(limits.activeMinMinutes) * 60, activeMax: Double(limits.activeMaxMinutes) * 60, originals: [], covers: []) }
    var window = ActivityWindow(start: span.start, end: span.end)
    window.moveStart(to: span.end, bounds: bounds(span))
    #expect(window.start == span.end.addingTimeInterval(-60))
    window.moveEnd(to: span.start, bounds: bounds(span))
    #expect(window.end == window.start.addingTimeInterval(60))
    let wide = DateInterval(start: span.start, duration: 18 * 3600)
    window = ActivityWindow(start: wide.start, end: wide.end)
    window.moveEnd(to: wide.end, bounds: bounds(wide))
    #expect(window.end.timeIntervalSince(window.start) == 12 * 3600)
    window.moveStart(to: window.end.addingTimeInterval(-60), bounds: bounds(wide), pauses: [ActivityPause(start: window.end.addingTimeInterval(-60), end: window.end)])
    #expect(window.start == window.end.addingTimeInterval(-120))
}

@Test func removedLocalActivityCannotReappearAfterServerEdit() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ActivityStore(directory: dir)
    let upload: ActivityUpload = try fixture("edits/requests/add.json", as: ActivityUpload.self)
    let now = at("2026-03-12T20:30:00Z")
    try await store.save(LocalActivity(upload: upload), now: now)
    #expect(ActivityMerge.workouts(server: [], local: try await store.activities(now: now), now: now).count == 1)
    try await store.delete(id: upload.id, now: now)
    #expect(ActivityMerge.workouts(server: [], local: try await store.activities(now: now), now: now).isEmpty)
}

#if DEBUG
@Test func fixtureEditAPIMatchesBodiesAndPreservesMergedDeleteUndo() async throws {
    let api = FixtureEditAPI(directory: fixtureRoot.appendingPathComponent("edits"))
    var wrong: EditBody = try fixture("edits/requests/edit.json", as: EditBody.self)
    wrong.end = wrong.end?.addingTimeInterval(60)
    await #expect(throws: ClientError.rejected) { try await api.putEdit(id: editID, wrong) }
    for (name, state) in [("edit", "edited"), ("merge", "merged"), ("delete_merged", "deleted_merged"), ("undo_merged", "merged")] {
        _ = try await api.putEdit(id: editID, fixture("edits/requests/\(name).json", as: EditBody.self))
        #expect(await api.state == state)
        let rows = try await api.snapshot().workouts.workouts
        #expect(rows.contains { $0.id == editID } == (state != "deleted_merged"))
        if state == "merged" { #expect(!rows.contains { $0.id == neighbourID }) }
    }
    try await api.deleteEdit(id: editID)
    #expect(try await api.snapshot().workouts.workouts.contains { $0.id == neighbourID })
    await #expect(throws: ClientError.notFound) { try await api.deleteEdit(id: editID) }
    var upload: ActivityUpload = try fixture("edits/requests/name.json", as: ActivityUpload.self)
    upload.id = UUID().uuidString.lowercased()
    #expect(try await api.postActivity(upload).id == upload.id)
    #expect(try await api.snapshot().workouts.workouts.contains { $0.id == "goop-\(upload.id)" })
    upload.notes = "Wrong request"
    await #expect(throws: ClientError.rejected) { try await api.postActivity(upload) }
    #expect(await api.matchedRequests == ["edit", "merge", "delete_merged", "undo_merged", "restore", "name"])
    let offline = FixtureEditAPI(directory: fixtureRoot, offline: true)
    await #expect(throws: ClientError.offline) { try await offline.heartRate(date: "2026-03-12") }
}

@Test func fixtureMutationModesMatchBeforeWaitingAndRetryWithoutChangingState() async throws {
    let directory = fixtureRoot.appendingPathComponent("edits")
    let body: EditBody = try fixture("edits/requests/edit.json", as: EditBody.self)
    let api = FixtureEditAPI(directory: directory, state: "unedited", mutationMode: .offlineOnce)
    await #expect(throws: ClientError.rejected) { _ = try await api.putEdit(id: "7300000000000000101", EditBody(notes: "Wrong body")) }
    await #expect(throws: ClientError.offline) { _ = try await api.putEdit(id: "7300000000000000101", body) }
    #expect(await api.state == "unedited")
    #expect(try await api.heartRate(date: "2026-03-11").minutes.count > 0)
    _ = try await api.putEdit(id: "7300000000000000101", body)
    #expect(await api.state == "edited")
    #expect(await api.matchedRequests == ["edit", "edit"])
    await api.setMutationMode(.reject(.conflict))
    await #expect(throws: ClientError.conflict) { try await api.deleteEdit(id: "7300000000000000101") }
    #expect(await api.state == "edited")
}
#endif
