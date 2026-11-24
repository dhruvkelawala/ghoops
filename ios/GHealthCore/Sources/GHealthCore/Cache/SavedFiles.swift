import Foundation

enum SavedFiles {
    static func read(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }

    static func prepare(_ names: [String], in directory: URL) throws {
        #if os(iOS)
        for name in names {
            let url = directory.appendingPathComponent(name)
            do {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            } catch CocoaError.fileNoSuchFile {}
        }
        #endif
    }
}
