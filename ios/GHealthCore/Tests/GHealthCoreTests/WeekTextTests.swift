import Foundation
import Testing
@testable import GHealthCore

@Test func weekInProgressSaysSoFarAndCountsUp() throws {
    let week: Week = try fixture("preview/week_this.json")
    #expect(WeekText.span(week) == "Mon 9 – Sun 15 Mar · so far")
    #expect(WeekText.legend(week).shown == "This week" && WeekText.legend(week).compared == "Same days last week")
    #expect(WeekText.Target.allCases.map { WeekText.progress($0, in: week).value } == ["1", "2:25", "0"])
    #expect(WeekText.Target.allCases.map { WeekText.progress($0, in: week).unit } == ["of 5", "of 2:30", "of 2"])
    #expect(WeekText.Target.allCases.compactMap { WeekText.statusWord(WeekText.status($0, in: week)) } == ["SO FAR", "SO FAR", "SO FAR"])
    #expect(WeekText.Target.allCases.allSatisfy { WeekText.statusDetail($0, in: week) == nil })
    #expect(WeekText.cardSpoken(week) == "Week in review, Monday 9 to Sunday 15 March, so far. Sleep, 1 of 5 nights. Zone minutes, 2 hours 25 of 2 hours 30. Strength, 0 of 2 days.")
}

@Test func finishedWeekNamesEachStatusAndTheMissingNight() throws {
    let week: Week = try fixture("preview/week_last.json")
    #expect(WeekText.span(week) == "Mon 2 – Sun 8 Mar")
    #expect(WeekText.legend(week).shown == "Last week" && WeekText.legend(week).compared == "Week before")
    #expect(WeekText.Target.allCases.compactMap { WeekText.statusWord(WeekText.status($0, in: week)) } == ["NO DATA", "MET", "NOT MET"])
    #expect(WeekText.statusDetail(.sleep, in: week) == "· 1 night missing")
    #expect(WeekText.statusDetail(.activity, in: week) == nil)
    #expect(WeekText.progress(.activity, in: week).value == "3:42")
    let sleep = try #require(WeekText.sections(week).first)
    #expect(sleep.title == "SLEEP")
    #expect(sleep.rows.map(\.note) == ["1 night missing", "1 night missing", "1 night missing"])
    let strain = try #require(WeekText.sections(week).first { $0.title == "STRAIN" })
    #expect(strain.rows.allSatisfy { $0.note == nil })
}

@Test func targetWordsComeFromTheMacsNumbers() throws {
    var week: Week = try fixture("week_full.json")
    #expect(WeekText.label(.sleep, in: week) == "Nights of 7 h or more")
    #expect(WeekText.activityRule(week) == "Zones 4–5 count 2 times") // goop-lint: allow enginenumber: expected copy
    week.targets.sleep.minMinutes = 450
    week.targets.activity.vigorousWeight = 3
    week.targets.sleep.nights = 6
    #expect(WeekText.label(.sleep, in: week) == "Nights of 7 h 30 min or more")
    #expect(WeekText.activityRule(week) == "Zones 4–5 count 3 times") // goop-lint: allow enginenumber: expected copy
    #expect(WeekText.progress(.sleep, in: week).unit == "of 6")
    #expect(WeekText.statusDetail(.activity, in: week) == "· 6 days missing")
    #expect(WeekText.statusWord("future_status") == nil)
}

@Test func weekWithoutZonesShowsADash() throws {
    var week: Week = try fixture("preview/week_this.json")
    week.targets.activity.creditMinutes = nil
    #expect(WeekText.progress(.activity, in: week).value == "—")
    #expect(WeekText.cardSpoken(week).contains("Zone minutes, no data of 2 hours 30"))
}
