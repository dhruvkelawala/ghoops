public enum PairingCopy {
    public static let invalidCode = "This isn't a ghoops pairing code. Run ghoops pair on your Mac and scan the code it shows."
    public static let expiredCode = "This code has expired or was already used. Run ghoops pair on your Mac again."
    public static let declined = "Your Mac didn't pair this iPhone. Run ghoops pair on your Mac to try again."
    public static let scanHint = "Point the camera at the code in your Mac's terminal. ghoops reads it here, so the code never passes through another app."
    public static let addressHint = "ghoops contacts this Mac only after you tap PAIR WITH THIS MAC. If you don't recognise the address, close this and run ghoops pair again."
    public static let compareCode = "Your Mac now shows a code. If it is the same as this one, type y on your Mac."
    public static let verificationHint = "The code changes every time you pair. ghoops never asks you to type it on this iPhone."
    public static let unpairTitle = "Unpair from your Mac?"
    public static let unpair = "Unpair"
    public static let unpairKeep = "Unpair, keep workouts"
    public static let unpairDelete = "Unpair, delete workouts"
    public static let unpairDuringOtherWorkout = "Finish the workout for your other Mac before you unpair."
    public static let backup = "Your scores stay on your Mac and this iPhone. Workouts that haven't reached your Mac yet are part of this iPhone's backup."

    public static func unpairMessage(workouts: Int, changes: Int, mac: String) -> String {
        var message = "This iPhone stops reading from \(mac) and deletes the scores saved on it. Nothing is deleted on your Mac."
        if workouts == 1 { message += " \(workouts) workout hasn't reached \(mac) yet." }
        if workouts > 1 { message += " \(workouts) workouts haven't reached \(mac) yet." }
        return switchMessage(base: message, activities: 0, changes: changes, mac: mac)
    }

    public static func switchMessage(base: String, activities: Int, changes: Int, mac: String, ifDifferentMac: Bool = false) -> String {
        var sentences = [base]
        let prefix = ifDifferentMac ? "If this is a different Mac, " : ""
        if activities > 0 {
            let action = activities == 1 ? "activity stays" : "activities stay"
            sentences.append(prefix + "\(activities) unsent \(action) on this iPhone for \(mac).")
        }
        if changes > 0 {
            let subject = changes == 1 ? "change" : "changes"
            let verb = changes == 1 ? "is" : "are"
            sentences.append(prefix + "\(changes) unsent \(subject) to \(mac) \(verb) discarded.")
        }
        return sentences.joined(separator: " ")
    }
}
