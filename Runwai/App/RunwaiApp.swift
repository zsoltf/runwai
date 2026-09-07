import AppKit
import SwiftUI

@main
struct RunwaiApp: App {
    @State private var model = UsageMonitorModel()
    @State private var activity = AgentActivityModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, activity: activity)
                .frame(width: 420, height: min(640, (NSScreen.main?.visibleFrame.height ?? 720) - 48), alignment: .topLeading)
        } label: {
            MenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("runwai Settings", id: "settings") {
            SettingsView(model: model, activity: activity)
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
