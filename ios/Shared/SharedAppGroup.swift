import Foundation

enum SharedAppGroup {
    static let id: String = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String,
              id.hasPrefix("group.") else {
            preconditionFailure("SharedAppGroup is missing from Info.plist. Regenerate the Xcode project with make.")
        }
        return id
    }()

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
