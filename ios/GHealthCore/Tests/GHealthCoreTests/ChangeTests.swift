import Foundation
import Testing
@testable import GHealthCore

private let changeWorkoutID = "7300000000000000101"
private let changeServer = "https://fixture.invalid:18780"
private func changeSnapshot(_ state: String) throws -> Snapshot { try fixture("edits/snapshot_\(state).json", as: Snapshot.self) }
private func changeDraft(_ state: String) throws -> EditDraft {
    let snapshot = try changeSnapshot(state)
    return EditDraft(workout: try #require(snapshot.workouts.workouts.first { $0.id == changeWorkoutID }), workouts: snapshot.workouts.workouts, heartRate: try fixture("edits/heart_rate_tue.json", as: HeartRateBody.self), limits: try reportedEditLimits(), now: snapshot.generatedAt)
}
private func choose(_ request: String, draft: inout EditDraft) throws {
    let body: EditBody = try fixture("edits/requests/\(request).json", as: EditBody.self)
    draft.sport = body.exerciseType ?? draft.sport
    draft.window = ActivityWindow(start: body.start ?? draft.window.start, end: body.end ?? draft.window.end)
    draft.notes = body.notes ?? ""
}
private func workoutFields(_ workout: Workout) throws -> NSDictionary {
    let keys = Set(["id", "exercise_type", "display_name", "category", "cycle_date", "start", "end", "elapsed_minutes", "strain", "trimp", "hr_coverage", "confidence", "avg_hr_bpm", "peak_hr_bpm", "zones_minutes", "notes", "edited", "origin", "edit"])
    var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(workout)) as? [String: Any])
    object = object.filter { keys.contains($0.key) }
    if var edit = object["edit"] as? [String: Any] { edit.removeValue(forKey: "updated_at"); object["edit"] = edit }
    return object as NSDictionary
}

@Test func overlaysMatchAllSevenGoGoldens() throws {
    let now = try changeSnapshot("edited").generatedAt
    for (start, action, expected) in [("unedited", "edit", "edited"), ("edited", "merge", "merged"), ("edited", "delete", "deleted"), ("deleted", "undo", "edited"), ("edited", "restore", "unedited"), ("edited", "name", "named"), ("edited", "add", "added")] {
        let snapshot = try changeSnapshot(start)
        var draft = try changeDraft(start == "deleted" ? "edited" : start)
        let change: PendingChange
        switch action {
        case "edit":
            try choose("edit", draft: &draft)
            change = ChangeBuilder.edit(draft, serverURL: changeServer, now: now)
        case "merge": change = ChangeBuilder.merge(draft, candidate: try #require(draft.next), serverURL: changeServer, now: now)
        case "delete": change = ChangeBuilder.delete(draft.workout, serverURL: changeServer, now: now)
        case "undo": change = try #require(ChangeBuilder.undo(ChangeBuilder.delete(draft.workout, serverURL: changeServer, now: now), now: now))
        case "restore": change = ChangeBuilder.restore(draft, serverURL: changeServer, now: now)
        case "name":
            let upload: ActivityUpload = try fixture("edits/requests/name.json", as: ActivityUpload.self)
            let effort = try #require(snapshot.workouts.workouts.first { $0.kind == "detected" && $0.cycleDate == snapshot.defaultDate })
            var nameDraft = EditDraft(workout: effort, workouts: snapshot.workouts.workouts, heartRate: try fixture("edits/heart_rate_thu_effort.json", as: HeartRateBody.self), limits: try reportedEditLimits(), now: snapshot.generatedAt)
            nameDraft.sport = upload.exerciseType
            change = ChangeBuilder.name(nameDraft, id: upload.id, serverURL: changeServer, now: now)
        default:
            let upload: ActivityUpload = try fixture("edits/requests/add.json", as: ActivityUpload.self)
            let hr: HeartRateBody = try fixture("edits/heart_rate_day_2026-03-11.json", as: HeartRateBody.self)
            var add = AddDraft(defaultDate: snapshot.defaultDate, workouts: snapshot.workouts.workouts, now: now, limits: try reportedEditLimits(), id: upload.id)
            add.selectDay("2026-03-11", heartRate: hr); add.sport = upload.exerciseType
            change = try #require(ChangeBuilder.add(add, heartRate: hr, serverURL: changeServer, now: now))
        }
        let result = Overlay.apply([change], to: snapshot)
        let golden = try changeSnapshot(expected)
        #expect(Set(result.workouts.workouts.map(\.id)) == Set(golden.workouts.workouts.map(\.id)), "\(action)")
        #expect(Set(result.day.workouts.map(\.id)) == Set(golden.day.workouts.map(\.id)), "\(action) default day")
        for actual in result.workouts.workouts {
            let want = try #require(golden.workouts.workouts.first { $0.id == actual.id })
            #expect(try workoutFields(actual) == workoutFields(want), "\(action) \(actual.id)")
        }
        for actual in result.day.workouts {
            let want = try #require(golden.day.workouts.first { $0.id == actual.id })
            #expect(try workoutFields(actual) == workoutFields(want), "\(action) default day \(actual.id)")
        }
        for date in Set(golden.workouts.workouts.map(\.cycleDate)) {
            var day = snapshot.day; day.date = date; day.workouts = snapshot.workouts.workouts.filter { $0.cycleDate == date }
            let (displayDay, rows) = Overlay.apply([change], date: date, day: day, workouts: day.workouts)
            let ids = Set(golden.workouts.workouts.filter { $0.cycleDate == date }.map(\.id))
            #expect(Set(rows.map(\.id)) == ids && Set(displayDay.workouts.map(\.id)) == ids, "\(action) bundle \(date)")
        }
        let replay = Overlay.apply([change], to: result)
        #expect(try replay.workouts.workouts.map(workoutFields) == result.workouts.workouts.map(workoutFields), "\(action) idempotent")
        #expect(try replay.day.workouts.map(workoutFields) == result.day.workouts.map(workoutFields), "\(action) default day idempotent")
        print("overlay \(action): \(result.workouts.workouts.count) workouts compared, default day \(result.day.workouts.count)")
    }
}

@Test func savedEditNamesMatchTheMacForEverySport() throws {
    let recorded: Workouts = try fixture("names/workouts.json")
    let saved: Workouts = try fixture("names/workouts_edited.json")
    let heartRate: HeartRateBody = try fixture("edits/heart_rate_tue.json")
    for base in recorded.workouts {
        let mac = try #require(saved.workouts.first { $0.id == base.id })
        var draft = EditDraft(workout: base, workouts: recorded.workouts, heartRate: heartRate, limits: try reportedEditLimits(), now: saved.generatedAt)
        draft.window = ActivityWindow(start: mac.start, end: mac.end)
        let change = ChangeBuilder.edit(draft, serverURL: changeServer, now: saved.generatedAt)
        let overlay = try #require(change.patch.upsert.first { $0.id == base.id })
        #expect(draft.body.exerciseType == nil)
        #expect(overlay.displayName == mac.displayName, "\(base.exerciseType ?? "missing")")
        if let sport = ActivitySport.all.first(where: { $0.id == base.exerciseType }) {
            #expect(mac.displayName == sport.name)
        } else {
            #expect(mac.displayName == "Downhill Ski")
        }
    }
}

@Test func overlapRulesRespectAbsorptionDatesAndHalfWindows() throws {
    let rules = try engineConstants().workouts
    let base = try changeDraft("unedited").workout
    var recorded = base; recorded.id = "recorded"
    var goop = base; goop.id = "goop"; goop.kind = "goop"
    var effort = base; effort.id = "effort"; effort.kind = "detected"
    let date = base.cycleDate
    #expect(OverlapRules.apply([recorded, goop, effort], cycleDates: [date], rules: rules).map(\.id) == ["goop"])
    #expect(OverlapRules.apply([recorded, goop, effort], cycleDates: [], rules: rules).count == 3)
    goop.start = base.start.addingTimeInterval(base.end.timeIntervalSince(base.start) / 2)
    goop.end = base.end.addingTimeInterval(base.end.timeIntervalSince(base.start) / 2)
    #expect(!OverlapRules.apply([recorded, goop], cycleDates: [date], rules: rules).contains { $0.id == "recorded" })
    goop.start = base.end.addingTimeInterval(-1); goop.end = base.end.addingTimeInterval(600)
    #expect(OverlapRules.apply([recorded, goop], cycleDates: [date], rules: rules).count == 2)
    goop = base; goop.kind = "goop"; goop.id = "goop"
    goop.edit = WorkoutEdit(mergeWith: [recorded.id], updatedAt: base.end)
    #expect(OverlapRules.apply([recorded, goop], cycleDates: [date], rules: rules).count == 2)
    goop.edit = nil; recorded.edit = WorkoutEdit(mergeWith: [goop.id], updatedAt: base.end)
    #expect(OverlapRules.apply([recorded, goop], cycleDates: [date], rules: rules).count == 2)
    var earlier = recorded; earlier.edit = nil; earlier.end = base.start.addingTimeInterval(base.end.timeIntervalSince(base.start) / 4)
    var later = earlier; later.id = "later"; later.start = base.end.addingTimeInterval(-base.end.timeIntervalSince(base.start) / 4); later.end = base.end
    #expect(!OverlapRules.apply([earlier, later, effort], cycleDates: [date], rules: rules).contains { $0.id == effort.id })
}

@Test func restoreProjectsAbsorbedEntriesAndAliases() throws {
    let draft = try changeDraft("merged")
    let change = ChangeBuilder.restore(draft, aliases: ["KICKBOXING": "BOXING"], serverURL: changeServer, now: draft.workout.end)
    #expect(change.targets == [changeWorkoutID, "7300000000000000102"])
    #expect(change.patch.upsert.count == 2)
    for row in change.patch.upsert {
        #expect(row.exerciseType == "BOXING" && row.displayName == "Boxing" && row.edit == nil && row.edited == false)
        #expect(row.merged.isEmpty && row.activeMinutes == nil && row.notes == nil)
    }
    var strength = try changeDraft("unedited"); strength.sport = "WEIGHTLIFTING"
    #expect(ChangeBuilder.edit(strength, serverURL: changeServer, now: strength.workout.end).patch.updating == [strength.workout.cycleDate])
    var oldStrength = strength.workout; oldStrength.category = "strength"
    #expect(ChangeBuilder.delete(oldStrength, serverURL: changeServer, now: oldStrength.end).patch.updating == [oldStrength.cycleDate])
    oldStrength.cycleDate = "2026-03-11"
    var add = AddDraft(defaultDate: "2026-03-12", workouts: [oldStrength], now: try fixture("edits/snapshot_edited.json", as: Snapshot.self).generatedAt, limits: try reportedEditLimits())
    add.selectDay("2026-03-11"); add.window = ActivityWindow(start: oldStrength.start, end: oldStrength.end); add.sport = "RUNNING"
    #expect(ChangeBuilder.add(add, heartRate: draft.heartRate, serverURL: changeServer, now: draft.workout.end)?.patch.updating == ["2026-03-11"])
}

@Test func changeTimingDelaysMarkersAndKeepsShownMarkers() throws {
    var change = ChangeBuilder.delete(try changeDraft("edited").workout, serverURL: changeServer, now: Date(timeIntervalSince1970: 0))
    #expect(!ChangeTiming.markerVisible(change: change, now: Date(timeIntervalSince1970: 0.59), shownAt: nil))
    #expect(ChangeTiming.markerVisible(change: change, now: Date(timeIntervalSince1970: 0.61), shownAt: nil))
    change.state = .accepted
    #expect(ChangeTiming.markerVisible(change: change, now: Date(timeIntervalSince1970: 1.09), shownAt: Date(timeIntervalSince1970: 0.6)))
    #expect(!ChangeTiming.markerVisible(change: change, now: Date(timeIntervalSince1970: 1.11), shownAt: Date(timeIntervalSince1970: 0.6)))
    #expect(ChangeTiming.markerVisible(change: change, now: Date(timeIntervalSince1970: 1.11), shownAt: nil, untilSettled: true))
}

@Test func projectionKeepsGoopNotesAndClipsPausesWithSparseHeartRate() throws {
    let now = try changeSnapshot("edited").generatedAt
    var base = try changeDraft("unedited").workout
    base.kind = "goop"; base.notes = "Saved live note"; base.source = .goop
    let start = base.start, end = start.addingTimeInterval(600)
    base.pauses = [ActivityPause(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(60)), ActivityPause(start: end.addingTimeInterval(-60), end: end.addingTimeInterval(60))]
    var hr: HeartRateBody = try fixture("edits/heart_rate_tue.json", as: HeartRateBody.self)
    hr.minutes = hr.minutes.filter { $0.t >= start.addingTimeInterval(60) && $0.t < start.addingTimeInterval(300) }
    let projected = WorkoutProjection.project(base, body: EditBody(), window: ActivityWindow(start: start, end: end), heartRate: hr, now: now)
    #expect(projected.notes == "Saved live note" && projected.edit == nil && projected.edited == false)
    #expect(projected.pauses == [ActivityPause(start: start, end: start.addingTimeInterval(60)), ActivityPause(start: end.addingTimeInterval(-60), end: end)])
    #expect(projected.pausedMinutes == 2 && projected.activeMinutes == 8)
    #expect(projected.hrCoverage == 0.5 && projected.confidence == .medium && projected.hrSeries.count == 4)
    hr.minutes = []
    let missing = WorkoutProjection.project(base, body: EditBody(), window: ActivityWindow(start: start, end: end), heartRate: hr, now: now)
    #expect(missing.strain == nil && missing.confidence == nil && missing.avgHrBpm == nil && missing.hrSeries.isEmpty)
}

@Test func editPreconditionsEncodeAbsentNullAndWholeSeconds() throws {
    let time = Date(timeIntervalSince1970: 1_773_311_400.75)
    for condition in [EditPrecondition.none, .noEdit, .updatedAt(time)] {
        let body = EditBody(precondition: condition)
        #expect(body == EditBody())
        let data = try JSONCoding.encoder().encode(body)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONCoding.decoder().decode(EditBody.self, from: data)
        switch condition {
        case .none: #expect(object["if_updated_at"] == nil && decoded.precondition == .none)
        case .noEdit: #expect(object["if_updated_at"] is NSNull && decoded.precondition == .noEdit)
        case .updatedAt:
            #expect(object["if_updated_at"] as? String == "2026-03-12T10:30:00Z")
            #expect(decoded.precondition == .updatedAt(Date(timeIntervalSince1970: floor(time.timeIntervalSince1970))))
        }
    }
    let unedited = ChangeBuilder.delete(try changeDraft("unedited").workout, serverURL: changeServer, now: time)
    if case .putEdit(_, let body) = unedited.request { #expect(body.precondition == .noEdit) } else { Issue.record("Expected PUT") }
    let edited = ChangeBuilder.delete(try changeDraft("edited").workout, serverURL: changeServer, now: time)
    if case .putEdit(_, let body) = edited.request { #expect(body.precondition == .updatedAt(try #require(edited.kept?.edit?.updatedAt))) } else { Issue.record("Expected PUT") }
}

@Test func rollbackAndWaitingCopyMatchesApprovedSentences() {
    for kind in [PendingChange.Kind.edit, .merge, .delete, .restore, .undo, .name, .add] {
        for error in [ClientError.rejected, .http(413), .notFound, .conflict] {
            let changed = error == .notFound || error == .conflict
            let text = RollbackNotice(changeID: UUID(), kind: kind, name: "Kickboxing", error: error).text
            let expected: String
            switch kind {
            case .name: expected = (changed ? "The detected effort changed on your Mac." : "Your Mac couldn't save the detected effort as Kickboxing.") + " It's back as it was."
            case .add: expected = "Your Mac couldn't add Kickboxing. Nothing was added."
            default: expected = (changed ? "Kickboxing changed on your Mac." : "Your Mac couldn't save the change to Kickboxing.") + " It's back as it was."
            }
            #expect(text == expected)
        }
    }
    #expect(ChangeTiming.waitingText(count: 1) == "1 change is waiting for your Mac. It will be saved when your Mac can be reached.")
    #expect(ChangeTiming.waitingText(count: 3) == "3 changes are waiting for your Mac. They will be saved when your Mac can be reached.")
}
