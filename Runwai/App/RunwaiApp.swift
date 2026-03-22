import SwiftUI

@main
struct RunwaiApp: App {
    @State private var model = UsageMonitorModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
                .frame(width: 420)
        } label: {
            MenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("runwai Settings", id: "settings") {
            SettingsView(model: model)
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
