import Foundation
import Testing
@testable import GHealthCore

struct GoopTrendTests {
    @Test(arguments: [
        (TrendWindow.Range.week, "2026-03-04", "2026-02-25", "2026-03-03"),
        (.month, "2026-02-09", "2026-01-10", "2026-02-08"),
        (.sixMonths, "2025-09-12", "2025-03-16", "2025-09-11")
    ])
    func windowsAndNavigation(_ range: TrendWindow.Range, _ start: String, _ priorStart: String, _ priorEnd: String) {
        let window = TrendWindow(range: range, end: "2026-03-10")
        #expect(window.start == start)
        #expect(window.prior.start == priorStart)
        #expect(window.prior.end == priorEnd)
        #expect(!window.canNext(defaultDate: "2026-03-10"))
        #expect(window.canPrevious(oldestDate: priorEnd))
        #expect(!window.canPrevious(oldestDate: start))
        #expect(!window.canPrevious(oldestDate: nil))
        #expect(window.prior.next(defaultDate: "2026-03-10") == window)
        let near = TrendWindow(range: range, end: "2026-03-09")
        #expect(near.canNext(defaultDate: "2026-03-10"))
        #expect(near.next(defaultDate: "2026-03-10").end == "2026-03-10")
    }

    @Test func windowMeansIgnoreNullsAndRoundToMetricPrecision() throws {
        let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
        var row = try #require(snapshot.days.days.last)
        row.date = "2026-03-10"; row.hrvRmssdMs = 56.4; row.strain = 12.34; row.asleepMinutes = 415
        var second = row; second.date = "2026-03-09"; second.hrvRmssdMs = 56.6; second.strain = 12.56; second.asleepMinutes = 416
        var missing = row; missing.date = "2026-03-08"; missing.hrvRmssdMs = nil
        var outside = row; outside.date = "2026-03-03"; outside.hrvRmssdMs = 100
        let window = TrendWindow(end: "2026-03-10")
        let summary = window.summary(rows: [row, second, missing, outside], metric: .hrv)
        #expect(summary.available == 2)
        #expect(summary.mean == 57)
        #expect(window.summary(rows: [row, second], metric: .strain).mean == 12.5)
        #expect(window.summary(rows: [row, second], metric: .hours).mean == 416)
        #expect(window.summary(rows: [missing], metric: .hrv).mean == nil)
    }

    @Test func sixMonthCurrentAndPriorUseFourBoundedRequestsAndCache() async throws {
        let body: Days = try fixture("days_full.json")
        let client = DaysStub(body: body)
        let store = TrendStore(defaultDate: "2026-03-10", seed: [], client: client)
        let window = TrendWindow(range: .sixMonths, end: "2026-03-10")
        let current = try await store.rows(from: window.start, to: window.end)
        let prior = try await store.rows(from: window.prior.start, to: window.prior.end)
        #expect(current.count == 180); #expect(prior.count == 180)
        let requests = await client.requests
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { GoopFormat.dates(from: $0.0, to: $0.1).count <= 90 && $0.1 <= "2026-03-10" })
        #expect(requests.first?.1 == "2026-03-10")
        #expect(requests[1].1 == "2025-12-10")
        _ = try await store.rows(from: window.prior.start, to: window.end)
        #expect(await client.requests.count == 4)
    }

    @Test func snapshotRowsWinAndMissingRunsStaySeparate() async throws {
        let body: Days = try fixture("days_full.json")
        var seed = try #require(body.days.last)
        seed.date = "2026-03-08"; seed.hrvRmssdMs = 123
        let client = DaysStub(body: body)
        let store = TrendStore(defaultDate: "2026-03-10", seed: [seed], client: client)
        let rows = try await store.rows(from: "2026-03-06", to: "2026-03-12")
        #expect(rows.count == 5)
        #expect(rows.first { $0.date == "2026-03-08" }?.hrvRmssdMs == 123)
        let requests = await client.requests
        #expect(requests.count == 2)
        #expect(requests[0].0 == "2026-03-09" && requests[0].1 == "2026-03-10")
        #expect(requests[1].0 == "2026-03-06" && requests[1].1 == "2026-03-07")
    }

    @Test func failedChunkThrowsAndKeepsEarlierChunks() async throws {
        let body: Days = try fixture("days_full.json")
        let client = DaysStub(body: body, failure: 2)
        let store = TrendStore(defaultDate: "2026-03-10", seed: [], client: client)
        let window = TrendWindow(range: .sixMonths, end: "2026-03-10")
        await #expect(throws: ClientError.offline) { try await store.rows(from: window.start, to: window.end) }
        #expect(await client.requests.count == 2)
        let newest = try await store.rows(from: "2025-12-11", to: "2026-03-10")
        #expect(newest.count == 90)
        #expect(await client.requests.count == 2)
        let all = try await store.rows(from: window.start, to: window.end)
        #expect(all.count == 180)
        #expect(await client.requests.count == 3)
    }
}

private actor DaysStub: DaysFetching {
    let body: Days
    let failure: Int?
    var requests: [(String, String)] = []
    init(body: Days, failure: Int? = nil) { self.body = body; self.failure = failure }
    func days(from: String, to: String) async throws -> Days {
        requests.append((from, to))
        if requests.count == failure { throw ClientError.offline }
        var response = body
        response.from = from; response.to = to
        response.days = GoopFormat.dates(from: from, to: to).map { date in
            var row = body.days[0]
            row.date = date
            return row
        }
        return response
    }
}
