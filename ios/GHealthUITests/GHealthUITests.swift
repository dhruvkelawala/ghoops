import UIKit
import XCTest

final class GHealthUITests: XCTestCase {
    @MainActor func testSleepEditFlow() {
        continueAfterFailure = false
        let app = sleepApp("detail")
        let open = app.buttons["sleep-edit-open"]
        reveal(open, in: app)
        XCTAssertTrue(open.isHittable)
        capture("sleep-edit-sleep", app: app)
        open.tap()
        XCTAssertTrue(app.buttons["sleep-edit-save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sleep-edit-save"].isEnabled)
        XCTAssertEqual(app.staticTexts["sleep-edit-value-asleep"].label, "6:55")
        let chart = app.descendants(matching: .any)["sleep-edit-chart"]
        let handle = app.descendants(matching: .any)["sleep-edit-handle-end"]
        let from = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 72.25 / 797 * (chart.frame.width - 60), dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(handle.label, "Wake, 07:41")
        XCTAssertEqual(app.staticTexts["sleep-edit-value-asleep"].label, "8:07")
        XCTAssertTrue(app.descendants(matching: .any)["sleep-edit-start-date"].exists)
        capture("sleep-edit-edit", app: app)
        app.buttons["sleep-edit-save"].tap()
        XCTAssertTrue(app.buttons["sleep-edit-save"].waitForNonExistence(timeout: 8))
        let footnote = app.descendants(matching: .any)["sleep-edited-footnote"]
        reveal(footnote, in: app)
        XCTAssertTrue(footnote.waitForExistence(timeout: 8))
        XCTAssertEqual(footnote.label, "Edited in ghoops. Google Health has 23:12 to 06:29.")
        XCTAssertTrue(app.staticTexts["8:29"].exists)
        capture("sleep-edit-edited", app: app)
        app.terminate()

        // A shortening that waits, then settles: the Mac's values replace the projection (oss-data-audit row 3).
        let settle = sleepApp("reconnect", wake: "05:59")
        XCTAssertTrue(settle.descendants(matching: .any)["change-waiting-banner"].waitForExistence(timeout: 8))
        XCTAssertEqual(settle.staticTexts["insight-text"].label, "Your Sleep Performance will update once your Mac has the change to your sleep. You slept 6:31.")
        XCTAssertFalse(settle.buttons["contributor-sleep_performance"].label.contains("94"))
        capture("sleep-edit-short-before-retry", app: settle)
        XCUIDevice.shared.press(.home)
        settle.activate()
        XCTAssertTrue(settle.descendants(matching: .any)["change-waiting-banner"].waitForNonExistence(timeout: 8))
        let settled = settle.staticTexts["insight-text"]
        XCTAssertTrue(settled.waitForLabel(prefix: "Your Sleep Performance is optimal. You got 6:31 of the 7:23 you needed.", timeout: 8), settled.label)
        XCTAssertTrue(settle.buttons["contributor-sleep_performance"].label.contains("88"))
        capture("sleep-edit-short-settled", app: settle)
        settle.buttons["back-button"].tap()
        let settledTile = settle.buttons["tile-sleep_performance"]
        reveal(settledTile, in: settle)
        XCTAssertTrue(settledTile.label.contains("88"))
        XCTAssertTrue(settle.buttons["tile-hours"].label.contains("6:31"))
        capture("sleep-edit-short-settled-home", app: settle)
        settle.terminate()
    }

    @MainActor func testSleepEditRestore() {
        continueAfterFailure = false
        let app = sleepApp(nil, set: "sleep_edit")
        reveal(app.buttons["sleep-edit-open"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["sleep-edited-footnote"].exists)
        app.buttons["sleep-edit-open"].tap()
        let restore = app.buttons["sleep-edit-restore"]
        reveal(restore, in: app)
        restore.tap()
        XCTAssertTrue(app.alerts["Restore Google's times?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Restore"].tap()
        XCTAssertTrue(app.buttons["sleep-edit-save"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sleep-edit-open"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["sleep-edited-footnote"].exists)
        XCTAssertTrue(app.staticTexts["7:17"].exists)
        capture("sleep-edit-restored", app: app)
        app.terminate()
    }

    @MainActor func testSleepEditLimits() {
        continueAfterFailure = false
        for key in ["old", "no_stages"] {
            let app = sleepApp(key)
            let note = app.descendants(matching: .any)[key == "old" ? "sleep-edit-horizon" : "sleep-edit-no-stages"]
            reveal(note, in: app)
            XCTAssertTrue(note.exists)
            XCTAssertFalse(app.buttons["sleep-edit-open"].exists)
            XCTAssertEqual(note.label, key == "old" ? "Only nights from the last 30 days can be edited." : "This night has no sleep stages from your band, so ghoops can't edit it.")
            capture("sleep-edit-\(key)", app: app)
            app.terminate()
        }
    }

    @MainActor func testSleepEditWaitingAndRollback() {
        continueAfterFailure = false
        for key in ["waiting", "rollback"] {
            let app = sleepApp(key)
            let banner = app.descendants(matching: .any)[key == "waiting" ? "change-waiting-banner" : "change-rollback-banner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 8))
            if key == "rollback" { XCTAssertTrue(app.staticTexts["NOT SAVED"].exists) }
            capture(key == "rollback" ? "sleep-edit-error" : "sleep-edit-waiting", app: app)
            app.buttons["back-button"].tap()
            let row = app.buttons["sleep-activity-link"]
            reveal(row, in: app)
            if key == "waiting" { XCTAssertTrue(row.label.contains("waiting for your Mac")) }
            else { XCTAssertTrue(app.descendants(matching: .any)["change-rollback-banner-0"].exists) }
            app.terminate()
        }

        // A three-hour shortening shows its hours at once and never the old verdict; a refusal restores Google's night (oss-data-audit row 3).
        for key in ["waiting", "rollback"] {
            let app = sleepApp(key, wake: "03:29")
            let banner = app.descendants(matching: .any)[key == "waiting" ? "change-waiting-banner" : "change-rollback-banner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 8))
            let insight = app.staticTexts["insight-text"]
            let performance = app.buttons["contributor-sleep_performance"]
            var hours = "6:55"
            if key == "waiting" {
                let prefix = "Your Sleep Performance will update once your Mac has the change to your sleep. You slept "
                XCTAssertTrue(insight.label.hasPrefix(prefix), insight.label)
                hours = String(insight.label.dropFirst(prefix.count).dropLast())
                XCTAssertNotEqual(hours, "6:55")
                XCTAssertTrue(performance.waitForLabel(containing: "updating", timeout: 5))
                XCTAssertFalse(performance.label.contains("94"))
            } else {
                XCTAssertTrue(insight.label.hasPrefix("Your Sleep Performance is optimal. You got 6:55 of the 7:23 you needed."), insight.label)
                XCTAssertTrue(performance.label.contains("94"))
            }
            capture("sleep-edit-short-\(key)", app: app)
            app.buttons["info-button"].tap()
            let scale = app.descendants(matching: .any)["scale-hours"]
            reveal(scale, in: app)
            XCTAssertTrue(scale.label.hasPrefix(key == "rollback" ? "Hours vs. needed, 94%." : "Hours vs. needed, no value."), scale.label)
            XCTAssertEqual(scale.label.contains("Today:"), key == "rollback")
            capture("sleep-edit-short-\(key)-info", app: app)
            app.buttons["sheet-close"].tap()
            reveal(insight, in: app)
            capture("sleep-edit-short-\(key)-insight", app: app)
            for _ in 0..<3 { scrollPage(app, up: false) }
            app.buttons["back-button"].tap()
            let tile = app.buttons["tile-sleep_performance"]
            reveal(tile, in: app)
            XCTAssertEqual(tile.label.contains("94"), key == "rollback")
            if key == "waiting" { XCTAssertTrue(tile.waitForLabel(containing: "updating", timeout: 5)) }
            XCTAssertTrue(app.buttons["tile-hours"].label.contains(hours))
            capture("sleep-edit-short-\(key)-home", app: app)
            app.terminate()
        }
    }

    @MainActor func testSleepEditUpdating() {
        continueAfterFailure = false
        let app = sleepApp("saving")
        XCTAssertTrue(app.staticTexts["UPDATING"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["contributor-sleep_performance"].label.contains("updating"))
        XCTAssertTrue(app.buttons["contributor-consistency"].label.contains("updating"))
        XCTAssertTrue(app.buttons["contributor-efficiency"].label.contains("96"))
        XCTAssertFalse(app.buttons["contributor-efficiency"].label.contains("updating"))
        XCTAssertTrue(app.staticTexts["—"].firstMatch.exists)
        XCTAssertEqual(app.staticTexts["insight-text"].label, "Your Sleep Performance will update once your Mac has the change to your sleep. You slept 8:07.")
        capture("sleep-edit-saving", app: app)
        app.buttons["back-button"].tap()
        let tile = app.buttons["tile-sleep_performance"]
        reveal(tile, in: app)
        XCTAssertEqual(tile.label, "Sleep Performance, updating")
        XCTAssertTrue(app.buttons["tile-hours"].label.contains("8:07"))
        app.terminate()
    }

    @MainActor private func sleepApp(_ key: String?, set: String = "fresh", large: Bool = false, wake: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", set]
        if let key { app.launchArguments += ["-GHealthSleepEditFixture", key] }
        if let wake { app.launchArguments += ["-GHealthSleepEditWake", wake] }
        if large { app.launchArguments += ["-GHealthAccessibility5"] }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor func testSleepClassicAndUnknownStages() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "sleep_classic"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        // Classic sleep keeps its duration and draws no stage it never had (oss-data-audit row 4).
        let classic = app.descendants(matching: .any)["hypnogram"]
        reveal(classic, in: app)
        XCTAssertEqual(classic.label, "Classic sleep: no sleep stages for this night")
        XCTAssertTrue(app.staticTexts["7:17"].exists)
        capture("sleep-classic-card", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "sleep_unknown_stage"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        let chart = app.descendants(matching: .any)["hypnogram"]
        reveal(chart, in: app)
        XCTAssertEqual(chart.value as? String, "Unknown stage 00:46 to 01:04, 18 minutes")
        XCTAssertTrue(app.buttons["stage-rem"].exists)
        capture("sleep-unknown-stage-card", app: app)
        app.terminate()
    }

    @MainActor func testSleepUnstaged() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "sleep_unstaged"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        capture("sleep-unstaged-top", app: app)
        let row = app.buttons["stage-unstaged"]
        reveal(row, in: app)
        XCTAssertEqual(row.label, "Unstaged, 15 percent, 1 hour 12 minutes")
        let chart = app.descendants(matching: .any)["hypnogram"]
        XCTAssertEqual(chart.value as? String, "Unstaged 06:29 to 07:41, 72 minutes")
        capture("sleep-unstaged-card", app: app)
        row.tap()
        XCTAssertTrue(row.isSelected)
        capture("sleep-unstaged-selected", app: app)
        for _ in 0..<3 { scrollPage(app, up: false) }
        app.buttons["info-button"].tap()
        let note = app.staticTexts["Includes 1:12 without stages"]
        reveal(note, in: app)
        XCTAssertTrue(note.exists)
        capture("sleep-unstaged-info", app: app)
        let rule = app.staticTexts["Time in a night with no sleep stages counts as sleep. It shows as unstaged."]
        reveal(rule, in: app)
        XCTAssertTrue(rule.exists)
        capture("sleep-unstaged-rule", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        capture("sleep-fresh-top", app: app)
        reveal(app.buttons["stage-rem"], in: app)
        XCTAssertFalse(app.buttons["stage-unstaged"].exists)
        capture("sleep-fresh-card", app: app)
        app.terminate()
    }

    @MainActor func testGoopTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["recovery-link"].label, "Recovery, 73 percent, high")
        XCTAssertTrue(app.buttons["monitor-health-link"].label.contains("outside range"))
        XCTAssertTrue(app.buttons["sleep-activity-link"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-link-")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["My Day"].exists)
        XCTAssertTrue(app.staticTexts["My Dashboard"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "CUSTOMIZE")).firstMatch.exists)
        capture("fresh-home", app: app)
        scrollPage(app, up: true)
        capture("fresh-home-2", app: app)
        scrollPage(app, up: true)
        capture("fresh-home-3", app: app)
        let tiles = ["hrv", "sleep_performance", "hours", "resting_hr", "steps"].map { app.buttons["tile-\($0)"] }
        XCTAssertTrue(tiles.allSatisfy { $0.exists })
        XCTAssertEqual(tiles.map { $0.frame.minY }, tiles.map { $0.frame.minY }.sorted())
        scrollPage(app, up: false)
        scrollPage(app, up: false)
        app.buttons["recovery-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["recovery-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["contributor-hrv"].exists)
        capture("fresh-recovery", app: app)
        app.buttons["contributor-hrv"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend-view-screen"].waitForExistence(timeout: 5))
        app.buttons["back-button"].tap()
        XCTAssertTrue(app.buttons["insight-action"].exists)
        XCTAssertTrue(app.staticTexts["BREAK DOWN MY RECOVERY"].exists)
        scrollPage(app, up: true)
        XCTAssertTrue(app.buttons["weekly-trend-recovery"].exists)
        capture("fresh-recovery-2", app: app)
        app.buttons["insight-action"].tap()
        XCTAssertTrue(app.staticTexts["RECOVERY"].exists)
        capture("fresh-recovery-sheet", app: app)
        app.buttons["sheet-close"].tap()
        XCTAssertFalse(app.buttons["sheet-close"].exists)
        scrollPage(app, up: false)
        scrollPage(app, up: false)
        app.buttons["back-button"].tap()
        app.buttons["strain-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["strain-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Strain, 12.8 of 21, moderate, so far")).firstMatch.exists)
        XCTAssertTrue(app.buttons["contributor-zones_1_3"].exists)
        XCTAssertTrue(app.staticTexts["SO FAR"].exists)
        XCTAssertTrue(app.staticTexts["EXPLORE MY STRAIN"].exists)
        capture("fresh-strain", app: app)
        scrollPage(app, up: true)
        capture("fresh-strain-2", app: app)
        XCTAssertTrue(app.buttons["weekly-trend-strain"].exists)
        app.buttons["insight-action"].tap()
        capture("fresh-strain-sheet", app: app)
        app.buttons["sheet-close"].tap()
        scrollPage(app, up: false)
        scrollPage(app, up: false)
        app.buttons["back-button"].tap()
        app.buttons["sleep-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["DIVE INTO MY SLEEP"].exists)
        capture("fresh-sleep", app: app)
        scrollPage(app, up: true)
        XCTAssertTrue(app.descendants(matching: .any)["hypnogram"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Typical range")).firstMatch.exists)
        capture("fresh-sleep-2", app: app)
        scrollPage(app, up: true)
        capture("fresh-sleep-3", app: app)
        XCTAssertTrue(app.staticTexts["RESTORATIVE SLEEP"].exists)
        app.buttons["stage-deep"].tap()
        XCTAssertTrue(app.buttons["stage-deep"].isSelected)
        scrollPage(app, up: false)
        capture("fresh-sleep-stage-selected", app: app)
        scrollPage(app, up: true)
        scrollPage(app, up: true)
        XCTAssertTrue(app.staticTexts["HOURS VS. NEEDED"].exists)
        capture("fresh-sleep-4", app: app)
        for _ in 0..<4 { scrollPage(app, up: false) }
        app.buttons["info-button"].tap()
        capture("fresh-sleep-sheet", app: app)
        app.buttons["sheet-close"].tap()
        app.buttons["back-button"].tap()
        let workout = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-link-")).firstMatch
        reveal(workout, in: app)
        workout.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ACTIVITY STRAIN"].exists)
        XCTAssertTrue(app.staticTexts["AVERAGE HR"].exists)
        capture("fresh-workout", app: app)
        scrollPage(app, up: true)
        capture("fresh-workout-2", app: app)
        XCTAssertTrue(app.staticTexts["ZONE 5"].exists)
        XCTAssertTrue(app.staticTexts["ZONE 0"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "heart rate reserve")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Wrist heart rate can read low in boxing and weightlifting, so Strain and zones may be low."].exists)
        scrollPage(app, up: false)
        scrollPage(app, up: false)
        app.buttons["back-button"].tap()
        scrollPage(app, up: true)
        app.buttons["tile-hrv"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend-view-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["metric-picker"].label.contains("Heart Rate Variability"))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Typical range")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["range-next"].isEnabled)
        capture("fresh-trend-hrv-w", app: app)
        app.buttons["range-M"].tap()
        Thread.sleep(forTimeInterval: 1)
        capture("fresh-trend-hrv-m", app: app)
        app.buttons["range-6M"].tap()
        XCTAssertTrue(app.staticTexts["Needs a connection to your Mac"].waitForExistence(timeout: 5))
        capture("fresh-trend-6m-offline", app: app)
        app.buttons["back-button"].tap()
        app.buttons["tab-trends"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trends-screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["back-button"].exists)
        capture("fresh-trends-tab", app: app)
        app.buttons["tab-health"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["health-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HEALTH MONITOR"].exists)
        XCTAssertTrue(app.staticTexts["Overnight Vitals"].exists)
        XCTAssertTrue(app.buttons["vital-respiratory_rate"].label.contains("above typical range"))
        capture("fresh-health", app: app)
        scrollPage(app, up: true)
        capture("fresh-health-2", app: app)
        app.buttons["view-trends"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend-view-screen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["metric-picker"].label, "Heart Rate Variability")
        app.buttons["metric-picker"].tap()
        XCTAssertTrue(app.buttons["metric-resting_hr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["metric-hrv"].isSelected)
        capture("fresh-metric-sheet", app: app)
        app.buttons["metric-resting_hr"].tap()
        XCTAssertTrue(app.buttons["metric-resting_hr"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["metric-picker"].label, "Resting Heart Rate")
        app.buttons["back-button"].tap()
        app.buttons["tab-more"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["more-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["PAIRED MAC"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Mac"].exists)
        XCTAssertTrue(app.buttons["UNPAIR"].exists)
        app.buttons["test-connection"].tap()
        XCTAssertEqual(app.staticTexts["connection-result"].label, "200 · 0 ms")
        capture("fresh-more", app: app)
        scrollPage(app, up: true)
        capture("fresh-more-2", app: app)
        scrollPage(app, up: true)
        capture("fresh-more-3", app: app)
        scrollPage(app, up: true)
        capture("fresh-more-4", app: app)
        XCTAssertTrue(app.staticTexts["OPEN-SOURCE FONTS"].exists)
        XCTAssertTrue(app.buttons["fixture-mode"].isHittable)
        app.buttons["tab-home"].tap()
        scrollPage(app, up: false)
        scrollPage(app, up: false)
        app.buttons["activities-expand"].tap()
        XCTAssertTrue(app.buttons["sheet-close"].waitForExistence(timeout: 5))
        capture("fresh-activities-sheet", app: app)
        app.descendants(matching: .any)["activities-sheet"].buttons["sleep-activity-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sheet-close"].exists)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "unpaired"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pairing-screen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab-home"].exists)
        capture("unpaired-pairing", app: app)
        app.terminate()
    }
    @MainActor func testNavigationShell() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        for (tab, screen) in [("health", "health"), ("trends", "trends"), ("more", "more"), ("home", "today")] {
            app.buttons["tab-\(tab)"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["\(screen)-screen"].waitForExistence(timeout: 5))
        }
        app.buttons["recovery-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["recovery-screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-home"].exists)
        app.buttons["back-button"].tap()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 5))
        app.buttons["recovery-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["recovery-screen"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["tab-home"].waitForExistence(timeout: 5))
        app.buttons["date-prev"].tap()
        XCTAssertTrue(app.staticTexts["Needs a connection to your Mac"].waitForExistence(timeout: 5))
        app.buttons["BACK TO TODAY"].tap()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["date-label"].label.contains("today"))
        app.terminate()
    }
    @MainActor func testStatesTour() {
        continueAfterFailure = false
        for set in ["stale", "no_sleep", "calibrating", "new_user", "offline", "unpaired", "fresh"] {
            let app = XCUIApplication()
            app.launchArguments = ["-GHealthFixture", set]
            app.launch()
            let screen = set == "unpaired" ? "pairing" : "today"
            XCTAssertTrue(app.descendants(matching: .any)["\(screen)-screen"].waitForExistence(timeout: 15))
            if set == "unpaired" {
                XCTAssertFalse(app.buttons["tab-home"].exists)
                capture("unpaired-pairing", app: app)
                app.terminate()
                continue
            }
            if set == "fresh" {
                app.buttons["date-prev"].tap()
                XCTAssertTrue(app.staticTexts["Needs a connection to your Mac"].waitForExistence(timeout: 5))
                capture("fresh-past-day", app: app)
                app.buttons["tab-health"].tap()
                XCTAssertTrue(app.staticTexts["Needs a connection to your Mac"].waitForExistence(timeout: 5))
                capture("fresh-past-day-health", app: app)
                app.buttons["BACK TO TODAY"].tap()
                XCTAssertTrue(app.buttons["vital-hrv_rmssd"].waitForExistence(timeout: 5))
                app.buttons["tab-home"].tap()
                XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 5))
                app.terminate()
                continue
            }
            switch set {
            case "stale":
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Your Mac last collected data")).firstMatch.exists)
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Updated ")).firstMatch.exists)
            case "no_sleep":
                XCTAssertEqual(app.buttons["recovery-link"].label, "Recovery, no data")
                XCTAssertTrue(app.staticTexts["Waiting for last night's sleep"].firstMatch.exists)
                XCTAssertFalse(app.buttons["sleep-activity-link"].exists)
            case "calibrating": XCTAssertTrue(app.staticTexts["Calibrating"].exists)
            case "new_user": XCTAssertTrue(app.staticTexts["Calibrating: 3 of 7 nights"].exists)
            case "offline": XCTAssertTrue(app.staticTexts["Offline. Showing your saved data."].exists)
            default: break
            }
            capture("\(set)-home", app: app)
            for detail in ["recovery", "strain", "sleep", "workout"] {
                let button = detail == "workout" ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-link-")).firstMatch : app.buttons["\(detail)-link"]
                if detail == "workout" && set == "no_sleep" { continue }
                reveal(button, in: app)
                button.tap()
                XCTAssertTrue(app.descendants(matching: .any)["\(detail)-screen"].waitForExistence(timeout: 5))
                if detail == "recovery" && ["no_sleep", "calibrating"].contains(set) { capture("\(set)-recovery", app: app) }
                if (set == "stale" && ["recovery", "sleep"].contains(detail)) || (set == "offline" && ["strain", "workout"].contains(detail)) {
                    capture("\(set)-\(detail)", app: app)
                }
                if detail == "recovery" && set == "calibrating" {
                    scrollPage(app, up: true)
                    XCTAssertTrue(app.staticTexts["CALIBRATING"].firstMatch.exists)
                    capture("calibrating-recovery-2", app: app)
                    scrollPage(app, up: false)
                }
                if detail == "sleep" && set == "no_sleep" {
                    XCTAssertTrue(app.staticTexts["Waiting for last night's sleep"].firstMatch.exists)
                    XCTAssertEqual(app.buttons["contributor-consistency"].label, "Sleep Consistency, —")
                    XCTAssertEqual(app.buttons["contributor-sleep_performance"].label, "HOURS VS. NEEDED, —")
                    XCTAssertEqual(app.buttons["contributor-efficiency"].label, "Sleep Efficiency, —")
                    capture("no_sleep-sleep", app: app)
                    scrollPage(app, up: true)
                    XCTAssertTrue(app.staticTexts["TONIGHT'S NEED SO FAR"].exists)
                    capture("no_sleep-sleep-2", app: app)
                    scrollPage(app, up: false)
                }
                if detail == "sleep" && set == "new_user" {
                    scrollPage(app, up: true)
                    capture("new_user-sleep-2", app: app)
                    scrollPage(app, up: false)
                }
                app.buttons["back-button"].tap()
                for _ in 0..<3 { scrollPage(app, up: false) }
            }
            app.buttons["tab-health"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["health-screen"].waitForExistence(timeout: 5))
            if set == "new_user" {
                XCTAssertTrue(app.staticTexts["Building baseline"].firstMatch.exists)
                capture("new_user-health", app: app)
            }
            if set == "stale" {
                let footer = app.staticTexts["ghoops shows estimates and your own ranges. It does not diagnose. Talk to a clinician about health concerns."]
                reveal(footer, in: app)
                XCTAssertLessThan(footer.frame.maxY, app.buttons["tab-home"].frame.minY)
                capture("stale-health-footer", app: app)
            }
            app.buttons["tab-more"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["more-screen"].waitForExistence(timeout: 5))
            if set == "offline" {
                app.buttons["test-connection"].tap()
                XCTAssertTrue(app.staticTexts["connection-result"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["connection-result"].label, "Can't reach your Mac over Tailscale. Is Tailscale on?")
            }
            app.buttons["tab-trends"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["trends-screen"].waitForExistence(timeout: 5))
            if set == "offline" {
                app.buttons["range-6M"].tap()
                XCTAssertTrue(app.staticTexts["Needs a connection to your Mac"].waitForExistence(timeout: 5))
                capture("offline-trend-6m", app: app)
            }
            app.terminate()
        }
    }

    @MainActor func testMissingValueBlocks() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "missing_values"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        let dayHR = app.buttons["monitor-dayhr-link"]
        XCTAssertTrue(dayHR.waitForExistence(timeout: 5))
        XCTAssertTrue(dayHR.label.contains("average no data"))
        capture("missing-home-2", app: app)
        let kickboxing = app.buttons["workout-link-7000000000000000002"]
        reveal(kickboxing, in: app)
        XCTAssertEqual(kickboxing.label, "Kickboxing, strain no data, 12:00 to 13:00")
        XCTAssertEqual(app.buttons["workout-link-effort-2026-03-10T09:05:00Z"].label, "Detected effort, strain no data, 09:05 to 09:40")
        XCTAssertEqual(app.buttons["sleep-activity-link"].label, "Sleep, no data in bed, 23:12 to 06:29")
        capture("missing-home", app: app)
        kickboxing.tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 5))
        capture("missing-workout", app: app)
        app.buttons["back-button"].tap()
        let strain = app.buttons["strain-link"]
        XCTAssertTrue(strain.waitForExistence(timeout: 5))
        for _ in 0..<6 where !strain.isHittable { scrollPage(app, up: false) }
        strain.tap()
        XCTAssertTrue(app.descendants(matching: .any)["strain-screen"].waitForExistence(timeout: 5))
        app.buttons["info-button"].tap()
        let coverage = app.descendants(matching: .any)["strain-window"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        reveal(coverage, in: app)
        XCTAssertTrue(coverage.label.hasSuffix("heart rate recorded —"))
        capture("missing-strain-window", app: app)
        app.buttons["sheet-close"].tap()
        app.buttons["back-button"].tap()
        let sleep = app.buttons["sleep-link"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 5))
        sleep.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        app.buttons["info-button"].tap()
        let night = app.descendants(matching: .any)["night-window"]
        XCTAssertTrue(night.waitForExistence(timeout: 5))
        reveal(night, in: app)
        XCTAssertTrue(night.label.hasSuffix("no data in bed"))
        capture("missing-night-window", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "engine_none", "-GHealthLiveFixture", "boxing_23m"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-minimise"].waitForExistence(timeout: 15))
        app.buttons["activity-minimise"].tap()
        let live = app.buttons["activity-live-row"]
        XCTAssertTrue(live.waitForExistence(timeout: 5))
        reveal(live, in: app)
        XCTAssertTrue(live.label.hasSuffix(" bpm"))
        capture("missing-live-row", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthGallery", "fresh"]
        app.launch()
        XCTAssertTrue(app.scrollViews["component-gallery"].waitForExistence(timeout: 15))
        let heading = app.staticTexts["gallery-heading-Missing values"]
        for _ in 0..<40 where !(heading.isHittable && heading.frame.minY < app.frame.midY) { scrollPage(app, up: true) }
        XCTAssertTrue(heading.isHittable)
        capture("missing-gallery", app: app)
        app.terminate()
    }

    @MainActor func testDestructiveAlerts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        app.buttons["tab-more"].tap()
        reveal(app.buttons["UNPAIR"], in: app)
        app.buttons["UNPAIR"].tap()
        let unpair = app.alerts["Unpair from your Mac?"]
        XCTAssertTrue(unpair.waitForExistence(timeout: 3))
        XCTAssertTrue(unpair.buttons["Unpair"].exists)
        XCTAssertTrue(unpair.buttons["Cancel"].exists)
        XCTAssertTrue(unpair.staticTexts["This iPhone stops reading from your Mac until you pair again. Nothing is deleted on your Mac."].exists)
        capture("alert-unpair", app: app)
        unpair.buttons["Cancel"].tap()
        XCTAssertFalse(unpair.exists)
        XCTAssertTrue(app.descendants(matching: .any)["more-screen"].exists)
        app.buttons["UNPAIR"].tap()
        unpair.buttons["Unpair"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pairing-screen"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        app.open(URL(string: "ghealth://pair?verify=invalid")!)
        let replace = app.alerts["Replace the current pairing?"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        XCTAssertTrue(replace.buttons["Replace pairing"].exists)
        XCTAssertTrue(replace.buttons["Cancel"].exists)
        capture("alert-replace", app: app)
        replace.buttons["Cancel"].tap()
        XCTAssertFalse(replace.exists)
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].exists)

        app.terminate()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthLiveFixture", "ended_pending"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 15))
        reveal(app.buttons["activity-delete"], in: app)
        app.buttons["activity-delete"].tap()
        let delete = app.alerts["Delete this activity?"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        capture("alert-delete", app: app)
        delete.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["activity-delete"].exists)
        app.terminate()
    }

    @MainActor func testHealthAttention() {
        let app = XCUIApplication()
        let phrase = "outside your typical range for 2 nights in a row"
        let message = "2 overnight vitals have been outside your usual range for 2 nights in a row, in the less favourable direction."
        app.launchArguments = ["-GHealthFixture", "health_attention"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[message].exists)
        capture("health-attention-home", app: app)
        let homeLabel = app.buttons["monitor-health-link"].label
        app.buttons["tab-health"].tap()
        XCTAssertTrue(app.buttons["vital-resting_hr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[message].exists)
        capture("health-attention", app: app)
        XCTAssertTrue(homeLabel.hasSuffix(phrase))
        XCTAssertTrue(app.buttons["vital-resting_hr"].label.hasSuffix(phrase))
        XCTAssertTrue(app.descendants(matching: .any)["health-status"].label.hasSuffix(phrase))
        XCTAssertFalse(app.buttons["vital-hrv_rmssd"].label.hasSuffix(phrase))
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "health_one_night"]
        app.launch()
        XCTAssertTrue(app.buttons["monitor-health-link"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts[message].exists)
        XCTAssertFalse(app.buttons["monitor-health-link"].label.contains(phrase))
        app.buttons["tab-health"].tap()
        XCTAssertTrue(app.buttons["vital-resting_hr"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[message].exists)
        XCTAssertFalse(app.buttons["vital-resting_hr"].label.contains(phrase))
        capture("health-one-night", app: app)
        app.terminate()
    }

    @MainActor func testGalleryTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthGallery", "fresh"]
        app.launch()
        XCTAssertTrue(app.scrollViews["component-gallery"].waitForExistence(timeout: 15))
        for index in 1...80 {
            let visible = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery-heading-")).allElementsBoundByIndex.filter { $0.isHittable }.map { $0.label }
            print("GALLERY_CAPTURE \(index): " + visible.joined(separator: ", "))
            capture(String(format: "gallery-%02d", index), app: app)
            if app.staticTexts["gallery-end"].isHittable { break }
            scrollPage(app, up: true)
        }
        XCTAssertTrue(app.staticTexts["gallery-end"].isHittable)
        app.terminate()
    }

    @MainActor func testWidgetsTour() {
        continueAfterFailure = false
        for set in ["fresh", "stale", "unpaired"] {
            let app = XCUIApplication()
            app.launchArguments = ["-GHealthWidgetPreview", set]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["widget-preview"].waitForExistence(timeout: 15))
            XCTAssertEqual(app.staticTexts["font-check"].label, "wght=750 OK, wght=650 OK")
            if set == "unpaired" { XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Open ghoops to pair")).firstMatch.exists) }
            capture("widgets-\(set)", app: app)
            scrollPage(app, up: true)
            capture("widgets-\(set)-2", app: app)
            reveal(app.descendants(matching: .any)["widget-parity"], in: app)
            if set == "fresh" {
                XCTAssertTrue(app.descendants(matching: .any)["widget-hrv-small"].label.contains("56"))
                XCTAssertTrue(app.descendants(matching: .any)["widget-lock-rect-bedtime"].descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "22:19")).firstMatch.exists)
                XCTAssertTrue(app.descendants(matching: .any)["widget-lock-rect-hrv"].descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "56")).firstMatch.exists)
            }
            capture("widgets-\(set)-3", app: app)
            app.terminate()
        }
    }

    @MainActor func testWidgetsAfterWake() {
        continueAfterFailure = false
        let app = XCUIApplication()
        func open(_ set: String, clock: String? = nil) {
            app.launchArguments = ["-GHealthWidgetPreview", set] + (clock.map { ["-GHealthClock", $0] } ?? [])
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["widget-preview"].waitForExistence(timeout: 15))
        }
        func labelled(_ predicate: String, _ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label \(predicate) %@", text)).firstMatch
        }
        // Downloaded before wake, then a failed refresh after it: the scores carry their day or a dash (oss-data-audit row 6).
        open("after_midnight", clock: "2026-03-11T05:00:00Z")
        XCTAssertTrue(app.staticTexts["Scores from Tue 10"].exists)
        XCTAssertTrue(app.staticTexts["Tue 10 · 64%"].exists)
        XCTAssertTrue(labelled("==", "Recovery, 73%, from Tuesday 10 March").exists)
        XCTAssertTrue(labelled("==", "Recovery, —, from Tuesday 10 March").exists)
        XCTAssertFalse(labelled("==", "Recovery, 73%").exists)
        capture("widgets-after-wake", app: app)
        app.terminate()

        // The same download before any refresh is due is still today.
        open("after_midnight", clock: "2026-03-11T00:20:00Z")
        XCTAssertFalse(labelled("CONTAINS", ", from ").exists)
        XCTAssertTrue(labelled("==", "Recovery, 73%").exists)
        app.terminate()

        // A fresh download of old data never says now: the age counts from the band's last sync.
        open("stale", clock: "2026-03-10T15:00:00Z")
        XCTAssertFalse(app.staticTexts["now"].exists)
        XCTAssertTrue(app.staticTexts["52m"].exists)
        XCTAssertTrue(app.staticTexts["14:08 · 64%"].exists)
        XCTAssertTrue(labelled("==", "Recovery, 73%, as of 14:08").exists)
        capture("widgets-stale-download", app: app)
        app.terminate()

        // Fresh and calibrating open cycles stay current.
        for set in ["fresh", "calibrating"] {
            open(set)
            XCTAssertFalse(labelled("CONTAINS", ", from ").exists)
            XCTAssertFalse(labelled("CONTAINS", ", as of ").exists)
            XCTAssertTrue(app.staticTexts["14:08 · 64%"].exists)
            capture("widgets-\(set)-current", app: app)
            app.terminate()
        }
    }

    @MainActor func testAccessibilityTour() {
        continueAfterFailure = false
        for key in ["open", "saving"] {
            let sleep = sleepApp(key, large: true)
            XCTAssertTrue(sleep.staticTexts[key == "open" ? "sleep-edit-value-asleep" : "UPDATING"].firstMatch.waitForExistence(timeout: 8))
            capture("sleep-edit-\(key)-ax5", app: sleep)
            if key == "open" {
                reveal(sleep.descendants(matching: .any)["sleep-edit-end"], in: sleep)
                XCTAssertTrue(sleep.buttons["sleep-edit-save"].isHittable)
                capture("sleep-edit-open-ax5-2", app: sleep)
            }
            sleep.terminate()
        }
        let rating = ratingApp("ask", extra: ["-GHealthAccessibility5", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(rating.descendants(matching: .any)["rating-sheet"].waitForExistence(timeout: 15))
        capture("rating-ask-ax5", app: rating)
        reveal(rating.buttons["rating-10"], in: rating)
        XCTAssertTrue(rating.buttons["rating-10"].isHittable)
        capture("rating-ask-ax5-2", app: rating)
        rating.terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthAccessibility5"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["recovery-link"].label, "Recovery, 73 percent, high")
        capture("fresh-home-ax5", app: app)
        scrollPage(app, up: true)
        capture("fresh-home-ax5-2", app: app)
        scrollPage(app, up: false)
        app.buttons["sleep-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
        capture("fresh-sleep-ax5", app: app)
        for index in 2...4 {
            scrollPage(app, up: true)
            capture("fresh-sleep-ax5-\(index)", app: app)
        }
        for _ in 0..<4 { scrollPage(app, up: false) }
        app.buttons["back-button"].tap()
        reveal(app.buttons["tile-hrv"], in: app)
        app.buttons["tile-hrv"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend-view-screen"].waitForExistence(timeout: 5))
        capture("fresh-trend-ax5", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "edit", "-GHealthAccessibility5", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-close"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["edit-sport-row"].exists)
        XCTAssertTrue(app.staticTexts["Editing changes this activity, not your Day Strain."].exists)
        XCTAssertGreaterThan(app.buttons["edit-sport-row"].staticTexts["SPORT"].frame.height, 20)
        XCTAssertTrue(app.buttons["edit-save"].isHittable)
        capture("edit-edit-ax5", app: app)
        reveal(app.descendants(matching: .any)["edit-notes"], in: app)
        capture("edit-edit-ax5-2", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthAccessibility5"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        reveal(app.descendants(matching: .any)["tonight-card"], in: app)
        capture("parity1-sleep-plan-ax5", app: app)
        app.terminate()
        for key in ["home-waiting", "rollback"] {
            app.launchArguments = ["-GHealthFixture", "edit", "-GHealthInstantFixture", key, "-GHealthAccessibility5"]
            app.launch()
            let banner = app.descendants(matching: .any)[key == "rollback" ? "change-rollback-banner-0" : "pending-changes-banner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 15))
            capture("instant-\(key)-ax5", app: app)
            if key == "home-waiting" {
                let running = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Running, strain")).firstMatch
                reveal(running, in: app)
                XCTAssertTrue(running.label.contains("waiting for your Mac"))
                capture("instant-home-waiting-ax5-2", app: app)
            }
            app.terminate()
        }
    }

    @MainActor func testBackgroundRefreshProbe() throws {
        guard ProcessInfo.processInfo.environment["GHEALTH_BG_PROBE"] == "1" else { throw XCTSkip("Run make ios-bg-probe to attach the debugger") }
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthBackgroundProbe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["background-probe-count"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        print("BG_PROBE_READY")
        Thread.sleep(forTimeInterval: 30)
        app.activate()
        let counter = app.staticTexts["background-probe-count"]
        let state = app.staticTexts["background-probe-state"].label
        print("BG_PROBE_STATE=" + state)
        if state.contains("scheduler error 1") && counter.label == "Stubbed background requests: 0" {
            app.terminate()
            print("BG_PROBE_UNAVAILABLE")
            throw XCTSkip("BGTaskScheduler error 1: Simulator does not support background processing")
        }
        XCTAssertEqual(counter.label, "Stubbed background requests: 1")
        if counter.label == "Stubbed background requests: 1" { print("BG_PROBE_REQUESTS=1") }
        app.terminate()
    }

    @MainActor func testActivityFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        let start = app.buttons["activity-open-picker"]
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(app.buttons["activity-sport-BOXING"].waitForExistence(timeout: 5))
        app.buttons["activity-sport-BOXING"].tap()
        app.buttons["activity-start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity-live-screen"].waitForExistence(timeout: 5))
        let timer = app.staticTexts["activity-timer"]
        let hold = app.buttons["activity-hold-end"]
        hold.press(forDuration: 0.3)
        XCTAssertTrue(timer.exists)
        app.buttons["activity-pause"].tap()
        XCTAssertEqual(app.buttons["activity-pause"].label, "Resume")
        let frozen = timer.label
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", frozen), object: timer)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 2.2), .completed)
        app.buttons["activity-pause"].tap()
        app.buttons["activity-minimise"].tap()
        let live = app.buttons["activity-live-row"]
        XCTAssertTrue(live.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity-open-picker"].exists)
        live.tap()
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let minute = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
            let parts = (element as? XCUIElement)?.label.split(separator: ":").compactMap { Int($0) } ?? []
            return parts.count == 3 && parts[0] * 3600 + parts[1] * 60 + parts[2] >= 60
        }, object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [minute], timeout: 80), .completed)
        hold.press(forDuration: 2.5)
        XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 8))
        closeRatingAsk(app, required: true)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Saved on your phone.")).firstMatch.exists)
        capture("activity-flow-pending", app: app)
        app.buttons["back-button"].tap()
        XCTAssertTrue(app.staticTexts["WAITING FOR MAC"].exists)
        let pending = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "workout-link-", "Boxing")).firstMatch
        reveal(pending, in: app)
        pending.tap()
        let delete = app.buttons["activity-delete"]
        reveal(delete, in: app)
        delete.tap()
        XCTAssertTrue(app.alerts["Delete this activity?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(delete.exists)
        delete.tap()
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["WAITING FOR MAC"].exists)
        app.terminate()
    }

    @MainActor func testTodayActivitiesFollowTheGhoopsDay() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for fixture in ["fresh", "after_midnight"] {
            app.launchArguments = ["-GHealthFixture", fixture]
            app.launch()
            XCTAssertTrue(app.buttons["Showing today"].waitForExistence(timeout: 15))
            scrollPage(app, up: true)
            capture("\(fixture)-today-home", app: app)
            XCTAssertTrue(app.staticTexts["TODAY'S ACTIVITIES"].exists)
            let start = app.buttons["activity-open-picker"]
            XCTAssertTrue(start.exists)
            XCTAssertFalse(app.buttons["activity-live-row"].exists)
            let add = app.buttons["activity-open-add"]
            reveal(add, in: app)
            add.tap()
            let day = app.buttons["add-day-2026-03-10"]
            XCTAssertTrue(day.waitForExistence(timeout: 5))
            XCTAssertTrue(day.isSelected)
            XCTAssertFalse(app.buttons["add-day-2026-03-11"].exists)
            capture("\(fixture)-today-past", app: app)
            app.terminate()

            app.launchArguments = ["-GHealthFixture", fixture, "-GHealthLiveFixture", "boxing_23m"]
            app.launch()
            XCTAssertTrue(app.buttons["activity-minimise"].waitForExistence(timeout: 15))
            app.buttons["activity-minimise"].tap()
            let live = app.buttons["activity-live-row"]
            XCTAssertTrue(live.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["TODAY'S ACTIVITIES"].exists)
            XCTAssertFalse(app.buttons["activity-open-picker"].exists)
            let end = app.buttons["activity-end-open"]
            XCTAssertEqual(end.label, "End Boxing")
            reveal(end, in: app)
            capture("\(fixture)-today-live", app: app)
            end.tap()
            app.buttons["activity-hold-end"].press(forDuration: 2.5)
            XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 8))
            closeRatingAsk(app)
            app.buttons["back-button"].tap()
            XCTAssertTrue(app.staticTexts["TODAY'S ACTIVITIES"].waitForExistence(timeout: 5))
            let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "workout-link-goop-", "Boxing,")).firstMatch
            XCTAssertTrue(saved.exists)
            if fixture == "after_midnight" { XCTAssertTrue(saved.label.contains("23:46 to 00:")) }
            reveal(saved, in: app)
            capture("\(fixture)-today-saved", app: app)
            app.terminate()
        }
    }

    @MainActor func testAfterMidnightSessionSaveStaysOnToday() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "after_midnight"]
        app.launch()
        XCTAssertTrue(app.buttons["Showing today"].waitForExistence(timeout: 15))
        let start = app.buttons["activity-open-picker"]
        reveal(start, in: app)
        start.tap()
        app.buttons["activity-sport-BOXING"].tap()
        app.buttons["activity-start"].tap()
        let timer = app.staticTexts["activity-timer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let minute = XCTNSPredicateExpectation(predicate: NSPredicate { element, _ in
            let parts = (element as? XCUIElement)?.label.split(separator: ":").compactMap { Int($0) } ?? []
            return parts.count == 3 && parts[0] * 3600 + parts[1] * 60 + parts[2] >= 60
        }, object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [minute], timeout: 80), .completed)
        app.buttons["activity-hold-end"].press(forDuration: 2.5)
        XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 8))
        closeRatingAsk(app)
        capture("after-midnight-save-detail", app: app)
        XCTAssertTrue(app.staticTexts["ACTIVITY STRAIN"].exists)
        XCTAssertTrue(app.staticTexts["148–167"].exists)
        app.buttons["back-button"].tap()
        XCTAssertTrue(app.buttons["Showing today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TODAY'S ACTIVITIES"].exists)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "workout-link-goop-", "Boxing,")).firstMatch
        capture("after-midnight-save-today", app: app)
        XCTAssertTrue(saved.exists)
        XCTAssertTrue(saved.label.contains("00:10 to 00:"))
        reveal(saved, in: app)
        saved.tap()
        XCTAssertTrue(app.staticTexts["ACTIVITY STRAIN"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["148–167"].exists)
        app.terminate()
    }

    @MainActor func testActivitySearchAndShortDiscard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        let start = app.buttons["activity-open-picker"]
        reveal(start, in: app)
        start.tap()
        let search = app.textFields["activity-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("bOxInG")
        XCTAssertTrue(app.buttons["activity-sport-BOXING"].exists)
        XCTAssertFalse(app.buttons["activity-sport-WALKING"].exists)
        app.buttons["activity-sport-BOXING"].tap()
        app.buttons["activity-start"].tap()
        XCTAssertTrue(app.buttons["activity-hold-end"].waitForExistence(timeout: 5))
        app.buttons["activity-hold-end"].press(forDuration: 2.5)
        let toast = app.descendants(matching: .any)["activity-too-short"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        capture("activity-too-short", app: app)
        XCTAssertTrue(toast.waitForNonExistence(timeout: 6))
        XCTAssertFalse(app.buttons["activity-live-row"].exists)
        XCTAssertFalse(app.staticTexts["WAITING FOR MAC"].exists)
        app.terminate()
    }

    @MainActor func testActivityScreensTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 15))
        capture("activity-a", app: app)
        let start = app.buttons["activity-open-picker"]
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity-picker"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["activity-picker-close"].frame.midX, app.frame.midX)
        app.buttons["activity-sport-BOXING"].tap()
        capture("activity-b", app: app)
        app.terminate()
        for name in ["boxing_23m", "no_hr", "stale", "paused", "ended_pending", "ended_estimate"] {
            app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthLiveFixture", name]
            app.launch()
            let saved = name.hasPrefix("ended_")
            XCTAssertTrue(app.descendants(matching: .any)[saved ? "workout-screen" : "activity-live-screen"].waitForExistence(timeout: 15))
            if name == "ended_pending" { XCTAssertTrue(app.descendants(matching: .any)["activity-save-banner"].exists) }
            capture(name == "boxing_23m" ? "activity-c" : name == "ended_estimate" ? "activity-f" : "activity-" + name, app: app)
            if name == "boxing_23m" {
                app.buttons["activity-minimise"].tap()
                XCTAssertTrue(app.buttons["activity-live-row"].waitForExistence(timeout: 5))
                capture("activity-e", app: app)
                scrollPage(app, up: true)
                XCTAssertTrue(app.buttons["activity-end-open"].exists)
                capture("activity-e-2", app: app)
            }
            app.terminate()
        }
    }

    @MainActor func testLiveActivityPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthWidgetPreview", "live"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["live-widget-preview"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["live-activity-view"].exists)
        capture("activity-d", app: app)
        scrollPage(app, up: true)
        XCTAssertTrue(app.descendants(matching: .any)["live-island-preview"].exists)
        capture("activity-island", app: app)
        app.terminate()
    }

    @MainActor func testLiveHeartStates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        var heights: [CGFloat] = []
        for (preview, bpm, status, chip) in [
            ("live", "158 bpm", "Zone 4", "Live"),
            ("live_target", "161 bpm", "Zone 4", "Live"),
            ("live_no_zone", "158 bpm", "Zone unknown", "Live"),
            ("live_no_hr", "No heart rate", "No heart rate", "No heart rate"),
            ("live_stale", "159 bpm, reconnecting", "Reconnecting", "Reconnecting"),
            ("live_paused", "158 bpm", "Zone 4", "Live")
        ] {
            app.launchArguments = ["-GHealthWidgetPreview", preview]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["live-widget-preview"].waitForExistence(timeout: 15))
            let lock = app.descendants(matching: .any)["live-activity-view"].firstMatch
            XCTAssertTrue(lock.exists)
            XCTAssertEqual(lock.descendants(matching: .any)["live-activity-bpm"].firstMatch.label, bpm)
            XCTAssertEqual(lock.descendants(matching: .any)["live-activity-status"].firstMatch.label, status)
            if preview != "live_target" { heights.append(lock.frame.height) }
            print("LIVE_HEART_HEIGHT \(preview)=\(lock.frame.height)")
            capture("live-hr-\(preview)", app: app)
            scrollPage(app, up: true)
            XCTAssertEqual(app.descendants(matching: .any)["live-island-bpm"].firstMatch.label, bpm)
            XCTAssertEqual(app.descendants(matching: .any)["live-island-minimal"].firstMatch.label, chip)
            let expanded = app.descendants(matching: .any)["live-island-expanded"].firstMatch
            XCTAssertTrue(expanded.exists)
            let expandedStatus = expanded.descendants(matching: .any)["live-activity-status"].firstMatch
            let needsStatus = preview == "live_no_hr" || preview == "live_stale"
            XCTAssertEqual(expandedStatus.exists, needsStatus)
            if needsStatus { XCTAssertEqual(expandedStatus.label, status) }
            capture("live-hr-\(preview)-island", app: app)
            app.terminate()
        }
        XCTAssertEqual(heights.max()!, heights.min()!, accuracy: 0.5)
        let elements = app.descendants(matching: .any)
        for (fixture, seed, chip) in [
            ("engine_none", "boxing_23m", "Live"),
            ("fresh", "stale", "Reconnecting"),
            ("fresh", "no_hr", "No heart rate"),
            ("fresh", "boxing_23m", "Live"),
            ("fresh", "paused", "Live")
        ] {
            app.launchArguments = ["-GHealthFixture", fixture, "-GHealthLiveFixture", seed]
            app.launch()
            XCTAssertTrue(elements["activity-live-screen"].waitForExistence(timeout: 15))
            XCTAssertEqual(elements["activity-hr-state"].firstMatch.label, chip)
            switch (fixture, seed) {
            case ("engine_none", _):
                XCTAssertNotNil(elements["activity-bpm"].firstMatch.label.range(of: "^[0-9]{2,3} bpm$", options: .regularExpression))
                XCTAssertEqual(elements["activity-zone-label"].firstMatch.label, "Zone unknown")
                for id in ["activity-zone-range", "activity-zones45", "activity-strain"] {
                    XCTAssertEqual(elements[id].firstMatch.label, "—")
                }
                XCTAssertEqual(elements["activity-ring-caption"].firstMatch.label, "Strain needs your Mac")
                capture("live-hr-app-no-zone", app: app)
            case (_, "stale"):
                XCTAssertEqual(elements["activity-bpm"].firstMatch.label, "159 bpm, reconnecting")
                XCTAssertEqual(elements["activity-zone-label"].firstMatch.label, "Zone 4")
                XCTAssertNotNil(elements["activity-zones45"].firstMatch.label.range(of: "^[0-9]+:[0-9]{2}$", options: .regularExpression))
                capture("live-hr-app-stale", app: app)
            case (_, "no_hr"):
                XCTAssertEqual(elements["activity-bpm"].firstMatch.label, "No heart rate")
                XCTAssertEqual(elements["activity-zone-label"].firstMatch.label, "Zone unknown")
                XCTAssertEqual(elements["activity-zones45"].firstMatch.label, "—")
                XCTAssertEqual(elements["activity-ring-caption"].firstMatch.label, "Activity Strain")
                capture("live-hr-app-no-hr", app: app)
            case (_, "boxing_23m"):
                XCTAssertNotNil(elements["activity-zone-label"].firstMatch.label.range(of: "^Zone [0-5]$", options: .regularExpression))
                XCTAssertNotNil(elements["activity-zones45"].firstMatch.label.range(of: "^[0-9]+:[0-9]{2}$", options: .regularExpression))
                app.buttons["activity-minimise"].tap()
                XCTAssertTrue(app.buttons["activity-live-row"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["activity-live-row"].label.hasSuffix(" bpm"))
            default:
                XCTAssertEqual(elements["activity-ring-caption"].firstMatch.label, "Paused")
            }
            app.terminate()
        }
    }

    @MainActor func testStrainTarget() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["strain-link"].waitForExistence(timeout: 15))
        app.buttons["strain-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["strain-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Today's target is 13.3 to 16.3 for high recovery. The target is ghoops' own rule of thumb, not a published method. You are below it.")).firstMatch.exists)
        reveal(app.staticTexts["insight-text"], in: app)
        capture("strain-complete-insight", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthLiveFixture", "boxing_23m"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["activity-target"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["activity-target-range"].label, "13.3–16.3")
        XCTAssertTrue(app.descendants(matching: .any)["activity-target-within"].exists)
        XCTAssertNotNil(app.staticTexts["activity-target-estimate"].label.range(of: #"^1[3-6]\.[0-9]$"#, options: .regularExpression))
        app.terminate()
    }

    @MainActor func testSparseStrainShowsScoreAndCoverageWithoutTargetVerdict() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "strain_sparse"]
        app.launch()
        XCTAssertTrue(app.buttons["strain-link"].waitForExistence(timeout: 15))
        app.buttons["strain-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["strain-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Strain, 0.2 of 21")).firstMatch.exists)
        let insight = app.staticTexts["insight-text"]
        reveal(insight, in: app)
        XCTAssertTrue(insight.label.contains("target is"))
        XCTAssertTrue(insight.label.contains("of the day's heart rate"))
        XCTAssertFalse(insight.label.contains("You finished"))
        XCTAssertFalse(insight.label.contains("You are"))
        capture("strain-sparse-insight", app: app)
        app.terminate()
    }

    @MainActor func testTonightsSleep() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        reveal(app.descendants(matching: .any)["tonight-card"], in: app)
        XCTAssertEqual(app.staticTexts["tonight-need"].label, "8:03")
        XCTAssertEqual(app.staticTexts["tonight-wake"].label, "07:07")
        XCTAssertEqual(app.descendants(matching: .any)["tonight-goal-100"].firstMatch.label, "100 percent of need: 8 hours 48 minutes in bed, bed by 22:19")
        app.buttons["tonight-info"].tap()
        let inBed = app.descendants(matching: .any)["plan-in-bed"]
        XCTAssertTrue(inBed.waitForExistence(timeout: 5))
        XCTAssertEqual(inBed.value as? String, "8:48")
        XCTAssertEqual(app.descendants(matching: .any)["need-total"].value as? String, "8:03")
        XCTAssertEqual(app.descendants(matching: .any)["plan-asleep"].value as? String, "8:03")
        XCTAssertEqual(app.descendants(matching: .any)["plan-awake"].value as? String, "+0:45")
        XCTAssertEqual(app.descendants(matching: .any)["plan-window"].label, "Bed by 22:19, wake at 07:07, 8 hours 48 minutes in bed")
        app.buttons["plan-goal-85"].tap()
        XCTAssertTrue(app.buttons["plan-goal-85"].isSelected)
        XCTAssertEqual(inBed.value as? String, "7:30")
        XCTAssertEqual(app.descendants(matching: .any)["plan-asleep"].value as? String, "6:51")
        XCTAssertEqual(app.descendants(matching: .any)["plan-awake"].value as? String, "+0:39")
        XCTAssertEqual(app.descendants(matching: .any)["plan-window"].label, "Bed by 23:37, wake at 07:07, 7 hours 30 minutes in bed")
        app.terminate()
    }

    @MainActor func testExplanationSheets() {
        continueAfterFailure = false
        var defaultHeights: [String: CGFloat] = [:]
        for accessibility in [false, true] {
            let size = accessibility ? "-ax5" : ""
            let app = XCUIApplication()
            app.launchArguments = ["-GHealthFixture", "fresh"] + (accessibility ? ["-GHealthAccessibility5", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch()
            XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
            app.buttons["sleep-link"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["sleep-screen"].waitForExistence(timeout: 5))
            app.buttons["info-button"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["plan-in-bed"].waitForExistence(timeout: 5))
            capture("sheets-sleep-1\(size)", app: app)
            for page in 2...4 {
                scrollPage(app, up: true)
                capture("sheets-sleep-\(page)\(size)", app: app)
            }
            for text in ["Sleep stages come from your band and are estimates.", "Past days are recalculated when Google updates your data or a Mac setting changes."] {
                let note = app.staticTexts[text]
                reveal(note, in: app)
                XCTAssertTrue(note.isHittable)
                if accessibility { XCTAssertGreaterThan(note.frame.height, defaultHeights[text] ?? .infinity) }
                else { defaultHeights[text] = note.frame.height }
            }
            capture("sheets-sleep-honesty\(size)", app: app)
            let night = app.descendants(matching: .any)["night-window"]
            XCTAssertEqual(night.label, "Bedtime 23:12, wake 06:29, 7 hours 17 minutes in bed")
            XCTAssertEqual(app.descendants(matching: .any)["scale-hours"].label, "Hours vs. needed, 93%. Poor 0–69%, Sufficient 70–84%, Optimal 85–100%. Today: Optimal")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "the middle 50% of your last 30 nights with sleep stages (shown after 7 such nights).")).firstMatch.exists)
            app.buttons["sheet-close"].tap()
            app.buttons["back-button"].tap()
            app.buttons["recovery-link"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["recovery-screen"].waitForExistence(timeout: 5))
            app.buttons["info-button"].tap()
            let total = app.descendants(matching: .any)["recovery-total"]
            XCTAssertTrue(total.waitForExistence(timeout: 5))
            XCTAssertEqual(total.value as? String, "73")
            let hrv = app.descendants(matching: .any)["recovery-hrv"]
            XCTAssertEqual(hrv.label, "HRV, 56 ms · usual 52 · 55% weight")
            XCTAssertEqual(hrv.value as? String, "+42.1")
            XCTAssertEqual(app.descendants(matching: .any)["recovery-resting-hr"].value as? String, "+10.1")
            XCTAssertEqual(app.descendants(matching: .any)["recovery-sleep"].value as? String, "+23.3")
            XCTAssertFalse(app.descendants(matching: .any)["recovery-inputs"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["scale-recovery"].label.hasSuffix("Today: High"))
            capture("sheets-recovery-1\(size)", app: app)
            scrollPage(app, up: true)
            capture("sheets-recovery-2\(size)", app: app)
            let revision = app.staticTexts["Past days are recalculated when Google updates your data or a Mac setting changes."]
            reveal(revision, in: app)
            XCTAssertTrue(revision.isHittable)
            if accessibility { XCTAssertGreaterThan(revision.frame.height, defaultHeights[revision.label] ?? .infinity) }
            else { defaultHeights[revision.label] = revision.frame.height }
            capture("sheets-recovery-honesty\(size)", app: app)
            app.buttons["sheet-close"].tap()
            app.buttons["back-button"].tap()
            app.buttons["strain-link"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["strain-screen"].waitForExistence(timeout: 5))
            let strength = app.staticTexts["Workouts recorded or started as strength."]
            reveal(strength, in: app)
            XCTAssertTrue(strength.isHittable)
            for _ in 0..<4 { scrollPage(app, up: false) }
            app.buttons["info-button"].tap()
            let window = app.descendants(matching: .any)["strain-window"]
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            XCTAssertEqual(window.label, "From 06:29 to 14:08, heart rate recorded 100%")
            capture("sheets-strain-1\(size)", app: app)
            for (key, text) in [
                ("wrist", "Wrist heart rate can read low in boxing and weightlifting, so Strain and zones may be low."),
                ("max", "Age-based maximums can be well off for one person. Set yours on the Mac."),
                ("scale", "Strain uses Banister's published heart-rate formula, on a scale ghoops set from public examples. It isn't WHOOP's Strain."),
                ("revision", "Past days are recalculated when Google updates your data or a Mac setting changes.")
            ] {
                let note = app.staticTexts[text]
                XCTAssertTrue(note.exists)
                reveal(note, in: app)
                XCTAssertTrue(note.isHittable)
                if accessibility { XCTAssertGreaterThan(note.frame.height, defaultHeights[text] ?? .infinity) }
                else { defaultHeights[text] = note.frame.height }
                capture("sheets-strain-honesty-\(key)\(size)", app: app)
            }
            XCTAssertTrue(app.descendants(matching: .any)["scale-strain"].label.hasSuffix("Today: Moderate"))
            app.terminate()
        }
    }


    @MainActor func testHonestMissingInputsAndDeviceStatus() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let battery = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Band battery ")).firstMatch
        for set in ["fresh", "stale", "honest_missing"] {
            app.launchArguments = ["-GHealthFixture", set]
            app.launch()
            XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
            XCTAssertEqual(battery.exists, set != "stale")
            capture("honesty-battery-\(set)", app: app)
            app.terminate()
        }
        app.launchArguments = ["-GHealthFixture", "honest_missing"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-health"].waitForExistence(timeout: 15))
        app.buttons["tab-health"].tap()
        let skin = app.buttons["vital-skin_temp_deviation"]
        reveal(skin, in: app)
        XCTAssertTrue(skin.label.hasPrefix("Skin temp vs usual, "))
        XCTAssertFalse(skin.label.contains("within"))
        XCTAssertTrue(skin.label.contains("typical range"))
        XCTAssertTrue(app.staticTexts["SKIN TEMP VS USUAL"].exists)
        XCTAssertFalse(app.staticTexts["SKIN TEMP"].exists)
        capture("honesty-skin-position-missing", app: app)
        app.buttons["tab-home"].tap()
        app.buttons["sleep-link"].tap()
        let recent = app.descendants(matching: .any)["need-strain"]
        reveal(recent, in: app)
        XCTAssertEqual(recent.value as? String, "—")
        XCTAssertEqual(app.descendants(matching: .any)["need-debt"].label, "Sleep debt, From 2 nights")
        capture("honesty-need-missing", app: app)
        for _ in 0..<4 { scrollPage(app, up: false) }
        app.buttons["info-button"].tap()
        XCTAssertTrue(app.buttons["sheet-close"].waitForExistence(timeout: 5))
        let sheet = app.scrollViews.containing(.button, identifier: "sheet-close").element
        XCTAssertEqual(sheet.descendants(matching: .any)["need-strain"].value as? String, "—")
        XCTAssertEqual(sheet.descendants(matching: .any)["need-debt"].label, "Sleep debt, From 1 nights")
        capture("honesty-plan-missing", app: app)
        app.buttons["sheet-close"].tap()
        app.buttons["back-button"].tap()
        let workout = app.buttons["workout-link-7000000000000000002"]
        reveal(workout, in: app)
        workout.tap()
        let wrist = app.staticTexts["Wrist heart rate can read low in boxing and weightlifting, so Strain and zones may be low."]
        reveal(wrist, in: app)
        XCTAssertTrue(wrist.isHittable)
        capture("honesty-strength-wrist", app: app)
        app.terminate()
    }

    @MainActor func testEngineNumbersFromMac() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for odd in [true, false] {
            app.launchArguments = ["-GHealthFixture", odd ? "engine_odd" : "engine_none"]
            app.launch()
            XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
            app.buttons["recovery-link"].tap()
            XCTAssertTrue(app.staticTexts[odd ? "vs. prior 28 days" : "vs. prior 30 days"].exists)
            app.buttons["info-button"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["recovery-total"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.descendants(matching: .any)["scale-recovery"].label, odd ? "Low 0–39, Medium 40–69, High 70–100. Today: High" : "Low —, Medium —, High —. Today: High")
            XCTAssertTrue(app.staticTexts[odd ? "Breathing rate and skin temperature only subtract, up to 8 points each, when they run above usual." : "Breathing rate and skin temperature only subtract when they run above usual."].exists)
            XCTAssertTrue(app.staticTexts[odd ? "4 nights to start · 12 for full confidence" : "7 nights to start · 14 for full confidence"].exists)
            capture(odd ? "engine-odd-recovery" : "engine-none-recovery", app: app)
            app.buttons["sheet-close"].tap()
            app.buttons["back-button"].tap()
            if odd {
                app.buttons["strain-link"].tap()
                app.buttons["info-button"].tap()
                XCTAssertTrue(app.descendants(matching: .any)["strain-window"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["155–173"].exists)
                capture("engine-odd-strain-zones", app: app)
                for _ in 0..<2 { scrollPage(app, up: true) }
                XCTAssertEqual(app.descendants(matching: .any)["scale-strain"].label, "Light 0–10.9, Moderate 11–15.4, Strenuous 15.5–18.9, All Out 19–21. Today: Moderate")
                capture("engine-odd-strain", app: app)
                app.buttons["sheet-close"].tap()
                app.buttons["back-button"].tap()
            }
            app.buttons["sleep-link"].tap()
            app.buttons["info-button"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["plan-in-bed"].waitForExistence(timeout: 5))
            for _ in 0..<3 { scrollPage(app, up: true) }
            if odd {
                XCTAssertEqual(app.descendants(matching: .any)["scale-hours"].label, "Hours vs. needed, 93%. Poor 0–74%, Sufficient 75–89%, Optimal 90–100%. Today: Optimal")
            }
            XCTAssertEqual(app.descendants(matching: .any)["scale-efficiency"].label, odd ? "Efficiency, 95%. Poor 0–87%, Sufficient 88–92%, Optimal 93–100%. Today: Optimal" : "Efficiency, 95%. Poor —, Sufficient —, Optimal —")
            capture(odd ? "engine-odd-sleep" : "engine-none-sleep", app: app)
            app.terminate()
        }
    }

    @MainActor func testJournalFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthJournalFixture", "answer"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        app.buttons["recovery-link"].tap()
        let open = app.buttons["journal-open"]
        reveal(open, in: app)
        let status = app.descendants(matching: .any)["journal-status"]
        XCTAssertTrue(status.label.contains("MON 9 MAR") && status.label.contains("1 OF 5 ANSWERED"), status.label)
        XCTAssertTrue(app.descendants(matching: .any)["journal-answer-alcohol"].label.contains("NO"))
        XCTAssertTrue(app.descendants(matching: .any)["journal-answer-stress"].label.contains("Not answered"))
        capture("journal-recovery", app: app)
        open.tap()
        let save = app.buttons["journal-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["MONDAY 9 MARCH"].exists)
        XCTAssertTrue(app.staticTexts["Did you drink any alcohol?"].exists)
        XCTAssertTrue(app.buttons["journal-alcohol-no"].isSelected)
        XCTAssertFalse(app.buttons["journal-stress-yes"].isSelected || app.buttons["journal-stress-no"].isSelected)
        app.buttons["journal-alcohol-yes"].tap()
        app.buttons["journal-late_caffeine-no"].tap()
        app.buttons["journal-late_meal-yes"].tap()
        XCTAssertTrue(save.isEnabled)
        capture("journal-sheet", app: app)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        reveal(status, in: app)
        XCTAssertTrue(status.waitForLabel(containing: "3 OF 5 ANSWERED", timeout: 10), status.label)
        XCTAssertTrue(app.descendants(matching: .any)["journal-answer-alcohol"].label.contains("YES"))
        XCTAssertTrue(app.descendants(matching: .any)["journal-answer-late_meal"].label.contains("YES"))
        XCTAssertTrue(app.buttons["journal-open"].waitForExistence(timeout: 10))
        capture("journal-saved", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthJournalFixture", "waiting"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        app.buttons["recovery-link"].tap()
        reveal(app.buttons["journal-open"], in: app)
        app.buttons["journal-open"].tap()
        XCTAssertTrue(app.buttons["journal-save"].waitForExistence(timeout: 5))
        app.buttons["journal-stress-yes"].tap()
        app.buttons["journal-save"].tap()
        let banner = app.descendants(matching: .any)["journal-waiting-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        reveal(banner, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["journal-status"].label.contains("WAITING FOR MAC"))
        XCTAssertTrue(app.descendants(matching: .any)["journal-answer-stress"].label.contains("YES"))
        XCTAssertFalse(app.buttons["journal-open"].exists)
        capture("journal-waiting", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "journal_first"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        app.buttons["recovery-link"].tap()
        reveal(app.buttons["journal-open"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["journal-status"].label.contains("NOT ANSWERED"))
        capture("journal-first", app: app)
        app.terminate()
    }

    @MainActor func testJournalHidden() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "journal_none"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        app.buttons["recovery-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["recovery-screen"].waitForExistence(timeout: 5))
        for _ in 0..<4 { scrollPage(app, up: true) }
        XCTAssertFalse(app.descendants(matching: .any)["journal-status"].exists)
        XCTAssertFalse(app.buttons["journal-open"].exists)
    }

    @MainActor func testRecoveryWeightsFromMac() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "recovery_weights"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["recovery-link"].label, "Recovery, 71 percent, high")
        app.buttons["recovery-link"].tap()
        app.buttons["info-button"].tap()
        let hrv = app.descendants(matching: .any)["recovery-hrv"]
        XCTAssertTrue(hrv.waitForExistence(timeout: 5))
        for (id, label, value) in [
            ("recovery-hrv", "HRV, 56 ms · usual 52 · 40% weight", "+30.6"),
            ("recovery-resting-hr", "Resting heart rate, 56 bpm · usual 56 · 30% weight", "+15.2"),
            ("recovery-sleep", "Sleep performance, 93% · 30% weight", "+27.9")
        ] {
            let row = app.descendants(matching: .any)[id]
            XCTAssertEqual(row.label, label)
            XCTAssertEqual(row.value as? String, value)
        }
        XCTAssertEqual(app.descendants(matching: .any)["recovery-breathing"].value as? String, "−2.3")
        XCTAssertEqual(app.descendants(matching: .any)["recovery-skin"].value as? String, "0.0")
        XCTAssertEqual(app.descendants(matching: .any)["recovery-total"].value as? String, "71")
        XCTAssertFalse(app.descendants(matching: .any)["recovery-inputs"].exists)
        capture("recovery-weights-sheet", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "recovery_no_weights"]
        app.launch()
        XCTAssertTrue(app.buttons["recovery-link"].waitForExistence(timeout: 15))
        app.buttons["recovery-link"].tap()
        app.buttons["info-button"].tap()
        XCTAssertTrue(hrv.waitForExistence(timeout: 5))
        XCTAssertEqual(hrv.label, "HRV, 56 ms · usual 52")
        XCTAssertEqual(hrv.value as? String, "—")
        let inputs = app.descendants(matching: .any)["recovery-inputs"]
        XCTAssertEqual(inputs.label, "HRV, resting HR and sleep, Update ghoops on your Mac to see each part")
        XCTAssertEqual(inputs.value as? String, "+75.5")
        XCTAssertEqual(app.descendants(matching: .any)["recovery-total"].value as? String, "73")
        capture("recovery-no-weights-sheet", app: app)
        app.terminate()
    }

    @MainActor func testSportSuggestion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "parity", "-GHealthParityFixture", "sport"]
        app.launch()
        let boxing = app.buttons["edit-sport-BOXING"]
        XCTAssertTrue(boxing.waitForExistence(timeout: 15))
        XCTAssertTrue(boxing.isSelected)
        XCTAssertEqual(boxing.label, "Boxing, usual on Monday")
        XCTAssertTrue(app.staticTexts["Usual on Mon"].exists)
        let use = app.buttons["edit-sport-use"]
        XCTAssertTrue(use.isEnabled)
        XCTAssertTrue(use.staticTexts["USE BOXING"].exists)
        use.tap()
        XCTAssertTrue(app.buttons["edit-sport-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-sport-row"].label.contains("Boxing"))
        XCTAssertTrue(app.buttons["edit-save"].staticTexts["SAVE BOXING"].exists)
        app.buttons["edit-close"].tap()
        XCTAssertTrue(app.buttons["edit-close"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-button"].exists)
        app.terminate()
    }

    @MainActor func testParityScreensTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["strain-link"].waitForExistence(timeout: 15))
        app.buttons["strain-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["strain-screen"].waitForExistence(timeout: 5))
        capture("parity1-strain-target", app: app)
        scrollPage(app, up: true)
        capture("parity1-strain-target-2", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthLiveFixture", "boxing_23m"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["activity-target"].waitForExistence(timeout: 15))
        capture("parity1-live-target", app: app)
        app.terminate()
        var heights: [CGFloat] = []
        for preview in ["live", "live_target"] {
            app.launchArguments = ["-GHealthWidgetPreview", preview]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["live-widget-preview"].waitForExistence(timeout: 15))
            let view = app.descendants(matching: .any)["live-activity-view"].firstMatch
            XCTAssertTrue(view.exists)
            heights.append(view.frame.height)
            XCTAssertGreaterThan(view.frame.height, 100)
            if preview == "live_target" { capture("parity1-lock-live", app: app) }
            app.terminate()
        }
        print("PARITY_LIVE_ACTIVITY_HEIGHT original=\(heights[0]) target=\(heights[1])")
        XCTAssertLessThanOrEqual(heights[1], heights[0])
        app.launchArguments = ["-GHealthFixture", "fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["sleep-link"].waitForExistence(timeout: 15))
        app.buttons["sleep-link"].tap()
        reveal(app.descendants(matching: .any)["tonight-card"], in: app)
        capture("parity1-sleep-plan", app: app)
        app.buttons["tonight-info"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan-in-bed"].waitForExistence(timeout: 5))
        capture("parity1-sleep-info", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "parity", "-GHealthParityFixture", "sport"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-sport-BOXING"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["edit-sport-BOXING"].isSelected)
        capture("parity1-sport-suggest", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthWidgetPreview", "fresh"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["widget-preview"].waitForExistence(timeout: 15))
        reveal(app.descendants(matching: .any)["widget-parity"], in: app)
        capture("parity1-widgets", app: app)
        app.terminate()
    }

    @MainActor func testAddStartCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for (key, category) in [
            ("card", ""),
            ("card-ax5", "UICTContentSizeCategoryAccessibilityXXXL"),
            ("card-xl", "UICTContentSizeCategoryXL"),
            ("card-xxl", "UICTContentSizeCategoryXXL"),
            ("card-xxxl", "UICTContentSizeCategoryXXXL")
        ] {
            app.launchArguments = ["-GHealthFixture", "fresh"]
            if !category.isEmpty { app.launchArguments += ["-UIPreferredContentSizeCategoryName", category] }
            if key == "card-ax5" { app.launchArguments += ["-GHealthAccessibility5"] }
            app.launch()
            XCTAssertTrue(app.buttons["activity-open-add"].waitForExistence(timeout: 15))
            let add = app.buttons["activity-open-add"], start = app.buttons["activity-open-picker"]
            reveal(start, in: app)
            let sideBySide = abs(add.frame.minY - start.frame.minY) < 1
            print("ADD START \(key): add=\(add.frame) start=\(start.frame) sideBySide=\(sideBySide)")
            if key == "card" {
                XCTAssertEqual(add.frame.minY, start.frame.minY, accuracy: 1)
                XCTAssertLessThan(add.frame.maxX, start.frame.minX)
                XCTAssertEqual(add.frame.width, start.frame.width, accuracy: 1)
            } else if key == "card-ax5" {
                XCTAssertLessThan(add.frame.maxY, start.frame.minY)
                XCTAssertEqual(add.frame.width, app.frame.width - 58, accuracy: 1)
                XCTAssertEqual(start.frame.width, app.frame.width - 58, accuracy: 1)
            }
            capture("add-start-" + key, app: app)
            if key == "card" {
                start.tap()
                XCTAssertTrue(app.buttons["activity-start"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["LIVE"].exists)
                XCTAssertEqual(app.staticTexts["start-target-range"].label, "13.3–16.3")
                XCTAssertEqual(app.staticTexts["start-target-value"].label, "12.8")
                capture("add-start-start", app: app)
            }
            app.terminate()
        }
        app.launchArguments = ["-GHealthFixture", "fresh", "-GHealthLiveFixture", "boxing_23m"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-minimise"].waitForExistence(timeout: 15))
        app.buttons["activity-minimise"].tap()
        let end = app.buttons["activity-end-open"]
        reveal(end, in: app)
        XCTAssertEqual(end.label, "End Boxing")
        XCTAssertEqual(end.frame.width, app.frame.width - 58, accuracy: 1)
        XCTAssertFalse(app.buttons["activity-open-add"].exists)
        capture("add-start-card-live", app: app)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "new_user"]
        app.launch()
        XCTAssertTrue(app.buttons["activity-open-picker"].waitForExistence(timeout: 15))
        reveal(app.buttons["activity-open-picker"], in: app)
        app.buttons["activity-open-picker"].tap()
        XCTAssertTrue(app.buttons["activity-start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["start-target"].exists)
        app.terminate()
        for odd in [false, true] {
            app.launchArguments = ["-GHealthFixture", "edit"]
            if odd { app.launchArguments += ["-GHealthEditLimits", "odd"] }
            app.launch()
            XCTAssertTrue(app.buttons["back-button"].waitForExistence(timeout: 15))
            app.buttons["back-button"].tap()
            app.buttons["date-label"].tap()
            XCTAssertEqual(app.buttons["date-label"].label, "Showing today")
            app.buttons["date-prev"].tap()
            XCTAssertEqual(app.buttons["date-label"].label, "Showing Wednesday 11 March")
            let add = app.buttons["activity-open-add"]
            reveal(add, in: app)
            XCTAssertEqual(add.frame.width, app.frame.width - 58, accuracy: 1)
            XCTAssertFalse(app.buttons["activity-open-picker"].exists)
            if !odd { capture("add-start-card-past", app: app) }
            add.tap()
            XCTAssertTrue(app.buttons["add-day-2026-03-11"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["add-day-2026-03-11"].isSelected)
            app.buttons["activity-add-close"].tap()
            for _ in 0..<4 {
                if app.buttons["date-prev"].isHittable { break }
                scrollPage(app, up: false)
            }
            for _ in 0..<(odd ? 2 : 3) { app.buttons["date-prev"].tap() }
            XCTAssertEqual(app.buttons["date-label"].label, odd ? "Showing Monday 9 March" : "Showing Sunday 8 March")
            XCTAssertTrue(app.staticTexts["ACTIVITIES"].exists)
            XCTAssertFalse(app.buttons["activity-open-add"].exists)
            XCTAssertFalse(app.buttons["activity-open-picker"].exists)
            app.terminate()
        }
    }

    @MainActor func testAddAcrossMidnight() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for midnight in [false, true] {
            app.launchArguments = ["-GHealthFixture", "edit"]
            if midnight { app.launchArguments += ["-GHealthClock", "2026-03-13T00:40:00Z", "-GHealthMutationMode", "hold"] }
            app.launch()
            XCTAssertTrue(app.buttons["back-button"].waitForExistence(timeout: 15))
            app.buttons["back-button"].tap()
            app.buttons["date-label"].tap()
            XCTAssertEqual(app.buttons["date-label"].label, "Showing today")
            reveal(app.buttons["activity-open-add"], in: app)
            app.buttons["activity-open-add"].tap()
            XCTAssertTrue(app.buttons["add-day-2026-03-12"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["add-day-2026-03-12"].isSelected)
            XCTAssertTrue(app.buttons["add-sport-row"].label.contains("Choose"))
            XCTAssertFalse(app.buttons["add-commit"].isEnabled)
            if !midnight {
                XCTAssertTrue(app.descendants(matching: .any)["add-chart"].waitForExistence(timeout: 5))
                capture("add-start-add", app: app)
                app.terminate()
                continue
            }
            app.buttons["add-sport-row"].tap()
            app.buttons["add-sport-BOXING"].tap()
            app.buttons["add-sport-use"].tap()
            reveal(app.staticTexts["add-end-date"], in: app)
            XCTAssertEqual(app.staticTexts["add-start-date"].label, "Thu 12 Mar")
            XCTAssertEqual(app.staticTexts["add-end-date"].label, "Fri 13 Mar")
            XCTAssertEqual(app.datePickers["add-start"].buttons["Time Picker"].value as? String, "23:40")
            XCTAssertEqual(app.datePickers["add-end"].buttons["Time Picker"].value as? String, "00:40")
            capture("add-start-add-midnight", app: app)
            app.buttons["add-commit"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 5))
            closeRatingAsk(app)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "23:40 to 00:40")).firstMatch.exists)
            app.buttons["back-button"].tap()
            XCTAssertEqual(app.buttons["date-label"].label, "Showing today")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-link-goop-")).firstMatch.exists)
            app.terminate()
        }
    }

    @MainActor func testAddActivitySheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "add"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["activity-add"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["add-day-2026-03-11"].isSelected)
        XCTAssertTrue(app.buttons["add-effort-row"].label.contains("18:04 to 19:04"))
        XCTAssertTrue(app.buttons["add-sport-row"].label.contains("Choose"))
        XCTAssertEqual(app.buttons["add-commit"].label, "Add activity")
        XCTAssertFalse(app.buttons["add-commit"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["heart-rate-banner"].exists)
        app.buttons["add-sport-row"].tap()
        XCTAssertTrue(app.buttons["add-sport-use"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["add-sport-use"].label, "Use activity")
        XCTAssertFalse(app.buttons["add-sport-use"].isEnabled)
        app.buttons["add-sport-BOXING"].tap()
        app.buttons["add-sport-use"].tap()
        XCTAssertEqual(app.buttons["add-commit"].label, "Add Boxing")
        XCTAssertTrue(app.buttons["add-commit"].isEnabled)
        XCTAssertFalse(app.staticTexts["add-start-date"].exists)
        app.buttons["add-day-2026-03-12"].tap()
        XCTAssertTrue(app.buttons["add-day-2026-03-12"].isSelected)
        XCTAssertTrue(app.buttons["add-effort-row"].label.contains("1 found"))
        capture("add-start-a2-sheet", app: app)
        app.terminate()
    }

    @MainActor func testEditScreensTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for key in ["detail", "edit", "sport", "merge", "delete", "undo", "effort", "add", "offline", "alias"] {
            app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", key]
            app.launch()
            if ["edit", "sport", "merge", "delete", "offline"].contains(key) {
                XCTAssertTrue(app.buttons["edit-close"].waitForExistence(timeout: 15))
                if key == "offline" { XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label == %@", "Can't reach your Mac over Tailscale. Is Tailscale on?")).firstMatch.waitForExistence(timeout: 5)) }
                else if key == "sport" { XCTAssertTrue(app.buttons["edit-sport-BOXING"].waitForExistence(timeout: 5)) }
                else if key == "delete" { XCTAssertTrue(app.alerts["Delete this activity?"].waitForExistence(timeout: 5)) }
                else if key == "merge" { XCTAssertTrue(app.buttons["edit-merge-commit"].waitForExistence(timeout: 5)); XCTAssertFalse(app.descendants(matching: .any)["edit-handle-start"].exists) }
                else {
                    XCTAssertTrue(app.descendants(matching: .any)["edit-chart"].waitForExistence(timeout: 5))
                    XCTAssertTrue(app.staticTexts["Editing changes this activity, not your Day Strain."].exists)
                }
            } else if key == "add" {
                XCTAssertTrue(app.buttons["add-commit"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["add-day-2026-03-11"].isSelected)
                XCTAssertTrue(app.buttons["add-effort-row"].label.contains("18:04 to 19:04"))
                XCTAssertFalse(app.descendants(matching: .any)["heart-rate-banner"].exists)
            } else if key == "undo" { XCTAssertTrue(app.buttons["activity-undo"].waitForExistence(timeout: 15)) }
            else { XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15)) }
            capture("edit-" + key, app: app)
            if ["detail", "edit", "effort", "add"].contains(key) {
                scrollPage(app, up: true)
                capture("edit-" + key + "-2", app: app)
                if key == "detail" { scrollPage(app, up: true); capture("edit-detail-3", app: app) }
                if key == "effort" { XCTAssertTrue(app.staticTexts["Wrist heart rate can read low in boxing and weightlifting, so Strain and zones may be low."].exists) }
            }
            app.terminate()
        }
    }

    @MainActor func testInstantEditFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "unedited", "-GHealthMutationMode", "hold"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15))
        saveBoxingEdit(in: app)
        XCTAssertTrue(app.buttons["edit-save"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "17:56 to 19:12")).firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["17:56 to 19:12 · Saving to your Mac"].waitForExistence(timeout: 2))
        reveal(app.staticTexts["workout-notes"], in: app)
        XCTAssertEqual(app.staticTexts["workout-notes"].label, "Sparring, 6 rounds of 3 minutes.")
        XCTAssertFalse(app.buttons["edit-button"].exists)
        capture("instant-edit-saved", app: app)
        app.terminate()
    }

    @MainActor func testInstantStatesTour() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for key in ["saving", "waiting", "home-waiting", "updating", "rollback", "delete-waiting"] {
            app.launchArguments = ["-GHealthFixture", "edit", "-GHealthInstantFixture", key]
            app.launch()
            switch key {
            case "saving":
                XCTAssertTrue(app.staticTexts["17:56 to 19:12 · Saving to your Mac"].waitForExistence(timeout: 15))
                XCTAssertFalse(app.buttons["edit-button"].exists)
            case "waiting":
                XCTAssertTrue(app.descendants(matching: .any)["change-waiting-banner"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.staticTexts["17:56 to 19:12 · Edited"].exists)
            case "updating":
                XCTAssertTrue(app.buttons["contributor-strength"].waitForExistence(timeout: 15))
                XCTAssertEqual(app.buttons["contributor-strength"].label, "Strength, updating")
            case "rollback":
                XCTAssertTrue(app.staticTexts["Kickboxing changed on your Mac. It's back as it was."].waitForExistence(timeout: 15))
            default:
                XCTAssertTrue(app.descendants(matching: .any)["pending-changes-banner"].waitForExistence(timeout: 15))
                if key == "delete-waiting" { XCTAssertTrue(app.buttons["activity-undo"].exists) }
            }
            capture("instant-\(key)", app: app)
            if key == "home-waiting" || key == "updating" {
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", key == "home-waiting" ? "waiting for your Mac" : "saving to your Mac")).firstMatch
                reveal(row, in: app)
                capture("instant-\(key)-rows", app: app)
            }
            app.terminate()
        }
    }

    @MainActor func testInstantRollbackAndUndo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthInstantFixture", "rollback"]
        app.launch()
        let text = "Kickboxing changed on your Mac. It's back as it was."
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 15))
        for _ in 0..<2 { app.buttons["date-prev"].tap() }
        let kickboxing = app.buttons["workout-link-7300000000000000101"]
        reveal(kickboxing, in: app)
        XCTAssertTrue(kickboxing.label.hasPrefix("Kickboxing, strain"))
        kickboxing.tap()
        XCTAssertTrue(app.staticTexts["18:05 to 19:02"].waitForExistence(timeout: 5))
        let banner = app.descendants(matching: .any)["change-rollback-banner"]
        XCTAssertTrue(banner.exists)
        XCTAssertTrue(app.staticTexts[text].exists)
        capture("instant-rollback-workout", app: app)
        app.buttons["Dismiss: \(text)"].tap()
        XCTAssertFalse(banner.exists)
        app.buttons["back-button"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["change-rollback-banner-0"].exists)
        app.terminate()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthInstantFixture", "delete-waiting"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pending-changes-banner"].waitForExistence(timeout: 15))
        app.buttons["activity-undo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pending-changes-banner"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity-undo"].exists)
        for _ in 0..<2 { app.buttons["date-prev"].tap() }
        let boxing = app.buttons["workout-link-7300000000000000101"]
        reveal(boxing, in: app)
        XCTAssertTrue(boxing.label.hasPrefix("Boxing, strain"))
        capture("instant-delete-cancelled", app: app)
        app.terminate()
    }

    @MainActor func testInstantWaitingClears() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "unedited", "-GHealthMutationMode", "offline-once"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15))
        saveBoxingEdit(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["change-waiting-banner"].waitForExistence(timeout: 5))
        app.buttons["back-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pending-changes-banner"].waitForExistence(timeout: 5))
        capture("instant-waiting-before-retry", app: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["pending-changes-banner"].waitForNonExistence(timeout: 8))
        let boxing = app.buttons["workout-link-7300000000000000101"]
        reveal(boxing, in: app)
        boxing.tap()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["17:56 to 19:12 · Edited"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["change-waiting-banner"].exists)
        capture("instant-waiting-cleared", app: app)
        app.terminate()
    }

    @MainActor private func saveBoxingEdit(in app: XCUIApplication) {
        app.buttons["edit-button"].tap()
        XCTAssertTrue(app.buttons["edit-sport-row"].waitForExistence(timeout: 5))
        app.buttons["edit-sport-row"].tap()
        app.textFields["edit-sport-search"].tap()
        app.textFields["edit-sport-search"].typeText("box")
        app.buttons["edit-sport-BOXING"].tap()
        app.buttons["edit-sport-use"].tap()
        let chart = app.descendants(matching: .any)["edit-chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let start = app.descendants(matching: .any)["edit-handle-start"]
        let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: -8.75 / 117 * chart.frame.width, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(start.label, "Start, 17:56")
        XCTAssertEqual(app.staticTexts["edit-value-duration"].label, "1:06")
        XCTAssertEqual(app.staticTexts["edit-prior-duration"].label, "0:57")
        let end = app.descendants(matching: .any)["edit-handle-end"]
        let endFrom = end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        endFrom.press(forDuration: 0.1, thenDragTo: endFrom.withOffset(CGVector(dx: 10.25 / 126 * chart.frame.width, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(end.label, "End, 19:12")
        XCTAssertEqual(app.staticTexts["edit-value-duration"].label, "1:16")
        let notes = app.descendants(matching: .any)["edit-notes"]
        reveal(notes, in: app)
        notes.tap()
        notes.typeText("Sparring, 6 rounds of 3 minutes.")
        app.buttons["edit-save"].tap()
    }

    @MainActor func testEditFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "unedited"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "· Edited")).firstMatch.exists)
        saveBoxingEdit(in: app)
        XCTAssertTrue(app.buttons["edit-save"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "· Edited")).firstMatch.waitForExistence(timeout: 8))
        reveal(app.staticTexts["workout-notes"], in: app)
        XCTAssertEqual(app.staticTexts["workout-notes"].label, "Sparring, 6 rounds of 3 minutes.")
        XCTAssertTrue(app.staticTexts["workout-edited-footnote"].label.contains("Kickboxing, 18:05 to 19:02"))
        capture("edit-flow-saved", app: app)
        for _ in 0..<3 { scrollPage(app, up: false) }
        app.buttons["edit-button"].tap()
        reveal(app.buttons["edit-restore"], in: app)
        app.buttons["edit-restore"].tap()
        app.alerts["Restore the band's version?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit-close"].exists)
        app.buttons["edit-restore"].tap()
        app.alerts["Restore the band's version?"].buttons["Restore"].tap()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "18:05 to 19:02")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "· Edited")).firstMatch.exists)
        capture("edit-flow-restored", app: app)
        app.terminate()
    }

    @MainActor func testEditLimitsFromMac() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "edit", "-GHealthEditLimits", "odd"]
        app.launch()
        let chart = app.descendants(matching: .any)["edit-chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["edit-merge-next"].exists)
        let start = app.descendants(matching: .any)["edit-handle-start"]
        for _ in 0..<3 {
            start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertEqual(start.label, "Start, 17:05")
        let end = app.descendants(matching: .any)["edit-handle-end"]
        for _ in 0..<3 {
            end.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertEqual(end.label, "End, 19:35")
        XCTAssertEqual(app.staticTexts["edit-value-duration"].label, "2:30")
        capture("edit-limits-odd-handles", app: app)
        let notes = app.descendants(matching: .any)["edit-notes"]
        reveal(notes, in: app)
        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        notes.typeText(" Good session today.")
        let cappedNote = "Sparring, 6 rounds of 3 minutes. Good se"
        let capped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", cappedNote), object: notes)
        XCTAssertEqual(XCTWaiter.wait(for: [capped], timeout: 5), .completed)
        XCTAssertEqual((notes.value as? String)?.unicodeScalars.count, 40)
        XCTAssertEqual(notes.value as? String, cappedNote)
        let notesLimit = app.staticTexts["edit-notes-limit"]
        XCTAssertTrue(notesLimit.waitForExistence(timeout: 5))
        if app.keyboards.firstMatch.exists { app.scrollViews.firstMatch.swipeDown() }
        reveal(notesLimit, in: app)
        XCTAssertEqual(notesLimit.label, "Notes can hold up to 40 characters.")
        capture("edit-limits-odd-sheet", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "old", "-GHealthEditLimits", "odd"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["edit-button"].exists)
        let horizon = app.staticTexts["workout-edit-horizon"]
        reveal(horizon, in: app)
        XCTAssertEqual(horizon.label, "Only activities from the last 3 days can be edited.")
        capture("edit-limits-odd-old", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "add", "-GHealthEditLimits", "odd"]
        app.launch()
        XCTAssertTrue(app.buttons["add-commit"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["add-day-2026-03-09"].exists)
        for day in ["10", "11", "12"] { XCTAssertTrue(app.buttons["add-day-2026-03-\(day)"].exists) }
        capture("edit-limits-odd-past", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "edit", "-GHealthEditLimits", "none"]
        app.launch()
        XCTAssertTrue(chart.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["edit-merge-next"].exists)
        capture("edit-limits-none-sheet", app: app)
        app.terminate()

        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "old", "-GHealthEditLimits", "none"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15))
        XCTAssertFalse(horizon.exists)
        app.terminate()
    }

    @MainActor func testNotesStopAtTheMacsLimit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "edit", "-GHealthEditLimits", "odd"]
        app.launch()
        let notes = app.descendants(matching: .any)["edit-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 15))
        reveal(notes, in: app)
        let fixtureNote = "Sparring, 6 rounds of 3 minutes.", fullNote = "Sparring, 6 rounds of 3 minutes. Good se"
        XCTAssertEqual(notes.value as? String, fixtureNote)
        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        notes.typeText(" Good se")
        XCTAssertEqual(notes.value as? String, fullNote)
        XCTAssertTrue(app.staticTexts["edit-notes-limit"].waitForExistence(timeout: 5))

        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        notes.typeText("X")
        let unchanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", fullNote), object: notes)
        XCTAssertEqual(XCTWaiter.wait(for: [unchanged], timeout: 2), .completed, "typing into a full note changed it: \(notes.value as? String ?? "")")
        XCTAssertEqual(notes.value as? String, fullNote)

        app.terminate()
        app.launch()
        XCTAssertTrue(notes.waitForExistence(timeout: 15))
        reveal(notes, in: app)
        XCTAssertEqual(notes.value as? String, fixtureNote)
        UIPasteboard.general.string = "Boxing. Good session today. "
        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1)
        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        let paste = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Paste")).firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        XCTAssertEqual(notes.value as? String, "Boxing. Sparring, 6 rounds of 3 minutes.")
        XCTAssertTrue(app.staticTexts["edit-notes-limit"].waitForExistence(timeout: 5))
        capture("edit-notes-full", app: app)
        app.terminate()
    }

    @MainActor func testEditMergeDeleteUndo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "detail"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15))
        app.buttons["edit-button"].tap()
        reveal(app.buttons["edit-merge-next"], in: app)
        app.buttons["edit-merge-next"].tap()
        XCTAssertTrue(app.buttons["edit-merge-commit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["edit-handle-start"].exists)
        app.buttons["edit-merge-commit"].tap()
        XCTAssertTrue(app.buttons["edit-merge-commit"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "17:56 to 19:38 · Edited")).firstMatch.waitForExistence(timeout: 8))
        capture("edit-flow-merged", app: app)
        app.buttons["edit-button"].tap()
        reveal(app.buttons["edit-delete"], in: app)
        app.buttons["edit-delete"].tap()
        app.alerts["Delete this activity?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["edit-close"].exists)
        app.buttons["edit-delete"].tap()
        app.alerts["Delete this activity?"].buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["activity-undo"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Boxing deleted."].exists)
        XCTAssertTrue(app.buttons["back-button"].waitForNonExistence(timeout: 5))
        capture("edit-flow-deleted", app: app)
        app.buttons["activity-undo"].tap()
        XCTAssertFalse(app.buttons["activity-undo"].exists)
        let restored = app.buttons["workout-link-7300000000000000101"]
        reveal(restored, in: app)
        XCTAssertTrue(restored.label.contains("19:38"))
        XCTAssertFalse(app.buttons["workout-link-7300000000000000102"].exists)
        capture("edit-flow-undone", app: app)
        app.terminate()
    }

    @MainActor func testNameEffortAndAddPast() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", "effort"]
        app.launch()
        XCTAssertTrue(app.buttons["edit-button"].waitForExistence(timeout: 15))
        app.buttons["edit-button"].tap()
        XCTAssertTrue(app.buttons["edit-sport-RUNNING"].waitForExistence(timeout: 5))
        app.buttons["edit-sport-RUNNING"].tap()
        app.buttons["edit-sport-use"].tap()
        XCTAssertEqual(app.buttons["edit-save"].label, "Save Running")
        app.buttons["edit-save"].tap()
        XCTAssertTrue(app.buttons["edit-save"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "07:10 to 07:41 · Added in ghoops")).firstMatch.waitForExistence(timeout: 8))
        capture("edit-flow-named", app: app)
        app.buttons["back-button"].tap()
        XCTAssertFalse(app.buttons["back-button"].exists)
        XCTAssertTrue(app.buttons["tab-home"].exists)
        reveal(app.buttons["activity-open-add"], in: app)
        app.buttons["activity-open-add"].tap()
        XCTAssertTrue(app.buttons["add-day-2026-03-11"].waitForExistence(timeout: 5))
        app.buttons["add-day-2026-03-11"].tap()
        XCTAssertTrue(app.buttons["add-effort-row"].label.contains("18:04 to 19:04"))
        app.buttons["add-effort-row"].tap()
        XCTAssertTrue(app.buttons["add-effort-use"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-effort-use"].isEnabled)
        app.buttons["add-effort-use"].tap()
        XCTAssertTrue(app.buttons["add-effort-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-effort-row"].label.contains("18:04 to 19:04"))
        XCTAssertEqual(app.buttons["add-commit"].label, "Add activity")
        XCTAssertFalse(app.buttons["add-commit"].isEnabled)
        app.buttons["add-sport-row"].tap()
        app.buttons["add-sport-BOXING"].tap()
        app.buttons["add-sport-use"].tap()
        XCTAssertEqual(app.buttons["add-commit"].label, "Add Boxing")
        app.buttons["add-commit"].tap()
        XCTAssertTrue(app.buttons["add-commit"].waitForNonExistence(timeout: 8))
        closeRatingAsk(app, required: true)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "18:04 to 19:04 · Added in ghoops")).firstMatch.waitForExistence(timeout: 8))
        capture("edit-flow-added", app: app)
        app.terminate()
    }

    /// After END or ADD the new session's page asks once for a rating (effort-rating-spec.md §3.3); a flow that tests something else closes it.
    @MainActor private func closeRatingAsk(_ app: XCUIApplication, required: Bool = false) {
        let sheet = app.descendants(matching: .any)["rating-sheet"]
        guard sheet.waitForExistence(timeout: required ? 8 : 3) else {
            if required { XCTFail("The rating sheet did not open") }
            return
        }
        app.buttons["rating-close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }

    @MainActor private func ratingApp(_ key: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GHealthFixture", "edit", "-GHealthEditFixture", key] + extra
        app.launch()
        return app
    }

    @MainActor func testRatingRow() {
        continueAfterFailure = false
        let app = ratingApp("rated")
        let row = app.buttons["workout-rating-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(row.label, "How hard it felt, 7, very hard")
        XCTAssertTrue(app.staticTexts["7 · Very hard"].exists)
        capture("rating-rated", app: app)
        app.terminate()
        let unrated = ratingApp("detail")
        XCTAssertTrue(unrated.buttons["edit-button"].waitForExistence(timeout: 15))
        XCTAssertEqual(unrated.buttons["workout-rating-row"].label, "How hard it felt, not rated")
        unrated.terminate()
        let effort = ratingApp("effort")
        XCTAssertTrue(effort.descendants(matching: .any)["workout-screen"].waitForExistence(timeout: 15))
        XCTAssertTrue(effort.buttons["edit-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(effort.descendants(matching: .any)["workout-rating-row"].exists)
        effort.terminate()
    }

    @MainActor func testRatingSheet() {
        continueAfterFailure = false
        let app = ratingApp("rated")
        let row = app.buttons["workout-rating-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rating-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rating-7"].isSelected)
        XCTAssertFalse(app.buttons["rating-save"].isEnabled)
        XCTAssertEqual(app.buttons["rating-6"].label, "6")
        XCTAssertTrue(app.staticTexts["Your rating stays on your Mac. It doesn't change Strain."].exists)
        app.buttons["rating-5"].tap()
        XCTAssertTrue(app.buttons["rating-5"].isSelected)
        XCTAssertTrue(app.buttons["rating-save"].isEnabled)
        capture("rating-chosen", app: app)
        app.buttons["rating-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["rating-sheet"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["workout-rating-row"].waitForLabel(containing: "5, hard", timeout: 8))
        app.terminate()
    }

    @MainActor func testRatingAsk() {
        continueAfterFailure = false
        let app = ratingApp("ask")
        XCTAssertTrue(app.descendants(matching: .any)["rating-sheet"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["rating-save"].isEnabled)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "rating-")).firstMatch.exists)
        capture("rating-ask", app: app)
        app.buttons["rating-close"].tap()
        let row = app.buttons["workout-rating-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "How hard it felt, not rated")
        capture("rating-unrated", app: app)
        app.buttons["back-button"].tap()
        let link = app.buttons["workout-link-7300000000000000102"]
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["rating-sheet"].waitForExistence(timeout: 2))
        app.terminate()
    }

    @MainActor func testRatingWaitingAndRefused() {
        continueAfterFailure = false
        let waiting = ratingApp("rated", extra: ["-GHealthMutationMode", "offline"])
        XCTAssertTrue(waiting.buttons["workout-rating-row"].waitForExistence(timeout: 15))
        waiting.buttons["workout-rating-row"].tap()
        waiting.buttons["rating-4"].tap()
        waiting.buttons["rating-save"].tap()
        XCTAssertTrue(waiting.descendants(matching: .any)["change-waiting-banner"].waitForExistence(timeout: 8))
        XCTAssertTrue(waiting.descendants(matching: .any)["workout-rating-row"].waitForLabel(containing: "4, somewhat hard", timeout: 5))
        capture("rating-waiting", app: waiting)
        waiting.terminate()
        let refused = ratingApp("rated", extra: ["-GHealthMutationMode", "reject-400"])
        XCTAssertTrue(refused.buttons["workout-rating-row"].waitForExistence(timeout: 15))
        refused.buttons["workout-rating-row"].tap()
        refused.buttons["rating-2"].tap()
        refused.buttons["rating-save"].tap()
        let banner = refused.descendants(matching: .any)["change-rollback-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        XCTAssertTrue(refused.staticTexts["Your Mac couldn't save your rating for Boxing. It's back as it was."].exists)
        XCTAssertTrue(refused.descendants(matching: .any)["workout-rating-row"].waitForLabel(containing: "7, very hard", timeout: 5))
        capture("rating-refused", app: refused)
        refused.terminate()
    }

    @MainActor private func scrollPage(_ app: XCUIApplication, up: Bool) {
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        (up ? lower : upper).press(forDuration: 0.05, thenDragTo: up ? upper : lower,
                                  withVelocity: .slow, thenHoldForDuration: 0.4)
        _ = app.wait(for: .runningForeground, timeout: 5)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            let bottom = ["tab-home", "edit-save", "edit-merge-commit", "edit-sport-use", "add-commit", "activity-start", "rating-save"].map { app.buttons[$0] }.filter { $0.exists && !$0.frame.isEmpty && app.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map { $0.frame.minY }.min() ?? app.frame.maxY
            if element.isHittable && element.frame.maxY < bottom - 12 { return }
            scrollPage(app, up: true)
        }
        XCTFail("Control did not become visible above the fixed controls: \(element.identifier)")
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name + ".png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForLabel(prefix: String, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: self)], timeout: timeout) == .completed
    }
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: self)], timeout: timeout) == .completed
    }
}
