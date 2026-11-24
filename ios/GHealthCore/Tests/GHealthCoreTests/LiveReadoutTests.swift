import Foundation
import Testing
@testable import GHealthCore

@Test func connectedBannerWaitsForItsFirstReading() {
    #expect(HeartRateBannerText.connected(bpm: 158) == "Live heart rate 158 bpm")
    #expect(HeartRateBannerText.connected(bpm: nil) == "Waiting for the first heart rate reading.")
}

private struct ReadoutCase: Sendable {
    var bpm: Int?
    var zone: Int?
    var hr: ActivityHRState
    var stale: Bool
    var heart: LiveReadout.Heart
    var status: LiveReadout.Status
    var value: String
    var unit: Bool
    var dimmed: Bool
    var statusText: String
    var statusSpoken: String
    var zoneText: String
    var zoneSpoken: String
    var chipText: String
    var chipSpoken: String
    var spoken: String
}

private let readoutCases: [ReadoutCase] = [
    .init(bpm: 158, zone: 4, hr: .live, stale: false, heart: .live, status: .zone(4), value: "158", unit: true, dimmed: false, statusText: "ZONE 4", statusSpoken: "Zone 4", zoneText: "ZONE 4", zoneSpoken: "Zone 4", chipText: "LIVE", chipSpoken: "Live", spoken: "158 bpm"),
    .init(bpm: 158, zone: nil, hr: .live, stale: false, heart: .live, status: .zoneUnknown, value: "158", unit: true, dimmed: false, statusText: "ZONE —", statusSpoken: "Zone unknown", zoneText: "ZONE —", zoneSpoken: "Zone unknown", chipText: "LIVE", chipSpoken: "Live", spoken: "158 bpm"),
    .init(bpm: nil, zone: nil, hr: .none, stale: false, heart: .none, status: .noHeartRate, value: "—", unit: false, dimmed: false, statusText: "NO HR", statusSpoken: "No heart rate", zoneText: "ZONE —", zoneSpoken: "Zone unknown", chipText: "NO HR", chipSpoken: "No heart rate", spoken: "No heart rate"),
    .init(bpm: 158, zone: 4, hr: .reconnecting, stale: false, heart: .lost, status: .reconnecting, value: "158", unit: true, dimmed: true, statusText: "RECONNECTING", statusSpoken: "Reconnecting", zoneText: "ZONE 4", zoneSpoken: "Zone 4", chipText: "RECONNECTING", chipSpoken: "Reconnecting", spoken: "158 bpm, reconnecting"),
    .init(bpm: 158, zone: nil, hr: .reconnecting, stale: false, heart: .lost, status: .reconnecting, value: "158", unit: true, dimmed: true, statusText: "RECONNECTING", statusSpoken: "Reconnecting", zoneText: "ZONE —", zoneSpoken: "Zone unknown", chipText: "RECONNECTING", chipSpoken: "Reconnecting", spoken: "158 bpm, reconnecting"),
    .init(bpm: 158, zone: 0, hr: .live, stale: false, heart: .live, status: .zone(0), value: "158", unit: true, dimmed: false, statusText: "ZONE 0", statusSpoken: "Zone 0", zoneText: "ZONE 0", zoneSpoken: "Zone 0", chipText: "LIVE", chipSpoken: "Live", spoken: "158 bpm"),
    .init(bpm: nil, zone: 4, hr: .live, stale: false, heart: .none, status: .noHeartRate, value: "—", unit: false, dimmed: false, statusText: "NO HR", statusSpoken: "No heart rate", zoneText: "ZONE —", zoneSpoken: "Zone unknown", chipText: "NO HR", chipSpoken: "No heart rate", spoken: "No heart rate"),
    .init(bpm: nil, zone: nil, hr: .none, stale: true, heart: .none, status: .noHeartRate, value: "—", unit: false, dimmed: false, statusText: "NO HR", statusSpoken: "No heart rate", zoneText: "ZONE —", zoneSpoken: "Zone unknown", chipText: "NO HR", chipSpoken: "No heart rate", spoken: "No heart rate"),
    .init(bpm: 158, zone: 4, hr: .live, stale: true, heart: .lost, status: .reconnecting, value: "158", unit: true, dimmed: true, statusText: "RECONNECTING", statusSpoken: "Reconnecting", zoneText: "ZONE 4", zoneSpoken: "Zone 4", chipText: "RECONNECTING", chipSpoken: "Reconnecting", spoken: "158 bpm, reconnecting"),
    .init(bpm: 158, zone: 4, hr: .none, stale: false, heart: .none, status: .noHeartRate, value: "—", unit: false, dimmed: false, statusText: "NO HR", statusSpoken: "No heart rate", zoneText: "ZONE —", zoneSpoken: "Zone unknown", chipText: "NO HR", chipSpoken: "No heart rate", spoken: "No heart rate")
]

@Test(arguments: readoutCases) private func readoutKeepsHeartRateApartFromZone(_ c: ReadoutCase) {
    let readout = LiveReadout(bpm: c.bpm, zone: c.zone, hr: c.hr, isStale: c.stale)
    #expect(readout.heart == c.heart && readout.status == c.status)
    #expect(readout.bpm == (c.heart == .none ? nil : c.bpm))
    #expect(readout.zone == (c.heart == .none ? nil : c.zone))
    #expect(readout.value == c.value && readout.showsUnit == c.unit && readout.dimmed == c.dimmed)
    #expect(readout.statusText == c.statusText && readout.statusSpoken == c.statusSpoken)
    #expect(readout.zoneText == c.zoneText && readout.zoneSpoken == c.zoneSpoken)
    #expect(readout.chipText == c.chipText && readout.chipSpoken == c.chipSpoken && readout.spoken == c.spoken)
    if c.bpm != nil, c.hr != .none {
        #expect(readout.statusText != "NO HR" && readout.chipText != "NO HR")
    }
    if c.stale, c.bpm != nil {
        #expect(readout == LiveReadout(bpm: c.bpm, zone: c.zone, hr: .reconnecting))
    }
}

@Test func readoutFollowsTheSessionClock() throws {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let full = LiveEstimator(restingHR: 56, maximumHR: 187, model: try engineConstants().strain)
    var session = ActivitySession(sport: .all[0], now: t)
    #expect(LiveReadout(session: session, estimate: full.estimate(session, now: t), now: t).heart == .none)
    #expect(session.liveUntil == nil)
    session.append(.init(t: t, bpm: 158))
    #expect(session.liveUntil == t.addingTimeInterval(10))
    for (offset, heart): (Double, LiveReadout.Heart) in [(9.9, .live), (10, .lost)] {
        let now = t.addingTimeInterval(offset)
        let readout = LiveReadout(session: session, estimate: full.estimate(session, now: now), now: now)
        #expect(readout.heart == heart && readout.zone == 4)
    }
    session.pause(at: t.addingTimeInterval(10))
    let now = t.addingTimeInterval(11)
    session.append(.init(t: now, bpm: 158))
    #expect(LiveReadout(session: session, estimate: full.estimate(session, now: now), now: now).heart == .live)
    for estimator in [LiveEstimator(restingHR: nil, maximumHR: 187, model: try engineConstants().strain), LiveEstimator(restingHR: 56, maximumHR: 187, model: nil)] {
        let readout = LiveReadout(session: session, estimate: estimator.estimate(session, now: now), now: now)
        #expect(readout.status == .zoneUnknown && readout.value == "158")
    }
}

@Test func contentStateReadoutMatchesTheSession() throws {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let full = LiveEstimator(restingHR: 56, maximumHR: 187, model: try engineConstants().strain)
    let missing = LiveEstimator(restingHR: 56, maximumHR: 187, model: nil)
    var session = ActivitySession(sport: .all[0], now: t)
    let empty = session
    session.append(.init(t: t, bpm: 158))
    var paused = session
    paused.pause(at: t.addingTimeInterval(10))
    paused.append(.init(t: t.addingTimeInterval(11), bpm: 158))
    for (s, now) in [(empty, t), (session, t.addingTimeInterval(9.9)), (session, t.addingTimeInterval(10)), (paused, t.addingTimeInterval(11))] {
        for estimator in [full, missing] {
            let estimate = estimator.estimate(s, now: now)
            let state = ActivityContentState(session: s, estimate: estimate, now: now)
            #expect(state.readout(isStale: false) == LiveReadout(session: s, estimate: estimate, now: now))
        }
    }
    let state = ActivityContentState(session: session, estimate: full.estimate(session, now: t), now: t)
    var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(state)) as? [String: Any])
    object["hr_state"] = "unknown"
    let decoded = try JSONCoding.decoder().decode(ActivityContentState.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.readout(isStale: false).heart == .none)
}

@Test func estimatorAvailabilityAndZoneTime() throws {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let model = try engineConstants().strain
    var session = ActivitySession(sport: .all[0], now: t)
    let empty = session
    session.append(.init(t: t, bpm: 158))
    for estimator in [LiveEstimator(restingHR: nil, maximumHR: 187, model: model), LiveEstimator(restingHR: 56, maximumHR: nil, model: model), LiveEstimator(restingHR: 56, maximumHR: 56, model: model), LiveEstimator(restingHR: 56, maximumHR: 55, model: model), LiveEstimator(restingHR: 56, maximumHR: 187, model: nil)] {
        #expect(!estimator.isAvailable)
        #expect(estimator.estimate(session, now: t.addingTimeInterval(90)).zones45Minutes == nil)
    }
    let full = LiveEstimator(restingHR: 56, maximumHR: 187, model: model)
    #expect(full.isAvailable)
    #expect(full.estimate(empty, now: t).zones45Minutes == nil)
    let estimate = full.estimate(session, now: t.addingTimeInterval(90))
    #expect(estimate.zones45Minutes == 1)
    #expect(estimate.zones45Minutes == Int(estimate.zones45Seconds / 60))
}

@Test func livePreviewsMatchTheirFixtures() throws {
    struct Seed: Decodable { var sport: String; var startOffset: Double; var bpm: [Double] }
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    let now = snapshot.generatedAt
    let estimator = LiveEstimator(restingHR: snapshot.day.strain.restingHrBpm.map(Double.init), maximumHR: snapshot.day.strain.maxHrBpm.map(Double.init), model: snapshot.day.scoreConstants?.strain)
    for (name, strain, average, maximum, minutes, projected): (String, Double, Int, Int, Int, Double) in [("boxing_23m", 7.9, 146, 161, 11, 14.1), ("paused", 5.6, 145, 161, 5, 13.5), ("stale", 7.9, 146, 161, 11, 14.1)] {
        let seed: Seed = try fixture("live/\(name).json")
        var session = ActivitySession(sport: .sport(seed.sport), now: now.addingTimeInterval(-seed.startOffset))
        for (i, bpm) in seed.bpm.enumerated() { session.append(.init(t: session.start.addingTimeInterval(Double(i)), bpm: bpm)) }
        if name == "paused" { session.pause(at: session.start.addingTimeInterval(760)) }
        let estimate = estimator.estimate(session, now: now)
        let target = SessionTarget.make(day: snapshot.day, sessionStart: session.start)?.projected(liveTrimp: estimate.trimp, scale: estimate.scale)
        print("live fixture \(name): strain \(String(describing: estimate.strain)), avg \(String(describing: estimate.average)), max \(String(describing: estimate.maximum)), zone \(String(describing: estimate.zone)), zones45 \(String(describing: estimate.zones45Minutes)), projected \(String(describing: target))")
        #expect(estimate.strain == strain && estimate.zone == 4)
        if name == "stale" {
            #expect(session.samples.last?.bpm == 159 && session.hrState(at: now) == .reconnecting)
        } else {
            #expect(estimate.average == average && estimate.maximum == maximum && estimate.zones45Minutes == minutes)
            #expect(target == projected)
        }
    }
    for (preview, bpm, zone, strain, average, paused, stale, status): (LivePreview, Int?, Int?, Double?, Int?, Bool, Bool, String) in [
        (.live, 158, 4, 7.9, 146, false, false, "ZONE 4"),
        (.liveTarget, 161, 4, 10.8, 152, false, false, "ZONE 4"),
        (.liveNoZone, 158, nil, nil, 146, false, false, "ZONE —"),
        (.liveNoHeartRate, nil, nil, nil, nil, false, false, "NO HR"),
        (.liveLost, 159, 4, 7.9, 146, false, true, "RECONNECTING"),
        (.livePaused, 158, 4, 5.6, 145, true, false, "ZONE 4")
    ] {
        let result = preview.make(now: now)
        #expect(result.state.bpm == bpm && result.state.zone == zone && result.state.strainEstimate == strain)
        #expect(result.state.avgHR == average && result.state.isPaused == paused && result.isStale == stale)
        #expect(result.state.readout(isStale: result.isStale).statusText == status)
        if preview == .liveTarget {
            #expect(result.state.dayStrain == 12.0 && result.state.targetLow == 11.6 && result.state.targetHigh == 14.6)
            #expect(result.state.targetWithin == true && result.state.elapsed == 48 * 60 + 10)
        }
    }
    #expect(LivePreview.allCases.map { $0.make(now: now).state.readout(isStale: $0 == .liveLost).statusText } == ["ZONE 4", "ZONE 4", "ZONE —", "NO HR", "RECONNECTING", "ZONE 4"])
}
