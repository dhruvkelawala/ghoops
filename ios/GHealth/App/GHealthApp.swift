import SwiftUI
import GHealthCore

@main
struct GHealthApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        BackgroundRefresh.register(model: model)
    }
    var body: some Scene {
        WindowGroup {
            AppRoot().environment(model).preferredColorScheme(.dark).tint(Goop.Color.strain)
                .task {
                    await model.start()
                    await model.becameActive()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(ChangeTiming.retryInterval))
                        model.tick()
                        if model.activity.appActive && model.pending.contains(where: { $0.state == .waiting || $0.state == .accepted }) { model.startSending() }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    model.activity.appActive = phase == .active
                    if phase == .active { Task { await model.becameActive() } }
                    if phase == .background {
                        model.expireActivityUndo()
                        model.rollbacks = []
                        Task { await model.activity.persist() }
                        BackgroundRefresh.schedule()
                        #if DEBUG
                        if model.backgroundProbe { model.backgroundState = BackgroundRefresh.scheduling }
                        #endif
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    Task { await model.protectedDataBecameAvailable() }
                }
                .onOpenURL { url in
                    if url.scheme == "ghealth" && url.host == "activity" { model.showActivity() }
                    else if url.scheme == "ghealth" && url.host == "today" { model.showToday() }
                    else if model.paired { model.pendingURL = url }
                    else { Task { await model.pair(url) } }
                }
                .goopDestructiveAlert("Replace the current pairing?", isPresented: Binding(get: { model.pendingURL != nil }, set: { if !$0 { model.pendingURL = nil } }), verb: "Replace pairing", message: "This iPhone switches to the Mac in the new link. Nothing is deleted on your Mac.") {
                    if let url = model.pendingURL { Task { await model.pair(url) } }
                    model.pendingURL = nil
                }
        }
    }
}

struct AppRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            #if DEBUG
            if model.componentGallery { ComponentGallery() }
            else if model.widgetPreview { WidgetPreviewHost() }
            else { tabs }
            #else
            tabs
            #endif
        }
        .sheet(isPresented: Binding(get: { model.activity.pickerPresented }, set: { model.activity.pickerPresented = $0 }), onDismiss: { model.activity.closePicker() }) { ActivityPicker().environment(model) }
        .sheet(isPresented: Binding(get: { model.addDay != nil }, set: { if !$0 { model.addDay = nil } }), onDismiss: { model.addDay = nil }) {
            if let day = model.addDay { AddActivitySheet(day: day).environment(model) }
        }
        .fullScreenCover(isPresented: Binding(get: { model.activity.livePresented }, set: { model.activity.livePresented = $0 })) { LiveActivityScreen().environment(model) }
        #if DEBUG
        .dynamicTypeSize(model.largestType ? .accessibility5 : typeSize)
        .overlay(alignment: .top) {
            if model.backgroundProbe {
                VStack {
                    Text("Stubbed background requests: \(model.backgroundRequests)").accessibilityIdentifier("background-probe-count")
                    Text("registered \(BackgroundRefresh.registered), \(BackgroundRefresh.scheduling), runs \(model.backgroundRuns), \(model.backgroundState)").font(.caption).accessibilityIdentifier("background-probe-state")
                }
            }
        }
        #endif
    }
    private var tabs: some View {
        Group {
            if !model.paired || model.invalidPairing { PairingScreen() }
            else { GoopTabs() }
        }
    }
}
