import GHealthCore
import Testing

@Test func unpairCountsUnsentWork() {
    let base = "This iPhone stops reading from Mac A and deletes the scores saved on it. Nothing is deleted on your Mac."
    #expect(PairingCopy.unpairMessage(workouts: 0, changes: 0, mac: "Mac A") == base)
    #expect(PairingCopy.unpairMessage(workouts: 1, changes: 1, mac: "Mac A")
            == base + " 1 workout hasn't reached Mac A yet. 1 unsent change to Mac A is discarded.")
    #expect(PairingCopy.unpairMessage(workouts: 2, changes: 2, mac: "Mac A")
            == base + " 2 workouts haven't reached Mac A yet. 2 unsent changes to Mac A are discarded.")
}

@Test func replaceQualifiesEachUnsentCount() {
    #expect(PairingCopy.switchMessage(base: "Replace.", activities: 0, changes: 0, mac: "Mac A", ifDifferentMac: true) == "Replace.")
    #expect(PairingCopy.switchMessage(base: "Replace.", activities: 1, changes: 0, mac: "Mac A", ifDifferentMac: true)
            == "Replace. If this is a different Mac, 1 unsent activity stays on this iPhone for Mac A.")
    #expect(PairingCopy.switchMessage(base: "Replace.", activities: 0, changes: 1, mac: "Mac A", ifDifferentMac: true)
            == "Replace. If this is a different Mac, 1 unsent change to Mac A is discarded.")
    #expect(PairingCopy.switchMessage(base: "Replace.", activities: 2, changes: 2, mac: "Mac A", ifDifferentMac: true)
            == "Replace. If this is a different Mac, 2 unsent activities stay on this iPhone for Mac A. If this is a different Mac, 2 unsent changes to Mac A are discarded.")
}
