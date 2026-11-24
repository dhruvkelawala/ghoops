import Foundation
import Testing
@testable import GHealthCore

@Test func systemErrorsUseTheOperationSentence() {
    let errors: [Error] = [
        NSError(domain: NSCocoaErrorDomain, code: 257, userInfo: [NSLocalizedDescriptionKey: "SYSTEM FILE TEXT"]),
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "SYSTEM DECODING TEXT")),
        URLError(.badServerResponse),
    ]
    let contexts: [(ErrorCopy.Context, String)] = [
        (.pair, "ghoops couldn't save this pairing on this phone. Try pairing again."),
        (.testConnection, "ghoops couldn't check the connection on your Mac. Try again."),
        (.unpair, "ghoops couldn't remove this pairing on this phone. Try unpairing again."),
        (.undoActivity, "ghoops couldn't undo this activity change on this phone. Close and open the activity to check it."),
        (.readHeartRate, "ghoops couldn't load heart rate on your Mac. Close and open this sheet to try again."),
        (.saveActivity, "ghoops couldn't save this activity on this phone. Try again."),
        (.deleteActivity, "ghoops couldn't delete this activity on this phone. Try again."),
        (.saveSession, "ghoops couldn't save your running activity on this phone. It will try again."),
    ]
    for (context, sentence) in contexts {
        for error in errors { #expect(ErrorCopy.message(error, context: context) == sentence) }
    }
    #expect(ErrorCopy.message(errors[1], context: .refresh) == "ghoops couldn't update your saved data on this phone. It will try again.")
    #expect(ErrorCopy.message(errors[1], context: .syncChanges) == "ghoops couldn't finish syncing your changes on this phone. It will try again.")
}

@Test func timeoutsAndFailedConnectionsHaveDifferentCopy() {
    #expect(ErrorCopy.message(URLError(.timedOut), context: .refresh) == "Your Mac is taking too long to answer. ghoops will try again.")
    #expect(ErrorCopy.message(ClientError.timedOut, context: .readHeartRate) == "Your Mac is taking too long to answer. ghoops will try again.")
    for code: URLError.Code in [.cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive, .dataNotAllowed] {
        #expect(ErrorCopy.message(URLError(code), context: .testConnection) == "Can't reach your Mac over Tailscale. Is Tailscale on?")
    }
    #expect(ErrorCopy.message(URLError(.secureConnectionFailed), context: .testConnection) == "ghoops couldn't check the connection on your Mac. Try again.")
}

@Test func approvedErrorsKeepTheirCopyAndRecoverableErrorsStaySilent() {
    let clientErrors: [(ClientError, String)] = [
        (.unauthorized, "This phone is no longer paired with your Mac. Run ghoops pair on your Mac, then scan its code."),
        (.rateLimited, "Your Mac is getting too many requests. Try again in a minute."),
        (.storeUnavailable, "Your Mac can't open its saved health data. Log in on your Mac, then try again."),
        (.offline, "Can't reach your Mac over Tailscale. Is Tailscale on?"),
        (.incompatibleVersion, "Your Mac and this phone run different versions of ghoops. Update both to the same version."),
        (.rejected, "Your Mac could not save this. Check the times and try again."),
        (.notFound, "This activity changed on your Mac. Close and open it again."),
        (.conflict, "This activity is now part of another one. Close and open it again."),
        (.http(500), "Your Mac ran into a problem. Try again in a moment."),
    ]
    for (error, sentence) in clientErrors {
        #expect(ErrorCopy.message(error, context: .refresh) == sentence)
    }
    let pairingErrors: [(PairingError, String)] = [
        (.invalidLink, "Paste a valid ghoops pairing link from your Mac."),
        (.keychain(-1), "ghoops couldn't use the pairing saved on this phone. Run ghoops pair on your Mac, then scan its code."),
    ]
    for (error, sentence) in pairingErrors {
        #expect(ErrorCopy.message(error, context: .pair) == sentence)
    }
    for (context, area): (ErrorCopy.Context, SavedDataError.Area) in [(.savedActivities, .activities), (.waitingChanges, .changes), (.refresh, .activities), (.syncChanges, .changes)] {
        let error = NSError(domain: NSCocoaErrorDomain, code: 257)
        #expect(ErrorCopy.message(error, context: context) == SavedDataError(area: area).errorDescription)
        #expect(ErrorCopy.message(error, context: context, protectedDataAvailable: false) == nil)
    }
    #expect(ErrorCopy.message(SavedDataError(area: .changes), context: .saveActivity) == "ghoops couldn't read your waiting changes on this phone. It will try again.")
    #expect(ErrorCopy.message(SavedDataError(area: .activities), context: .deleteActivity, protectedDataAvailable: false) == nil)
    #expect(ErrorCopy.message(CancellationError(), context: .refresh) == nil)
    #expect(ErrorCopy.message(URLError(.cancelled), context: .refresh) == nil)
}
