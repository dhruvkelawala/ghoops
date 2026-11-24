import Darwin
import Foundation
import Testing
@testable import GHealthCore

private func referenceDateDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid RFC 3339 time"))
    }
    return decoder
}

@Test(.serialized, arguments: responseFixtures)
func fixtureDatesMatchReferenceParser(_ url: URL) throws {
    func dates(in value: Any) throws {
        if let object = value as? [String: Any] {
            for item in object.values { try dates(in: item) }
        } else if let array = value as? [Any] {
            for item in array { try dates(in: item) }
        } else if let text = value as? String, text.count >= 20, text.first?.isNumber == true, text.contains("T") {
            let raw = try JSONEncoder().encode(text)
            let reference = try referenceDateDecoder().decode(Date.self, from: raw)
            let date = try JSONCoding.decoder().decode(Date.self, from: raw)
            #expect(abs(reference.timeIntervalSince(date)) < 0.001, "\(url.lastPathComponent)")
        }
    }
    try dates(in: JSONSerialization.jsonObject(with: Data(contentsOf: url)))
}

@Test func dateStrategyKeepsOffsetsFractionsAndError() throws {
    for text in ["2026-03-10T06:29:35Z", "2026-03-10T07:29:35+01:00", "2026-03-10T01:29:35-05:00", "2026-03-10T07:29:35.600123+01:00", "2026-03-10T06:29:35.600123Z"] {
        let raw = try JSONEncoder().encode(text)
        let date = try JSONCoding.decoder().decode(Date.self, from: raw)
        let reference = try referenceDateDecoder().decode(Date.self, from: raw)
        #expect(abs(date.timeIntervalSince(reference)) < 0.001)
    }
    do {
        _ = try JSONCoding.decoder().decode(Date.self, from: Data(#""not a time""#.utf8))
        Issue.record("Invalid time accepted")
    } catch DecodingError.dataCorrupted(let context) {
        #expect(context.debugDescription == "Invalid RFC 3339 time")
    }
}

@Test func twentyEditedSnapshotsDecodeUnderOneSecond() throws {
    let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("edits/snapshot_edited.json"))
    let start = try threadCPUTime()
    for _ in 0..<20 { _ = try JSONCoding.decoder().decode(Snapshot.self, from: data) }
    let elapsed = try threadCPUTime() - start
    print("20 edited snapshot decodes used \(elapsed) of thread CPU time")
    #expect(elapsed < .seconds(1))
}

private func threadCPUTime() throws -> Duration {
    var time = timespec()
    try #require(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0)
    return .seconds(time.tv_sec) + .nanoseconds(time.tv_nsec)
}
