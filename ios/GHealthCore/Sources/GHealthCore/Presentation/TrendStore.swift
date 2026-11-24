import Foundation

public protocol DaysFetching: Sendable {
    func days(from: String, to: String) async throws -> Days
}

public actor TrendStore {
    private var rows: [String: DayRow]
    private let defaultDate: String
    private let client: any DaysFetching

    public init(defaultDate: String, seed: [DayRow], client: any DaysFetching) {
        self.defaultDate = defaultDate
        self.rows = Dictionary(seed.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
        self.client = client
    }

    public func rows(from: String, to: String) async throws -> [DayRow] {
        let dates = GoopFormat.dates(from: from, to: min(to, defaultDate))
        let missing = dates.filter { rows[$0] == nil }
        var runs: [[String]] = []
        for date in missing {
            if let last = runs.last?.last, GoopFormat.addingDays(1, to: last) == date { runs[runs.count - 1].append(date) }
            else { runs.append([date]) }
        }
        for run in runs.reversed() {
            var end = run.count
            while end > 0 {
                let start = max(0, end - 90)
                let response = try await client.days(from: run[start], to: run[end - 1])
                for row in response.days where row.date >= run[start] && row.date <= run[end - 1] && rows[row.date] == nil {
                    rows[row.date] = row
                }
                end = start
            }
        }
        return dates.compactMap { rows[$0] }
    }
}
