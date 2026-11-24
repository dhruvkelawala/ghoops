import Foundation
import Testing
@testable import GHealthCore

func reportedEditLimits() throws -> EditLimits { try #require(fixture("status_full.json", as: Status.self).editLimits) }
private func oddEditLimits() throws -> EditLimits {
    struct Body: Decodable { var editLimits: EditLimits }
    return try fixture("edits/odd_limits.json", as: Body.self).editLimits
}
private let limitTarget = "7300000000000000101"
private let limitNeighbor = "7300000000000000102"
private func limitTime(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private let limitNow = limitTime("2026-03-12T20:30:00Z")
private func limitWorkout(_ state: String = "edited") throws -> Workout {
    try #require(fixture("edits/snapshot_\(state).json", as: Snapshot.self).workouts.workouts.first { $0.id == limitTarget })
}
private func limitHeartRate() throws -> HeartRateBody {
    var hr: HeartRateBody = try fixture("edits/heart_rate_tue.json")
    hr.start = limitTime("2026-03-10T12:00:00Z"); hr.end = limitTime("2026-03-11T00:00:00Z")
    return hr
}

@Test func statusDecodesEditLimits() throws {
    let status: Status = try fixture("status_full.json")
    let l = try #require(status.editLimits)
    let values: [Int] = [l.horizonDays, l.shiftMinutes, l.mergeGapMinutes, l.mergeMaxIds, l.notesMaxChars, l.activeMinMinutes, l.activeMaxMinutes, l.heartRateSpanMaxMinutes]
    #expect(values == [30, 180, 15, 4, 500, 1, 720, 1080])
    var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(status)) as? [String: Any])
    object.removeValue(forKey: "edit_limits")
    let older = try JSONCoding.decoder().decode(Status.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(older.editLimits == nil)
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(older)) as? [String: Any])
    #expect(NSDictionary(dictionary: object).isEqual(to: encoded))
    #expect(try fixture("preview/snapshot_fresh.json", as: Snapshot.self).status.editLimits == l)
}

@Test func limitCasesMatchTheMac() throws {
    struct Vectors: Decodable {
        struct Case: Decodable { var name: String; var state: String; var start: Date; var end: Date; var mergeWith: [String]; var accepted: Bool }
        var cases: [Case]
    }
    let vectors: Vectors = try fixture("edits/limit_cases.json")
    let limits = try reportedEditLimits(), hr = try limitHeartRate()
    let unedited: Snapshot = try fixture("edits/snapshot_unedited.json")
    let candidate = try #require(unedited.workouts.workouts.first { $0.id == limitNeighbor })
    for c in vectors.cases {
        let bounds = EditBounds.edit(try limitWorkout(c.state), heartRate: hr, limits: limits, now: limitNow, merging: c.name.hasPrefix("n") ? candidate : nil)
        #expect(bounds.allows(ActivityWindow(start: c.start, end: c.end), pauses: []) == c.accepted, "\(c.name)")
    }
}

@Test func boundsUseTheMacsShiftAndLength() throws {
    let workout = try limitWorkout(), hr = try limitHeartRate()
    for (limits, first, last, movedEnd): (EditLimits?, String, String, String) in [
        (try reportedEditLimits(), "15:05", "22:02", "22:02"),
        (try oddEditLimits(), "17:05", "20:02", "19:35")
    ] {
        let bounds = EditBounds.edit(workout, heartRate: hr, limits: limits, now: limitNow)
        #expect(bounds.span == DateInterval(start: limitTime("2026-03-10T\(first):00Z"), end: limitTime("2026-03-10T\(last):00Z")))
        var window = ActivityWindow(start: workout.start, end: workout.end)
        window.moveStart(to: limitTime("2026-03-10T14:00:00Z"), bounds: bounds)
        #expect(GoopFormat.time(window.start) == first)
        window.moveEnd(to: limitTime("2026-03-10T23:00:00Z"), bounds: bounds)
        #expect(GoopFormat.time(window.end) == movedEnd)
    }
    let unknown = EditBounds.edit(workout, heartRate: hr, limits: nil, now: limitNow)
    #expect(unknown.span == DateInterval(start: hr.start, end: hr.end) && unknown.activeMax == nil)
}

@Test func editBoundsNeverInvert() throws {
    let workout = try limitWorkout(), hr = try limitHeartRate(), limits = try oddEditLimits()
    let saved = ActivityWindow(start: workout.start, end: workout.end)
    var inverted = limits; inverted.activeMaxMinutes = 1
    var short = hr; short.start = workout.start; short.end = short.start.addingTimeInterval(120)
    var offGrid = hr; offGrid.start = workout.start.addingTimeInterval(1); offGrid.end = workout.start.addingTimeInterval(59)
    func check(_ bounds: EditBounds) {
        #expect(bounds.startRange(end: saved.end) == saved.start...saved.start)
        #expect(bounds.endRange(start: saved.start) == saved.end...saved.end)
        #expect(bounds.clamp(saved, pauses: []) == saved)
        for date in [hr.start, hr.end] {
            var window = saved
            window.moveStart(to: date, bounds: bounds)
            window.moveEnd(to: date, bounds: bounds)
            #expect(window == saved)
        }
    }
    for (heartRate, reported, now) in [(hr, inverted, limitNow), (hr, limits, hr.start.addingTimeInterval(-3600)), (short, limits, limitNow), (offGrid, limits, limitNow)] {
        for kind in ["recorded", "detected"] {
            var target = workout; target.kind = kind
            let draft = EditDraft(workout: target, workouts: [], heartRate: heartRate, limits: reported, now: now)
            try #require(draft.window == saved)
            check(draft.bounds)
        }
        check(EditBounds.add(day: DateInterval(start: heartRate.start, end: heartRate.end), window: saved, limits: reported, now: now))
    }
    let bounds = EditBounds.edit(workout, heartRate: hr, limits: limits, now: limitNow)
    for visible in [DateInterval(start: saved.start, end: saved.start.addingTimeInterval(60)), DateInterval(start: hr.end, end: hr.end.addingTimeInterval(60))] {
        check(bounds.clipped(to: visible, window: saved))
    }
}

@Test func overlapAndCoverStopTheHandles() throws {
    let limits = try reportedEditLimits(), hr = try limitHeartRate(), workout = try limitWorkout()
    let bounds = EditBounds.edit(workout, heartRate: hr, limits: limits, now: limitNow)
    var window = ActivityWindow(start: workout.start, end: workout.end)
    window.moveStart(to: limitTime("2026-03-10T19:30:00Z"), bounds: bounds)
    #expect(GoopFormat.time(window.start) == "19:01")
    window = ActivityWindow(start: workout.start, end: workout.end)
    window.moveEnd(to: limitTime("2026-03-10T17:00:00Z"), bounds: bounds)
    #expect(GoopFormat.time(window.end) == "18:06")
    #expect(bounds.startRange(end: workout.end) == limitTime("2026-03-10T15:05:00Z")...limitTime("2026-03-10T19:01:00Z"))
    #expect(bounds.endRange(start: workout.start) == limitTime("2026-03-10T18:06:00Z")...limitTime("2026-03-10T22:02:00Z"))
    let merged = try limitWorkout("merged")
    let cover = EditBounds.edit(merged, heartRate: hr, limits: limits, now: limitNow)
    window = ActivityWindow(start: merged.start, end: merged.end)
    window.moveEnd(to: limitTime("2026-03-10T19:20:00Z"), bounds: cover)
    #expect(GoopFormat.time(window.end) == "19:38")
    window.moveStart(to: limitTime("2026-03-10T19:30:00Z"), bounds: cover)
    #expect(GoopFormat.time(window.start) == "19:16")
}

@Test func addBoundsUseTheMacsHorizonAndMinimum() throws {
    let window = ActivityWindow(start: limitTime("2026-03-09T21:00:00Z"), end: limitTime("2026-03-09T22:00:00Z"))
    let horizon = EditBounds.add(day: DateInterval(start: limitTime("2026-03-09T07:00:00Z"), end: limitTime("2026-03-10T07:00:00Z")), window: window, limits: try oddEditLimits(), now: limitNow)
    #expect(horizon.span.start == limitTime("2026-03-09T20:30:00Z"))
    let day = DateInterval(start: limitTime("2026-03-11T07:00:00Z"), end: limitTime("2026-03-12T07:00:00Z"))
    for (limits, expected) in [(try reportedEditLimits(), "18:59"), (try oddEditLimits(), "18:55")] {
        var window = ActivityWindow(start: limitTime("2026-03-11T18:00:00Z"), end: limitTime("2026-03-11T19:00:00Z"))
        window.moveStart(to: limitTime("2026-03-11T18:59:00Z"), bounds: .add(day: day, window: window, limits: limits, now: limitNow))
        #expect(GoopFormat.time(window.start) == expected)
    }
    var effort = try limitWorkout(); effort.kind = "detected"
    effort.start = limitTime("2026-03-09T20:35:00Z"); effort.end = limitTime("2026-03-09T21:35:00Z")
    var hr = try limitHeartRate()
    hr.start = limitTime("2026-03-09T07:00:00Z"); hr.end = limitTime("2026-03-10T07:00:00Z")
    let naming = EditBounds.name(effort, heartRate: hr, limits: try oddEditLimits(), now: limitNow)
    #expect(naming.span.start == limitTime("2026-03-09T20:30:00Z"))
    #expect(!naming.allows(ActivityWindow(start: limitTime("2026-03-09T20:29:00Z"), end: effort.end), pauses: []))
    effort.cycleDate = "2026-03-11"
    effort.start = limitTime("2026-03-11T18:00:00Z"); effort.end = limitTime("2026-03-11T18:04:00Z")
    var past = AddDraft(defaultDate: "2026-03-12", workouts: [effort], now: limitNow, limits: try oddEditLimits())
    past.selectDay("2026-03-11")
    #expect(past.efforts.isEmpty)
    effort.end = limitTime("2026-03-11T20:31:00Z")
    past = AddDraft(defaultDate: "2026-03-12", workouts: [effort], now: limitNow, limits: try oddEditLimits())
    past.selectDay("2026-03-11")
    #expect(past.efforts.isEmpty)
}

@Test func fetchSpanUsesTheMacsShiftAndCap() throws {
    let snapshot: Snapshot = try fixture("edits/snapshot_edited.json"), workout = try limitWorkout()
    var capped = try reportedEditLimits(); capped.heartRateSpanMaxMinutes = 300
    for (limits, start, end) in [(try reportedEditLimits(), "14:56", "22:38"), (try oddEditLimits(), "16:56", "20:12"), (capped, "16:04", "21:04")] {
        let span = EditDraft.fetchSpan(for: workout, workouts: snapshot.workouts.workouts, limits: limits, now: limitNow)
        #expect(GoopFormat.time(span.start) == start && GoopFormat.time(span.end) == end)
    }
}

@Test func mergeRowsUseTheMacsLimits() throws {
    let snapshot: Snapshot = try fixture("edits/snapshot_edited.json"), hr = try limitHeartRate(), limits = try reportedEditLimits()
    let workout = try limitWorkout()
    #expect(EditDraft(workout: workout, workouts: snapshot.workouts.workouts, heartRate: hr, limits: limits, now: limitNow).next?.id == limitNeighbor)
    #expect(EditDraft(workout: workout, workouts: snapshot.workouts.workouts, heartRate: hr, limits: try oddEditLimits(), now: limitNow).next == nil)
    #expect(EditDraft(workout: workout, workouts: snapshot.workouts.workouts, heartRate: hr, limits: nil, now: limitNow).next == nil)
    var target = try limitWorkout("unedited")
    target.edit = WorkoutEdit(mergeWith: ["a", "b", "c", "d"], updatedAt: limitNow)
    #expect(EditDraft(workout: target, workouts: snapshot.workouts.workouts, heartRate: hr, limits: limits, now: limitNow).next == nil)
    target.edit?.mergeWith.removeLast()
    #expect(EditDraft(workout: target, workouts: snapshot.workouts.workouts, heartRate: hr, limits: limits, now: limitNow).next?.id == limitNeighbor)
    var candidate = try #require(snapshot.workouts.workouts.first { $0.id == limitNeighbor })
    candidate.edit = WorkoutEdit(mergeWith: ["x"], updatedAt: limitNow)
    #expect(!EditDraft(workout: target, workouts: [candidate], heartRate: hr, limits: limits, now: limitNow).offers(candidate))
    candidate.kind = "detected"; candidate.start = limitTime("2026-03-10T19:10:00Z"); candidate.end = limitTime("2026-03-10T23:00:00Z")
    let draft = EditDraft(workout: try limitWorkout("unedited"), workouts: [], heartRate: hr, limits: limits, now: limitNow)
    #expect(!draft.offers(candidate))
    candidate.end = limitTime("2026-03-10T22:00:00Z")
    #expect(draft.offers(candidate))
    var shorter = limits; shorter.activeMaxMinutes = 150
    candidate.end = limitTime("2026-03-10T20:36:00Z")
    #expect(!EditDraft(workout: workout, workouts: [], heartRate: hr, limits: shorter, now: limitNow).offers(candidate))
}

@Test func notesStopAtTheMacsLimit() throws {
    #expect(EditNotes.capped(String(repeating: "é", count: 600), max: 500).unicodeScalars.count == 500)
    let prefix = String(repeating: "a", count: 39)
    #expect(EditNotes.capped(prefix + "👍🏽", max: 40) == prefix)
    #expect(EditNotes.capped(prefix + "👍🏽", max: nil) == prefix + "👍🏽")
    var workout = try limitWorkout(); workout.notes = String(repeating: "a", count: 60)
    var draft = EditDraft(workout: workout, workouts: [], heartRate: try limitHeartRate(), limits: try oddEditLimits(), now: limitNow)
    #expect(draft.notes.count == 40)
    draft.notes = String(repeating: "é", count: 60)
    #expect(draft.notes.unicodeScalars.count == 40)
}

@Test func notesInputStopsAtTheMacsLimit() {
    let full = "Sparring, 6 rounds of 3 minutes. Good se"
    #expect(EditNotes.fitted("X", keeping: full, max: 40) == "")
    #expect(EditNotes.fitted(" Good session today.", keeping: "Sparring, 6 rounds of 3 minutes.", max: 40) == " Good se")
    #expect(EditNotes.fitted("👍🏽", keeping: String(repeating: "a", count: 39), max: 40) == "")
    #expect(EditNotes.fitted("é", keeping: String(repeating: "a", count: 39), max: 40) == "é")
    #expect(EditNotes.fitted("X", keeping: full, max: nil) == "X")
    #expect(EditNotes.fitted("", keeping: full + "extra", max: 40) == "")

    let typed = EditNotes.trimmed(before: "Sparring" + " session today", after: ", 6 rounds of 3 minutes. Good se", max: 40)
    #expect(typed.before == "Sparring" && typed.after == ", 6 rounds of 3 minutes. Good se")
    let pasted = EditNotes.trimmed(before: "Sparring, 6 rounds of 3 minutes. Good session today.", after: "", max: 40)
    #expect(pasted.before == full && pasted.after == "")
    let tail = EditNotes.trimmed(before: "ab", after: String(repeating: "c", count: 45), max: 40)
    #expect(tail.before == "" && tail.after == String(repeating: "c", count: 40))
    let open = EditNotes.trimmed(before: full + "X", after: "Y", max: nil)
    #expect(open.before == full + "X" && open.after == "Y")
}

@Test func horizonUsesTheMacsDays() throws {
    let odd = try oddEditLimits(), normal = try reportedEditLimits()
    for (date, limits, expected): (String, EditLimits?, Bool) in [("2026-03-10", odd, true), ("2026-03-09", odd, false), ("2026-02-11", normal, true), ("2026-02-10", normal, false), ("2026-01-01", nil, true)] {
        #expect(EditLimits.editable(cycleDate: date, defaultDate: "2026-03-12", limits: limits) == expected)
    }
    for (limits, days): (EditLimits?, [String]) in [(normal, ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12"]), (odd, ["2026-03-10", "2026-03-11", "2026-03-12"]), (nil, ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12"])] {
        #expect(AddDraft(defaultDate: "2026-03-12", workouts: [], now: limitNow, limits: limits).days == days)
    }
    var today = odd; today.horizonDays = 1
    #expect(AddDraft(defaultDate: "2026-03-12", workouts: [], now: limitNow, limits: today).days == ["2026-03-12"])
}

@Test func controlsStayInsideTheMacsLimits() throws {
    let hr = try limitHeartRate()
    for state in ["edited", "merged"] {
        let workout = try limitWorkout(state)
        for limits in [try reportedEditLimits(), try oddEditLimits()] {
            let bounds = EditBounds.edit(workout, heartRate: hr, limits: limits, now: limitNow)
            let saved = ActivityWindow(start: workout.start, end: workout.end)
            for offset in stride(from: 0, through: 720, by: 5) {
                let date = hr.start.addingTimeInterval(Double(offset) * 60)
                for start in [true, false] {
                    var window = saved
                    if start { window.moveStart(to: date, bounds: bounds) } else { window.moveEnd(to: date, bounds: bounds) }
                    #expect(bounds.allows(window, pauses: []), "\(state), \(offset), start=\(start)")
                }
            }
            for end in stride(from: 0, through: 720, by: 30) {
                for start in stride(from: 0, through: 720, by: 30) {
                    var window = saved
                    window.moveEnd(to: hr.start.addingTimeInterval(Double(end) * 60), bounds: bounds)
                    window.moveStart(to: hr.start.addingTimeInterval(Double(start) * 60), bounds: bounds)
                    #expect(bounds.allows(window, pauses: []), "\(state), end=\(end), start=\(start)")
                }
            }
        }
    }
}
