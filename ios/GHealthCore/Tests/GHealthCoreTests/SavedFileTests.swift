import Foundation
import Testing
@testable import GHealthCore

@Test(arguments: [NSFileReadNoPermissionError, NSFileWriteNoPermissionError])
func savedFilePermissionErrorsUseGhoopsCopy(_ code: Int) {
    let error = NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "fixture system message"])
    let wrapped = NSError(domain: "fixture", code: 1, userInfo: [NSUnderlyingErrorKey: error])
    for area in [SavedDataError.Area.activities, .changes] {
        let failure = SavedDataError(wrapped, area: area)
        #expect(failure.permissionDenied)
        #expect(failure.message(protectedDataAvailable: false) == nil)
        #expect(failure.message(protectedDataAvailable: true)?.hasPrefix("ghoops couldn't read") == true)
        #expect(!failure.localizedDescription.contains("fixture system message"))
    }
}

@Test func savedFileProtectionWritesAndReclassesExistingFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let upload: ActivityUpload = try fixture("activities/valid.json")
    let store = ActivityStore(directory: directory)
    let queue = ChangeQueue(directory: directory, serverURL: "https://fixture.invalid")
    try await store.prepareForProtectedData()
    try await queue.prepareForProtectedData()
    try await queue.load()
    try await store.save(LocalActivity(upload: upload), now: upload.end)
    try await store.saveSession(ActivitySession(sport: .all[0], now: upload.end), now: upload.end)
    try await queue.submit(PendingChange(kind: .add, request: .postActivity(upload), targets: [upload.id], cycleDates: [], name: "Boxing", patch: WorkoutPatch(), serverURL: "https://fixture.invalid", createdAt: upload.end))
    let names = ["activities-local.json", "live-session.json", "pending-changes.json"]
    #if os(iOS)
    let probe = directory.appendingPathComponent("protection-probe.json")
    try Data("{}".utf8).write(to: probe, options: .completeFileProtection)
    let reportsProtection = try FileManager.default.attributesOfItem(atPath: probe.path)[.protectionKey] as? FileProtectionType == .complete
    print("file-protection: requested-attribute-reported=\(reportsProtection)")
    #else
    let reportsProtection = false
    print("file-protection: ios-policy-tested=false, platform-macos=true")
    #endif
    var writtenAttributes = 0
    var migratedAttributes = 0
    for name in names {
        let file = directory.appendingPathComponent(name)
        let written = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
        if written != nil { writtenAttributes += 1 }
        if reportsProtection { #expect(written == .completeUntilFirstUserAuthentication) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        #endif
    }
    try await store.prepareForProtectedData()
    try await queue.prepareForProtectedData()
    for name in names {
        let protection = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.protectionKey] as? FileProtectionType
        if protection != nil { migratedAttributes += 1 }
        if reportsProtection { #expect(protection == .completeUntilFirstUserAuthentication) }
    }
    #if os(iOS) && !targetEnvironment(simulator)
    #expect(reportsProtection)
    #endif
    print("file-protection: write-attributes=\(writtenAttributes), reclass-attributes=\(migratedAttributes)")
    #expect(try await store.activities(now: upload.end).count == 1)
    #expect(try await store.restoreSession(now: upload.end) != nil)
    #expect(try await queue.load().count == 1)
}
