import SwiftUI

@main
struct BreathOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @State private var settings = BreathSettings.load()
    @State private var showSession = false

    var body: some View {
        SettingsView(settings: $settings) {
            settings.save()
            showSession = true
        }
        .fullScreenCover(isPresented: $showSession) {
            SessionView(settings: settings) { showSession = false }
        }
        // Persist whenever a setting changes so config survives a quit without "Начать".
        .onChange(of: settings) { _, newValue in
            newValue.save()
        }
    }
}
