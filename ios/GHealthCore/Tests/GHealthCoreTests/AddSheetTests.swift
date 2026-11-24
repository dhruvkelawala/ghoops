import Foundation
import Testing
@testable import GHealthCore

private func addTime(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private func addSheet(day: String? = nil, now: Date? = nil, limits: EditLimits? = nil) throws -> AddDraft {
    let snapshot: Snapshot = try fixture("edits/snapshot_edited.json")
    return AddDraft(defaultDate: "2026-03-12", workouts: snapshot.workouts.workouts, now: now ?? snapshot.generatedAt, limits: try limits ?? reportedEditLimits(), day: day)
}
private func expectWindow(_ draft: AddDraft, _ start: String, _ end: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(GoopFormat.time(draft.window.start) == start, sourceLocation: sourceLocation)
    #expect(GoopFormat.time(draft.window.end) == end, sourceLocation: sourceLocation)
}

@Test func addSheetOpensOnTheGivenDay() throws {
    #expect(try addSheet().day == "2026-03-12")
    #expect(try addSheet(day: "2026-03-11").day == "2026-03-11")
    #expect(try addSheet(day: "2026-03-08").day == "2026-03-12")
    let snapshot: Snapshot = try fixture("edits/snapshot_edited.json")
    let earlier = snapshot.workouts.workouts.filter { $0.cycleDate != "2026-03-12" }
    #expect(try AddDraft(defaultDate: "2026-03-12", workouts: earlier, now: snapshot.generatedAt, limits: reportedEditLimits()).day == "2026-03-12")
}

@Test func addSheetHasNoSportUntilChosen() throws {
    var draft = try addSheet()
    let hr: HeartRateBody = try fixture("edits/heart_rate_day_2026-03-12.json")
    #expect(draft.sport == nil && draft.upload == nil)
    #expect(ChangeBuilder.add(draft, heartRate: hr, serverURL: "https://fixture.invalid", now: draft.now) == nil)
    draft.sport = "BOXING"
    #expect(draft.upload?.displayName == "Boxing")
    #expect(ChangeBuilder.add(draft, heartRate: hr, serverURL: "https://fixture.invalid", now: draft.now) != nil)
}

@Test func addSheetDefaultWindowToday() throws {
    var draft = try addSheet()
    expectWindow(draft, "19:30", "20:30")
    #expect(draft.snapped == nil)
    var hr: HeartRateBody = try fixture("edits/heart_rate_day_2026-03-12.json")
    hr.start = addTime("2026-03-12T20:10:00Z")
    draft = try addSheet(now: addTime("2026-03-12T20:30:42Z"))
    draft.load(hr)
    expectWindow(draft, "20:10", "20:30")
}

@Test func addSheetDefaultWindowPastDay() throws {
    var draft = try addSheet()
    draft.selectDay("2026-03-11")
    expectWindow(draft, "18:04", "19:04")
    draft.selectDay("2026-03-10")
    expectWindow(draft, "18:00", "19:00")
    draft.selectDay("2026-03-12")
    expectWindow(draft, "19:30", "20:30")
}

@Test func addSheetEffortLabel() throws {
    var draft = try addSheet()
    #expect(draft.effortLabel == "1 found")
    draft.snap(to: try #require(draft.efforts.first))
    #expect(draft.effortLabel == "07:10 to 07:41")
    let snapshot: Snapshot = try fixture("edits/snapshot_edited.json")
    var extra = try #require(draft.efforts.first)
    extra.id = "effort-extra"; extra.start = extra.start.addingTimeInterval(3600); extra.end = extra.end.addingTimeInterval(3600)
    draft = try AddDraft(defaultDate: "2026-03-12", workouts: snapshot.workouts.workouts + [extra], now: snapshot.generatedAt, limits: reportedEditLimits())
    #expect(draft.effortLabel == "2 found")
    draft.selectDay("2026-03-10")
    #expect(draft.effortLabel == "None found")
}

@Test func addSheetStaysInsideTheMacsLimits() throws {
    struct Body: Decodable { var editLimits: EditLimits }
    let limits = try fixture("edits/odd_limits.json", as: Body.self).editLimits
    var draft = try addSheet(limits: limits)
    #expect(draft.days == ["2026-03-10", "2026-03-11", "2026-03-12"])
    for day in draft.days {
        draft.selectDay(day)
        #expect(draft.bounds.allows(draft.window, pauses: []))
    }
}

@Test func dateLabelsAcrossMidnight() throws {
    func labels(_ start: String, _ end: String) -> (start: String, end: String)? {
        ActivityTime.dateLabels(ActivityWindow(start: addTime(start), end: addTime(end)))
    }
    #expect(labels("2026-03-11T18:00:00Z", "2026-03-11T19:00:00Z") == nil)
    let march = try #require(labels("2026-03-12T23:40:00Z", "2026-03-13T00:40:00Z"))
    #expect(march.start == "Thu 12 Mar" && march.end == "Fri 13 Mar")
    let summer = try #require(labels("2026-06-10T22:30:00Z", "2026-06-10T23:30:00Z"))
    #expect(summer.start == "Wed 10 Jun" && summer.end == "Thu 11 Jun")
    #expect(ActivityTime.spokenDate(addTime("2026-03-12T23:40:00Z")) == "Thursday 12 March")
}
